/* GPL-3.0-or-later */
#ifndef CDROM_H
#define CDROM_H

#include "cdrom_image.h"

#define CD_MEDIA_BUSY 5
#define CD_MEDIA_LOCKED 6
#define CD_MEDIA_SLOT 7

void CDResetConfiguration(void);
int CDValidateImage(unsigned long directory, const char *name, int cue);
const char *CDMediaError(int result);
int CDConfigure(unsigned int unit);
void CDDetach(unsigned int unit);
int CDMount(unsigned int unit, unsigned long directory, const char *name, int cue);
int CDEject(unsigned int unit);
int CDMediaPending(unsigned int unit);
int CDMediaPresent(unsigned int unit);
int CDPoll(unsigned int status);
void CDCommand(unsigned char *taskfile, unsigned int unit);

#endif
