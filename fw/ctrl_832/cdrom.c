/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Copyright 2008, 2009 Jakub Bednarski (original Minimig hdd.c).
 * Alastair M. Robinson (2020 ATA read/write changes in MiST hdd.c).
 * Gyorgy Szombathelyi (MiST ATAPI/CD-ROM implementation).
 *
 * The SPI packet handshake, identification fields and SCSI response conventions
 * are adapted from mist-firmware/hdd.c. The cooperative state machine and live
 * media integration are new for this target. Original author notices retained.
 */

#include "cdrom.h"
#include "hdd.h"
#include <string.h>

static CDImage images[2];
static unsigned int current;

static int cd_unit = -1, loaded, pending, locked, attention;

static unsigned char key, asc, ascq;
static unsigned char buffer[2048];
static unsigned int phase, limit, length, position, generation;
static unsigned long deadline, lba, remaining;

/* phase: 0 idle, 1 command packet, 2 wait for empty FIFO/data producer */
static inline unsigned long be32(const unsigned char *p) {
    return ((unsigned long)p[0] << 24) | ((unsigned long)p[1] << 16) | ((unsigned long)p[2] << 8) | p[3];
}

static inline unsigned int be16(const unsigned char *p) { return ((unsigned int)p[0] << 8) | p[1]; }

static inline void put32(unsigned char *p, unsigned long n) {
    p[0] = n >> 24;
    p[1] = n >> 16;
    p[2] = n >> 8;
    p[3] = n;
}

static inline unsigned int head(void) { return 0xa0 | ((cd_unit & 1) << 4); }

static inline void sense(unsigned char k, unsigned char a, unsigned char q) {
    key = k;
    asc = a;
    ascq = q;
}

static void complete(void) {
    IDEWriteTaskFile(0, 3, 0, 0, 0, head());
    IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ);
    phase = 0;
}

static void fail(unsigned char k, unsigned char a, unsigned char q) {
    sense(k, a, q);
    IDEWriteTaskFile((k << 4) | 4, 3, 0, 0, 0, head());
    IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ | IDE_STATUS_ERR | IDE_STATUS_ABORT);
    phase = 0;
}

static int ready(void) {
    if (attention) {
        unsigned char changed = attention;
        attention = 0;
        fail(6, changed, 0);
        return 0;
    }
    if (!loaded) {
        fail(2, 0x3a, 0);
        return 0;
    }
    return 1;
}

static void commit(void) {
    if (!pending || phase)
        return;
    current ^= 1;
    loaded = images[current].blocks != 0;
    pending = 0;
    attention = 0x28;
    CDImageInvalidate();
}

void CDResetConfiguration(void) {
    if (phase) {
        IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_ABORT);
        phase = 0;
    }
    cd_unit = -1;
    pending = loaded = locked = 0;
    CDImageInvalidate();
}

int CDValidateImage(unsigned long directory, const char *name, int cue) {
    if (pending)
        return CD_MEDIA_BUSY;
    return CDImageOpen(&images[current ^ 1], directory, name, cue);
}

const char *CDMediaError(int result) {
    switch (result) {
        case CD_IMAGE_IO:
            return "CD image file read failed";
        case CD_IMAGE_MODE:
            return "Unsupported CUE layout";
        case CD_MEDIA_BUSY:
            return "CD media change pending";
        case CD_MEDIA_LOCKED:
            return "CD removal is locked";
        case CD_MEDIA_SLOT:
            return "Only one CD-ROM supported";
        default:
            return "Invalid CD image";
    }
}

int CDConfigure(unsigned int unit) {
    if (cd_unit >= 0 && cd_unit != (int)unit)
        return 0;
    cd_unit = unit;
    phase = pending = locked = loaded = attention = 0;
    memset(images, 0, sizeof(images));
    current = 0;
    sense(0, 0, 0);
    CDImageInvalidate();
    return 1;
}

void CDDetach(unsigned int unit) {
    if (cd_unit != (int)unit)
        return;
    phase = pending = loaded = locked = 0;
    cd_unit = -1;
    CDImageInvalidate();
}

