/* GPL-3.0-or-later. Generate wire bytes from the production firmware tests. */
#define main regression_main
#ifdef BOOT_TRACE
#include "../../fw/ctrl_832/tests/boot_spi_test.c"
#else
#include "../../fw/ctrl_832/tests/mmc_error_test.c"
#endif
#undef main

static void emit(unsigned int first,unsigned int last,unsigned int divider)
{
    unsigned int i;
    assert(last<=sizeof(transmitted));
    for(i=first;i<last;++i)
        fprintf(stdout,"%u %u %u\n",selected[i],transmitted[i],divider);
}
int main(void)
{
    unsigned char buffer[512];
    unsigned int first;
    begin();
#ifdef BOOT_TRACE
    modern(0);ocr(0xc0);assert(spi_init());
    first=calls;emit(0,first,TRACE_SLOW_DIVIDER);
    command(0);block();assert(sd_read_sector(7,buffer));
    emit(first,calls,TRACE_FAST_DIVIDER);
#else
    timer_expired=0;modern_init(0);csd(0x40);assert(MMC_Init()==CARDTYPE_SDHC);
    first=spi_calls;
    /* Replay initialization conservatively at the slow divider, including CSD.
     * Runtime switches to fast for CSD; byte framing is independent of speed. */
    emit(0,first,TRACE_SLOW_DIVIDER);
    command(0);read_sector();assert(MMC_ReadQuiet(7,buffer));
    command(0);read_sector();stop(0,0xff);assert(MMC_ReadMultipleQuiet(8,buffer,1));
    command(0);append(0xff,516);append(5,1);append(0xff,1);
    assert(MMC_WriteQuiet(9,buffer));
    emit(first,spi_calls,TRACE_FAST_DIVIDER);
#endif
    return 0;
}
