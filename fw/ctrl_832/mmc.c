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

// --== based on the work by Dennis van Weeren and Jan Derogee ==--
// 2008-10-03 - adaptation for ARM controller
// 2009-07-23 - clean-up and some optimizations
// 2009-11-22 - multiple sector read implemented


//#include "AT91SAM7S256.h"
#include "stdio.h"
//#include "string.h"
#include "errors.h"
#include "hardware.h"
#include "mmc.h"
#include "fat.h"
#include "config.h"
//#include "firmware.h"

// variables
static unsigned long sd_lbas;
static unsigned long timeout;
static unsigned char response;
static unsigned char CardType;

static unsigned char CSDData[16];

// internal functions
static inline unsigned char MMC_CRC(unsigned char c, unsigned char crc);
static inline unsigned char MMC_CMD12(void);

static unsigned char MMC_Command(unsigned char cmd, unsigned long arg);

/* Complete the transaction before stopping SCK. CS may be high for these
 * eight clocks; direct mode must already have been disabled by the caller. */
static void MMC_Release(void)
{
    DisableCard();
    SPI(0xFF);
}

// init memory card
unsigned char MMC_Init(void)
{
    unsigned char n;
    unsigned char ocr[4];

    CardType = CARDTYPE_NONE;
    sd_lbas = 0;
    SPI_slow();
    DisableCard();
    WaitTimer(20); // allow power to settle before the initial clocks
    for (n = 10; n > 0; n--)
        SPI(0xFF); // at least 74 clocks with CS and MOSI high
    EnableCard();

    if (MMC_Command(CMD0, 0) == 0x01)
    { // idle state
        timeout = GetTimer(1000); // initialization timeout 1000 ms
        if (MMC_Command(CMD8, 0x1AA) == 0x01) // check if the card can operate with 2.7-3.6V power
        {   // SDHC card
            for (n = 0; n < 4; n++)
                ocr[n] = SPI(0xFF); // get the rest of R7 response
            if (ocr[2] == 0x01 && ocr[3] == 0xAA)
            { // the card can work at 2.7-3.6V
                INFO("SDHC card detected\n");
                while (!CheckTimer(timeout))
                { // now we must wait until CMD41 returns 0 (or timeout elapses)
                    if (MMC_Command(CMD55, 0) == 0x01)
                    { // CMD55 must precede any ACMD command
                        if (MMC_Command(CMD41, 1 << 30) == 0x00) // ACMD41 with HCS bit
                        { // initialization completed
                            if (MMC_Command(CMD58, 0) == 0x00)
                            { // check CCS (Card Capacity Status) bit in the OCR
                                for (n = 0; n < 4; n++)
                                    ocr[n] = SPI(0xFF);

                                CardType = (ocr[0] & 0x40) ? CARDTYPE_SDHC : CARDTYPE_SD; // if CCS set then the card is SDHC compatible
                            }
                            else
                            {
                                ERR("CMD58 (READ_OCR) failed!\n");
                                MMC_Release();
                                return CARDTYPE_NONE;
                            }

                            MMC_Release();
                            SPI_fast();
                            if (!MMC_GetCapacity())
                                CardType = CARDTYPE_NONE;
                            return(CardType);
                        }
                    }
                    else
                    {
                        ERR("CMD55 (APP_CMD) failed!\n");
                        MMC_Release();
                        return(CARDTYPE_NONE);
                    }
                }
                ERR("SDHC card initialization timed out!\n");
                MMC_Release();
                return(CARDTYPE_NONE);
            }
        }

        // it's not an SDHC card
        if (MMC_Command(CMD55, 0) == 0x01)
        { // CMD55 accepted so it's an SD card (or Kingston 128 MB MMC)
            if (MMC_Command(CMD41, 0) <= 0x01)
            { // SD card detected - wait for the end of initialization
                INFO("SD card detected\n");
                /* The first ACMD41 may already have completed initialization.
                 * Once ready, CMD55 legitimately returns zero rather than idle. */
                while (response != 0 && !CheckTimer(timeout))
                {
                    if (MMC_Command(CMD55, 0) != 0x01)
                    {
                        ERR("CMD55 (APP_CMD) failed!\n");
                        MMC_Release();
                        return CARDTYPE_NONE;
                    }
                    if (MMC_Command(CMD41, 0) > 0x01)
                    {
                        ERR("ACMD41 (SD_SEND_OP_COND) failed!\n");
                        MMC_Release();
                        return CARDTYPE_NONE;
                    }
                }
                if (response == 0)
                {
                    if (MMC_Command(CMD16, 512) != 0x00)
                    {
                        ERR("CMD16 (SET_BLOCKLEN) failed!\n");
                        MMC_Release();
                        return CARDTYPE_NONE;
                    }
                    MMC_Release();
                    SPI_fast();
                    CardType = CARDTYPE_SD;
                    if (!MMC_GetCapacity())
                        CardType = CARDTYPE_NONE;
                    return CardType;
                }
                ERR("SD card initialization timed out!\n");
                MMC_Release();
                return(CARDTYPE_NONE);
            }
        }

        // it's not an SD card
        INFO("MMC card detected\n");
        while (!CheckTimer(timeout))
        { // now we must wait until CMD1 returns 0 (or timeout elapses)
            if (MMC_Command(CMD1, 0) == 0x00)
            { // initialization completed

                if (MMC_Command(CMD16, 512) != 0x00) // set block length
                {
                    ERR("CMD16 (SET_BLOCKLEN) failed!\n");
                    MMC_Release();
                    return CARDTYPE_NONE;
                }

                MMC_Release();

                SPI_fast();
                CardType = CARDTYPE_MMC;
                if (!MMC_GetCapacity())
                    CardType = CARDTYPE_NONE;
                return(CardType);
            }
        }

        ERR("MMC card initialization timed out!\n");
        MMC_Release();
        return(CARDTYPE_NONE);
    }

    MMC_Release();
    ERR("No memory card detected!\n");
    return(CARDTYPE_NONE);
}

