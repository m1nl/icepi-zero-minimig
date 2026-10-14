/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Reference: mist-firmware/cue_parser.c, 2021, Gyorgy Szombathelyi.
 * This parser and its multi-file layout/I/O are written for this target;
 * no upstream parser source is copied. Track conventions follow that reference.
 */

#include "cdrom_image.h"
#include <string.h>

/* One cache shared by the one configured CD drive. No per-track 4 KiB index. */
static fileTYPE cache, input, opened;
static unsigned long seek_index[1024], stride;
static const CDImage *cached_image;
static int cached_file = -1;
static unsigned char input_sector[512];
static char line[768], token[261];
static unsigned long input_pos, input_block;

void CDImageInvalidate(void) {
    cached_image = 0;
    cached_file = -1;
}

static int input_char(void) {
    unsigned long block;
    if (input_pos >= input.size)
        return -1;
    block = input_pos >> 9;
    if (block != input_block) {
        if (!FileSeekChecked(&input, block) || !FileReadChecked(&input, input_sector))
            return -2;
        input_block = block;
    }
    return input_sector[input_pos++ & 511];
}

/* Exact tokens, bounded quoted names, CRLF and final lines without a newline. */
static char *word(char **cursor) {
    char *p = *cursor;
    unsigned int n = 0;
    int quote;
    while (*p == ' ' || *p == '\t')
        ++p;
    quote = *p == '"';
    if (quote)
        ++p;
    while (*p && (quote ? *p != '"' : *p != ' ' && *p != '\t')) {
        if (n >= sizeof(token) - 1)
            return 0;
        token[n++] = *p++;
    }
    if (quote) {
        if (*p != '"')
            return 0;
        ++p;
    }
    token[n] = 0;
    *cursor = p;
    return token;
}

static int frame(const char *p, unsigned long *value) {
    unsigned long m = 0, s, f;
    int n = 0;
    while (*p >= '0' && *p <= '9' && n++ < 3)
        m = m * 10 + *p++ - '0';
    if (!n || *p++ != ':')
        return 0;
    if (p[0] < '0' || p[0] > '9' || p[1] < '0' || p[1] > '9' || p[2] != ':')
        return 0;
    s = (p[0] - '0') * 10 + p[1] - '0';
    p += 3;
    if (p[0] < '0' || p[0] > '9' || p[1] < '0' || p[1] > '9' || p[2])
        return 0;
    f = (p[0] - '0') * 10 + p[1] - '0';
    if (s >= 60 || f >= 75)
        return 0;
    *value = (m * 60 + s) * 75 + f;
    return 1;
}

static int add(unsigned long a, unsigned long b, unsigned long *out) {
    if (a > 0xffffffffUL - b)
        return 0;
    *out = a + b;
    return 1;
}

static int layout(CDImage *image) {
    int i;
    unsigned long bytes = 0, end = 0, boundary, length, offset, gap;
    CDTrack *t, *prev = 0;
    for (i = 0; i < image->ntracks; ++i) {
        t = &image->tracks[i];
        if (!t->has1 || (t->has0 && t->index0 > t->index1))
            return CD_IMAGE_INVALID;
        boundary = t->has0 ? t->index0 : t->index1;
        if (!prev || prev->file != t->file) {
            bytes = 0;
            boundary = 0;
        } else {
            if (boundary < prev->index1)
                return CD_IMAGE_INVALID;
            length = boundary - prev->index1;
            if (!length || length > (image->files[prev->file].size - prev->offset) / prev->sector_size)
                return CD_IMAGE_INVALID;
            bytes = prev->offset + length * prev->sector_size;
            if (!add(prev->start, length, &end))
                return CD_IMAGE_INVALID;
            prev->end = end;
        }
        gap = t->index1 - boundary;
        if (gap > (image->files[t->file].size - bytes) / t->sector_size)
            return CD_IMAGE_INVALID;
        offset = bytes + gap * t->sector_size;
        t->offset = offset;
        t->gap = end;
        if (!i)
            t->start = 0; /* first-track lead-in is outside logical media */
        else if (!add(gap, t->pregap, &gap) || !add(end, gap, &t->start))
            return CD_IMAGE_INVALID;
        if (i + 1 == image->ntracks || image->tracks[i + 1].file != t->file) {
            length = image->files[t->file].size - offset;
            if (!length || length % t->sector_size)
                return CD_IMAGE_INVALID;
            if (!add(t->start, length / t->sector_size, &end))
                return CD_IMAGE_INVALID;
            t->end = end;
        }
        prev = t;
    }
    image->blocks = end;
    return image->blocks ? CD_IMAGE_OK : CD_IMAGE_INVALID;
}

