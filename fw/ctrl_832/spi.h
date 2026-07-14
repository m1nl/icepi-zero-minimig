#ifndef SPI_H
#define SPI_H

#if 0
volatile void EnableCard();
volatile void DisableCard();
volatile void EnableFpga();
volatile void DisableFpga();
volatile void EnableOsd();
volatile void DisableOsd();
volatile void EnableDMode();
volatile void DisableDMode();

void spi_osd_cmd_cont(unsigned char cmd);
void spi_osd_cmd(unsigned char cmd);
void spi_osd_cmd8_cont(unsigned char cmd, unsigned char parm);
void spi_osd_cmd8(unsigned char cmd, unsigned char parm);
void spi_osd_cmd32_cont(unsigned char cmd, unsigned long parm);
void spi_osd_cmd32(unsigned char cmd, unsigned long parm);
void spi_osd_cmd32le_cont(unsigned char cmd, unsigned long parm);
void spi_osd_cmd32le(unsigned char cmd, unsigned long parm);
#endif

#endif
