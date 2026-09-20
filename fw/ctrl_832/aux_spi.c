#include "aux_spi.h"
#include "interrupts.h"

#ifndef AUX_SPI_BUFFER_ADDRESS
volatile char _spi_buffer[AUX_SPI_BUFFER_SIZE];
#endif

volatile unsigned int _spi_buffer_length;

void aux_spi_read_raw(char *spi_buffer, unsigned int *spi_buffer_size) {
    unsigned int _spi = 0;
    unsigned int i = 0;

    do {
        _spi = HW_AUX_SPI;
        if ((_spi & (1U << 30)) != 0) {
            spi_buffer[i++] = (char)_spi;
        } else if ((_spi & (1U << 31)) == 0) {
            break;
        }
    } while (i < (*spi_buffer_size));

    (*spi_buffer_size) = i;
}

void aux_spi_read(char *dest, unsigned int *length) {
    if (_spi_buffer_length == 0) {
        (*length) = 0;
        return;
    }
    DisableInterrupts();
    if (_spi_buffer_length < (*length)) {
        (*length) = _spi_buffer_length;
    }
    memcpy(dest, _spi_buffer, (*length));
    _spi_buffer_length = 0;
    EnableInterrupts();
}

__constructor(102.aux_spi) void aux_spi_init(void) {
    puts("AUX SPI init\n");
    _spi_buffer_length = 0;
}
