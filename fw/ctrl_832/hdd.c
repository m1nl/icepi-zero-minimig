/*
Copyright 2008, 2009 Jakub Bednarski

This file is part of Minimig

Minimig is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

Minimig is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// 2009-11-22 - read/write multiple implemented

// 2020-11-14 - AMR: Simplified and combined read / readm + write / writem.  AROS IDE now works.

//#include "AT91SAM7S256.h"
//#include "stdio.h"
//#include "string.h"
#include "errors.h"
#include "hardware.h"
#include "fat.h"
#include "hdd.h"
#include "cdrom.h"
#include "hdd_internal.h"
#include "mmc.h"
#include "menu.h"
#include "fpga.h"
#include "config.h"
#include "drivesounds.h"

#include <stdio.h>
#include <string.h>

// hardfile structure
hdfTYPE hdf[HDF_COUNT];

#define DIRECTMODE

static int lastcyl;

static void RDBChecksum(unsigned long *p)
{
	unsigned long count=p[1];
	unsigned long c2;
	long result=0;
	DBG("Generating checksum");
	p[2]=0;
	for(c2=0;c2<count;++c2)
		result+=p[c2];
	p[2]=(unsigned long)-result;
}


// If the hardfile doesn't have a RigidDiskBlock,
// we synthesize one.
static void FakeRDB(unsigned char* sector_buffer,int unit,int block)
{
	int i;
	DBG("Clearing sector buffer");
	// Start by clearing the sector buffer
	for(i=0;i<512;++i)
		sector_buffer[i]=0;

	// If we're asked for LBA 0 we create an RDSK block, and if LBA 1, a PART block.
	switch(block)
	{
		case 0: // RDB
			{
				struct RigidDiskBlock *rdb=(struct RigidDiskBlock *)sector_buffer;
				DBG("Creating RDB...");
				rdb->rdb_ID = 'R'<<24 | 'D' << 16 | 'S' << 8 | 'K';

				rdb->rdb_Summedlongs=0x40;
				rdb->rdb_HostID=0x07;
				rdb->rdb_BlockBytes=0x200;
				rdb->rdb_Flags=0x12; // (Disk ID valid, no LUNs after this one)
				rdb->rdb_BadBlockList=0xffffffff; // We don't provide a bad block list
				rdb->rdb_PartitionList=1;
				rdb->rdb_FileSysHeaderList=0xffffffff;
				rdb->rdb_DriveInit=0xffffffff;
				rdb->rdb_Reserved1[0]=0xffffffff;
				rdb->rdb_Reserved1[1]=0xffffffff;
				rdb->rdb_Reserved1[2]=0xffffffff;
				rdb->rdb_Reserved1[3]=0xffffffff;
				rdb->rdb_Reserved1[4]=0xffffffff;
				rdb->rdb_Reserved1[5]=0xffffffff;
				rdb->rdb_Cylinders=hdf[unit].cylinders;
				rdb->rdb_Sectors=hdf[unit].sectors;
				rdb->rdb_Heads=hdf[unit].heads;
				rdb->rdb_Interleave=1;
				rdb->rdb_Park=rdb->rdb_Cylinders;
				rdb->rdb_WritePreComp=rdb->rdb_Cylinders;
				rdb->rdb_ReducedWrite=rdb->rdb_Cylinders;
				rdb->rdb_StepRate=3;
				rdb->rdb_RDBBlocksLo=0;
				rdb->rdb_RDBBlocksHi=1;
				rdb->rdb_LoCylinder=1;
				rdb->rdb_HiCylinder=rdb->rdb_Cylinders-1;
				rdb->rdb_CylBlocks=rdb->rdb_Heads * rdb->rdb_Sectors;
				rdb->rdb_AutoParkSeconds=0;
				rdb->rdb_HighRDSKBlock=1;
				strcpy(rdb->rdb_DiskVendor,"Do not ");
				strcpy(rdb->rdb_DiskProduct, "repartition!");

				RDBChecksum((unsigned long *)rdb);
			}
			break;
		case 1: // Partition
			{
				struct PartitionBlock *pb=(struct PartitionBlock *)sector_buffer;
				DBG("Creating RDB...");
				pb->pb_ID = 'P'<<24 | 'A' << 16 | 'R' << 8 | 'T';

				pb->pb_Summedlongs=0x40;
				pb->pb_HostID=0x07;
				pb->pb_Next=0xffffffff;
				pb->pb_Flags=0x1; // Bootable
				pb->pb_DevFlags=0;
				strcpy(pb->pb_DriveName," DH0");
				pb->pb_DriveName[0]=3;	// BCPL string

				pb->pb_Environment.de_TableSize=0x10;
				pb->pb_Environment.de_SizeBlock=0x80;
				pb->pb_Environment.de_Surfaces=hdf[unit].heads;
				pb->pb_Environment.de_SectorPerBlock=1;
				pb->pb_Environment.de_BlocksPerTrack=hdf[unit].sectors;
				pb->pb_Environment.de_Reserved=2;
				pb->pb_Environment.de_LowCyl=1;
				pb->pb_Environment.de_HighCyl=hdf[unit].cylinders-1;
				pb->pb_Environment.de_NumBuffers=30;
				pb->pb_Environment.de_MaxTransfer=0x1fffe;
				pb->pb_Environment.de_Mask=0x7ffffffe;
				pb->pb_Environment.de_DosType=0x444f5301;

				RDBChecksum((unsigned long *)pb);
			}
			break;
			break;
		default:
			break;
	}
}


void IdentifyDevice(unsigned short *pBuffer, int unit)
{ // builds Identify Device struct
	char *p;
	int i, x;
	unsigned long total_sectors = hdf[unit].total_sectors;

	hardfileTYPE *hf;
	if(unit<2)
		hf=&config.hardfile[unit];
	else if(unit<4)
		hf=&config.secondaryhardfile[unit-2];
	else
		return;

	memset(pBuffer, 0, 512);

	switch(hdf[unit].type)
	{
		case HDF_FILE | HDF_SYNTHRDB:
		case HDF_FILE:
			DBG("Identify - Type: HDF_FILE");
			pBuffer[0] = 1 << 6; // hard disk
			pBuffer[1] = hdf[unit].cylinders; // cyl count
			pBuffer[3] = hdf[unit].heads; // head count
			pBuffer[6] = hdf[unit].sectors; // sectors per track
			// FIXME - can get serial no from card itself.
			memcpy((char*)&pBuffer[10], "1234567890ABCDEFGHIJ", 20); // serial number - byte swapped
			memcpy((char*)&pBuffer[23], ".100    ", 8); // firmware version - byte swapped
			p = (char*)&pBuffer[27];
			// FIXME - likewise the model name can be fetched from the card.
			if(hdf[unit].type & HDF_SYNTHRDB)
			{
				memcpy(p, "DON'T                                   ", 40);
				p += 8;
				memcpy(p, "REPARTITION!    ", 16);
			}
			else
			{
				memcpy(p, "YAQUBE                                  ", 40); // model name - byte swapped
				p += 8;
				if (hf->long_name[0])
				{
					for (i = 0; (x = hf->long_name[i]) && i < 16; i++) // copy file name as model name
						p[i] = x;
				}
				else
				{
					memcpy(p, hf->name, 8); // copy file name as model name
				}
			}
		//    SwapBytes((char*)&pBuffer[27], 40); //not for 68000
			break;
		case HDF_CARD:
		case HDF_CARDPART0:
		case HDF_CARDPART1:
		case HDF_CARDPART2:
		case HDF_CARDPART3:
			DBG("Identify - Type: HDF_CARD");
			pBuffer[0] = 1 << 6; // hard disk
			pBuffer[1] = hdf[unit].cylinders; // cyl count
			pBuffer[3] = hdf[unit].heads; // head count
			pBuffer[6] = hdf[unit].sectors; // sectors per track
			// FIXME - can get serial no from card itself.
			memcpy((char*)&pBuffer[10], "TC64MiniMigSD0      ", 20); // serial number - byte swapped
			pBuffer[23]+=hdf[unit].type-HDF_CARD;
			memcpy((char*)&pBuffer[23], ".100    ", 8); // firmware version - byte swapped
			p = (char*)&pBuffer[27];
			// FIXME - likewise the model name can be fetched from the card.
			memcpy(p, "YAQUBE                                  ", 40); // model name - byte swapped
			p += 8;
			if(hdf[unit].type==HDF_CARD)
				memcpy(p, "SD/MMC Card", 11); // copy file name as model name
			else
			{
				memcpy(p, "Card Part 1", 11); // copy file name as model name
				p[10]+=hdf[unit].partition;
			}
			//    SwapBytes((char*)&pBuffer[27], 40); //not for 68000
			break;
	}

	pBuffer[47] = 0x8000 | ATA_MULTIPLE_MAX_SECTORS; //maximum sectors per block in Read/Write Multiple command
	pBuffer[59] = 0x0100 | hdf[unit].sectors_per_block; // current multiple mode, valid
	pBuffer[53] = 1;
	pBuffer[54] = hdf[unit].cylinders;
	pBuffer[55] = hdf[unit].heads;
	pBuffer[56] = hdf[unit].sectors;
	pBuffer[57] = (unsigned short)total_sectors;
	pBuffer[58] = (unsigned short)(total_sectors >> 16);
}

static inline unsigned long chs2lba(int cylinder, int head, int sector, int unit)
{
	return(cylinder * hdf[unit].heads + head) * hdf[unit].sectors + sector - 1;
}

void IDEWriteTaskFile(int error,int sector_count,int sector_number,int cylinder_low,int cylinder_high,int drive_head)
{
	EnableFpga();

	SPI(CMD_IDE_REGS_WR); // write task file registers command
	SPI(0x00);
	SPI(0x00); // dummy
	SPI(0x00);
	SPI(0x00); // dummy
	SPI(0x00);



	SPI(0x00); // dummy

	SPI(0x00);
	SPI(0x00);
	SPI(error); // error
	SPI(0x00);
	SPI(sector_count); // sector count
	SPI(0x00);
	SPI(sector_number); //sector number
	SPI(0x00);
	SPI(cylinder_low); // cylinder low
	SPI(0x00);
	SPI(cylinder_high); // cylinder high
	SPI(0x00);
	SPI(drive_head); // drive/head

	DisableFpga();
}

void IDEWriteStatus(unsigned int status)
{
	EnableFpga();

	SPI(CMD_IDE_STATUS_WR);
	SPI(status);
	SPI(0x00);
	SPI(0x00);
	SPI(0x00);
	SPI(0x00);

	DisableFpga();
}

/* Byte-oriented ATAPI SPI adapter. ATA IDENTIFY emits its own LE words. */
void IDEReadPacket(unsigned char *packet)
{
	int i;
	EnableFpga(); SPI(CMD_IDE_DATA_RD);
	for (i=0; i<5; ++i) SPI(0);
	for (i=0; i<12; ++i) packet[i]=SPI(0xff);
	DisableFpga();
}
void IDEWriteData(const unsigned char *data, unsigned int bytes)
{
	unsigned int i;
	EnableFpga(); SPI(CMD_IDE_DATA_WR);
	for (i=0; i<5; ++i) SPI(0);
	for (i=0; i<bytes; ++i) SPI(data[i]);
	if (bytes&1) SPI(0);
	DisableFpga();
}
unsigned long IDEDeadline(void) { return GetTimer(2000); }

