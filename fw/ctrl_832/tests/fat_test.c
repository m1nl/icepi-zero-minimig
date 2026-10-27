/* GPL-3.0-or-later. Production FAT operations on a fragmented in-memory disk. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "fat.h"
#include "mmc.h"
#include "swap.h"
extern unsigned long fat_start, data_start, root_directory_start, root_directory_size;
extern unsigned long root_directory_cluster;
extern FATBUFFER fat_buffer;
static unsigned char disk[32][512];
static int failures, direct_reads, fail_read;
static unsigned char out[1536];
void FatalError(int e,const char *s,int a,int b) { (void)e;(void)s;(void)a;(void)b;++failures; }
void SetError(int e,const char *s,int a,int b) { (void)e;(void)s;(void)a;(void)b; }
unsigned char MMC_ReadImpl(unsigned long lba,unsigned char *buffer,int quiet)
{
    assert(lba<32);if(fail_read){if(!quiet)++failures;return 0;}memcpy(buffer,disk[lba],512);return 1;
}
unsigned char MMC_ReadMultipleImpl(unsigned long lba,unsigned char *buffer,unsigned long count,int quiet)
{
    if(quiet && fail_read)return 0;
    unsigned long i;for(i=0;i<count;++i){if(buffer)memcpy(buffer+i*512,disk[lba+i],512);else ++direct_reads;}return 1;
}
unsigned char MMC_WriteImpl(unsigned long lba,unsigned char *buffer,int quiet)
{
    if(quiet && fail_read)return 0;
    assert(lba<32);memcpy(disk[lba],buffer,512);return 1;
}
static void entry(unsigned int slot,const char *name,unsigned int cluster,unsigned int bytes,unsigned char attributes)
{
    DIRENTRY *e=(DIRENTRY*)disk[2];e+=slot;memset(e,0,sizeof(*e));memcpy(e->Name,name,11);
    e->StartCluster=SwapBB(cluster);e->FileSize=SwapBBBB(bytes);e->Attributes=attributes;
}
static void lfn(unsigned int slot,const char *name)
{
    static const unsigned char positions[]={1,3,5,7,9,14,16,18,20,22,24,28,30};
    unsigned int i;unsigned char *p=disk[2]+slot*32;memset(p,0,32);p[0]=0x41;p[11]=ATTR_LFN;
    for(i=0;i<13 && name[i];++i)p[positions[i]]=name[i];
}
int main(void)
{
    fileTYPE f;unsigned int i;
    assert(sizeof(DIRENTRY)==32);
    fat32=0;cluster_size=2;cluster_mask=~1UL;fat_start=1;data_start=4;
    root_directory_start=2;root_directory_size=1;root_directory_cluster=0;fat_buffer.index=~0UL;
    ((unsigned short*)disk[1])[2]=SwapBB(5);((unsigned short*)disk[1])[5]=SwapBB(0xfff8);
    memset(disk[4],0x44,512);memset(disk[5],0x55,512);memset(disk[10],0xaa,512);memset(disk[11],0xbb,512);
    memset(&f,0,sizeof(f));f.start_cluster=f.cluster=2;f.size=2048;f.sector=1;
    assert(FileReadEx(&f,out,3));for(i=0;i<512;++i){assert(out[i]==0x55);assert(out[i+512]==0xaa);assert(out[i+1024]==0xbb);}
    memset(&f,0,sizeof(f));f.start_cluster=f.cluster=2;f.size=2048;f.sector=1;
    assert(FileReadEx(&f,0,3));assert(direct_reads==3);
    assert(!FileSeekChecked(&f,5));assert(!failures);
    memset(&f,0,sizeof(f));f.start_cluster=f.cluster=2;f.size=4096;
    assert(!FileSeekChecked(&f,4));assert(!failures); /* early FAT EOC */
    memset(&f,0,sizeof(f));f.start_cluster=f.cluster=2;f.size=2048;
    fail_read=1;assert(!FileReadChecked(&f,out));assert(!failures);fail_read=0;
    fat32=1;fat_buffer.index=~0UL;
    memset(disk[1],0,512);((unsigned int*)disk[1])[2]=SwapBBBB(5);((unsigned int*)disk[1])[5]=SwapBBBB(0x0ffffff8);
    memset(&f,0,sizeof(f));f.start_cluster=f.cluster=2;f.size=2048;f.sector=1;
    assert(FileReadEx(&f,out,3));assert(out[0]==0x55 && out[512]==0xaa && out[1024]==0xbb);
    memset(&f,0,sizeof(f));f.start_cluster=f.cluster=2;f.size=4096;
    assert(!FileSeekChecked(&f,4));assert(!failures);
    fat32=0;fat_buffer.index=~0UL;
    memset(disk[1],0,512);((unsigned short*)disk[1])[2]=SwapBB(5);((unsigned short*)disk[1])[5]=SwapBB(0xfff8);
    lfn(0,"disc.iso.bak");entry(1,"BACKUP  ISO",2,2048,0);
    lfn(2,"disc.iso");entry(3,"DISC    ISO",5,2048,0);
    assert(FileOpenPath(&f,0,"disc.iso"));assert(f.start_cluster==5);
    assert(FileOpenPath(&f,0,"DISC.ISO"));assert(f.start_cluster==5);
    assert(FileOpenPath(&f,0,"./DISC.ISO"));assert(f.start_cluster==5);
    assert(!FileOpenPath(&f,0,"disc"));assert(!FileOpenPath(&f,0,"missing.iso"));assert(!failures);
    entry(4,"SUBDIR     ",2,0,ATTR_DIRECTORY);
    /* Directory cluster 2 shares the test data area, with its own file entry. */
    memset(disk[4],0,512);memcpy(disk[4],disk[2]+3*32,32);
    assert(FileOpenPath(&f,0,"subdir/disc.iso"));assert(f.start_cluster==5);
    assert(!FileOpenPath(&f,0,"subdir//disc.iso"));assert(!FileOpenPath(&f,0,"subdir/"));
    assert(CurrentDirectory()==0 && !failures);
    memset(&f,0,sizeof(f));f.size=512;f.cluster=f.start_cluster=2;
    fail_read=1;
    assert(!FileReadExChecked(&f,out,1));assert(!FileWriteChecked(&f,out));assert(!failures);
    fail_read=0;f.attributes=ATTR_READONLY;assert(!FileWriteChecked(&f,out));
    f.attributes=0;f.sector=1;assert(!FileWriteChecked(&f,out));assert(!failures);
    puts("PASS: checked FAT I/O returns recoverable failures");
    puts("PASS: buffered/direct cluster crossings, checked errors, exact names and relative paths");return 0;
}