/* Keep token diagnostics local; no logging or timer reads per polling byte. */
typedef struct {
    unsigned long polls, elapsed_ms, unexpected;
    unsigned char token, first, last;
} MMCReadDiagnostic;

static int MMC_WaitReadToken(MMCReadDiagnostic *diag)
{
    unsigned long started = GetTimer(0);
    diag->polls = diag->unexpected = 0;
    diag->first = diag->last = 0xff;
    for (;;) {
        diag->token = SPI(0xff);
        ++diag->polls;
        if (diag->token == 0xfe)
            return 1;
        if (diag->token != 0xff) {
            if (!diag->unexpected) diag->first = diag->token;
            diag->last = diag->token;
            ++diag->unexpected;
            /* SD SPI read-error token: 0000xxxx, with at least one flag.
             * 0x00 alone is not a data-error token; retain bounded waiting. */
            if (diag->token && !(diag->token & 0xf0))
                break;
        }
        /* Preserve the previous limit of 1,000,001 received bytes. */
        if (diag->polls >= 1000001UL)
            break;
    }
    diag->elapsed_ms = (GetTimer(0) - started) / TIMER_MS_TO_TICKS(1);
    return 0;
}

static void MMC_ReadTokenError(unsigned int cmd, unsigned long sector,
                               unsigned long argument, const MMCReadDiagnostic *diag, int quiet, int stop_response)
{
    int data_error = diag->token && !(diag->token & 0xf0);
    const char *message;
    ERR("SD CMD%u %s: sector=%lu arg=0x%lx card=%u token=0x%02X wait=%lu ms polls=%lu\n",
        cmd, data_error ? "data error" : "no data token", sector, argument,
        (unsigned int)CardType, (unsigned int)diag->token, diag->elapsed_ms, diag->polls);
    ERR("SD token bytes: first=0x%02X last=0x%02X unexpected=%lu\n",
        (unsigned int)diag->first, (unsigned int)diag->last, diag->unexpected);
    if (data_error)
        ERR("SD read flags: error=%u cc=%u ecc=%u range=%u\n",
            (unsigned int)(diag->token & 1), (unsigned int)((diag->token >> 1) & 1),
            (unsigned int)((diag->token >> 2) & 1), (unsigned int)((diag->token >> 3) & 1));
    if (cmd == 17)
        message = data_error ? "CMD17 Data error" : "CMD17 No data token";
    else
        message = data_error ? "CMD18 Data error" : "CMD18 No data token";
    /* Keep the first pending diagnostic stable while users read its pages.
     * Later fatal failures may escalate severity without replacing its data. */
    if ((ErrorMask & (1<<ERROR_SDCARD)) && Errors[ERROR_SDCARD].detail_count) {
        if (!quiet) ErrorFatal=1;
        return;
    }
    {
        static char details[10][ERROR_DETAIL_WIDTH];
        const char *card=CardType==CARDTYPE_SDHC ? "SDHC/SDXC (blocks)" :
                         CardType==CARDTYPE_SD ? "SDSC (bytes)" :
                         CardType==CARDTYPE_MMC ? "MMC (bytes)" : "unknown";
        snprintf(details[0],ERROR_DETAIL_WIDTH," Sector: 0x%lx",sector);
        snprintf(details[1],ERROR_DETAIL_WIDTH," Arg: 0x%lx",argument);
        snprintf(details[2],ERROR_DETAIL_WIDTH," Card: %s",card);
        snprintf(details[3],ERROR_DETAIL_WIDTH," Token: 0x%02X",(unsigned int)diag->token);
        snprintf(details[4],ERROR_DETAIL_WIDTH," Wait: %lu ms",diag->elapsed_ms);
        snprintf(details[5],ERROR_DETAIL_WIDTH," Polls: %lu",diag->polls);
        snprintf(details[6],ERROR_DETAIL_WIDTH," First:%02X Last:%02X",
                 (unsigned int)diag->first,(unsigned int)diag->last);
        snprintf(details[7],ERROR_DETAIL_WIDTH," Unexpected: %lu",diag->unexpected);
        if (data_error)
            snprintf(details[8],ERROR_DETAIL_WIDTH," Err:%u CC:%u ECC:%u Range:%u",
                     (unsigned int)(diag->token & 1),(unsigned int)((diag->token>>1) & 1),
                     (unsigned int)((diag->token>>2) & 1),(unsigned int)((diag->token>>3) & 1));
        else
            snprintf(details[8],ERROR_DETAIL_WIDTH," Card error flags: none");
        if (stop_response>=0)
            snprintf(details[9],ERROR_DETAIL_WIDTH," CMD12 response: 0x%02X",(unsigned int)stop_response);
        if (quiet) SetError(ERROR_SDCARD,message,sector,diag->token);
        else FatalError(ERROR_SDCARD,message,sector,diag->token);
        SetErrorDetails(ERROR_SDCARD,details,stop_response>=0 ? 10 : 9);
    }
}