int IDEExpired(unsigned long deadline) { return CheckTimer(deadline); }

unsigned int IDETransportState(void)
{
	unsigned int i, meta=0;
	EnableFpga(); SPI(CMD_IDE_REGS_RD);
	for (i=0; i<5; ++i) SPI(0);
	for (i=0; i<8; ++i) { meta=SPI(0); SPI(0); }
	DisableFpga();
	return (meta>>2) | ((meta&2) ? 0 : 64);
}

static unsigned int ata_generation; // Captured with the dispatched task file

// ATA_Recalibrate()
static inline void ATA_Recalibrate(unsigned char* tfr, int unit)
{
	// Recalibrate 0x10-0x1F (class 3 command: no data)
	DBG("Recalibrate");
	IDEWriteTaskFile(0, 0, 1, 0, 0, tfr[6] & 0xF0);
	IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ);
}

// ATA_Diagnostic()
static inline void ATA_Diagnostic(unsigned char* tfr)
{
	// Execute Drive Diagnostic (0x90)
	DBG("IDE: Drive Diagnostic");
	IDEWriteTaskFile(1, 0, 0, 0, 0, 0);
	IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ);
}

// ATA_IdentifyDevice()
void ATA_IdentifyDevice(unsigned char* tfr, int unit)
{
	unsigned short id[256];
	int i;
	// Identify Device (0xec)
	DBG("IDE%d: Identify Device", unit);
	IdentifyDevice(id, unit);
	IDEWriteTaskFile(0, tfr[2], tfr[3], tfr[4], tfr[5], tfr[6]);
	IDEWriteStatus(IDE_STATUS_RDY); // pio in (class 1) command type
	EnableFpga();
	SPI(CMD_IDE_DATA_WR); // write data command
	SPI(0x00);
	SPI(0x00);
	SPI(0x00);
	SPI(0x00);
	SPI(0x00);
	for (i = 0; i < 256; i++) {
		SPI((unsigned char)id[i]);
		SPI((unsigned char)(id[i] >> 8));
	}
	DisableFpga();
	IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ);
}


