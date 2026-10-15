/* GPL-3.0-or-later. In-memory I/O and scripted SPI for the production modules. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "cdrom.h"
#include "hdd.h"

struct fixture { const char *name; unsigned char *data; unsigned long size; } fixtures[16];
static int nf, io_fail;
static unsigned char command[12], output[32768];
static unsigned int output_size, tf[6], last_status, gen=1, phases;
static int expired;
static CDImage image;
static unsigned char data[2048];
static void add_file(const char *name, unsigned char *bytes, unsigned long size)
{
    fixtures[nf].name=name; fixtures[nf].data=bytes; fixtures[nf++].size=size;
}
unsigned int FileOpenPath(fileTYPE *file, unsigned long directory, const char *name)
{
    int i; (void)directory;
    for(i=0;i<nf;++i) if(!strcmp(name,fixtures[i].name)) {
        memset(file,0,sizeof(*file)); file->size=fixtures[i].size;
        file->cluster=file->start_cluster=i+2; return 1;
    }
    return 0;
}
unsigned int FileSeekChecked(fileTYPE *file, unsigned long offset)
{
    assert(offset<=file->size/512); if(io_fail) return 0;
    file->sector=offset; return 1;
}
unsigned int FileReadChecked(fileTYPE *file, unsigned char *buffer)
{
    unsigned long offset=file->sector*512, n;
    struct fixture *f=&fixtures[file->start_cluster-2];
    if(io_fail) return 0;
    assert(offset<f->size); n=f->size-offset; if(n>512)n=512;
    memset(buffer,0,512); memcpy(buffer,f->data+offset,n); return 1;
}
void IDEWriteTaskFile(int e,int c,int n,int lo,int hi,int head)
{
    tf[0]=e;tf[1]=c;tf[2]=n;tf[3]=lo;tf[4]=hi;tf[5]=head;
}
void IDEWriteStatus(unsigned int s) { last_status=s; }
void IDEReadPacket(unsigned char *p) { memcpy(p,command,12); }
void IDEWriteData(const unsigned char *p,unsigned int n)
{
    assert(n<=2048); assert(output_size+n<=sizeof(output));
    if(tf[1]==2) { assert(n==(tf[3]|tf[4]<<8));++phases; }
    memcpy(output+output_size,p,n);output_size+=n;
}
unsigned long IDEDeadline(void) { return 1; }
int IDEExpired(unsigned long d) { (void)d;return expired; }
unsigned int IDETransportState(void) { return gen; }
static void start(unsigned int opcode, unsigned int limit)
{
    unsigned char tfr[8]={0};
    ++gen; tfr[7]=0xa0;tfr[4]=limit;tfr[5]=limit>>8;
    output_size=phases=last_status=0; memset(command,0,sizeof(command)); command[0]=opcode;
    CDCommand(tfr,1);
}
static void finish(void)
{
    unsigned int n=0;
    CDPoll(CMD_IDEDAT);
    while(CDPoll(CMD_IDECMD)) assert(++n<10000);
}
static void tur(void) { start(0,2048);finish(); }
static void read_blocks(unsigned int lba,unsigned int count,unsigned int limit)
{
    start(0x28,limit);command[2]=lba>>24;command[3]=lba>>16;command[4]=lba>>8;command[5]=lba;
    command[7]=count>>8;command[8]=count;finish();
}
int main(void)
{
    unsigned char *iso=malloc(5*2048), *raw=calloc(4,2352), *audio=calloc(2,2352);
    unsigned int i;
    const char cue[]="REM test\r\nFILE \"sub dir/raw.bin\" BINARY\r\n TRACK 01 MODE1/2352\n INDEX 01 00:00:00\nFILE \"audio.bin\" BINARY\n TRACK 02 AUDIO\n PREGAP 00:00:02\n INDEX 01 00:00:00";
    const char one[]="FILE \"sub dir/raw.bin\" BINARY\nTRACK 01 MODE1/2352\nINDEX 01 00:00:00\nTRACK 02 AUDIO\nINDEX 00 00:00:02\nINDEX 01 00:00:03\n";
    const char xa[]="FILE \"sub dir/raw.bin\" BINARY\nTRACK 01 MODE2/2352\nINDEX 01 00:00:00\n";
    const char bad[]="FILE \"audio.bin\" WAVE\nTRACK 01 AUDIO\nINDEX 01 00:00:00\n";
    const char truncated[]="FILE \"audio.bin\" BINARY\nTRACK 01 AUDIO\nINDEX 01 00:\n";
    for(i=0;i<5*2048;++i)iso[i]=(i*17+i/2048)&255;
    for(i=0;i<4;++i)memset(raw+i*2352+16,0x30+i,2048);
    add_file("disc.iso",iso,5*2048);add_file("sub dir/raw.bin",raw,4*2352);add_file("audio.bin",audio,2*2352);
    add_file("disc.cue",(unsigned char*)cue,strlen(cue));add_file("one.cue",(unsigned char*)one,strlen(one));
    add_file("xa.cue",(unsigned char*)xa,strlen(xa));add_file("bad.cue",(unsigned char*)bad,strlen(bad));
    add_file("truncated.cue",(unsigned char*)truncated,strlen(truncated));
    assert(!CDImageOpen(&image,0,"disc.iso",0));assert(image.blocks==5);
    assert(!CDImageRead(&image,4,data));assert(!memcmp(data,iso+4*2048,2048));
    assert(CDImageRead(&image,5,data)==CD_IMAGE_RANGE);
    io_fail=1;assert(CDImageRead(&image,0,data)==CD_IMAGE_IO);io_fail=0;
    assert(!CDImageOpen(&image,0,"disc.cue",1));CDImageInvalidate();assert(image.ntracks==2 && image.nfiles==2 && image.blocks==8);
    assert(image.tracks[1].start==6 && image.tracks[0].end==4);
    assert(!CDImageRead(&image,3,data));for(i=0;i<2048;++i)assert(data[i]==0x33);
    assert(CDImageRead(&image,6,data)==CD_IMAGE_MODE);
    assert(!CDImageOpen(&image,0,"one.cue",1));CDImageInvalidate();assert(image.blocks==4 && image.tracks[1].start==3);
    assert(image.tracks[0].end==2 && image.tracks[1].offset==3*2352);
    assert(CDImageOpen(&image,0,"bad.cue",1)==CD_IMAGE_MODE);
    assert(CDImageOpen(&image,0,"truncated.cue",1)==CD_IMAGE_INVALID);
    assert(!CDImageOpen(&image,0,"xa.cue",1));CDImageInvalidate();
    memset(raw+16,0,8);memset(raw+24,0xa5,2048);
    assert(!CDImageRead(&image,0,data));assert(data[0]==0xa5 && data[2047]==0xa5);
    raw[18]=raw[22]=0x20;assert(CDImageRead(&image,0,data)==CD_IMAGE_MODE);
    raw[18]=raw[22]=0;

    assert(CDConfigure(1));assert(!CDConfigure(0));
    {
        unsigned char tfr[8]={0};
        output_size=0;tfr[7]=0xa1;CDCommand(tfr,1);
        assert(output_size==512 && output[0]==0x80 && output[1]==0x85);
        tfr[7]=0xec;CDCommand(tfr,1);
        assert((last_status&IDE_STATUS_ERR) && tf[3]==0x14 && tf[4]==0xeb);
    }
    tur();assert(last_status&IDE_STATUS_ERR);assert(tf[0]>>4==2);
    start(0x12,8);command[4]=35;finish();assert(output_size==35 && phases==5 && output[0]==5);
    assert(!CDMount(1,0,"disc.iso",0));tur();assert(tf[0]>>4==6);tur();assert(!(last_status&IDE_STATUS_ERR));
    read_blocks(1,3,510);assert(output_size==3*2048 && !memcmp(output,iso+2048,output_size));
    start(0xa8,2048);command[5]=3;command[9]=2;finish();
    assert(output_size==4096 && !memcmp(output,iso+3*2048,4096));
    start(0xa8,2048);command[6]=command[7]=command[8]=command[9]=255;finish();
    assert(tf[0]>>4==5 && !output_size);
    read_blocks(0,0,2048);assert(!output_size && !(last_status&IDE_STATUS_ERR));
    read_blocks(4,1,2048);assert(output_size==2048 && !memcmp(output,iso+8192,2048));
    read_blocks(5,1,2048);assert(tf[0]>>4==5 && !output_size);
    start(3,2048);command[4]=18;finish();assert(output[2]==5 && output[12]==0x21);
    start(0x25,2048);finish();assert(output_size==8 && output[3]==4 && output[6]==8);
    start(0x43,2048);command[8]=255;finish();assert(output_size==20 && output[6]==1 && output[14]==0xaa);
    start(0x5a,2048);command[2]=0x2a;command[8]=255;finish();assert(output_size==28 && output[8]==0x2a && !(output[12]&1));
    start(0x1e,2048);command[4]=1;finish();assert(CDEject(1)==CD_MEDIA_LOCKED);
    assert(CDMount(1,0,"disc.cue",1)==CD_MEDIA_LOCKED);
    start(0x1e,2048);finish();assert(!CDMount(1,0,"disc.cue",1));tur();tur();
    start(0x43,2048);command[8]=255;finish();assert(output_size==28 && output[14]==2 && output[13]==0x10);
    assert(CDMount(1,0,"missing.iso",0)==CD_IMAGE_IO);assert(CDMediaPresent(1));
    /* Media replacement while a read is in progress commits at completion. */
    start(0x28,512);command[8]=1;CDPoll(CMD_IDEDAT);CDPoll(CMD_IDECMD);
    assert(!CDMount(1,0,"disc.iso",0));assert(CDEject(1)==CD_MEDIA_BUSY);
    while(CDPoll(CMD_IDECMD)) {}
    tur();assert(tf[0]>>4==6);tur();
    /* Abort and repeated command generation, timeout, and guest tray load. */
    start(0x28,2048);command[8]=1;CDPoll(CMD_IDEDAT);++gen;assert(!CDPoll(0));
    start(0x12,2048);expired=1;CDPoll(0);assert(tf[0]>>4==0xb);expired=0;
    start(0x28,512);command[8]=1;CDPoll(CMD_IDEDAT);CDPoll(CMD_IDECMD);
    expired=1;CDPoll(0);assert(last_status&IDE_STATUS_ABORT);expired=0;
    start(0x1b,2048);command[4]=2;finish();assert(!CDMediaPresent(1));
    start(0x1b,2048);command[4]=3;finish();assert(CDMediaPresent(1));tur();tur();
    assert(!CDEject(1));tur();tur();assert(tf[0]>>4==2);
    start(0xfe,2048);finish(); /* Unsupported commands return illegal request even without media. */
    assert(!CDMount(1,0,"disc.iso",0));tur();start(0xfe,2048);finish();assert(tf[0]>>4==5);
    /* Reset releases a guest lock and reports reset unit attention. */
    start(0x1e,2048);command[4]=1;finish();
    start(0x28,2048);gen=64;assert(!CDPoll(0));gen=1;
    assert(!CDEject(1));
    puts("PASS: ISO/CUE mapping, mixed/multi-file tracks, PIO phases, sense, live media and recovery");
    free(iso);free(raw);free(audio);return 0;
}