// Read single 512-byte block
unsigned char MMC_ReadImpl(unsigned long lba, unsigned char *pReadBuffer, int quiet)
{
// if pReadBuffer is NULL then use direct to the FPGA transfer mode (FPGA2 asserted)

    unsigned long i, sector = lba;
    MMCReadDiagnostic diag;
//    unsigned long t;
	unsigned char *p;

    if(lba>=sd_lbas)
	{
		if (!quiet) FatalError(ERROR_SDCARD,"Read beyond end of device.",lba,sd_lbas);
		return(0);
	}

    if (CardType != CARDTYPE_SDHC) // SDHC cards are addressed in sectors not bytes
        lba = lba << 9; // otherwise convert sector adddress to byte address

    EnableCard();

    if (MMC_Command(CMD17, lba))
    {
        MMC_Release();
        ERR("SD CMD17 rejected: sector=%lu arg=0x%lx card=%u R1=0x%02X\n",
            sector, lba, (unsigned int)CardType, (unsigned int)response);
		if (!quiet) FatalError(ERROR_SDCARD,"CMD17 Read block",sector,response);
        return(0);
    }

    if (!MMC_WaitReadToken(&diag))
    {
        MMC_Release();
        MMC_ReadTokenError(17,sector,lba,&diag,quiet,-1);
        return 0;
    }

    if (pReadBuffer == 0)
    {   // in this mode we do not receive data, instead the FPGA captures directly the data stream transmitted by the SD/MMC card
		EnableDMode();
		SPI(0xFF); // dummy write for 4096 clocks
		i = RDSPI; // wait until SPI ready
		DisableDMode();
    }
    else
    {
		p=pReadBuffer;
		for (i = 0; i < 128; i++)
		{
			*(p++) = SPI(0xFF);
			*(p++) = SPI(0xFF);
			*(p++) = SPI(0xFF);
			*(p++) = SPI(0xFF);
		}
    }

    SPI(0xFF); // read CRC lo byte
    SPI(0xFF); // read CRC hi byte

    MMC_Release();
    return(1);
}