// ATA_Initialize()
void ATA_Initialize(unsigned char* tfr, int unit)
{
	// Initialize Device Parameters (0x91)
	DBG("Initialize Device Parameters\n");
	IDEWriteTaskFile(0, tfr[2], tfr[3], tfr[4], tfr[5], tfr[6]);
	IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ);
}

static inline int ATA_ValidMultipleSize(unsigned int count)
{
	return count && count <= ATA_MULTIPLE_MAX_SECTORS && !(count & (count - 1));
}

// ATA_SetMultipleMode()
void ATA_SetMultipleMode(unsigned char* tfr, int unit)
{
		unsigned int count = tfr[2];
		/* Zero disables multiple mode; otherwise require a supported power of two. */
		if (count && !ATA_ValidMultipleSize(count)) {
				IDEWriteTaskFile(0x04,tfr[2],tfr[3],tfr[4],tfr[5],tfr[6]); /* ABRT */
				IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ | IDE_STATUS_ERR | IDE_STATUS_ABORT);
				return; /* Preserve the previous valid setting. */
		}
		hdf[unit].sectors_per_block = count;
		DBG("Set Multiple Mode %d\n",count);
		IDEWriteTaskFile(0,tfr[2],tfr[3],tfr[4],tfr[5],tfr[6]);
		IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ);
}


/* Called once when opening an ATA device, after its geometry is known. */
static int CacheHardfileCapacity(hdfTYPE *drive)
{
		unsigned long capacity, prefix = 0, card;

		drive->total_sectors = 0;
		if (!drive->cylinders || !drive->heads || !drive->sectors) return 0;
		switch (drive->type) {
		case HDF_FILE | HDF_SYNTHRDB:
				prefix = (unsigned long)drive->heads * drive->sectors;
				if (drive->offset != -(long)prefix) return 0;
				/* The synthetic cylinder precedes the backing file. */
				/* fall through */
		case HDF_FILE:
				capacity = drive->file.size >> 9;
				if (!capacity || (drive->type == HDF_FILE && drive->offset != 0)) return 0;
				if (capacity > 0xffffffffUL - prefix) return 0;
				capacity += prefix;
				break;
		case HDF_CARD:
				capacity = MMC_GetSectorCount();
				break;
		case HDF_CARDPART0:
		case HDF_CARDPART1:
		case HDF_CARDPART2:
		case HDF_CARDPART3:
				if (drive->partition >= 4 || drive->partition >= partitioncount) return 0;
				card = MMC_GetSectorCount();
				if (partitions[drive->partition].startlba >= card ||
						(unsigned long)drive->offset != partitions[drive->partition].startlba)
						return 0;
				capacity = partitions[drive->partition].sectors;
				if (capacity > card - partitions[drive->partition].startlba) return 0;
				break;
		default:
				return 0;
		}
		/* CHS can have a partial last cylinder; backing storage defines its end. */
		drive->total_sectors = capacity;
		return capacity != 0;
}

