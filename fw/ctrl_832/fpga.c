/*
Copyright 2005, 2006, 2007 Dennis van Weeren
Copyright 2008, 2009 Jakub Bednarski

This file is part of Minimig

Minimig is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 3 of the License, or
(at your option) any later version.

Minimig is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

// 2009-10-10   - any length (any multiple of 8 bytes) fpga core file support
// 2009-12-10   - changed command header id
// 2010-04-14   - changed command header id

//#include "AT91SAM7S256.h"
#include <stdio.h>
#include <string.h>
#include "version.h"
#include "errors.h"
#include "hardware.h"
#include "fat.h"
#include "fdd.h"
#include "rafile.h"
#include "boot.h"

#include "fpga.h"
#include "osd.h"
#include "config.h"

#define CMD_HDRID 0xAACA

extern fileTYPE file;
extern char s[40];

int checksum_pre;


int CheckSum(char *adr,int size);

char BootPrint(const char *text);


char kick1xfoundstr[] = "Kickstart v1.x found\n";
const char applymemdetectionpatchstr[] = "Applying Kickstart 1.x memory detection patch\n";

const char *kickfoundstr, *applypatchstr;

void PatchKick1xMemoryDetection(unsigned char *buf) {
  int applypatch = 0;

  if (!strncmp(buf + 0x18, "exec 33.192 (8 Oct 1986)", 24)) {
    kick1xfoundstr[13] = '2';
    kickfoundstr = kick1xfoundstr;
    goto applypatch;
  }
  if (!strncmp(buf + 0x18, "exec 34.2 (28 Oct 1987)", 23)) {
    kick1xfoundstr[13] = '3';
    kickfoundstr = kick1xfoundstr;
    goto applypatch;
  }

  goto out;

applypatch:
  if ((buf[0x154] == 0x66) && (buf[0x155] == 0x78)) {
    applypatchstr = applymemdetectionpatchstr;
    buf[0x154] = 0x60;
  }

out:
  return;
}


// SendFileV2 (for minimig_v2)
void SendFileV2(RAFile* file, unsigned char* key, int keysize, int address, int size)
{
	int i,j;
	unsigned int keyidx=0;
	unsigned char sector_buffer[1024];       // sector buffer - room for two consecutive sectors...

	checksum_pre=0;


	printf("File size: %dkB\r", size>>1);
	printf("[");
	if (keysize) {
		// read header
		RARead(file, sector_buffer, 0xb);
	}

	for (i=0; i<size; i++) {
		unsigned char *adr = (unsigned char *)(((address + i*512) & 0x7fffff) ^ HOSTMAP_ADDR);
		if (!(i&31)) printf("*");
		RARead(file, adr, 512);
		if (keysize) {
			// decrypt ROM
			for (j=0; j<512; j++) {
				adr[j] ^= key[keyidx++];
				if(keyidx >= keysize) keyidx -= keysize;
			}
		}
		checksum_pre+=CheckSum(adr,512);

		// patch kickstart 1.x to force memory detection every time the AMIGA is reset
		if (config.kick13patch && (i == 0 || i == 512)) {
			kickfoundstr = NULL;
			applypatchstr = NULL;
			PatchKick1xMemoryDetection(adr);
		}

	}
	printf("]\r");

	if (kickfoundstr) {
		printf(kickfoundstr);
	}
	if (applypatchstr) {
		printf(applypatchstr);
	}
}


// print message on the boot screen
// (Temporarily disabled.)
char BootPrint(const char *text)
{
//	BootPrintEx(text);
	return(1);
}


void ClearMemory(unsigned long base, unsigned long size)
{
    unsigned char c1, c2, c3, c4;

    while (1)
    {
        EnableFpga();
        c1 = SPI(0x10); // track read command
        c2 = SPI(0x01); // disk present
        SPI(0);
        SPI(0);
        c3 = SPI(0);
        c4 = SPI(0);
        if (c1 & CMD_RDTRK)
        {
            if (c3 == 0x80 && c4 == 0x06)// command packet size 12 bytes
            {
                SPI(CMD_HDRID >> 8); // command header
                SPI(CMD_HDRID & 0xFF);
                SPI(0x00); // cmd: 0x0004 = clear memory
                SPI(0x04);
                // memory base
                SPI((unsigned char)(base >> 24));
                SPI((unsigned char)(base >> 16));
                SPI((unsigned char)(base >> 8));
                SPI((unsigned char)base);
                // memory size
                SPI((unsigned char)(size >> 24));
                SPI((unsigned char)(size >> 16));
                SPI((unsigned char)(size >> 8));
                SPI((unsigned char)size);
            }
            DisableFpga();
            return;
        }
        DisableFpga();
    }
}

unsigned char GetFPGAStatus(void)
{
    unsigned char status;

    EnableFpga();
    status = SPI(0);
    SPI(0);
    SPI(0);
    SPI(0);
    SPI(0);
    SPI(0);
    DisableFpga();

    return status;
}


void fpga_init() {
	unsigned long time = GetTimer(0);
	int ver_beta,ver_major,ver_minor,ver_minion;
	char rtl_ver[45];
	int rstval;

	EnableOsd();
	SPI(OSD_CMD_VERSION);
	ver_beta   = SPI(0xff);
	ver_major  = SPI(0xff);
	ver_minor  = SPI(0xff);
	ver_minion = SPI(0xff);
	DisableOsd();
	SPIN; SPIN; SPIN; SPIN;

	OsdDoReset(SPI_RST_USR | SPI_RST_CPU | SPI_CPU_HLT,SPI_RST_CPU | SPI_CPU_HLT);

	WaitTimer(50);
	BootInit();
	WaitTimer(100);

	BootHome();

	sprintf(rtl_ver, "Minimig AGA%s version 20%d-%d-%d for Turbo Chameleon 64", ver_beta ? " BETA" : "",
		ver_major, ver_minor, ver_minion);
	BootPrintEx(rtl_ver);
	sprintf(rtl_ver, "Firmware version: %s",MM_FIRMWARE_VERSION);
	BootPrintEx(rtl_ver);
	BootPrintEx(" ");
	BootPrintEx("Minimig AGA by Rok Krajnc.  Original Minimig by Dennis van Weeren");
	BootPrintEx("Updates by Jakub Bednarski, Tobias Gubener, Sascha Boing, A.M. Robinson & others");
	BootPrintEx(" ");
	BootPrintEx("Ported to Turbo Chameleon 64 by Alastair M. Robinson");
	BootPrintEx("Ported to IcePi Zero by Alastair M. Robinson and Mateusz Nalewajski");
	BootPrintEx(" ");
	WaitTimer(1000);

    //eject all disk
    df[0].status = 0;
    df[1].status = 0;
    df[2].status = 0;
    df[3].status = 0;
}

