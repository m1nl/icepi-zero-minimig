#ifndef CONFIG_H
#define CONFIG_H

#include "uart.h"
#include "fat.h"

#define CONFIG_VERSION 3
#define CONFIG_VERSION_EXTROM 2
#define CONFIG_VERSION_ROMPATH 3
#define CONFIG_VERSION_DRIVESOUNDS 3

typedef struct
{
    char name[8];
    char long_name[16];
} kickstartTYPE;

typedef struct
{
    unsigned char lores;
    unsigned char hires;
} filterTYPE;

typedef struct
{
    unsigned char speed;
    unsigned char drives;
} floppyTYPE;

typedef struct
{
    unsigned char enabled;	// 0: Disabled, 1: Hard file, 2: MMC (entire card), 3-6: Partition 1-4 of MMC card
    unsigned char present;
    char name[8];
    char long_name[16];
} hardfileTYPE;

#define ENABLE_IDE_PRIMARY 1
#define ENABLE_IDE_SECONDARY 2

#define ENABLE_CD32_PAD 4

#define MOUSE_SPEED_1_00 0
#define MOUSE_SPEED_0_75 1
#define MOUSE_SPEED_0_50 2
#define MOUSE_SPEED_0_25 3

typedef struct
{
    char          id[8];
    unsigned long version;
    kickstartTYPE kickstart;
    filterTYPE    filter;
    unsigned char memory;
    unsigned char chipset;
    floppyTYPE    floppy;
    unsigned char disable_ar3;
    unsigned char enable_ide;
    unsigned char scanlines;
	unsigned char misc; // Contains extra settings, such as scandoubler
    hardfileTYPE  hardfile[2];
    unsigned char cpu;
	unsigned char fastram;	// Contains fast mem (bit 0 & 1) and turbo chipram (bit 7) settings.
	unsigned char kick13patch;
	unsigned char joystick;
    kickstartTYPE extrom;		// Added in V2 config
	unsigned char drivesounds;	// Added in V3 config
	unsigned char pad1;
	unsigned char pad2;
	unsigned char pad3;
	unsigned long kickdir;	// Directory of kick file.
	unsigned long extromdir;	// Directory of ext rom file.
	unsigned long hdfdir[4]; // Directory for HDF files.  Space for expansion to four devices.
    hardfileTYPE  secondaryhardfile[2]; // hardfile entries for potential secondary IDE devices.
    unsigned char mouse_speed;
    unsigned char x_offset;
    unsigned char y_offset;
    unsigned char video_mode;
} configTYPE;

extern fileTYPE file;	// Temporary file available for use by other modules, to avoid repeated memory usage.
						// Shouldn't be considered persistent.

extern configTYPE config;

#ifdef DEBUG
extern char DebugMode;
extern char DebugMsg[128];

#define DBG(...) do { \
        snprintf(DebugMsg, sizeof(DebugMsg), __VA_ARGS__); \
        if(DebugMode) { \
            DebugMessage(DebugMsg); \
        } \
        puts(DebugMsg); \
    } while (0)

#else
#define DBG(...) do { } while (0)
#endif

#define ERR(...) do { printf(__VA_ARGS__); } while (0)
#define INFO(...) do { printf(__VA_ARGS__); } while (0)

static inline signed char MouseScale(char v) {
    switch (config.mouse_speed) {
        case MOUSE_SPEED_0_75:
            return (v >> 1) + (v >> 2);
        case MOUSE_SPEED_0_50:
            return (v >> 1);
        case MOUSE_SPEED_0_25:
            return (v >> 2);
        default:
            return v;
    }
}

int UploadKickstart(unsigned long dir,char *name);
char UploadActionReplay();
void SetConfigurationFilename(int config);	// Set configuration filename by slot number
unsigned char LoadConfiguration(fileTYPE *cfgfile);	// Can supply NULL to use filename previously set by slot number
unsigned char SaveConfiguration(fileTYPE *cfgfile);	// Can supply NULL to use filename previously set by slot number
unsigned char ConfigurationExists(char *filename);
unsigned char CheckConfiguration(fileTYPE *cfgfile);
int ApplyConfiguration(char reloadkickstart,char applydrives,char ignoreoverclock);

#endif