/* Hot path: only CHS validation, address conversion and cached-limit checks. */
static int ATA_CheckRange(unsigned char *tfr, int sector, int cylinder, int head, int unit, int count, long *result)
{
		hdfTYPE *drive = &hdf[unit];
		unsigned long lba;
		unsigned int error = 0x10; /* IDNF */

		if (tfr[6] & 0x40) { error = 0x04; goto invalid; } /* LBA mode unsupported */
		if (cylinder < 0 || cylinder >= drive->cylinders ||
				head < 0 || head >= drive->heads || sector < 1 || sector > drive->sectors ||
				count < 1 || count > 256)
				goto invalid;
		lba = chs2lba(cylinder, head, sector, unit);
		if (lba >= drive->total_sectors ||
				(unsigned long)count > drive->total_sectors - lba)
				goto invalid;
		*result = (long)lba;
		return 1;
invalid:
		IDEWriteTaskFile(error, tfr[2], tfr[3], tfr[4], tfr[5], tfr[6]);
		IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ | IDE_STATUS_ERR | IDE_STATUS_ABORT);
		return 0;
}

/* End a failed command without a later success acknowledgement. */
static void ATA_StorageError(unsigned char *tfr, unsigned int error)
{
		IDEWriteTaskFile(error,tfr[2],tfr[3],tfr[4],tfr[5],tfr[6]);
		IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ | IDE_STATUS_ERR | IDE_STATUS_ABORT);
}

/* Generation plus BSY distinguishes an active command from reset/completion. */
static int ATA_CommandActive(void)
{
		return IDETransportState() == ata_generation;
}

/* A cancelled command must not overwrite the replacement command's task file. */
static void ATA_FailCurrent(unsigned char *tfr, unsigned int error)
{
		if (ATA_CommandActive())
				ATA_StorageError(tfr,error);
}

/* Bound each guest-buffer wait; throttle metadata reads while the guest stalls. */
static int ATA_WaitBuffer(unsigned int ready, unsigned char *tfr)
{
		unsigned long deadline = GetTimer(2000);
		unsigned long next_check = GetTimer(2);
		if (!ATA_CommandActive())
				return 0;
		for (;;) {
				if (GetFPGAStatus() & ready)
						return ATA_CommandActive();
				if (CheckTimer(deadline)) {
						ATA_FailCurrent(tfr,0x04); // ABRT, including FIFO/PIO cleanup
						return 0;
				}
				if (CheckTimer(next_check)) {
						if (!ATA_CommandActive())
								return 0;
						next_check = GetTimer(2);
				}
		}
}

