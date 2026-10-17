/* GPL-3.0-or-later. Exercise the production bootstrap SD reader. */
#include <assert.h>
#include <stdio.h>
#include <string.h>
#define SPI_H
static unsigned char replies[8192], transmitted[8192], selected[8192], fallback;
static unsigned int length, position, calls;
static int card_selected, slow_calls, fast_calls;
static unsigned long ticks, timer_step;
static unsigned long timer(void) { ticks+=timer_step;return ticks; }
static unsigned char transfer(unsigned char byte)
{
    if(calls<sizeof(transmitted)) {
        transmitted[calls]=byte;selected[calls]=card_selected;
    }
    ++calls;
    return position<length ? replies[position++] : fallback;
}
#define SPI(x) transfer((unsigned char)(x))
#define HW_TIMER timer()
#define EnableCard() (card_selected=1)
#define DisableCard() (card_selected=0)
#define SPI_slow() (++slow_calls)
#define SPI_fast() (++fast_calls)
#include "../../ctrl_boot_832/spi.c"

static void begin(void)
{
    length=position=calls=0;fallback=0xff;
    card_selected=slow_calls=fast_calls=0;card_type=0;
    ticks=0;timer_step=1;
    memset(transmitted,0,sizeof(transmitted));memset(selected,0,sizeof(selected));
}
static void append(unsigned char value,unsigned int count)
{
    assert(length+count<=sizeof(replies));
    memset(replies+length,value,count);length+=count;
}
static void command(unsigned char response)
{
    append(0xff,7);append(response,1); /* ready, 6-byte command, R1 */
}
static void reset(void)
{
    append(0xff,200);command(1);
}
static void modern(unsigned char response)
{
    reset();command(1);append(0,2);append(1,1);append(0xaa,1);
    command(1);command(0);command(response); /* CMD55, ACMD41, CMD58 */
}
static void ocr(unsigned char high)
{
    append(high,1);append(0xff,1);append(0x80,1);append(0,1);
}
static void legacy(int mmc,unsigned char response)
{
    reset();command(5);command(mmc ? 5 : 1);command(0);command(response);
}
static void released(void)
{
    assert(!card_selected && calls && calls<=sizeof(transmitted));
    assert(!selected[calls-1] && transmitted[calls-1]==0xff);
}
static void block(void)
{
    unsigned int i;
    append(0xfe,1);
    for(i=0;i<512;++i) append((unsigned char)i,1);
    append(0xab,1);append(0xcd,1);append(0xff,1); /* CRC16, release */
}
int main(void)
{
    unsigned char buffer[514];
    unsigned int i,offset;
    begin();modern(0);ocr(0xc0);
    assert(spi_init() && card_type==2 && slow_calls==1 && !fast_calls);
    released();
    for(i=0;i<200;++i) assert(!selected[i] && transmitted[i]==0xff);
    assert(transmitted[201]==0x40 && transmitted[206]==0x95);
    assert(transmitted[209]==0x48 && transmitted[214]==0x87);
    offset=calls;command(0);block();memset(buffer,0xa5,sizeof(buffer));
    /* An unaligned destination must preserve all bytes and both guard bytes. */
    assert(sd_read_sector(0x123456,buffer+1));released();
    assert(position==length && calls-offset==524 && fast_calls==1);
    assert(transmitted[offset+1]==0x51 && transmitted[offset+2]==0);
    assert(transmitted[offset+3]==0x12 && transmitted[offset+4]==0x34 && transmitted[offset+5]==0x56);
    assert(selected[offset+521] && selected[offset+522] && !selected[offset+523]);
    assert(buffer[0]==0xa5 && buffer[513]==0xa5);
    for(i=0;i<512;++i) assert(buffer[i+1]==(unsigned char)i);

    begin();legacy(0,0);assert(spi_init() && card_type==1);released();
    /* CMD16 argument is 512 bytes, not an LBA subjected to another shift. */
    assert(transmitted[233]==0x50 && transmitted[234]==0 && transmitted[235]==0);
    assert(transmitted[236]==2 && transmitted[237]==0);
    offset=calls;command(0);block();assert(sd_read_sector(7,buffer));released();
    assert(transmitted[offset+2]==0 && transmitted[offset+3]==0);
    assert(transmitted[offset+4]==0x0e && transmitted[offset+5]==0);
    offset=calls;assert(!sd_read_sector(0x800000,buffer) && calls==offset);
    begin();legacy(1,0);assert(spi_init() && card_type==1);released();
    begin();modern(0);ocr(0x80);command(0);
    assert(spi_init() && card_type==1);released(); /* v2 SDSC also sets block length */
    begin();reset();command(5);command(1);command(1);command(1);command(0);command(0);
    assert(spi_init() && card_type==1);released(); /* delayed ACMD41 */
    begin();legacy(0,4);assert(!spi_init() && !card_type);released();
    begin();modern(4);assert(!spi_init() && !card_type);released();
    begin();modern(0);ocr(0x40);assert(!spi_init() && !card_type);released(); /* invalid OCR */
    begin();reset();command(1);append(0,4);
    assert(!spi_init() && !card_type);released(); /* bad CMD8 echo */
    begin();reset();command(4);assert(!spi_init() && !card_type);released();
    begin();reset();command(5);command(1);command(4);
    assert(!spi_init() && !card_type);released(); /* ACMD41 rejected */
    begin();timer_step=11290000;reset();command(5);command(1);command(1);
    assert(!spi_init() && !card_type);released(); /* ACMD41 timeout */
    begin();assert(!spi_init() && !card_type);released(); /* absent card, bounded reset retries */
    offset=calls;assert(!sd_read_sector(0,buffer) && calls==offset);

    begin();card_type=2;command(4);memset(buffer,0xa5,sizeof(buffer));
    assert(!sd_read_sector(0,buffer) && buffer[0]==0xa5);released();
    for(i=1;i<16;++i) {
        begin();card_type=2;command(0);append(i,1);
        assert(!sd_read_sector(0,buffer) && calls==10);released();
    }
    begin();card_type=2;timer_step=11290000;command(0);
    assert(!sd_read_sector(0,buffer) && calls==10);released(); /* missing token */
    begin();card_type=2;timer_step=11290000;fallback=0;
    assert(!sd_read_sector(0,buffer) && calls==2);released(); /* busy: no command sent */
    assert(transmitted[0]==0xff && transmitted[1]==0xff);
    begin();card_type=2;append(0,3);command(0);block();
    assert(sd_read_sector(0,buffer));released();assert(transmitted[4]==0x51);
    begin();append(0xff,7);append(0x80,1);append(0,1);EnableCard();
    assert(sd_command(0x51,0)==0 && calls==9);sd_release();released();
    begin();append(0,1);append(0xff,6);append(1,1);EnableCard();
    assert(sd_command(0x40,0)==1 && calls==8);sd_release();released();
    puts("PASS: bootstrap SDHC/SDSC/MMC initialization, CRC framing, addressing, read completion and error cleanup");
    return 0;
}
