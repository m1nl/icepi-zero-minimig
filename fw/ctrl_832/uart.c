#include "hardware.h"

int putchar(int c)
{
	if (c == '\n')
		RS232('\r');
	RS232(c);
	return(c);
}
