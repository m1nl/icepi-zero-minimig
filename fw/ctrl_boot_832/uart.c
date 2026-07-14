#include "uart.h"

int putchar(int c)
{
	if (c == '\n')
		HW_UART(REG_UART)='\r';
	HW_UART(REG_UART)=c;
	return(c);
}
