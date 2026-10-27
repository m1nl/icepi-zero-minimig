/* GPL-3.0-or-later. Exercise production HDD code with mocked SPI/storage. */
#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

/* Replace memory-mapped hardware only in this native test translation unit. */
#define HARDWARE_H
#define RAMFUNC
#define DISKLED_ON
#define DISKLED_OFF
static unsigned int spi_position, spi_command, last_status, last_error;
static unsigned char read_sector[512], transferred_sector[512];
static int supply_sector;
static unsigned int transferred_bytes;
static unsigned int transport_state, next_transport=1, status_polls, cancel_at_poll;
static unsigned int available_status=0x0c;
static unsigned long test_now;
static int cancel_after_seek, cancel_after_read, cancel_after_write, cancel_on_fifo;
static void test_select(void) { spi_position=0; }
static unsigned char test_spi(unsigned char value)
{
    if (!spi_position) spi_command=value;
    else if (spi_command==0xf0 && spi_position==1) last_status=value;
    else if (spi_command==0x90 && spi_position==9) last_error=value;
    else if (spi_command==0xa0 && spi_position>=6 && transferred_bytes<512)
        transferred_sector[transferred_bytes++]=value;
    if (spi_command==0xb0 && spi_position==517 && cancel_on_fifo)
        transport_state=next_transport;
    if (spi_command==0x80 && spi_position++==20)
        return (unsigned char)((transport_state&63)*4+((transport_state&64) ? 0 : 2));
    if (spi_command!=0x80) ++spi_position;
    return 0x5a;
}
#define EnableFpga() test_select()
#define DisableFpga() ((void)0)
#define SPI(x) test_spi(x)
static unsigned long GetTimer(unsigned short ms) { return test_now+ms; }
static int CheckTimer(unsigned long deadline) { return test_now>=deadline; }
#include "../hdd.c"

configTYPE config;
struct PartitionEntry partitions[4];
int partitioncount=1;
unsigned char fat32;
unsigned long cluster_mask=~1UL;
static unsigned long card_size=4096, opened_size=1024*1024, disk_lba, disk_count;
static unsigned int capacity_calls, reads, writes, seeks, errors;
static int open_ok=1, fail_seek, fail_read, fail_write, index_mapping, fail_after=-1;