int CDMount(unsigned int unit, unsigned long directory, const char *name, int cue) {
    int result;
    if (cd_unit != (int)unit)
        return CD_MEDIA_SLOT;
    if (locked)
        return CD_MEDIA_LOCKED;
    if (pending)
        return CD_MEDIA_BUSY;
    result = CDImageOpen(&images[current ^ 1], directory, name, cue);
    if (result)
        return result;
    pending = 1;
    commit();
    return CD_IMAGE_OK;
}

int CDEject(unsigned int unit) {
    if (cd_unit != (int)unit)
        return CD_MEDIA_SLOT;
    if (locked)
        return CD_MEDIA_LOCKED;
    if (pending)
        return CD_MEDIA_BUSY;
    memset(&images[current ^ 1], 0, sizeof(CDImage));
    pending = 1;
    commit();
    return 0;
}

int CDMediaPending(unsigned int unit) { return cd_unit == (int)unit && pending; }

int CDMediaPresent(unsigned int unit) { return cd_unit == (int)unit && loaded; }

static void response(unsigned int bytes, unsigned int allocation) {
    length = bytes < allocation ? bytes : allocation;
    position = 0;
    remaining = 0;
    if (!length) {
        complete();
        return;
    }
    IDEWriteStatus(IDE_STATUS_RDY | IDE_STATUS_PKT);
    phase = 2;
    deadline = IDEDeadline();
}

static void address(unsigned char *p, unsigned long block, int msf) {
    if (!msf)
        put32(p, block);
    else {
        block += 150;
        p[0] = 0;
        p[1] = block / 4500;
        p[2] = (block / 75) % 60;
        p[3] = block % 75;
    }
}

static void toc(const unsigned char *packet) {
    CDImage *image = &images[current];
    unsigned int i, n = 4, fmt = packet[2] & 15, first = packet[6];
    unsigned char *p;
    if (fmt > 1 || (packet[1] & ~2)) {
        fail(5, 0x24, 0);
        return;
    }
    buffer[2] = fmt ? 1 : image->tracks[0].number;
    buffer[3] = fmt ? 1 : image->tracks[image->ntracks - 1].number;
    if (fmt == 1) {
        for (i = 0; i < image->ntracks && image->tracks[i].mode == CD_AUDIO; ++i)
            ;
        if (i == image->ntracks)
            i = 0;
        p = buffer + 4;
        p[1] = image->tracks[i].mode == CD_AUDIO ? 0x10 : 0x14;
        p[2] = image->tracks[i].number;
        address(p + 4, image->tracks[i].start, packet[1] & 2);
        n += 8;
    } else {
        if (first && first != 0xaa &&
            (first < image->tracks[0].number || first > image->tracks[image->ntracks - 1].number)) {
            fail(5, 0x24, 0);
            return;
        }
        for (i = 0; i < image->ntracks; ++i) {
            if (first == 0xaa || image->tracks[i].number < first)
                continue;
            p = buffer + n;
            p[1] = image->tracks[i].mode == CD_AUDIO ? 0x10 : 0x14;
            p[2] = image->tracks[i].number;
            address(p + 4, image->tracks[i].start, packet[1] & 2);
            n += 8;
        }
        p = buffer + n;
        p[1] = image->tracks[image->ntracks - 1].mode == CD_AUDIO ? 0x10 : 0x14;
        p[2] = 0xaa;
        address(p + 4, image->blocks, packet[1] & 2);
        n += 8;
    }
    buffer[0] = (n - 2) >> 8;
    buffer[1] = n - 2;
    response(n, be16(packet + 7));
}
static void mode_sense(const unsigned char *packet) {
    unsigned int ten = packet[0] == 0x5a, n = ten ? 8 : 4, page = packet[2] & 0x3f;
    unsigned char *p = buffer + n;
    if ((packet[2] >> 6) == 3 || packet[3] || (packet[1] & ~8)) {
        fail(5, 0x24, 0);
        return;
    }
    if (page != 0x2a && page != 1 && page != 0x3f) {
        fail(5, 0x24, 0);
        return;
    }
    if (ten)
        buffer[3] = 0x80;
    else
        buffer[2] = 0x80; /* write protected */
    if (page == 1 || page == 0x3f) {
        p[0] = 1;
        p[1] = 6;
        n += 8;
        p = buffer + n;
    }
    if (page == 0x2a || page == 0x3f) {
        p[0] = 0x2a;
        p[1] = 18;
        if ((packet[2] >> 6) != 1) {
            p[6] = 0x29 | (locked ? 2 : 0); /* tray, lock, eject */
            p[8] = 0x02;
            p[9] = 0xc2;
            p[12] = 0;
            p[13] = 2;
            p[14] = 0x02;
            p[15] = 0xc2;
        }
        n += 20;
    }
    if (ten) {
        buffer[0] = (n - 2) >> 8;
        buffer[1] = n - 2;
    } else
        buffer[0] = n - 1;
    response(n, ten ? be16(packet + 7) : packet[4]);
}

