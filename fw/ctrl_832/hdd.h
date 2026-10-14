#ifndef HDD_H
#define HDD_H
#include "fat.h"

#define CMD_IDECMD 0x04
#define CMD_IDEDAT 0x08

#define CMD_IDE_REGS_RD 0x80
#define CMD_IDE_REGS_WR 0x90
#define CMD_IDE_DATA_WR 0xA0
#define CMD_IDE_DATA_RD 0xB0
#define CMD_IDE_STATUS_WR 0xF0

#define IDE_STATUS_ABORT 0x40
#define IDE_STATUS_PKT 0x20
#define IDE_STATUS_END 0x80
#define IDE_STATUS_IRQ 0x10
#define IDE_STATUS_RDY 0x08
#define IDE_STATUS_REQ 0x04
#define IDE_STATUS_ERR 0x01

#define ACMD_RECALIBRATE 0x10
#define ACMD_IDENTIFY_DEVICE 0xEC
#define ACMD_INITIALIZE_DEVICE_PARAMETERS 0x91
#define ACMD_READ_SECTORS 0x20
#define ACMD_WRITE_SECTORS 0x30
#define ACMD_READ_MULTIPLE 0xC4
#define ACMD_WRITE_MULTIPLE 0xC5
#define ACMD_SET_MULTIPLE_MODE 0xC6
#define ACMD_DIAGNOSTIC 0x90

#define ATA_MULTIPLE_MAX_SECTORS 16

#define HDF_COUNT 4
#define HDF_DISABLED 0
#define HDF_FILE 1
#define HDF_CARD 2
#define HDF_CARDPART0 3
#define HDF_CARDPART1 4
#define HDF_CARDPART2 5
#define HDF_CARDPART3 6
#define HDF_CDROM 7
#define HDF_CDROM_CUE 8
#define HDF_IS_CD(t) ((t)==HDF_CDROM || (t)==HDF_CDROM_CUE)
#define HDF_TYPEMASK 15
#define HDF_SYNTHRDB 128	// Flag to indicate whether we should auto-synthesize a RigidDiskBlock

typedef struct
{
	int			   type;	// Are we using a file, the entire SD card or a partition on the SD card?
    fileTYPE       file;
    unsigned short cylinders;
    unsigned short heads;
    unsigned short sectors;
    unsigned short sectors_per_block;
	unsigned short partition;	// Partition no.
	long  offset;	// If a partition, the lba offset of the partition.  Can be negative if we've synthesized an RDB.
    unsigned long  index[1024];
    unsigned long  index_size;
    unsigned long  total_sectors; // Cached guest-visible capacity, including synthetic RDB
} hdfTYPE;

void IdentifyDevice(unsigned short *pBuffer, int unit);
void IDEWriteTaskFile(int error,int sector_count,int sector_number,int cylinder_low,int cylinder_high,int drive_head);
void IDEWriteStatus(unsigned int status);
void HandleIDE(unsigned int c1, unsigned int c2);

/* Shared IDE SPI/timer transport, implemented in hdd.c. */
void IDEReadPacket(unsigned char *packet);
void IDEWriteData(const unsigned char *data, unsigned int bytes);
unsigned long IDEDeadline(void);
int IDEExpired(unsigned long deadline);
unsigned int IDETransportState(void);

void GetHardfileGeometry(hdfTYPE *hdf);
int BuildHardfileIndex(hdfTYPE *hdf);
unsigned char HardFileSeek(hdfTYPE *hdf, unsigned long lba);
unsigned char OpenHardfile(unsigned int unit);

#define HDF_FILETYPE_UNKNOWN 0
#define HDF_FILETYPE_NOTFOUND 1
#define HDF_FILETYPE_RDB 2
#define HDF_FILETYPE_DOS 3

unsigned char GetHDFFileType(char *filename);

extern hdfTYPE hdf[HDF_COUNT];

#endif