int CDImageOpen(CDImage *image, unsigned long directory, const char *name, int cue) {
    int ch, i, result;
    char *p, *w;
    CDTrack *track = 0;
    unsigned long v;
    memset(image, 0, sizeof(*image));
    if (!FileOpenPath(&input, directory, name))
        return CD_IMAGE_IO;
    if (!cue) {
        if (!input.size || input.size % 2048)
            return CD_IMAGE_INVALID;
        image->nfiles = image->ntracks = 1;
        image->files[0].cluster = input.start_cluster;
        image->files[0].size = input.size;
        track = &image->tracks[0];
        track->number = 1;
        track->mode = CD_MODE1;
        track->sector_size = 2048;
        track->has1 = 1;
        return layout(image);
    }
    input_pos = 0;
    input_block = 0xffffffffUL;
    while (input_pos < input.size) {
        i = 0;
        while ((ch = input_char()) >= 0 && ch != '\n') {
            if (ch == '\r')
                continue;
            if (!ch || i >= (int)sizeof(line) - 1)
                return CD_IMAGE_INVALID;
            line[i++] = ch;
        }
        if (ch == -2)
            return CD_IMAGE_IO;
        line[i] = 0;
        p = line;
        w = word(&p);
        if (!w)
            return CD_IMAGE_INVALID;
        if (!*w || *w == ';' || !strcmp(w, "REM") || !strcmp(w, "TITLE") || !strcmp(w, "PERFORMER") ||
            !strcmp(w, "SONGWRITER") || !strcmp(w, "CATALOG") || !strcmp(w, "ISRC"))
            continue;
        if (!strcmp(w, "FILE")) {
            if (image->nfiles >= CD_MAX_TRACKS || (image->nfiles && (!track || track->file != image->nfiles - 1)))
                return CD_IMAGE_INVALID;
            w = word(&p);
            if (!w || !*w || !FileOpenPath(&opened, directory, w))
                return CD_IMAGE_IO;
            w = word(&p);
            if (!w || strcmp(w, "BINARY"))
                return CD_IMAGE_MODE;
            image->files[image->nfiles].cluster = opened.start_cluster;
            image->files[image->nfiles++].size = opened.size;
            track = 0;
        } else if (!strcmp(w, "TRACK")) {
            if (!image->nfiles || image->ntracks >= CD_MAX_TRACKS)
                return CD_IMAGE_INVALID;
            w = word(&p);
            if (!w || !w[0] || !w[1] || w[2] || w[0] < '0' || w[0] > '9' || w[1] < '0' || w[1] > '9')
                return CD_IMAGE_INVALID;
            v = (w[0] - '0') * 10 + w[1] - '0';
            if (!v || (image->ntracks && v != image->tracks[image->ntracks - 1].number + 1UL))
                return CD_IMAGE_INVALID;
            track = &image->tracks[image->ntracks++];
            track->file = image->nfiles - 1;
            track->number = v;
            w = word(&p);
            if (!w)
                return CD_IMAGE_INVALID;
            if (!strcmp(w, "AUDIO")) {
                track->mode = CD_AUDIO;
                track->sector_size = 2352;
            } else if (!strcmp(w, "MODE1/2048")) {
                track->mode = CD_MODE1;
                track->sector_size = 2048;
            } else if (!strcmp(w, "MODE1/2352")) {
                track->mode = CD_MODE1;
                track->sector_size = 2352;
            } else if (!strcmp(w, "MODE2/2352")) {
                track->mode = CD_MODE2;
                track->sector_size = 2352;
            } else if (!strcmp(w, "MODE2/2336")) {
                track->mode = CD_MODE2;
                track->sector_size = 2336;
            } else
                return CD_IMAGE_MODE;
        } else if (!strcmp(w, "INDEX")) {
            if (!track)
                return CD_IMAGE_INVALID;
            w = word(&p);
            if (!w)
                return CD_IMAGE_INVALID;
            if (!strcmp(w, "00"))
                result = 0;
            else if (!strcmp(w, "01"))
                result = 1;
            else
                return CD_IMAGE_MODE;
            w = word(&p);
            if (!w || !frame(w, &v))
                return CD_IMAGE_INVALID;
            if (result) {
                if (track->has1)
                    return CD_IMAGE_INVALID;
                track->has1 = 1;
                track->index1 = v;
            } else {
                if (track->has0 || track->has1)
                    return CD_IMAGE_INVALID;
                track->has0 = 1;
                track->index0 = v;
            }
        } else if (!strcmp(w, "PREGAP")) {
            if (!track || track->pregap)
                return CD_IMAGE_INVALID;
            w = word(&p);
            if (!w || !frame(w, &track->pregap))
                return CD_IMAGE_INVALID;
        } else
            return CD_IMAGE_MODE;
    }
    if (!image->ntracks || !track)
        return CD_IMAGE_INVALID;
    return layout(image);
}