static void dispatch(const unsigned char *packet) {
    unsigned int op = packet[0];
    memset(buffer, 0, sizeof(buffer));
    if (packet[1] & 0xe0) {
        fail(5, 0x25, 0);
        return;
    }
    if ((op == 0 || op == 0x25 || op == 0x43 || op == 0x28 || op == 0xa8) && !ready())
        return;
    switch (op) {
        case 0:
            sense(0, 0, 0);
            complete();
            break;
        case 3:
            if (packet[1] & 1) {
                fail(5, 0x24, 0);
                break;
            }
            buffer[0] = 0x70;
            buffer[2] = key;
            buffer[7] = 10;
            buffer[12] = asc;
            buffer[13] = ascq;
            sense(0, 0, 0);
            response(18, packet[4]);
            break;
        case 0x12:
            if (packet[1] & 3 || packet[2]) {
                fail(5, 0x24, 0);
                break;
            }
            buffer[0] = 5;
            buffer[1] = 0x80;
            buffer[2] = 0;
            buffer[3] = 0x21;
            buffer[4] = 31;
            memcpy(buffer + 8, "MINIMIG ", 8);
            memcpy(buffer + 16, "VIRTUAL CD-ROM  ", 16);
            memcpy(buffer + 32, "1.00", 4);
            response(36, packet[4]);
            break;
        case 0x25:
            if (be32(packet + 2) || packet[8]) {
                fail(5, 0x24, 0);
                break;
            }
            put32(buffer, images[current].blocks - 1);
            put32(buffer + 4, 2048);
            response(8, 8);
            break;
        case 0x43:
            toc(packet);
            break;
        case 0x1a:
        case 0x5a:
            mode_sense(packet);
            break;
        case 0x28:
        case 0xa8:
            if (packet[1] & ~0x18) {
                fail(5, 0x24, 0);
                break;
            }
            lba = be32(packet + 2);
            remaining = op == 0x28 ? be16(packet + 7) : be32(packet + 6);
            if (lba > images[current].blocks || remaining > images[current].blocks - lba) {
                fail(5, 0x21, 0);
                break;
            }
            if (!remaining) {
                complete();
                break;
            }
            length = position = 0;
            phase = 2;
            IDEWriteStatus(IDE_STATUS_RDY | IDE_STATUS_PKT);
            deadline = IDEDeadline();
            break;
        case 0x1b:
            if (packet[4] & ~3 || (packet[1] & ~1)) {
                fail(5, 0x24, 0);
                break;
            }
            if ((packet[4] & 2) && !(packet[4] & 1)) {
                if (locked) {
                    fail(5, 0x53, 2);
                    break;
                }
                if (loaded) {
                    loaded = 0;
                    attention = 0x28;
                    CDImageInvalidate();
                }
            } else if ((packet[4] & 3) == 3 && images[current].blocks && !loaded) {
                loaded = 1;
                attention = 0x28;
                CDImageInvalidate();
            }
            complete();
            break;
        case 0x1e:
            if (packet[4] & ~1) {
                fail(5, 0x24, 0);
                break;
            }
            locked = packet[4] & 1;
            complete();
            break;
        default:
            fail(5, 0x20, 0);
            break;
    }
}

