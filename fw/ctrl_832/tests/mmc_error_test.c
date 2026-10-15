/* GPL-3.0-or-later. Scripted SPI verifies recoverable SD error paths. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define HARDWARE_H
#define RAMFUNC
static unsigned char script[2048], fallback;
static unsigned int length, position, stops, fatal_count;
static unsigned char test_spi(unsigned char value)
{
    if (value==0x4c) ++stops;
    return position<length ? script[position++] : fallback;
}
#define SPI(x) test_spi(x)
#define RDSPI 0xff
#define EnableCard() ((void)0)
#define DisableCard() ((void)0)
#define EnableDMode() ((void)0)
#define DisableDMode() ((void)0)
#define SPI_slow() ((void)0)
#define SPI_fast() ((void)0)
static unsigned long GetTimer(unsigned short ms) { return ms; }
static int CheckTimer(unsigned long deadline) { (void)deadline;return 1; }
static void WaitTimer(unsigned short ms) { (void)ms; }
#include "../mmc.c"
void FatalError(int type,const char *message,int a,int b)
{
    (void)type;(void)message;(void)a;(void)b;++fatal_count;
}
static void begin(void)
{
    length=position=stops=fatal_count=0;fallback=0xff;
    CardType=CARDTYPE_SDHC;sd_lbas=100;
}
static void append(unsigned char value,unsigned int count)
{
    assert(length+count<=sizeof(script));memset(script+length,value,count);length+=count;
}
static void command(unsigned char response_value)
{
    append(0xff,7);append(response_value,1); /* flush, command/CRC, R1 */
}
static void read_sector(void)
{
    append(0xfe,1);append(0x5a,512);append(0xff,2);
}
static void stop(unsigned char response_value,unsigned char ready)
{
    append(0xff,7);append(response_value,1);append(ready,1);
}
int main(void)
{
    unsigned char buffer[512];
    begin();assert(!MMC_ReadMultipleQuiet(100,buffer,1));assert(!fatal_count && !position);
    begin();assert(!MMC_WriteQuiet(100,buffer));assert(!fatal_count && !position);
    begin();command(4);assert(!MMC_ReadMultipleQuiet(0,buffer,1));assert(!fatal_count && !stops);
    begin();command(4);assert(!MMC_WriteQuiet(0,buffer));assert(!fatal_count);
    begin();command(0);read_sector();stop(0,0xff);
    assert(MMC_ReadMultipleQuiet(99,buffer,1));assert(buffer[0]==0x5a && buffer[511]==0x5a && stops==1 && !fatal_count);
    begin();command(0);read_sector();stop(4,0xff);
    assert(!MMC_ReadMultipleQuiet(0,buffer,1));assert(stops==1 && !fatal_count);
    begin();command(0);read_sector();stop(0,0);fallback=0;
    assert(!MMC_ReadMultipleQuiet(0,buffer,1));assert(stops==1 && !fatal_count);
    begin();command(0); /* No data token: timeout must stop the stream. */
    assert(!MMC_ReadMultipleQuiet(0,buffer,1));assert(stops==1 && !fatal_count);
    begin();command(0);append(0xff,516);append(5,1);append(0xff,1);
    assert(MMC_WriteQuiet(99,buffer));assert(!fatal_count);
    begin();command(0);append(0xff,516);append(0x0b,1);
    assert(!MMC_WriteQuiet(0,buffer));assert(!fatal_count);
    begin();command(0);append(0xff,516);append(5,1);fallback=0;
    assert(!MMC_WriteQuiet(0,buffer));assert(!fatal_count);
    begin();assert(!MMC_ReadMultiple(100,buffer,1));assert(fatal_count==1);
    begin();assert(!MMC_Write(100,buffer));assert(fatal_count==1);
    puts("PASS: SD quiet reads/writes, final sector, rejected commands/data, stop failures and timeouts");return 0;
}