static int select_file(const CDImage *image, int number) {
    unsigned long pos;
    unsigned int n = 0;
    if (cached_image == image && cached_file == number)
        return 1;
    CDImageInvalidate();
    memset(&cache, 0, sizeof(cache));
    cache.size = image->files[number].size;
    cache.cluster = cache.start_cluster = image->files[number].cluster;
    stride = 128;
    while ((cache.size - 1) / 512 / stride >= 1024)
        stride <<= 1;
    for (pos = 0; pos <= (cache.size - 1) / 512; pos += stride) {
        if (!FileSeekChecked(&cache, pos))
            return 0;
        seek_index[n++] = cache.cluster;
    }
    cached_file = number;
    cached_image = image;
    return 1;
}

static int read_bytes(unsigned long offset, unsigned char *out, unsigned int count) {
    unsigned char sector[512];
    unsigned long block, anchor;
    unsigned int n, skip;
    if (offset > cache.size || count > cache.size - offset)
        return 0;
    while (count) {
        block = offset >> 9;
        anchor = block / stride;
        if (cache.sector > block || cache.sector / stride != anchor) {
            cache.sector = anchor * stride;
            cache.cluster = seek_index[anchor];
        }
        if (!FileSeekChecked(&cache, block) || !FileReadChecked(&cache, sector)) {
            CDImageInvalidate();
            return 0;
        }
        skip = offset & 511;
        n = 512 - skip;
        if (n > count)
            n = count;
        memcpy(out, sector + skip, n);
        out += n;
        offset += n;
        count -= n;
    }
    return 1;
}

int CDImageRead(const CDImage *image, unsigned long lba, unsigned char *data) {
    int i;
    const CDTrack *t;
    unsigned long offset;
    unsigned char header[8];
    if (lba >= image->blocks)
        return CD_IMAGE_RANGE;
    for (i = 0; i < image->ntracks && lba >= image->tracks[i].end; ++i)
        ;
    if (i == image->ntracks)
        return CD_IMAGE_RANGE;
    t = &image->tracks[i];
    if (t->mode == CD_AUDIO)
        return CD_IMAGE_MODE;
    if (lba < t->start) {
        memset(data, 0, 2048);
        return CD_IMAGE_OK;
    }
    if (!select_file(image, t->file))
        return CD_IMAGE_IO;
    offset = t->offset + (lba - t->start) * t->sector_size;
    if (t->mode == CD_MODE2) {
        if (t->sector_size == 2352)
            offset += 16;
        if (!read_bytes(offset, header, 8))
            return CD_IMAGE_IO;
        if (memcmp(header, header + 4, 4) || (header[2] & 0x20))
            return CD_IMAGE_MODE;
        offset += 8;
    } else if (t->sector_size == 2352)
        offset += 16;
    return read_bytes(offset, data, 2048) ? CD_IMAGE_OK : CD_IMAGE_IO;
}
