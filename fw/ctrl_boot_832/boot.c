/*	Firmware for loading files from SD card.
	Part of the MinimigAGA core TC64 port by Alastair M. Robinson.
	SPI and FAT code borrowed from the Minimig project.
*/

#include <stdio.h>
#include "spi.h"
#include "minfat.h"
#include "checksum.h"
#include "uart.h"

/* #define STANDALONE to disable anything that requires the Minimig core to be functional,
   to reduce build times when debugging host facilities. */
/*#define STANDALONE*/

#include "bootdiag.h"

#ifndef STANDALONE
void BootDiag()
{
	unsigned char *upload=(unsigned char *)(0x780000^0x680000);
	unsigned char *src=bootdiag_bin;
	int i=bootdiag_bin_len;
	while(i--)
		*upload++=*src++;
}
#endif

void ErrorCode(int code)
{
#ifndef STANDALONE
	unsigned char *upload=(unsigned char *)(0x780000^0x680000);
	EnableOsd();
	HW_SPI(HW_SPI_DATA)=OSD_CMD_RST;
	HW_SPI(HW_SPI_DATA)=SPI_RST_CPU|SPI_CPU_HLT; // Reset the chipset to allow the NTSC flag to take effect.
	DisableOsd();
	upload[10]=code>>8;
	upload[11]=code&255;
	EnableOsd();
	HW_SPI(HW_SPI_DATA)=OSD_CMD_RST;
	HW_SPI(HW_SPI_DATA)=0; // Reset the chipset to allow the NTSC flag to take effect.
	DisableOsd();
#endif
}

void _boot()
{
	void (*entry)();
	entry=(void (*)())prg_start;
	entry();
}

void _break();


char printbuf[32];

void cvx(int val,char *buf)
{
	int i;
	int c;
	for(i=0;i<8;++i)
	{
		c=(val>>28)&0xf;
		val<<=4;
		if(c>9)
			c+='A'-10;
		else
			c+='0';
		*buf++=c;
	}
}


void memcheck()
{
	int t;
	volatile char *cbase=(volatile char *)0x10000;
	volatile int *ibase=(volatile int *)cbase;
	ibase[0]=0x11223344;
	ibase[1]=0xffeeddcc;
	ibase[2]=0x88776655;
	ibase[3]=0x99aabbcc;
	for(t=0;t<4;++t)
		printf("%x\n",ibase[t]);
	cbase[3]=0x55;
	cbase[6]=0xaa;
	cbase[9]=0x33;
	cbase[12]=0xcc;
	t=ibase[0x2000];
	t=ibase[0x4000]; // Should result in cacheline being flushed
	t=ibase[0];
	for(t=0;t<4;++t)
		printf("%x\n",ibase[t]);

}

int main(int argc,char **argv)
{
	int i;
	int err=0;
	SPI_slow();
	printf("Sanity check: %x\n",42);
	memcheck();

#ifndef STANDALONE
	EnableOsd();
	HW_SPI(HW_SPI_DATA)=OSD_CMD_RST;
	HW_SPI(HW_SPI_DATA)=SPI_RST_CPU|SPI_CPU_HLT; // Allow the Chipset to start up
	DisableOsd();

	PLATFORM=(1<<PLATFORM_SCANDOUBLER);

	EnableOsd();
	HW_SPI(HW_SPI_DATA)=OSD_CMD_CHIP;
	HW_SPI(HW_SPI_DATA)=CONFIG_NTSC;
	DisableOsd();

	EnableOsd();
	HW_SPI(HW_SPI_DATA)=OSD_CMD_RST;
	HW_SPI(HW_SPI_DATA)=SPI_RST_USR|SPI_RST_CPU|SPI_CPU_HLT; // Reset the chipset to allow the NTSC flag to take effect.
	DisableOsd();

	BootDiag();
	ErrorCode(0xfff);
#endif

	while(1)
	{
		err=0xf00;
		puts("Initializing SD card\n");
		if(spi_init())
		{
			err=0xff0;
			puts("Hunting for partition\n");
			if(FindDrive())
			{
				err=0x0f0;
				int romsize;
				int *checksums;
				if(romsize=LoadFile(OSDNAME,prg_start))
				{
					int error=0;
					char *sector=(char *)prg_start;
					int offset=0;
					err=0x0ff;
					puts("Booting...\n");
					_boot();
				}
				else
					puts("Can't load firmware\n");
			}
			else
			{
				puts("Unable to locate partition\n");
			}
		}
		else
			puts("Failed to initialize SD card\n");
		ErrorCode(err);
	}
	return(0);
}

