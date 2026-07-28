#include "aux_spi.h"
#include "interrupts.h"

#ifndef AUX_SPI_BUFFER_ADDRESS
volatile char _spi_buffer[AUX_SPI_BUFFER_SIZE];
#endif

volatile unsigned int _spi_buffer_length;

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