// ATA_ReadSectors()
void ATA_ReadSectors(unsigned char* tfr, int sector, int cylinder, int head, int unit, int sector_count, int multiple)
{
	long lba;
	int i;
	int block_count;
	int blk;
	unsigned char sector_buffer[512]; // One sector is processed at a time.

	if (!ATA_CommandActive())
		return;
	if (multiple && !ATA_ValidMultipleSize(hdf[unit].sectors_per_block)) {
		ATA_StorageError(tfr,0x04); /* Multiple mode disabled or invalid. */
		return;
	}

/* Define HDD_DISABLE_READ_RANGE_CHECK to skip command-level read validation.
 * Write validation and the hardfile seek-index guard remain enabled. */
#ifndef HDD_DISABLE_READ_RANGE_CHECK
	if (!ATA_CheckRange(tfr, sector, cylinder, head, unit, sector_count, &lba))
		return;
#else
	lba=chs2lba(cylinder, head, sector, unit);
#endif
	DBG(multiple ? "ReadM %ld, %d" : "Read  %ld, %d",lba,sector_count);

	while (sector_count)
	{
		block_count = multiple ? sector_count : 1;
		if (multiple && block_count > hdf[unit].sectors_per_block)
			block_count = hdf[unit].sectors_per_block;

		if (!ATA_CommandActive())
			return;
		IDEWriteStatus(IDE_STATUS_RDY); // pio in (class 1) command type
		if (!ATA_WaitBuffer(CMD_IDECMD,tfr))
			return;

		/* Advance CHS values */
		blk=block_count;
		while(--blk)
		{
			if (sector == hdf[unit].sectors)
			{
				sector = 1;
				head++;
				if (head == hdf[unit].heads)
				{
					head = 0;
					cylinder++;
				}
			}
			else
				sector++;
		}

		/* Update task file with CHS address */
		IDEWriteTaskFile(0, tfr[2], sector, cylinder, (cylinder >> 8), (tfr[6] & 0xF0) | head);

		IDEWriteStatus(IDE_STATUS_IRQ);

		switch(hdf[unit].type)
		{
			case HDF_FILE | HDF_SYNTHRDB:
			case HDF_FILE:
				if (hdf[unit].file.size)
				{
					blk=block_count;
					// Deal with FakeRDB and the potential for a read_multiple to cross the boundary into actual data.
					while(blk && ((lba+hdf[unit].offset)<0) || (unit==0 && hdf[unit].type==HDF_FILE && lba==0))
					{
						if (!ATA_CommandActive())
							return;
						if(hdf[unit].type==HDF_FILE)
						{
							if (!HardFileSeek(&hdf[unit], lba + hdf[unit].offset) ||
								!FileReadExChecked(&hdf[unit].file, sector_buffer, 1))
								goto read_error;
							/* Apply the boot flags workaround only to an RDB block. */
							if (sector_buffer[0]=='R' && sector_buffer[1]=='D' &&
									sector_buffer[2]=='S' && sector_buffer[3]=='K') {
								struct RigidDiskBlock *rdb = (struct RigidDiskBlock *)sector_buffer;
								rdb->rdb_ChkSum = rdb->rdb_ChkSum + rdb->rdb_Flags - 0x12;
								rdb->rdb_Flags=0x12;
							}
						}
						else
							FakeRDB(sector_buffer,unit,lba);
						if (!ATA_CommandActive())
							return;
						EnableFpga();
						SPI(CMD_IDE_DATA_WR); // write data command
						SPI(0x00); SPI(0x00); SPI(0x00); SPI(0x00); SPI(0x00);
						for (i = 0; i < 512; i++)
						{
							SPI(sector_buffer[i]);
						}
						DisableFpga();
						++lba;
						--blk;
					}
					if(blk) // Any blocks left?
					{
						int j;
#ifdef DIRECTMODE
						if (!ATA_CommandActive())
							return;
						if (!HardFileSeek(&hdf[unit], lba + hdf[unit].offset))
							goto read_error;
						if (!ATA_CommandActive())
							return;
						if (!FileReadExChecked(&hdf[unit].file, 0, blk))
							goto read_error;
						lba+=blk;
#else
						while(blk)
						{
							if (!ATA_CommandActive())
								return;
							if (!HardFileSeek(&hdf[unit], lba + hdf[unit].offset) ||
								!FileReadExChecked(&hdf[unit].file, sector_buffer, 1))
								goto read_error;
							if (!ATA_CommandActive())
								return;
							EnableFpga();
							SPI(CMD_IDE_DATA_WR); // write data command
							SPI(0x00); SPI(0x00); SPI(0x00); SPI(0x00); SPI(0x00);
							for (i = 0; i < 512; i++)
							{
								SPI(sector_buffer[i]);
							}
							DisableFpga();
							++lba;
							--blk;
						}
#endif
					}
				}
				else
					goto read_error;
				break;

			case HDF_CARD:
			case HDF_CARDPART0:
			case HDF_CARDPART1:
			case HDF_CARDPART2:
			case HDF_CARDPART3:
#ifdef DIRECTMODE
				if (!ATA_CommandActive())
					return;
				if (!MMC_ReadMultipleQuiet((unsigned long)lba + (unsigned long)hdf[unit].offset,0,block_count))
					goto read_error;
				lba+=block_count;
#else
				blk=block_count;
				while(blk)
				{
					if (!ATA_CommandActive())
						return;
					if (!MMC_ReadQuiet((unsigned long)lba + (unsigned long)hdf[unit].offset,sector_buffer))
						goto read_error;
					if (!ATA_CommandActive())
						return;
					EnableFpga();
					SPI(CMD_IDE_DATA_WR); // write data command
					SPI(0x00); SPI(0x00); SPI(0x00); SPI(0x00); SPI(0x00);
					for (i = 0; i < 512; i++)
					{
						SPI(sector_buffer[i]);
					}
					DisableFpga();
					++lba;
					--blk;
				}
#endif
				break;
			default:
				goto read_error;
		}

		sector_count-=block_count;

	}
	if(cylinder!=lastcyl)
		drivesounds_queueevent(DRIVESOUND_HDDSTEP);
	lastcyl=cylinder;
	// A final read may already have cleared BSY when the guest drained it.
	if(multiple && ATA_CommandActive())
		IDEWriteStatus(IDE_STATUS_END);
	return;
read_error:
	ATA_FailCurrent(tfr,0x40); /* UNC: data could not be read */
}


// ATA_WriteSectors()
void ATA_WriteSectors(unsigned char* tfr, int sector, int cylinder, int head, int unit, int sector_count, int multiple)
{
	long lba;
	unsigned long card_lba;
	int block_count;
	int i;
	int blk;
	unsigned char sector_buffer[512]; // One sector is processed at a time.

	if (!ATA_CommandActive())
		return;
	if (multiple && !ATA_ValidMultipleSize(hdf[unit].sectors_per_block)) {
		ATA_StorageError(tfr,0x04); /* Multiple mode disabled or invalid. */
		return;
	}

	if (!ATA_CheckRange(tfr, sector, cylinder, head, unit, sector_count, &lba))
		return;
	DBG(multiple ? "WriteM %ld, %d" : "Write  %ld, %d",lba,sector_count);
	card_lba = (unsigned long)lba + (unsigned long)hdf[unit].offset;
	if (hdf[unit].type == (HDF_FILE | HDF_SYNTHRDB)) {
		lba += hdf[unit].offset;
	}

	/* Advance CHS values */
	blk=sector_count;
	while(--blk)
	{
		if (sector == hdf[unit].sectors)
		{
			sector = 1;
			head++;
			if (head == hdf[unit].heads)
			{
				head = 0;
				cylinder++;
			}
		}
		else
			sector++;
	}

	if (!ATA_CommandActive()) {
		return;
	}
	/* Update task file with CHS address */
	IDEWriteTaskFile(0, tfr[2], sector, cylinder, (cylinder >> 8), (tfr[6] & 0xF0) | head);

	IDEWriteStatus(IDE_STATUS_REQ); // pio out (class 2) command type

	if(lba<0)
		SetError(ERROR_HDD,"Write to auto-generated RDB!",lba,0);

	if (hdf[unit].file.size &&
		!HardFileSeek(&hdf[unit], (lba>-1) ? lba : 0))
		goto write_error;

	while (sector_count)
	{
		block_count = multiple ? sector_count : 1;
		if (multiple && block_count > hdf[unit].sectors_per_block)
		block_count = hdf[unit].sectors_per_block;

		while(block_count--)
		{
			if (!ATA_WaitBuffer(CMD_IDEDAT,tfr))
				return;
			EnableFpga();
			SPI(CMD_IDE_DATA_RD); // read data command
			SPI(0x00); SPI(0x00); SPI(0x00); SPI(0x00); SPI(0x00);
			for (i = 0; i < 512; i++)
			sector_buffer[i] = SPI(0xFF);
			DisableFpga();

			if (!ATA_CommandActive())
				return;
			switch(hdf[unit].type)
			{
				case HDF_FILE | HDF_SYNTHRDB:
				case HDF_FILE:
					if (hdf[unit].file.size && (lba>-1))	// Don't attempt to write to fake RDB
					{
						if (!FileWriteChecked(&hdf[unit].file, sector_buffer))
							goto write_error;
						if (!ATA_CommandActive())
							return;
						/* No next-sector seek after the final successful write. */
						if (sector_count > 1 &&
							!FileSeekChecked(&hdf[unit].file, hdf[unit].file.sector + 1))
							goto write_error;
					}
					++lba;
					break;
				case HDF_CARD:
				case HDF_CARDPART0:
				case HDF_CARDPART1:
				case HDF_CARDPART2:
				case HDF_CARDPART3:
					DBG("Write HDF_Card");
					if (!MMC_WriteQuiet(card_lba,sector_buffer))
							goto write_error;
					++card_lba;
					break;
				default:
					goto write_error;
			}
			--sector_count;
		}

		if (!ATA_CommandActive())
			return;
		if (sector_count)
			IDEWriteStatus(IDE_STATUS_IRQ);
		else
			IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ);
	}
	if(cylinder!=lastcyl)
	drivesounds_queueevent(DRIVESOUND_HDDSTEP);
	lastcyl=cylinder;
	return;