// Read CSD register
static unsigned char MMC_GetCSD()
{
	int i;
    EnableCard();

    if (MMC_Command(CMD9,0))
    {
        ERR("CMD9 (GET_CSD): invalid response 0x%02X \n", response);
        MMC_Release();
		FatalError(ERROR_SDCARD,"GetCSD - invalid response",response,0);
        return(0);
    }

    // now we are waiting for data token, it takes around 300us
    timeout = 0;
    while ((SPI(0xFF)) != 0xFE)
    {
        if (timeout++ >= 1000000) // we can't wait forever
        {
            ERR("CMD9 (READ_BLOCK): no data token!\n");
            MMC_Release();
            FatalError(ERROR_SDCARD,"GetCSD - No data token",0,0);
            return(0);
        }
    }

	for (i = 0; i < 16; i++)
		CSDData[i]=SPI(0xFF);

    SPI(0xFF); // read CRC lo byte
    SPI(0xFF); // read CRC hi byte

    MMC_Release();
    return(1);
}


unsigned long MMC_GetSectorCount(void)
{
    return sd_lbas;
}

unsigned long MMC_GetCapacity()
{
	unsigned long result=0;
    sd_lbas = 0;
    if (!MMC_GetCSD())
        return 0;
    if ((CSDData[0] & 0xC0)==0x40)   //CSD Version 2.0 - SDHC
    {
			result=(CSDData[7]&0x3f)<<26;
			result|=CSDData[8]<<18;
			result|=CSDData[9]<<10;
			result+=1024;
			sd_lbas=result;
			return(result);
	}
	else
	{
			int blocksize=CSDData[5]&15;	// READ_BL_LEN
			if ((CSDData[0] & 0xC0) != 0 || blocksize < 9 || blocksize > 11)
			{
				FatalError(ERROR_SDCARD,"Invalid CSD",CSDData[0],blocksize);
				return 0;
			}
			blocksize=1<<(blocksize-9);		// Now a scalar:  physical block size / 512.
			result=(CSDData[6]&3)<<10;
			result|=CSDData[7]<<2;
 			result|=(CSDData[8]>>6)&3;		// result now contains C_SIZE
			int cmult=(CSDData[9]&3)<<1;
			cmult|=(CSDData[10]>>7) & 1;
			++result;
			result<<=cmult+2;
			result*=blocksize;	// Scale by the number of 512-byte chunks per block.
			sd_lbas=result;
			return(result);
    }
}


