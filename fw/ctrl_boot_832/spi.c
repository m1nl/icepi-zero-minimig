/* Bootstrap SD reader from Alastair M. Robinson's MinimigAGA TC64 port.
 * SPI/FAT ancestry: Minimig, Dennis van Weeren and Jakub Bednarski.
 * Keep only initialization and single-sector reads used by the loader.
 */
#include "spi.h"

/* 0: unavailable, 1: byte-addressed SDSC/MMC, 2: block-addressed SDHC/SDXC. */
static int card_type;

static void sd_release(void)
{
	DisableCard();
	SPI(0xff); /* eight completion clocks before stopping SCK */
}

static int sd_expired(unsigned long started)
{
	/* Same free-running 44.1 kHz timer as ctrl_832, scaled by 256. */
	return (unsigned long)(HW_TIMER-started) >= 11290000UL; /* one second */
}

static int sd_command(unsigned char cmd, unsigned long arg)
{
	unsigned long started=HW_TIMER;
	unsigned int count=500000;
	unsigned char r;

	/* CMD0 can reset a busy card. No other command may be sent during busy.
	 * The byte budget also bounds recovery if the hardware timer stops. */
	if(cmd==0x40)
		SPI(0xff);
	else
		while(SPI(0xff)!=0xff)
			if(!--count || sd_expired(started))
				return 0xff;

	SPI(cmd);
	SPI(arg>>24);
	SPI(arg>>16);
	SPI(arg>>8);
	SPI(arg);
	/* CRC is disabled in SPI mode, except for CMD0 and CMD8. Every command
	 * still needs an end bit of one. Arguments here are never LBA-scaled. */
	SPI(cmd==0x40 ? 0x95 : cmd==0x48 ? 0x87 : 0xff);
	for(count=0;count<9;++count)
	{
		r=SPI(0xff); /* clock a new byte; do not sample the command CRC byte */
		if(!(r&0x80))
			return r;
	}
	return 0xff;
}

int spi_init(void)
{
	int i,r,v2,mmc=0;
	unsigned long started,ocr;

	card_type=0;
	SPI_slow(); /* ~119 kHz; keep both selected/deselected clocks below 400 kHz */
	for(i=0;i<7;++i)
	{
		DisableCard();
		/* Preserve the loader's long startup preamble, with CS/MOSI high. */
		for(r=0;r<200;++r)
			SPI(0xff);
		EnableCard();
		if(sd_command(0x40,0)==1)
			break;
		sd_release();
	}
	if(i==7)
		goto fail;

	r=sd_command(0x48,0x1aa);
	v2=(r==1);
	if(v2)
	{
		ocr=0;
		for(i=0;i<4;++i)
			ocr=(ocr<<8)|SPI(0xff);
		if((ocr&0xffff)!=0x1aa)
			goto fail;
	}
	else if(r!=5) /* idle + illegal command is the legacy-card response */
		goto fail;

	started=HW_TIMER;
	for(i=0;i<10000;++i)
	{
		if(!mmc)
		{
			r=sd_command(0x77,0); /* CMD55 */
			if(!v2 && r==5)
				mmc=1;
			else if(r!=1)
				goto fail;
		}
		r=sd_command(mmc ? 0x41 : 0x69,v2 ? 0x40000000UL : 0);
		if(!r) /* accept the very first successful ACMD41/CMD1 */
			break;
		if(r!=1 || sd_expired(started))
			goto fail;
	}
	if(i==10000)
		goto fail;

	if(v2)
	{
		if(sd_command(0x7a,0)) /* CMD58 */
			goto fail;
		ocr=0;
		for(i=0;i<4;++i)
			ocr=(ocr<<8)|SPI(0xff);
		if(!(ocr&0x80000000UL)) /* OCR valid only after power-up completes */
			goto fail;
		if(ocr&0x40000000UL)
		{
			card_type=2;
			sd_release();
			return 1;
		}
	}
	/* CMD16 takes a byte count, including on byte-addressed cards. */
	if(sd_command(0x50,512))
		goto fail;
	card_type=1;
	sd_release();
	return 1;
fail:
	sd_release();
	return 0;
}

int sd_read_sector(unsigned long lba,unsigned char *buf)
{
	unsigned long started;
	unsigned int i;
	unsigned char token;
	int result=0;

	if(!card_type || (card_type==1 && lba>0x7fffffUL))
		return 0;
	EnableCard();
	SPI_fast(); /* ~3.36 MHz; bootstrap does not need high-speed mode */
	if(sd_command(0x51,card_type==2 ? lba : lba<<9))
		goto out;
	started=HW_TIMER;
	for(i=0;i<1500000;++i)
	{
		token=SPI(0xff);
		if(token==0xfe)
		{
			/* Byte stores preserve card byte order without alignment assumptions. */
			for(i=0;i<512;++i)
				buf[i]=SPI(0xff);
			SPI(0xff); /* both bytes of CRC16 must be consumed while selected */
			SPI(0xff);
			result=1;
			break;
		}
		if((token && !(token&0xf0)) || sd_expired(started))
			break;
	}
out:
	sd_release(); /* including command rejection, error tokens and timeouts */
	return result;
}