write_error:
	ATA_FailCurrent(tfr,0x04); /* ABRT: write could not be completed */
}


void trap()
{
	putchar('t');
}

void trap2()
{
	putchar('T');
}

void HandleIDE(unsigned int c1, unsigned int c2)
{
	unsigned char tfr[8];
	int i;
	int sector;
	int cylinder;
	int head;
	int unit;
	int sector_count;
	int block_count;

	if (CDPoll(c1)) return;
	if (c1 & CMD_IDECMD)
	{
		DISKLED_ON;
		EnableFpga();
		SPI(CMD_IDE_REGS_RD); // read task file registers
		SPI(0x00);
		SPI(0x00);
		SPI(0x00);
		SPI(0x00);
		SPI(0x00);
		for (i = 0; i < 8; i++)
		{
			int t=SPI(0);
			tfr[i] = SPI(0);
			if(i==6)
				unit=((tfr[i]>>4)&1)|((t&1)<<1);
			if (i==7)
				ata_generation=(unsigned int)t>>2;
		}
		DisableFpga();

//		unit = ((tfr[6]<<1)&2)|((tfr[6]>>4)&1); // master/slave selection

		if (hdf[unit].type==HDF_DISABLED) {
		  IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ | IDE_STATUS_ERR);
		  DISKLED_OFF;
		  return;
		}
		sector = tfr[3];
		cylinder = tfr[4] | (tfr[5] << 8);
		head = tfr[6] & 0x0F;
		sector_count = tfr[2];
		if (sector_count == 0) sector_count = 0x100;

//		if (cylinder==444 && head==2 && sector==51)
//			trap();

#ifdef SERIALDEBUG
	DBG("IDE:");
	for (i = 1; i<=7; i++)
		DBG("%02X.",tfr[i]);
	DBG(", C: %d, H: %d, S: %d, count: %d\n", cylinder,head,sector,sector_count);
#endif
		if (HDF_IS_CD(hdf[unit].type)) {
			CDCommand(tfr, unit);
		} else if ((tfr[7] & 0xF0) == ACMD_RECALIBRATE) {
		  ATA_Recalibrate(tfr,  unit);
		} else if (tfr[7] == ACMD_DIAGNOSTIC) {
		  ATA_Diagnostic(tfr);
		} else if (tfr[7] == ACMD_IDENTIFY_DEVICE) {
		  ATA_IdentifyDevice(tfr, unit);
		} else if (tfr[7] == ACMD_INITIALIZE_DEVICE_PARAMETERS) {
		  ATA_Initialize(tfr, unit);
		} else if (tfr[7] == ACMD_SET_MULTIPLE_MODE) {
		  ATA_SetMultipleMode(tfr, unit);
		} else if (tfr[7] == ACMD_READ_SECTORS) {
		  ATA_ReadSectors(tfr, sector, cylinder, head, unit, sector_count,0);
		} else if (tfr[7] == ACMD_READ_MULTIPLE) {
		  ATA_ReadSectors(tfr, sector, cylinder, head, unit, sector_count,1);
		} else if (tfr[7] == ACMD_WRITE_SECTORS) {
		  ATA_WriteSectors(tfr, sector, cylinder, head, unit, sector_count,0);
		} else if (tfr[7] == ACMD_WRITE_MULTIPLE) {
		  ATA_WriteSectors(tfr, sector, cylinder, head, unit, sector_count,1);
		} else {
			ERR("Unknown ATA command\n");

			INFO("IDE:");
			for (i = 1; i < 7; i++)
				INFO("%02X.", tfr[i]);
			INFO("%02X\n", tfr[7]);
			IDEWriteTaskFile(0x04, tfr[2], tfr[3], tfr[4], tfr[5], tfr[6]);
			IDEWriteStatus(IDE_STATUS_END | IDE_STATUS_IRQ | IDE_STATUS_ERR);
		}
		DISKLED_OFF;
		if(cylinder==444 && head==2 && sector==61)
			trap2();
	}
}