// read multiple 512-byte blocks
unsigned char MMC_ReadMultipleImpl(unsigned long lba, unsigned char *pReadBuffer, unsigned long nBlockCount, int quiet)
{
// if pReadBuffer is NULL then use direct to the FPGA transfer mode (FPGA2 asserted)
    unsigned long i, sector = lba;
    unsigned char stop_response;
    MMCReadDiagnostic diag;
	unsigned char *p;

    if(lba >= sd_lbas || nBlockCount > sd_lbas - lba)
	{
		if (!quiet) FatalError(ERROR_SDCARD,"ReadM beyond end of device.",lba+nBlockCount,sd_lbas);
		return(0);
	}

    if (CardType != CARDTYPE_SDHC) // SDHC cards are addressed in sectors not bytes
        lba = lba << 9; // otherwise convert sector adddress to byte address
    EnableCard();

    if (MMC_Command(CMD18, lba))
    {
        ERR("SD CMD18 rejected: sector=%lu arg=0x%lx card=%u R1=0x%02X\n",
            sector, lba, (unsigned int)CardType, (unsigned int)response);
        MMC_Release();
		if (!quiet) FatalError(ERROR_SDCARD,"CMD18 - invalid response",sector,response);
        return(0);
    }

    while (nBlockCount--)
    {
        if (!MMC_WaitReadToken(&diag))
        {
            stop_response = MMC_CMD12(); // cancel the started multi-block stream
            MMC_Release();
            MMC_ReadTokenError(18,sector,lba,&diag,quiet,stop_response);
            if (stop_response)
                ERR("SD CMD18 cleanup: CMD12 failed, response=0x%02X\n", (unsigned int)stop_response);
            return 0;
        }

        if (pReadBuffer == 0)
        {   // in this mode we do not receive data, instead the FPGA captures directly the data stream transmitted by the SD/MMC card
			EnableDMode();
			SPI(0xFF); // dummy write for 4096 clocks
			i = RDSPI; // wait until SPI ready
			DisableDMode();
        }
        else
        {
			p=pReadBuffer;
			for (i = 0; i < 128; i++)
			{
				*(p++) = SPI(0xFF);
				*(p++) = SPI(0xFF);
				*(p++) = SPI(0xFF);
				*(p++) = SPI(0xFF);
			}

            pReadBuffer += 512; // point to next sector
        }

        SPI(0xFF); // read CRC lo byte
        SPI(0xFF); // read CRC hi byte
        ++sector;
    }

    response = MMC_CMD12(); // stop multi block transmission
    MMC_Release();
    if (response) {
        if (!quiet) FatalError(ERROR_SDCARD,"CMD12 stop failed",response,lba);
        return 0;
    }
    return(1);
}

// write 512-byte block
unsigned char MMC_WriteImpl(unsigned long lba, unsigned char *pWriteBuffer, int quiet)
{
    unsigned long i;

    if(lba>=sd_lbas)
	{
		if (!quiet) FatalError(ERROR_SDCARD,"Read beyond end of device.",lba,sd_lbas);
		return(0);
	}

   if (CardType != CARDTYPE_SDHC) // SDHC cards are addressed in sectors not bytes
        lba = lba << 9; // otherwise convert sector adddress to byte address

    EnableCard();

    if (MMC_Command(CMD24, lba))
    {
        ERR("CMD24 (WRITE_BLOCK): invalid response 0x%02X (lba=%lu)\n", response, lba);
        MMC_Release();
		if (!quiet) FatalError(ERROR_SDCARD,"CMD24 invalid response",response,lba);
        return(0);
    }

    SPI(0xFF); // one byte gap
    SPI(0xFE); // send Data Token

    // send sector bytes
    for (i = 0; i < 512; i++)
         SPI(*(pWriteBuffer++));

    SPI(0xFF); // send CRC lo byte
    SPI(0xFF); // send CRC hi byte

    response = SPI(0xFF); // read packet response
    // Status codes
    // 010 = Data accepted
    // 101 = Data rejected due to CRC error
    // 110 = Data rejected due to write error
//    response &= 0x1F;
    if ((response&0x1f) != 0x05)
    {
        ERR("CMD24 (WRITE_BLOCK): invalid status 0x%02X (lba=%lu)\n", response, lba);
        MMC_Release();
		if (!quiet) FatalError(ERROR_SDCARD,"CMD24 invalid response",response,lba);
        return(0);
    }

    timeout = 0;
    while ((SPI(0xFF)) == 0x00) // wait until the card is not busy
    {
        if (timeout++ >= 1000000)
        {
            ERR("CMD24 (WRITE_BLOCK): busy wait timeout! (lba=%lu)\n", lba);
            MMC_Release();
			if (!quiet) FatalError(ERROR_SDCARD,"CMD24 post-write timeout",lba,0);
            return(0);
        }
    }

    MMC_Release();
    return(1);
}

