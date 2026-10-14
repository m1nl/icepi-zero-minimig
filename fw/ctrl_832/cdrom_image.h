/* Read-only CD image backend. GPL-3.0-or-later. */
#ifndef CDROM_IMAGE_H
#define CDROM_IMAGE_H

#include "fat.h"

#define CD_MAX_TRACKS 99
#define CD_AUDIO 0
#define CD_MODE1 1
#define CD_MODE2 2
#define CD_IMAGE_OK 0
#define CD_IMAGE_INVALID 1
#define CD_IMAGE_IO 2
#define CD_IMAGE_MODE 3
#define CD_IMAGE_RANGE 4

typedef struct {
    unsigned long cluster, size;
} CDImageFile;

typedef struct {
    unsigned long start, end, gap, offset, index0, index1, pregap;
    unsigned short sector_size;
    unsigned char file, number, mode, has0, has1;
} CDTrack;

typedef struct {
    CDImageFile files[CD_MAX_TRACKS];
    CDTrack tracks[CD_MAX_TRACKS];
    unsigned long blocks;
    unsigned char nfiles, ntracks;
} CDImage;

int CDImageOpen(CDImage *image, unsigned long directory, const char *name, int cue);
int CDImageRead(const CDImage *image, unsigned long lba, unsigned char *data);
void CDImageInvalidate(void);

#endif