void GetHardfileGeometry(hdfTYPE *pHDF)
{ // this function comes from WinUAE, should return the same CHS as WinUAE

	unsigned long total=0;
	unsigned long i, head, cyl, spt;
	long sptt[] = { 63, 127, 255, -1 };
	unsigned long cyllimit=65535;

	switch(pHDF->type)
	{
		case (HDF_FILE | HDF_SYNTHRDB):
			if (pHDF->file.size == 0)
				return;
			// For WinUAE generated hardfiles we have a fixed sectorspertrack of 32, number of heads and cylinders are variable.
			// Make a first guess based on 1 head, then refine that guess until the geometry gives a plausible number of
			// cylinders and also has the correct number of blocks.
			total = pHDF->file.size / 512;
			pHDF->sectors = 32;
			head=1;
			cyl = total/32;
			cyllimit-=1;
			while(head<16 && (cyl>cyllimit || (head*cyl*32)!=total))
			{
				++head;
				cyl=total/(32*head);
			}
			pHDF->heads = head;
			pHDF->cylinders = cyl+1;	// Add a cylinder for the fake RDB.

			if ((head*cyl*32)==total)	// Does the geometry match the size of the underlying hard file?
				return;
			// If not, fall back to regular hardfile geometry aproximations...
			break;
		case HDF_FILE:
			if (pHDF->file.size == 0)
				return;
			total = pHDF->file.size / 512;
			break;
		case HDF_CARD:
			total = MMC_GetCapacity();	// GetCapacity returns number of blocks, not bytes.
			break;
		case HDF_CARDPART0:
		case HDF_CARDPART1:
		case HDF_CARDPART2:
		case HDF_CARDPART3:
			total = partitions[pHDF->partition].sectors;
			break;
		default:
			break;
	}

	for (i = 0; sptt[i] >= 0; i++)
	{
		spt = sptt[i];
		for (head = 4; head <= 16; head++)
		{
			/* Cover the final partial cylinder without overflowing total. */
			cyl = total / (head * spt) + (total % (head * spt) != 0);
			if (total <= 1024 * 1024)
			{
				if (cyl <= 1023)
					break;
			}
			else
			{
				if (cyl < 16383)
					break;
				if (cyl < 32767 && head >= 5)
					break;
				if (cyl <= cyllimit)
					break;
			}
		}
		if (head <= 16)
			break;
	}
	if(pHDF->type == (HDF_FILE | HDF_SYNTHRDB))
		++cyl;	// Add an extra cylinder for the fake RDB
	pHDF->cylinders = (unsigned short)cyl;
	pHDF->heads = (unsigned short)head;
	pHDF->sectors = (unsigned short)spt;
	INFO("Total sectors: %d, cyl: %d, heads: %d, sectors: %d\n",total, cyl, head,spt);
}

int BuildHardfileIndex(hdfTYPE *pHDF)
{
	fileTYPE *file = &pHDF->file;
	unsigned long sectors = file->size >> 9;
	const unsigned int entries = sizeof(pHDF->index) / sizeof(pHDF->index[0]);
	unsigned int shift = 7; // minimum stride: 128 sectors = 64 KiB
	unsigned int count, i;

	pHDF->index_size = 0; // invalid until every required entry is built
	if (!sectors) return 0;
	while (((sectors - 1) >> shift) >= entries)
		++shift;
	count = ((sectors - 1) >> shift) + 1;

	/* Sector offsets cannot wrap at 4 GiB; count is bounded by the table. */
	for (i = 0; i < count; ++i) {
		if (!FileSeekChecked(file, (unsigned long)i << shift))
			return 0;
		pHDF->index[i] = file->cluster;
	}
	pHDF->index_size = shift + 9; // retain the existing byte-stride encoding
	return 1;
}

unsigned char HardFileSeek(hdfTYPE *pHDF, unsigned long lba)
{
	unsigned long shift;
	if (lba >= (pHDF->file.size >> 9) || pHDF->index_size < 9 || pHDF->index_size > 31)
		return 0;
	shift = pHDF->index_size - 9;
	if ((lba >> shift) >= sizeof(pHDF->index) / sizeof(pHDF->index[0]))
		return 0;
	if ((pHDF->file.sector ^ lba) & cluster_mask)
	{ // different clusters
		if ((pHDF->file.sector > lba) || ((pHDF->file.sector ^ lba) & (cluster_mask << (fat32 ? 7 : 8)))) // 7: 128 FAT32 links per sector, 8: 256 FAT16 links per sector
		{ // requested cluster lies before current pointer position or in different FAT sector
			pHDF->file.cluster = pHDF->index[lba >> (pHDF->index_size - 9)];// minus 9 because lba is in 512-byte sectors
			pHDF->file.sector = lba & ~((1UL << shift) - 1);
		}
	}
	return FileSeekChecked(&pHDF->file, lba);
}