static unsigned char MMC_Command(unsigned char cmd, unsigned long arg)
{
    unsigned char c;
    unsigned char crc;

    crc = 0;
    /* CMD0 resets the card; other ordinary commands must wait for busy to
     * clear. CMD12 is sent separately because it interrupts an active read. */
    if (cmd == CMD0)
        SPI(0xFF);
    else
    {
        unsigned long deadline = GetTimer(1000);
        while (SPI(0xFF) != 0xFF)
        {
            if (CheckTimer(deadline))
            {
                response = 0xFF; // no command was sent; never report busy as R1=0
                return response;
            }
        }
    }

    SPI(cmd);
    crc = MMC_CRC(cmd, crc);

    c = (unsigned char)(arg >> 24);
    SPI(c);
    crc = MMC_CRC(c, crc);

    c = (unsigned char)(arg >> 16);
    SPI(c);
    crc = MMC_CRC(c, crc);

    c = (unsigned char)(arg >> 8);
    SPI(c);
    crc = MMC_CRC(c, crc);

    c = (unsigned char)(arg);
    SPI(c);
    crc = MMC_CRC(c, crc);

    crc <<= 1;
    crc++;
    SPI(crc);

    unsigned char Ncr = 100;  // Ncr = 0..8 (SD) / 1..8 (MMC)
    do
        response = SPI(0xFF); // get response
    while ((response & 0x80) && Ncr--);

    return response;
}

// stop multi block data transmission
static inline unsigned char MMC_CMD12(void)
{
    SPI(CMD12); // command
    SPI(0x00);
    SPI(0x00);
    SPI(0x00);
    SPI(0x00);
    unsigned char crc = MMC_CRC(CMD12, 0);
    unsigned char n;
    for (n = 0; n < 4; ++n)
        crc = MMC_CRC(0, crc);
    SPI((crc << 1) | 1); // CRC7 and mandatory command end bit
    SPI(0xFF); // skip stuff byte

    unsigned char Ncr = 100;  // Ncr = 0..8 (SD) / 1..8 (MMC)
    do
    {    response = SPI(0xFF); // get response
//        RS232(response);
   } while ((response & 0x80) && Ncr--);

    timeout = 0;
    while ((SPI(0xFF)) == 0x00) // wait until the card is not busy
    {   // RS232('+');
        if (timeout++ >= 1000000)
        {
            ERR("CMD12 (STOP_TRANSMISSION): busy wait timeout!\n");
            MMC_Release();
            return 0xff; // distinguish timeout from successful R1=0
        }
}
    return response;
}

static inline unsigned char MMC_CRC(unsigned char c, unsigned char crc)
{
    unsigned char i;

    for (i = 0; i < 8; i++)
    {
        crc <<= 1;
        if (c & 0x80)
            crc ^= 0x09;
        if (crc & 0x80)
            crc ^= 0x09;
        c <<= 1;
    }

    return crc;
}