unsigned long MMC_GetSectorCount(void) { ++capacity_calls; return card_size; }
unsigned long MMC_GetCapacity(void) { return card_size; }
unsigned char GetFPGAStatus(void) {
    ++test_now;
    if (++status_polls==cancel_at_poll) transport_state=next_transport;
    return available_status;
}
unsigned int FileSeek(fileTYPE *file,unsigned long offset,unsigned long origin)
{
    if (origin==SEEK_CUR) offset+=file->sector;
    assert(offset<=file->size/512);file->sector=offset;++seeks;return 1;
}
unsigned int FileReadEx(fileTYPE *file,unsigned char *buffer,unsigned long count)
{
    assert(file->sector<file->size/512 && count<=file->size/512-file->sector);
    if (buffer) {
        if (supply_sector) { assert(count==1);memcpy(buffer,read_sector,512); }
        else memset(buffer,0,count*512);
    }
    reads+=count;file->sector+=count;return 1;
}
unsigned int FileWrite(fileTYPE *file,unsigned char *buffer)
{
    (void)buffer;assert(file->sector<file->size/512);++writes;return 1;
}
unsigned char MMC_ReadMultipleImpl(unsigned long lba,unsigned char *buffer,unsigned long count,int quiet)
{
    assert(quiet); /* HDD transport must use recoverable SD I/O. */
    if (fail_read) return 0;
    (void)buffer;assert(lba<card_size && count<=card_size-lba);
    disk_lba=lba;disk_count=count;reads+=count;return 1;
}
unsigned char MMC_WriteImpl(unsigned long lba,unsigned char *buffer,int quiet)
{
    assert(quiet);
    if (fail_write) return 0;
    (void)buffer;assert(lba<card_size);disk_lba=lba;++writes;return 1;
}
void SetError(int type,const char *message,int a,int b)
{
    (void)type;(void)message;(void)a;(void)b;++errors;
}
void drivesounds_queueevent(enum DriveSound_Type type) { (void)type; }
int ValidateDirectory(unsigned long directory) { (void)directory;return 1; }
void ChangeDirectory(unsigned long directory) { (void)directory; }
unsigned int FileOpen(fileTYPE *file,const char *name)
{
    memset(file,0,sizeof(*file));
    if (!open_ok) return 0;
    memcpy(file->name,name,11);file->size=opened_size;file->cluster=file->start_cluster=2;return 1;
}
void CDDetach(unsigned int unit) { (void)unit; }
int CDConfigure(unsigned int unit) { (void)unit;return 1; }
int CDMount(unsigned int unit,unsigned long directory,const char *name,int cue)
{
    (void)unit;(void)directory;(void)name;(void)cue;return 0;
}
unsigned int FileSeekChecked(fileTYPE *f,unsigned long sector)
{
    if (cancel_after_seek) transport_state=next_transport;
    if (fail_seek || (fail_after>=0 && seeks==(unsigned int)fail_after)) return 0;
    if (index_mapping) {
        assert(sector<f->size/512);f->sector=sector;f->cluster=2+sector/2;++seeks;return 1;
    }
    return FileSeek(f,sector,SEEK_SET);
}
unsigned int FileReadExChecked(fileTYPE *f,unsigned char *b,unsigned long count)
{
    if (cancel_after_read) transport_state=next_transport;
    return fail_read ? 0 : FileReadEx(f,b,count);
}
unsigned int FileWriteChecked(fileTYPE *f,unsigned char *b)
{
    if (cancel_after_write) transport_state=next_transport;
    return fail_write ? 0 : FileWrite(f,b);
}
static void clear_io(void) { reads=writes=seeks=last_status=last_error=0; }
int main(void)
{
    unsigned char taskfile[8]={0};
    hdfTYPE *drive=&hdf[1];
    unsigned int calls;
    long address;
    memset(drive,0,sizeof(*drive));
    drive->type=HDF_FILE;drive->file.size=95*512;
    drive->cylinders=10;drive->heads=1;drive->sectors=10;
    assert(CacheHardfileCapacity(drive) && drive->total_sectors==95);
    calls=capacity_calls;
    assert(ATA_CheckRange(taskfile,5,9,0,1,1,&address) && address==94);
    assert(!ATA_CheckRange(taskfile,5,9,0,1,2,&address) && last_error==0x10);
    assert(!ATA_CheckRange(taskfile,0,0,0,1,1,&address));
    assert(!ATA_CheckRange(taskfile,1,0,1,1,1,&address));
    taskfile[6]=0x40;assert(!ATA_CheckRange(taskfile,1,0,0,1,1,&address) && last_error==4);taskfile[6]=0;
    assert(capacity_calls==calls);
    drive->type=HDF_FILE|HDF_SYNTHRDB;drive->file.size=64*512;
    drive->cylinders=3;drive->sectors=32;drive->offset=-32;
    assert(CacheHardfileCapacity(drive) && drive->total_sectors==96);
    assert(ATA_CheckRange(taskfile,32,0,0,1,2,&address) && address==31);
    assert(ATA_CheckRange(taskfile,32,2,0,1,1,&address));
    assert(!ATA_CheckRange(taskfile,32,2,0,1,2,&address));

    /* Check actual read/write entry points, with and without the read opt-out. */
    memset(drive,0,sizeof(*drive));drive->type=HDF_FILE;
    drive->file.size=1024;drive->cylinders=1;drive->heads=1;drive->sectors=2;
    drive->index_size=16;drive->total_sectors=1;
    clear_io();ATA_ReadSectors(taskfile,2,0,0,1,1,0);
#ifndef HDD_DISABLE_READ_RANGE_CHECK
    assert(!reads && !seeks && (last_status&IDE_STATUS_ERR));
#else
    assert(reads==1 && !(last_status&IDE_STATUS_ERR));
#endif
    clear_io();ATA_WriteSectors(taskfile,2,0,0,1,1,0);
    assert(!writes && !seeks && (last_status&IDE_STATUS_ERR));
    drive->total_sectors=2;clear_io();ATA_WriteSectors(taskfile,2,0,0,1,1,0);
    assert(writes==1 && last_status==(IDE_STATUS_END|IDE_STATUS_IRQ));
    clear_io();assert(!HardFileSeek(drive,2) && !seeks);
    drive->file.size=2048*512;drive->index_size=9;
    assert(!HardFileSeek(drive,1024) && !seeks);

    /* Sector-zero boot flags apply only to a real RDSK signature. */
    {
        unsigned char expected[512];
        unsigned long flags=0x35, checksum=0x12345678, patched_flags=0x12;
        unsigned long patched_checksum=checksum+flags-patched_flags;
        unsigned int i;
        memset(&hdf[0],0,sizeof(hdf[0]));hdf[0].type=HDF_FILE;
        hdf[0].file.size=512;hdf[0].cylinders=1;hdf[0].heads=1;hdf[0].sectors=1;
        hdf[0].index_size=16;hdf[0].total_sectors=1;
        supply_sector=1;
        for(i=0;i<512;++i)read_sector[i]=(unsigned char)(i*37+11);
        memcpy(read_sector,"DOS\0",4);memcpy(expected,read_sector,512);
        clear_io();transferred_bytes=0;ATA_ReadSectors(taskfile,1,0,0,0,1,0);
        assert(reads==1 && transferred_bytes==512 && !memcmp(transferred_sector,expected,512));
        memcpy(read_sector,"RDSX",4);memcpy(expected,read_sector,512);
        clear_io();transferred_bytes=0;ATA_ReadSectors(taskfile,1,0,0,0,1,0);
        assert(reads==1 && transferred_bytes==512 && !memcmp(transferred_sector,expected,512));
        memcpy(read_sector,"RDSK",4);
        memcpy(read_sector+offsetof(struct RigidDiskBlock,rdb_Flags),&flags,sizeof(flags));
        memcpy(read_sector+offsetof(struct RigidDiskBlock,rdb_ChkSum),&checksum,sizeof(checksum));
        memcpy(expected,read_sector,512);
        memcpy(expected+offsetof(struct RigidDiskBlock,rdb_Flags),&patched_flags,sizeof(patched_flags));
        memcpy(expected+offsetof(struct RigidDiskBlock,rdb_ChkSum),&patched_checksum,sizeof(patched_checksum));
        clear_io();transferred_bytes=0;ATA_ReadSectors(taskfile,1,0,0,0,1,0);
        assert(reads==1 && transferred_bytes==512 && !memcmp(transferred_sector,expected,512));
        supply_sector=0;
        puts("PASS: sector-zero RDB patch preserves non-RDSK data and adjusts valid RDB flags/checksum");
    }

    /* Synthetic RDB/PART generation must fit a single-sector stack buffer. */
    {
        unsigned int sector;
        memset(drive,0,sizeof(*drive));drive->type=HDF_FILE|HDF_SYNTHRDB;
        drive->file.size=64*512;drive->cylinders=3;drive->heads=1;drive->sectors=32;
        drive->offset=-32;drive->index_size=16;drive->total_sectors=96;
        for(sector=1;sector<=2;++sector) {
            clear_io();transferred_bytes=0;
            ATA_ReadSectors(taskfile,sector,0,0,1,1,0);
            assert(transferred_bytes==512 && !reads && !last_error);
        }
        puts("PASS: synthetic RDB and PART fit single-sector stack buffers");
    }

    /* Opening/remounting populates or invalidates the cache. */
    memset(config.hardfile,0,sizeof(config.hardfile));
    config.hardfile[1].enabled=HDF_FILE;memcpy(config.hardfile[1].name,"TEST    ",8);
    assert(OpenHardfile(1) && drive->total_sectors==opened_size/512);
    open_ok=0;assert(!OpenHardfile(1) && !drive->total_sectors && drive->type==HDF_DISABLED);open_ok=1;
    config.hardfile[1].enabled=HDF_FILE|HDF_SYNTHRDB;
    assert(OpenHardfile(1) && drive->total_sectors==opened_size/512+drive->heads*drive->sectors);
    config.hardfile[1].enabled=HDF_CARDPART0;partitions[0].startlba=3072;partitions[0].sectors=1024;
    assert(OpenHardfile(1) && drive->total_sectors==1024);
    calls=capacity_calls;
    clear_io();ATA_WriteSectors(taskfile,1,0,0,1,1,0);
    assert(writes==1 && disk_lba==3072 && capacity_calls==calls);
    clear_io();ATA_ReadSectors(taskfile,1,0,0,1,1,0);
    assert(reads==1 && disk_lba==3072 && disk_count==1 && capacity_calls==calls);
    partitions[0].sectors=1025;
    assert(!OpenHardfile(1) && !drive->total_sectors && !config.hardfile[1].present);
    config.hardfile[1].enabled=HDF_CARD;
    assert(OpenHardfile(1) && drive->total_sectors==card_size);
    config.hardfile[1].enabled=HDF_DISABLED;
    assert(!OpenHardfile(1) && !drive->total_sectors && drive->type==HDF_DISABLED);
    /* Fault injection into real transfer handlers: no false success. */
    memset(drive,0,sizeof(*drive));drive->type=HDF_FILE;
    drive->file.size=1024;drive->cylinders=1;drive->heads=1;drive->sectors=2;
    drive->index_size=16;drive->total_sectors=2;
    clear_io();fail_seek=1;ATA_WriteSectors(taskfile,1,0,0,1,1,0);
    assert(!writes && last_error==4 && last_status==(IDE_STATUS_END|IDE_STATUS_ERR|IDE_STATUS_IRQ|IDE_STATUS_ABORT));fail_seek=0;
    clear_io();fail_write=1;ATA_WriteSectors(taskfile,1,0,0,1,1,0);
    assert(!writes && last_error==4 && (last_status&IDE_STATUS_ERR));fail_write=0;
    clear_io();fail_read=1;ATA_ReadSectors(taskfile,1,0,0,1,1,0);
    assert(!reads && last_error==0x40 && (last_status&IDE_STATUS_ABORT));fail_read=0;
    clear_io();ATA_WriteSectors(taskfile,2,0,0,1,1,0);
    assert(writes==1 && seeks==1 && !(last_status&IDE_STATUS_ERR));
    drive->type=HDF_CARD;drive->file.size=0;drive->offset=0;
    clear_io();fail_write=1;ATA_WriteSectors(taskfile,1,0,0,1,1,0);
    assert(!writes && last_error==4 && (last_status&IDE_STATUS_ERR));fail_write=0;
    clear_io();fail_read=1;ATA_ReadSectors(taskfile,1,0,0,1,1,0);
    assert(!reads && last_error==0x40 && (last_status&IDE_STATUS_ERR));fail_read=0;
    {
        unsigned int n,i;
        unsigned short identify[256];
        const unsigned char invalid[]={3,5,15,17,32,255};
        memset(drive,0,sizeof(*drive));drive->type=HDF_FILE;
        drive->file.size=64*512;drive->file.cluster=drive->file.start_cluster=2;
        drive->cylinders=2;drive->heads=1;drive->sectors=32;
        drive->total_sectors=64;drive->index_size=16;drive->index[0]=2;
        for(n=1;n<=16;n*=2) {
            clear_io();taskfile[2]=n;ATA_SetMultipleMode(taskfile,1);
            assert(drive->sectors_per_block==n && !last_error && !(last_status&IDE_STATUS_ERR));
            IdentifyDevice(identify,1);assert(identify[47]==0x8010 && identify[59]==(0x100|n));
            clear_io();ATA_ReadSectors(taskfile,1,0,0,1,n+1,1);
            assert(reads==n+1 && !(last_status&IDE_STATUS_ERR));
            clear_io();ATA_WriteSectors(taskfile,1,0,0,1,n+1,1);
            assert(writes==n+1 && last_status==(IDE_STATUS_END|IDE_STATUS_IRQ));
        }
        for(i=0;i<sizeof(invalid);++i) {
            clear_io();taskfile[2]=invalid[i];ATA_SetMultipleMode(taskfile,1);
            assert(drive->sectors_per_block==16 && last_error==4 && (last_status&IDE_STATUS_ERR));
        }
        clear_io();taskfile[2]=0;ATA_SetMultipleMode(taskfile,1);
        assert(!drive->sectors_per_block && !last_error && !(last_status&IDE_STATUS_ERR));
        IdentifyDevice(identify,1);assert(identify[59]==0x100);
        /* IDENTIFY response is generated and sent before its local buffer expires. */
        clear_io();transferred_bytes=0;ATA_IdentifyDevice(taskfile,1);
        assert(transferred_bytes==512 && last_status==(IDE_STATUS_END|IDE_STATUS_IRQ));
        for(i=0;i<256;++i) {
            assert(transferred_sector[2*i]==(unsigned char)identify[i]);
            assert(transferred_sector[2*i+1]==(unsigned char)(identify[i]>>8));
        }

        clear_io();ATA_ReadSectors(taskfile,1,0,0,1,1,1);
        assert(last_error==4 && !reads && !seeks);
        clear_io();ATA_WriteSectors(taskfile,1,0,0,1,1,1);
        assert(last_error==4 && !writes && !seeks);
        drive->sectors_per_block=17;
        clear_io();ATA_ReadSectors(taskfile,1,0,0,1,1,1);assert(last_error==4 && !reads);
        clear_io();ATA_WriteSectors(taskfile,1,0,0,1,1,1);assert(last_error==4 && !writes);
        config.hardfile[1].enabled=HDF_FILE;
        assert(OpenHardfile(1) && !drive->sectors_per_block);
        puts("PASS: multiple sizes 1/2/4/8/16, partial blocks, invalid settings, disable, IDENTIFY and reopen reset");
    }
    {
        const unsigned long sizes[]={512,0x03fffe00UL,0x04000000UL,0x04000200UL,
                                     0x08000200UL,0xffc00000UL,0xffc00200UL,0xfffffe00UL,0xffffffffUL};
        unsigned int i,j,count,shift;
        index_mapping=1;
        for(i=0;i<sizeof(sizes)/sizeof(sizes[0]);++i) {
            memset(drive,0,sizeof(*drive));drive->file.size=sizes[i];drive->total_sectors=0x12345678UL;
            clear_io();assert(BuildHardfileIndex(drive));
            shift=drive->index_size-9;count=(((sizes[i]>>9)-1)>>shift)+1;
            assert(count<=1024 && seeks==count && drive->total_sectors==0x12345678UL);
            for(j=0;j<count;++j)assert(drive->index[j]==2+(((unsigned long)j<<shift)/2));
        }
        clear_io();drive->file.size=511;assert(!BuildHardfileIndex(drive) && !seeks && !drive->index_size);
        clear_io();drive->file.size=0;assert(!BuildHardfileIndex(drive) && !seeks && !drive->index_size);
        clear_io();drive->file.size=1024*1024;fail_after=2;
        assert(!BuildHardfileIndex(drive) && seeks==2 && !drive->index_size);
        index_mapping=0;clear_io();config.hardfile[1].enabled=HDF_FILE;
        assert(!OpenHardfile(1) && !drive->index_size && !drive->total_sectors && !config.hardfile[1].present);
        assert(drive->type==HDF_DISABLED);fail_after=-1;
        puts("PASS: bounded index through 4 GiB, stride boundaries, failed seeks and failed-open cleanup");
    }
    /* The 201 MiB PFS3 image ends part way through a calculated cylinder. */
    {
        const unsigned long sectors=411648UL;
        unsigned long original_size=opened_size, first=sectors-1, track;
        unsigned short identify[256];
        int cylinder,head,sector;
        opened_size=sectors*512;
        config.hardfile[1].enabled=HDF_FILE;
        assert(OpenHardfile(1));
        assert(drive->total_sectors==sectors);
        assert(drive->heads==7 && drive->sectors==63 && drive->cylinders==934);
        IdentifyDevice(identify,1);
        assert(identify[1]==934 && identify[54]==934);
        assert(((unsigned long)identify[58]<<16|identify[57])==sectors);
        track=first/drive->sectors;
        cylinder=track/drive->heads;head=track%drive->heads;sector=first%drive->sectors+1;
        clear_io();ATA_ReadSectors(taskfile,sector,cylinder,head,1,1,0);
        assert(reads==1 && drive->file.sector==sectors && !last_error);
        clear_io();ATA_WriteSectors(taskfile,sector,cylinder,head,1,1,0);
        assert(writes==1 && seeks==1 && !last_error);
        assert(ATA_CheckRange(taskfile,sector,cylinder,head,1,1,&address) && address==411647);
        assert(!ATA_CheckRange(taskfile,sector,cylinder,head,1,2,&address));
        assert(!ATA_CheckRange(taskfile,sector+1,cylinder,head,1,1,&address));
#ifndef HDD_DISABLE_READ_RANGE_CHECK
        clear_io();ATA_ReadSectors(taskfile,sector,cylinder,head,1,2,0);
        assert(!reads && !seeks && last_error==0x10);
#endif
        clear_io();ATA_WriteSectors(taskfile,sector,cylinder,head,1,2,0);
        assert(!writes && !seeks && last_error==0x10);
        first=sectors-16;track=first/drive->sectors;
        cylinder=track/drive->heads;head=track%drive->heads;sector=first%drive->sectors+1;
        drive->sectors_per_block=16;
        clear_io();ATA_ReadSectors(taskfile,sector,cylinder,head,1,16,1);
        assert(reads==16 && drive->file.sector==sectors && !last_error);
        /* Exact whole cylinders must not acquire an unnecessary extra cylinder. */
        opened_size=411453UL*512;assert(OpenHardfile(1));
        assert(drive->cylinders==933 && drive->total_sectors==411453UL);
        opened_size=original_size;
        puts("PASS: 201 MiB HDF last block 411647, final multiple block, IDENTIFY and EOF bounds");
    }
    {
        unsigned int which, inactive;
        memset(drive,0,sizeof(*drive));drive->type=HDF_FILE;
        drive->file.size=1024;drive->cylinders=1;drive->heads=1;drive->sectors=2;
        drive->index_size=16;drive->total_sectors=2;drive->sectors_per_block=2;
        ata_generation=0;transport_state=0;
        /* Both waits time out and return ABRT with transport cleanup. */
        for(which=0;which<2;++which) {
            clear_io();available_status=0;test_now=0;
            if(which) ATA_WriteSectors(taskfile,1,0,0,1,1,0);
            else ATA_ReadSectors(taskfile,1,0,0,1,1,0);
            assert(test_now==2000 && !reads && !writes);
            assert(last_error==4 && last_status==(IDE_STATUS_END|IDE_STATUS_IRQ|IDE_STATUS_ERR|IDE_STATUS_ABORT));
        }
        /* Reset (including generation zero) or replacement: leave its status alone. */
        for(inactive=0;inactive<2;++inactive) {
            next_transport=inactive ? 64 : 1;
            for(which=0;which<2;++which) {
                clear_io();transport_state=0;status_polls=0;cancel_at_poll=3;test_now=0;available_status=0;
                if(which) ATA_WriteSectors(taskfile,1,0,0,1,1,0);
                else ATA_ReadSectors(taskfile,1,0,0,1,1,0);
                assert(test_now<2000 && !reads && !writes && !last_error);
                assert(last_status==(which ? IDE_STATUS_REQ : IDE_STATUS_RDY));
            }
            cancel_at_poll=0;available_status=CMD_IDECMD|CMD_IDEDAT;
            /* Ready flags from another command must not be consumed. */
            clear_io();transport_state=0;status_polls=0;cancel_at_poll=1;
            ATA_WriteSectors(taskfile,1,0,0,1,1,0);
            assert(!writes && last_status==IDE_STATUS_REQ);cancel_at_poll=0;
            /* A reset during FAT seek must prevent the direct read from starting. */
            clear_io();transport_state=0;cancel_after_seek=1;
            ATA_ReadSectors(taskfile,2,0,0,1,1,0);
            assert(!reads && !last_error);cancel_after_seek=0;
            /* A storage error after cancellation must not overwrite the new task file. */
            clear_io();transport_state=0;cancel_after_read=1;fail_read=1;
            ATA_ReadSectors(taskfile,2,0,0,1,1,0);
            assert(!last_error && !(last_status&IDE_STATUS_END));cancel_after_read=fail_read=0;
            /* Cancellation during buffered RDB read: no stale sector goes to the FPGA. */
            clear_io();transport_state=0;cancel_after_read=1;transferred_bytes=0;
            ATA_ReadSectors(taskfile,1,0,0,0,1,0);
            assert(reads==1 && !transferred_bytes && !last_error);cancel_after_read=0;
            /* Cancellation during FIFO reception: do not commit that sector. */
            clear_io();transport_state=0;cancel_on_fifo=1;
            ATA_WriteSectors(taskfile,1,0,0,1,1,0);
            assert(!writes && last_status==IDE_STATUS_REQ);cancel_on_fifo=0;
            /* An in-progress write can finish, but no following sector is written. */
            clear_io();transport_state=0;cancel_after_write=1;
            ATA_WriteSectors(taskfile,1,0,0,1,2,1);
            assert(writes==1 && seeks==1 && last_status==IDE_STATUS_REQ);cancel_after_write=0;
        }
        transport_state=0;
        puts("PASS: ATA buffer timeouts, reset/replacement cancellation and stale-write/error suppression");
    }
    puts("PASS: storage-failure propagation and last-sector write");
    puts("PASS: production HDD open/cache, transfer bounds, partition offsets and read-check configuration");
    return 0;
}