unsigned char OpenHardfile(unsigned int unit)
{
	char filename[12];
	unsigned long time;
	hardfileTYPE *hf;
	if(unit<2)
		hf=&config.hardfile[unit];
	else if(unit<4)
		hf=&config.secondaryhardfile[unit-2];
	else
		return(0);

	hdf[unit].total_sectors = 0;
	hdf[unit].index_size = 0;
	hdf[unit].sectors_per_block = 0; // disabled until SET MULTIPLE MODE
	if (!HDF_IS_CD(hf->enabled)) CDDetach(unit);
	switch(hf->enabled)
	{
		case HDF_CDROM:
		case HDF_CDROM_CUE:
			if (!CDConfigure(unit)) {
				hdf[unit].type=HDF_DISABLED; hf->present=0;
				SetError(ERROR_HDD,"Only one CD-ROM supported",unit,0); return 0;
			}
			hdf[unit].type=hf->enabled; hf->present=1;
			hdf[unit].cylinders=hdf[unit].heads=hdf[unit].sectors=0;
			if (hf->name[0]) {
				memcpy(filename,hf->name,8);
				memcpy(filename+8,hf->enabled==HDF_CDROM_CUE ? "CUE" : "ISO",3); filename[11]=0;
				if (CDMount(unit,config.hdfdir[unit],filename,hf->enabled==HDF_CDROM_CUE))
					SetError(ERROR_HDD,"Cannot mount CD image",unit,0);
			}
			return 1;
		case HDF_FILE | HDF_SYNTHRDB:
		case HDF_FILE:
			hdf[unit].type=hf->enabled;
			strncpy(filename, hf->name, 8);
			strcpy(&filename[8], "HDF");

			if (filename[0])
			{
				if(ValidateDirectory(config.hdfdir[unit]))
				{
					ChangeDirectory(config.hdfdir[unit]);
					if (FileOpen(&hdf[unit].file, filename))
					{
						GetHardfileGeometry(&hdf[unit]);

						INFO("HARDFILE %d:\n", unit);
						INFO("file: \"%.8s.%.3s\"\n", hdf[unit].file.name, &hdf[unit].file.name[8]);
						INFO("size: %lu (%lu MB)\n", hdf[unit].file.size, hdf[unit].file.size >> 20);
						INFO("CHS: %u.%u.%u", hdf[unit].cylinders, hdf[unit].heads, hdf[unit].sectors);
						INFO(" (%lu MB)\n", ((((unsigned long) hdf[unit].cylinders) * hdf[unit].heads * hdf[unit].sectors) >> 11));

#ifdef DEBUG
						time = GetTimer(0);
#endif
						if (!BuildHardfileIndex(&hdf[unit])) {
							SetError(ERROR_HDD,"Hardfile index read failed",unit,0);
							goto open_failed;
						}
#ifdef DEBUG
						time = GetTimer(0) - time;
						DEBUG("Hardfile indexed in %lu ms\n", time >> 16);
#endif

						if(hf->enabled & HDF_SYNTHRDB)
							hdf[unit].offset=-(hdf[unit].heads*hdf[unit].sectors);
						else
							hdf[unit].offset=0;

						if (!CacheHardfileCapacity(&hdf[unit])) goto invalid_geometry;
						hf->present = 1;
						return 1;
					}
				}
				else
				{
					hf->present = 0;
					SetError(ERROR_HDD,"Bad hardfile directory",config.hdfdir[unit],0);
				}
			}
			break;
		case HDF_CARD:
			hdf[unit].type=HDF_CARD;
			hf->present = 1;
			hdf[unit].file.size=0;
			hdf[unit].offset=0;
			GetHardfileGeometry(&hdf[unit]);
			if (!CacheHardfileCapacity(&hdf[unit])) goto invalid_geometry;
			return 1;
			break;
		case HDF_CARDPART0:
		case HDF_CARDPART1:
		case HDF_CARDPART2:
		case HDF_CARDPART3:
			hdf[unit].type=hf->enabled;
			hdf[unit].partition=hdf[unit].type-HDF_CARDPART0;
			hf->present = 1;
			hdf[unit].file.size=0;
			hdf[unit].offset=partitions[hdf[unit].partition].startlba;
			GetHardfileGeometry(&hdf[unit]);
			if (!CacheHardfileCapacity(&hdf[unit])) goto invalid_geometry;
			return 1;
			break;
	}
	goto open_failed;
invalid_geometry:
	SetError(ERROR_HDD,"Invalid hardfile geometry or capacity",unit,0);
open_failed:
	hdf[unit].total_sectors = 0;
	hdf[unit].type = HDF_DISABLED;
	hf->present = 0;
	return 0;
}


unsigned char GetHDFFileType(char *filename)
{
	fileTYPE rdbfile;	// We scan for RDB without mounting the file as a unit, so need a file struct specifically for this task.
	unsigned char sector_buffer[512]; // One sector is processed at a time.
	if(FileOpen(&rdbfile,filename))
	{
		int i;
		DBG("Hunting for RDB...");
		for(i=0;i<16 && (unsigned long)i<(rdbfile.size>>9);++i)
		{
			// File offsets are in 512-byte sectors, not bytes.
			if (!FileSeekChecked(&rdbfile, (unsigned long)i) ||
				!FileReadChecked(&rdbfile, sector_buffer))
				return(HDF_FILETYPE_UNKNOWN);
			if(sector_buffer[0]=='R' && sector_buffer[1]=='D' && sector_buffer[2]=='S' && sector_buffer[3]=='K')
				return(HDF_FILETYPE_RDB);
			if(sector_buffer[0]=='D' && sector_buffer[1]=='O' && sector_buffer[2]=='S')
				return(HDF_FILETYPE_DOS);
			if(sector_buffer[0]=='P' && sector_buffer[1]=='F' && sector_buffer[2]=='S')
				return(HDF_FILETYPE_DOS);
			if(sector_buffer[0]=='S' && sector_buffer[1]=='F' && sector_buffer[2]=='S')
				return(HDF_FILETYPE_DOS);
		}
		return(HDF_FILETYPE_UNKNOWN);
	}
	return(HDF_FILETYPE_NOTFOUND);
}