int CDPoll(unsigned int status) {
    unsigned int bytes, last, state;
    int result;
    if (!phase) {
        commit();
        return 0;
    }
    /* A new guest command or reset invalidates the outstanding transfer.
     * The generation is exposed in the unused high byte of taskfile word 7. */
    state = IDETransportState();
    if (state != generation) {
        phase = 0;
        if (state & 64) {
            locked = 0;
            attention = 0x29;
        } else
            sense(0xb, 0x47, 0);
        commit();
        return 0;
    }
    if (IDEExpired(deadline)) {
        fail(0xb, 0x47, 0);
        commit();
        return 1;
    }
    if (phase == 1) {
        if (!(status & CMD_IDEDAT))
            return 1;
        unsigned char packet[12];
        IDEReadPacket(packet);
        dispatch(packet);
        return 1;
    }
    if (!(status & CMD_IDECMD))
        return 1;
    if (position == length && remaining) {
        result = CDImageRead(&images[current], lba, buffer);
        if (result) {
            if (result == CD_IMAGE_RANGE)
                fail(5, 0x21, 0);
            else if (result == CD_IMAGE_MODE)
                fail(5, 0x64, 0);
            else
                fail(3, 0x11, 0);
            return 1;
        }
        ++lba;
        --remaining;
        position = 0;
        length = 2048;
    }
    bytes = length - position;
    if (bytes > limit)
        bytes = limit;
    last = position + bytes == length && !remaining;
    IDEWriteTaskFile(0, 2, 0, bytes & 255, bytes >> 8, head());
    IDEWriteData(buffer + position, bytes);
    position += bytes;
    IDEWriteStatus(IDE_STATUS_IRQ | (last ? IDE_STATUS_END : 0));
    deadline = IDEDeadline();
    if (last)
        phase = 0;
    return 1;
}

static void identify(void) {
    unsigned char id[512];
    unsigned int i;
    memset(id, 0, 512);
    id[0] = 0x80;
    id[1] = 0x85; /* removable CD, 12-byte packets */
    memcpy(id + 20, "00000000000000000001", 20);
    memcpy(id + 46, "1.00    ", 8);
    memset(id + 54, ' ', 40);
    memcpy(id + 54, "MINIMIG VIRTUAL ATAPI CD-ROM", 26);
    for (i = 20; i < 94; i += 2) {
        unsigned char t = id[i];
        id[i] = id[i + 1];
        id[i + 1] = t;
    }
    id[99] = 1;
    id[106] = 1;
    id[164] = 0x14;
    id[165] = 0x42;
    id[252] = 0xfe;
    id[253] = 0xff;
    IDEWriteTaskFile(0, 1, 1, 0x14, 0xeb, head());
    IDEWriteStatus(IDE_STATUS_RDY);
    IDEWriteData(id, 512);
    IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ);
}

void CDCommand(unsigned char *tfr, unsigned int unit) {
    if (cd_unit != (int)unit) {
        IDEWriteTaskFile(4, 0, 0, 0, 0, tfr[6]);
        IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_ERR | IDE_STATUS_IRQ);
        return;
    }
    commit();
    if (tfr[7] == 0xa1) {
        identify();
        return;
    }
    if (tfr[7] == 8 || tfr[7] == 0x90) {
        locked = 0;
        phase = 0;
        sense(0, 0, 0);
        attention = 0x29;
        IDEWriteTaskFile(1, 1, 1, 0x14, 0xeb, head());
        IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ);
        return;
    }
    if (tfr[7] != 0xa0 || (tfr[1] & 3)) {
        IDEWriteTaskFile(4, 1, 1, 0x14, 0xeb, head());
        IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_ERR | IDE_STATUS_IRQ);
        return;
    }
    limit = ((unsigned int)tfr[5] << 8) | tfr[4];
    if (!limit || limit == 0xffff)
        limit = 2048;
    if (limit == 1) {
        fail(5, 0x24, 0);
        return;
    }
    if (limit > 2048)
        limit = 2048;
    /* Non-final data phases contain complete words; final odd responses are
     * padded by the SPI adapter without increasing the reported byte count. */
    if (limit > 1)
        limit &= ~1U;
    generation = IDETransportState();
    IDEWriteTaskFile(0, 1, 0, tfr[4], tfr[5], head());
    IDEWriteStatus(IDE_STATUS_REQ | IDE_STATUS_PKT);
    phase = 1;
    deadline = IDEDeadline();
}
