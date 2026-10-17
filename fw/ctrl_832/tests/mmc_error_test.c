/* GPL-3.0-or-later. Scripted SPI verifies recoverable SD error paths. */
#include <assert.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#define HARDWARE_H
#define RAMFUNC
static unsigned char script[2048], fallback;
static unsigned int length, position, stops, fatal_count;
static unsigned long spi_calls;
static unsigned char transmitted[4096], selected[4096];
static int timer_expired = 1, slow_calls, fast_calls;
static int card_selected, fatal_sector, fatal_token;
static char diagnostic_log[2048];
static unsigned int log_size;
static const char *fatal_message;
static int test_printf(const char *format,...)
{
    int count;
    va_list args;
    va_start(args,format);
    count=vsnprintf(diagnostic_log+log_size,sizeof(diagnostic_log)-log_size,format,args);
    va_end(args);
    assert(count>=0 && (unsigned int)count<sizeof(diagnostic_log)-log_size);
    log_size+=count;
    return count;
}
static unsigned char test_spi(unsigned char value)
{
    if (spi_calls < sizeof(transmitted)) {
        transmitted[spi_calls] = value;
        selected[spi_calls] = card_selected;
    }
    ++spi_calls;
    if (value==0x4c) ++stops;
    return position<length ? script[position++] : fallback;
}
#define SPI(x) test_spi(x)
#define RDSPI 0xff
#define EnableCard() (card_selected=1)
#define DisableCard() (card_selected=0)
#define EnableDMode() ((void)0)
#define DisableDMode() ((void)0)
#define SPI_slow() (++slow_calls)
#define SPI_fast() (++fast_calls)
#define TIMER_MS_TO_TICKS(ms) ((unsigned long)(ms)*10UL)
static unsigned long GetTimer(unsigned short ms) { return spi_calls+TIMER_MS_TO_TICKS(ms); }
static int CheckTimer(unsigned long deadline) { (void)deadline;return timer_expired; }
static void WaitTimer(unsigned short ms) { (void)ms; }
#define printf test_printf
#include "../mmc.c"
#define FatalError real_fatal_error
#include "../errors.c"
#undef FatalError
#undef printf
static char osd_lines[8][ERROR_DETAIL_WIDTH];
static unsigned int osd_rows;
void OsdSetTitle(char *text,int arrows) { (void)text;(void)arrows; }
void OsdWrite(unsigned char row,char *text,unsigned char inverse,unsigned char stipple)
{
    (void)inverse;(void)stipple;
    assert(row<8 && strlen(text)<ERROR_DETAIL_WIDTH);
    strcpy(osd_lines[row],text);osd_rows|=1U<<row;
}
void FatalError(int type,const char *message,int a,int b)
{
    assert(type==ERROR_SDCARD);assert(!card_selected);
    fatal_message=message;fatal_sector=a;fatal_token=b;++fatal_count;
    real_fatal_error(type,message,a,b);
}
static void begin(void)
{
    length=position=stops=fatal_count=0;fallback=0xff;
    spi_calls=log_size=0;diagnostic_log[0]=0;card_selected=0;
    fatal_message=0;fatal_sector=fatal_token=0;
    ClearError(ERROR_ALL);osd_rows=0;memset(osd_lines,0,sizeof(osd_lines));
    CardType=CARDTYPE_SDHC;sd_lbas=100;
    timer_expired=1;slow_calls=fast_calls=0;
    memset(transmitted,0,sizeof(transmitted));memset(selected,0,sizeof(selected));
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
/* Verify framing on the wire, not just high-level return values. */
static void assert_released(void)
{
    assert(!card_selected && spi_calls && spi_calls <= sizeof(transmitted));
    assert(!selected[spi_calls-1] && transmitted[spi_calls-1] == 0xff);
}
static void csd(unsigned char version)
{
    unsigned char data[16] = {0};
    data[0] = version;data[5] = 9;
    command(0);append(0xfe,1);
    assert(length+sizeof(data)<=sizeof(script));
    memcpy(script+length,data,sizeof(data));length+=sizeof(data);
    append(0xff,3); /* CRC16 and deselected completion clocks */
}
static void legacy_init(unsigned char first_response)
{
    append(0xff,10); /* startup clocks with CS high */
    command(1);command(5); /* CMD0, unsupported CMD8 */
    command(1);command(first_response); /* CMD55, ACMD41 */
}
static void modern_init(unsigned char ocr_response)
{
    append(0xff,10);command(1);command(1);
    append(0,2);append(1,1);append(0xaa,1); /* R7 */
    command(1);command(0);command(ocr_response);
    if (!ocr_response) { append(0x40,1);append(0,3); }
    append(0xff,1); /* release before capacity read */
}
static void protocol_tests(void)
{
    unsigned char buffer[512];
    unsigned int i;
    begin();command(0);read_sector();
    assert(MMC_ReadQuiet(7,buffer));
    assert(spi_calls==524 && position==length);assert_released();
    assert(selected[522]); /* both CRC bytes were clocked while selected */
    begin();command(4);assert(!MMC_ReadQuiet(7,buffer));assert_released();
    begin();command(0);read_sector();stop(0,0xff);
    assert(MMC_ReadMultipleQuiet(7,buffer,1));assert_released();
    assert(transmitted[523]==CMD12 && transmitted[528]==0x61);
    assert(transmitted[529]==0xff); /* stuff byte */
    begin();command(0);read_sector();stop(4,0xff);
    assert(!MMC_ReadMultipleQuiet(7,buffer,1));assert_released();

    /* Busy must delay command transmission; timeout must send no command. */
    begin();timer_expired=0;append(0,3);command(0);read_sector();
    assert(MMC_ReadQuiet(7,buffer));assert_released();
    for(i=0;i<4;++i) assert(transmitted[i]==0xff && selected[i]);
    assert(transmitted[4]==CMD17);
    begin();fallback=0;
    assert(!MMC_ReadQuiet(7,buffer));
    assert(spi_calls==2 && transmitted[0]==0xff && transmitted[1]==0xff);
    assert_released();
    begin();fallback=0;
    assert(!MMC_WriteQuiet(7,buffer) && spi_calls==2);assert_released();
    begin();fallback=0;
    assert(!MMC_ReadMultipleQuiet(7,buffer,1) && spi_calls==2 && !stops);
    assert_released();
    /* CMD0 must still work when the card is not ready. */
    begin();append(0,1);append(0xff,6);append(1,1);
    EnableCard();assert(MMC_Command(CMD0,0)==1);
    assert(transmitted[1]==CMD0);MMC_Release();assert_released();
    /* R1 begins with zero; bytes with bit 7 set are not responses. */
    begin();append(0xff,7);append(0x80,1);append(0,1);
    EnableCard();assert(MMC_Command(CMD17,7)==0 && spi_calls==9);
    MMC_Release();assert_released();

    begin();CSDData[0]=0x40;command(4);
    assert(!MMC_GetCapacity() && !MMC_GetSectorCount() && fatal_count==1);
    assert_released();
    begin();csd(0x40);assert(MMC_GetCapacity()==1024 && sd_lbas==1024);
    assert_released();
    begin();csd(0x80);assert(!MMC_GetCapacity() && !sd_lbas && fatal_count==1);
    /* Reject malformed CSD without an undefined negative shift. */
    begin();command(0);append(0xfe,1);append(0,16);append(0xff,3);
    assert(!MMC_GetCapacity() && !sd_lbas && fatal_count==1);

    begin();legacy_init(0);command(0);append(0xff,1);csd(0);
    assert(MMC_Init()==CARDTYPE_SD && sd_lbas==4);
    assert(slow_calls==1 && fast_calls==1);assert_released();
    for(i=0;i<10;++i) assert(!selected[i] && transmitted[i]==0xff);
    assert(selected[10] && transmitted[11]==CMD0);
    begin();timer_expired=0;legacy_init(1);command(1);command(0);
    command(0);append(0xff,1);csd(0);
    assert(MMC_Init()==CARDTYPE_SD && sd_lbas==4);assert_released();
    begin();legacy_init(0);command(4);
    assert(MMC_Init()==CARDTYPE_NONE && !sd_lbas && !fast_calls);
    assert_released(); /* failed CMD16 must not publish a usable card */
    begin();legacy_init(0);command(0);append(0xff,1);command(4);
    assert(MMC_Init()==CARDTYPE_NONE && !sd_lbas && fatal_count==1);
    assert_released();
    begin();timer_expired=0;modern_init(0);csd(0x40);
    assert(MMC_Init()==CARDTYPE_SDHC && sd_lbas==1024);assert_released();
    begin();timer_expired=0;modern_init(0);command(4);
    assert(MMC_Init()==CARDTYPE_NONE && !sd_lbas && fatal_count==1);
    assert_released();
    begin();timer_expired=0;modern_init(4);
    assert(MMC_Init()==CARDTYPE_NONE && !sd_lbas && !fast_calls);
    assert_released();
    puts("PASS: SD command framing, completion clocks, busy recovery, initialization and CSD failure propagation");
}
int main(void)
{
    unsigned char buffer[512];
    protocol_tests();
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
    /* CMD17 success and missing-token diagnostics use physical sector numbers. */
    begin();command(0);read_sector();assert(MMC_ReadQuiet(99,buffer));
    assert(buffer[0]==0x5a && buffer[511]==0x5a && !fatal_count && !card_selected && !log_size);
    begin();sd_lbas=65536;command(0);assert(!MMC_Read(0x5de0,buffer));
    assert(fatal_count==1 && fatal_sector==0x5de0 && fatal_token==0xff && !card_selected);
    assert(!strcmp(fatal_message,"CMD17 No data token"));
    assert(strstr(diagnostic_log,"sector=24032 arg=0x5de0 card=3 token=0xFF"));
    assert(strstr(diagnostic_log,"wait=100000 ms polls=1000001"));
    assert(strstr(diagnostic_log,"first=0xFF last=0xFF unexpected=0"));
    begin();command(0);fallback=0;assert(!MMC_ReadQuiet(7,buffer));
    assert(!fatal_count && strstr(diagnostic_log,"no data token"));
    assert(strstr(diagnostic_log,"token=0x00") && strstr(diagnostic_log,"unexpected=1000001"));
    /* Keep anomalous bytes for diagnosis; tolerate them if valid data follows. */
    begin();command(0);append(0xf5,1);append(0,1);append(0x7e,1);
    assert(!MMC_ReadQuiet(7,buffer));
    assert(strstr(diagnostic_log,"first=0xF5 last=0x7E unexpected=3"));
    begin();command(0);append(0,2);append(0x7e,1);read_sector();
    assert(MMC_ReadQuiet(7,buffer) && !log_size);
    /* Every nonzero 0000xxxx token is a card-reported error, not a timeout. */
    {
        unsigned int token;
        for(token=1;token<=15;++token) {
            begin();command(0);append(token,1);memset(buffer,0xa5,sizeof(buffer));
            assert(!MMC_ReadQuiet(7,buffer));
            assert(!fatal_count && !card_selected && spi_calls==10 && !stops);
            assert(buffer[0]==0xa5 && buffer[511]==0xa5);
            assert(strstr(diagnostic_log,"CMD17 data error") && strstr(diagnostic_log,"polls=1"));
        }
        assert(strstr(diagnostic_log,"error=1 cc=1 ecc=1 range=1"));
    }
    begin();CardType=CARDTYPE_SD;command(0);append(4,1);
    assert(!MMC_Read(7,buffer));
    assert(fatal_count==1 && fatal_sector==7 && fatal_token==4);
    assert(!strcmp(fatal_message,"CMD17 Data error"));
    assert(strstr(diagnostic_log,"sector=7 arg=0xe00 card=2 token=0x04"));
    assert(strstr(diagnostic_log,"error=0 cc=0 ecc=1 range=0"));
    /* CMD18 reports the failing sector, retains the command's start argument,
     * and stops the stream before either returning quietly or raising fatal. */
    begin();command(0);read_sector();append(8,1);stop(0,0xff);
    assert(!MMC_ReadMultipleQuiet(98,buffer,2));
    assert(stops==1 && !fatal_count && !card_selected);
    assert(strstr(diagnostic_log,"CMD18 data error: sector=99 arg=0x62"));
    assert(strstr(diagnostic_log,"error=0 cc=0 ecc=0 range=1"));
    begin();command(0);read_sector();append(8,1);stop(4,0xff);
    assert(!MMC_ReadMultiple(98,buffer,2));
    assert(stops==1 && fatal_count==1 && fatal_sector==99 && fatal_token==8);
    assert(!strcmp(fatal_message,"CMD18 Data error"));
    assert(strstr(diagnostic_log,"CMD12 failed, response=0x04"));
    begin();command(4);assert(!MMC_ReadQuiet(7,buffer));
    assert(strstr(diagnostic_log,"CMD17 rejected: sector=7 arg=0x7 card=3 R1=0x04"));
    begin();CardType=CARDTYPE_SD;command(4);assert(!MMC_Read(7,buffer));
    assert(fatal_count==1 && fatal_sector==7 && fatal_token==4);
    begin();CardType=CARDTYPE_SD;command(4);assert(!MMC_ReadMultiple(7,buffer,1));
    assert(fatal_count==1 && fatal_sector==7 && fatal_token==4);
    assert(strstr(diagnostic_log,"CMD18 rejected: sector=7 arg=0xe00 card=2 R1=0x04"));
    /* Render the actual OSD pages without relying on serial output. */
    begin();sd_lbas=65536;command(0);assert(!MMC_ReadQuiet(0x5de0,buffer));
    assert(!fatal_count && !ErrorFatal && (ErrorMask & (1<<ERROR_SDCARD)));
    assert(ErrorPageCount(ERROR_SDCARD)==3);
    DrawErrorPage(ERROR_SDCARD,0);assert(osd_rows==255);
    assert(!strcmp(osd_lines[1]," SD Card 1/3"));
    assert(!strcmp(osd_lines[2]," CMD17 No data token"));
    assert(!strcmp(osd_lines[3]," Sector: 0x5de0") && !strcmp(osd_lines[4]," Arg: 0x5de0"));
    assert(strstr(osd_lines[5],"SDHC/SDXC (blocks)") && strstr(osd_lines[6],"0xFF"));
    DrawErrorPage(ERROR_SDCARD,1);
    assert(!strcmp(osd_lines[3]," Wait: 100000 ms") && !strcmp(osd_lines[4]," Polls: 1000001"));
    assert(!strcmp(osd_lines[5]," First:FF Last:FF") && !strcmp(osd_lines[6]," Unexpected: 0"));
    DrawErrorPage(ERROR_SDCARD,2);
    assert(!strcmp(osd_lines[3]," Card error flags: none"));
    assert(!osd_lines[4][0] && !osd_lines[5][0] && !osd_lines[6][0]);
    assert(ErrorMask & (1<<ERROR_SDCARD)); /* Drawing must not dismiss the error. */
    begin();command(0);read_sector();append(15,1);stop(4,0xff);
    assert(!MMC_ReadMultiple(98,buffer,2));assert(ErrorFatal);
    DrawErrorPage(ERROR_SDCARD,2);
    assert(!strcmp(osd_lines[3]," Err:1 CC:1 ECC:1 Range:1"));
    assert(!strcmp(osd_lines[4]," CMD12 response: 0x04"));
    assert(strstr(osd_lines[0],"FATAL") && strstr(osd_lines[7],"Reboot") && ErrorFatal);
    /* Preserve the first pending snapshot even if further reads fail. */
    begin();CardType=CARDTYPE_SD;command(0);append(4,1);assert(!MMC_ReadQuiet(7,buffer));
    command(0);append(8,1);assert(!MMC_Read(8,buffer));
    assert(ErrorFatal && Errors[ERROR_SDCARD].a==7 && Errors[ERROR_SDCARD].b==4);
    DrawErrorPage(ERROR_SDCARD,0);
    assert(!strcmp(osd_lines[3]," Sector: 0x7") && !strcmp(osd_lines[4]," Arg: 0xe00"));
    assert(strstr(osd_lines[5],"SDSC (bytes)"));
    ClearError(ERROR_ALL);
    assert(!ErrorMask && !ErrorFatal && !Errors[ERROR_SDCARD].details);
    assert(ErrorPageCount(ERROR_SDCARD)==1);
    command(0);append(8,1);assert(!MMC_ReadQuiet(8,buffer));
    DrawErrorPage(ERROR_SDCARD,0);assert(!strcmp(osd_lines[3]," Sector: 0x8"));
    /* Parent-level errors must not overwrite a pending diagnostic snapshot. */
    SetError(ERROR_SDCARD,"SD initialisation failed",0,0);
    assert(ErrorPageCount(ERROR_SDCARD)==3 && Errors[ERROR_SDCARD].a==8);
    /* A new ordinary error after acknowledgement must not inherit old pages. */
    ClearError(ERROR_ALL);
    SetError(ERROR_SDCARD,"Other error",0x12,0x34);
    assert(ErrorPageCount(ERROR_SDCARD)==1);
    DrawErrorPage(ERROR_SDCARD,0);
    assert(!strcmp(osd_lines[3]," Other error"));
    assert(!strcmp(osd_lines[4]," 12") && !strcmp(osd_lines[5]," 34"));
    puts("PASS: OSD diagnostic pages, quiet errors, fatal retention, snapshot stability and acknowledgement");
    puts("PASS: CMD17/CMD18 token diagnostics, decoded card errors, wait timing and failing-sector addresses");
    puts("PASS: SD quiet reads/writes, final sector, rejected commands/data, stop failures and timeouts");return 0;
}
