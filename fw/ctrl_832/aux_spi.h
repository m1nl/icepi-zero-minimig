#ifndef AUX_SPI_H
#define AUX_SPI_H

#include "hardware.h"
#include "string.h"

#ifndef AUX_SPI_BUFFER_SIZE
#define AUX_SPI_BUFFER_SIZE 32
#endif

#ifdef AUX_SPI_BUFFER_ADDRESS
#define _spi_buffer ((volatile char *)AUX_SPI_BUFFER_ADDRESS)
#else
extern volatile char _spi_buffer[AUX_SPI_BUFFER_SIZE];
#endif

extern volatile unsigned int _spi_buffer_length;

static inline void aux_spi_inthandler(void) {
    unsigned int _spi = 0;
#ifdef AUX_SPI_BUFFER_ADDRESS
    volatile char *temp = _spi_buffer;
#else
    char temp[AUX_SPI_BUFFER_SIZE];
#endif
    int i = 0;

    do {
        _spi = HW_AUX_SPI;
        if ((_spi & (1U << 30)) != 0) {
            temp[i++] = (char)_spi;
        } else if ((_spi & (1U << 31)) == 0) {
            break;
        }
    } while (i < AUX_SPI_BUFFER_SIZE);

    if (i != 0) {
#ifndef AUX_SPI_BUFFER_ADDRESS
        memcpy(_spi_buffer, temp, i);
#endif
        _spi_buffer_length = i;
    }
}

void aux_spi_read(char *dest, unsigned int *length);

#endif
