#include "errors.h"
#include "hardware.h"
#include "mmc.h"
#include "fat.h"
#include "osd.h"
#include "fpga.h"
#include "fdd.h"
#include "hdd.h"
#include "firmware.h"
#include "menu.h"
#include "config.h"

#include "hexdump.h"

#include <stdio.h>
#include <string.h>

#define EXTENDED_ROM

configTYPE config;
fileTYPE file;
char configfilename[12];

static char configuration_titles[CONFIG_SLOT_COUNT][CONFIG_TITLE_STORAGE_LENGTH + 1];
static int configuration_slot;
static int active_configuration_slot=-1;
static char active_configuration_name[CONFIG_TITLE_STORAGE_LENGTH+1]="Built-in defaults";

const char *GetConfigurationTitle(unsigned int slot)
{
	static const char *defaults[CONFIG_SLOT_COUNT] = {
		"Default", "Configuration slot 1", "Configuration slot 2",
		"Configuration slot 3", "Configuration slot 4"
	};
	if(slot >= CONFIG_SLOT_COUNT)
		return "";
	return configuration_titles[slot][0] ? configuration_titles[slot] : defaults[slot];
}

const char *GetConfigurationDisplayTitle(unsigned int slot, int exists)
{
	static const char *empty_defaults[CONFIG_SLOT_COUNT] = {
		"Default", "Configuration 1", "Configuration 2", "Configuration 3", "Configuration 4"
	};
	if(slot>=CONFIG_SLOT_COUNT) return "";
	if(!exists && !configuration_titles[slot][0]) return empty_defaults[slot];
	return GetConfigurationTitle(slot);
}

void FormatConfigurationSlotLabel(char *label, unsigned int slot, int exists, int saving)
{
	FormatConfigurationSlotLabelAtOffset(label, slot, exists, saving, 0);
}

void FormatConfigurationSlotLabelAtOffset(char *label, unsigned int slot, int exists, int saving, unsigned int offset)
{
	const char *suffix=exists ? "" : CONFIG_EMPTY_SUFFIX;
	char title[CONFIG_TITLE_LENGTH+1];
	unsigned int length=CONFIG_TITLE_LENGTH-strlen(suffix);
	const char *name;
	unsigned int i, name_length;
	if(slot>=CONFIG_SLOT_COUNT)
	{
		label[0]=0;
		return;
	}
	/* The firmware printf does not support string precision (%.*s). */
	name=GetConfigurationDisplayTitle(slot, exists);
	name_length=strlen(name);
	if(offset && name_length>length)
	{
		/* Repeat the full title with a three-space gap, keeping status fixed. */
		for(i=0; i<length; ++i)
		{
			unsigned int position=(offset+i)%(name_length+3);
			title[i]=position<name_length ? name[position] : ' ';
		}
	}
	else
		strncpy(title, name, length);
	title[length]=0;
	snprintf(label, CONFIG_SLOT_LABEL_LENGTH+1, " %d%c %s%s", slot,
		saving && exists ? '*' : ':', title, suffix);
}

void FormatActiveConfigurationLabel(char *label)
{
	if(active_configuration_slot>=0)
		snprintf(label, CONFIG_SLOT_LABEL_LENGTH+1, " Active: %d: %s",
			active_configuration_slot, GetConfigurationTitle(active_configuration_slot));
	else
		snprintf(label, CONFIG_SLOT_LABEL_LENGTH+1, " Active: %s", active_configuration_name);
}

void LoadConfigurationTitles(void)
{
	fileTYPE titlefile;
	unsigned char buffer[512];
	char title[CONFIG_TITLE_STORAGE_LENGTH + 1];
	unsigned long remaining;
	unsigned int i, count, slot=0, length=0, state=0;
	unsigned long directory=CurrentDirectory();

	memset(configuration_titles, 0, sizeof(configuration_titles));
	ChangeDirectory(DIRECTORY_ROOT);
	if(!FileOpen(&titlefile, "MINMGAA TXT"))
	{
		/* This file is optional, just like missing configuration slots. */
		ClearError(ERROR_FILESYSTEM);
		ChangeDirectory(directory);
		return;
	}
	ChangeDirectory(directory);
	remaining=titlefile.size;
	while(remaining)
	{
		if(!FileRead(&titlefile, buffer))
			goto read_error;
		count=remaining > sizeof(buffer) ? sizeof(buffer) : remaining;
		i=0;
		/* Accept a UTF-8 BOM, but titles themselves use the OSD's ASCII font. */
		if(titlefile.sector==0 && count>=3 && buffer[0]==0xef && buffer[1]==0xbb && buffer[2]==0xbf)
			i=3;
		for(; i<count; ++i)
		{
			unsigned char c=buffer[i];
			if(c=='\r' || c=='\n')
			{
				if(state==2 || state==3)
				{
					while(length && title[length-1]==' ') --length;
					title[length]=0;
					strcpy(configuration_titles[slot], title);
				}
				state=0;
				length=0;
			}
			else if(state==0)
			{
				if(c==' ' || c=='\t') continue;
				if(c>='0' && c<'0'+CONFIG_SLOT_COUNT)
				{
					slot=c-'0';
					state=1;
				}
				else state=4; /* Comment or invalid slot: discard the line. */
			}
			else if(state==1)
			{
				if(c=='=') state=2;
				else if(c!=' ' && c!='\t') state=4;
			}
			else if(state==2 || state==3)
			{
				if(c=='\t') c=' ';
				if(state==2 && c==' ') continue;
				if(c<32 || c>126) state=4;
				else
				{
					state=3;
					if(length<CONFIG_TITLE_STORAGE_LENGTH) title[length++]=c;
				}
			}
		}
		remaining-=count;
		if(remaining && !FileNextSector(&titlefile))
			goto read_error;
	}
	/* EOF also terminates the last line, without reading sector padding. */
	if(state==2 || state==3)
	{
		while(length && title[length-1]==' ') --length;
		title[length]=0;
		strcpy(configuration_titles[slot], title);
	}
	return;

read_error:
	/* Never expose a partially read set of titles. Keep the I/O error visible. */
	memset(configuration_titles, 0, sizeof(configuration_titles));
}

#ifdef DEBUG
char DebugMode;
char DebugMsg[128];
#endif

int CheckSum();

unsigned char romkey[3072];

static char filename[12];

void ClearKickstartMirrorE0(void)
{
	int i;
	int *p=(int *)((0xe00000 & 0x7fffff) ^ HOSTMAP_ADDR);
	for (i = 0; i < (0x80000 / 4); i++) {
		*p++=0;
	}
}

void ClearVectorTable(void)
{
	int i;
	int *p=(int *)(0 ^ HOSTMAP_ADDR);
	for (i = 0; i < 256; i++) {
		*p++=0;
	}
}

//// UploadKickstart() ////
int UploadKickstart(unsigned long dir,char *name)
{
	RAFile romfile;

	int keysize=0;
	char filename[12];

	strncpy(filename, name, 8); // copy base name
	strcpy(&filename[8], "ROM"); // add extension

	INFO("ROM dir: %d\n",dir);

	if(!ValidateDirectory(dir))
	{
		SetError(ERROR_ROM,"Bad ROM Directory",dir,0);
		return(0);
	}
	ChangeDirectory(dir);

	BootPrint("Checking for Amiga Forever key file:");
	if(RAOpen(&romfile,"ROM     KEY")) {
		keysize=romfile.size;
		if(romfile.size<sizeof(romkey)) {
			RARead(&romfile, &romkey[0],romfile.size);
		} else {
			SetError(ERROR_ROM,"ROM Key file wrong size",romfile.size,0);
		}
	}

	if (RAOpen(&romfile, filename)) {
		ClearError(ERROR_FILESYSTEM);
		if ((romfile.size & 0xf) == 0xb && !keysize) {
			FatalError(ERROR_ROM,"ROM requires key file",0,0);
		}
		else if (romfile.size == 0x100000) {
			// 1MB Kickstart ROM
			BootPrint("Uploading 1MB Kickstart ...");
			SendFileV2(&romfile, NULL, 0, 0xe00000, romfile.size>>10);
			SendFileV2(&romfile, NULL, 0, 0xf80000, romfile.size>>10);
			ClearVectorTable();
			return(1024);
		} else if(romfile.size == 0x80000) {
			// 512KB Kickstart ROM
			SendFileV2(&romfile, NULL, 0, 0xf80000, romfile.size>>9);
			RAOpen(&romfile, filename);
			SendFileV2(&romfile, NULL, 0, 0xe00000, romfile.size>>9);
			ClearVectorTable();
			return(512);
		} else if ((romfile.size == 0x8000b)) {
			// 512KB Kickstart ROM
			SendFileV2(&romfile, romkey, keysize, 0xf80000, romfile.size>>9);
			RAOpen(&romfile, filename);
			SendFileV2(&romfile, romkey, keysize, 0xe00000, romfile.size>>9);
			ClearVectorTable();
			return(512);
		} else if (romfile.size == 0x40000) {
			// 256KB Kickstart ROM
			SendFileV2(&romfile, NULL, 0, 0xf80000, romfile.size>>9);
			RAOpen(&romfile, filename);
			SendFileV2(&romfile, NULL, 0, 0xfc0000, romfile.size>>9);
			ClearVectorTable();
			ClearKickstartMirrorE0();
			return(256);
		} else if ((romfile.size == 0x4000b)) {
			// 256KB Kickstart ROM
			SendFileV2(&romfile, romkey, keysize, 0xf80000, romfile.size>>9);
			RAOpen(&romfile, filename);
			SendFileV2(&romfile, romkey, keysize, 0xfc0000, romfile.size>>9);
			ClearVectorTable();
			ClearKickstartMirrorE0();
			return(256);
		} else {
			FatalError(ERROR_ROM,"ROM size incorrect",romfile.size,0);
		}
	} else {
		FatalError(ERROR_ROM,"ROM missing",0,0);
	}
	return(0);
}


// Upload Extended ROM
char UploadExtROM(unsigned long dir,char *name)
{
#ifdef EXTENDED_ROM
	char filename[12];
	RAFile romfile;

	strncpy(filename, name, 8); // copy base name
	strcpy(&filename[8], "ROM"); // add extension

	if(ValidateDirectory(dir))
	{
		ChangeDirectory(dir);
		if (RAOpen(&romfile, filename)) {
			ClearError(ERROR_FILESYSTEM);
			if(romfile.size == 0x80000) {
				// 512KB Extended CD32 ROM
				SendFileV2(&romfile, NULL, 0, 0xe00000, romfile.size>>9);
				return(1);
			}
			else
			{
				FatalError(ERROR_ROM,"ExtROM size incorrect",romfile.size,0);
			}
		}
	}
	else
		FatalError(ERROR_ROM,"Bad ExtROM directory",dir,0);
	return(0);
#else
	return(1);
#endif
}


//// UploadActionReplay() ////
char UploadActionReplay()
{
	// FIXME - migrate to direct access
	RAFile romfile;

	if (RAOpen(&romfile, "HRTMON  ROM")) {
		unsigned char *adr;
		int data;
		INFO("Uploading HRTmon ROM... ");
		SendFileV2(&romfile, NULL, 0, 0xa10000, (romfile.file.size+511)>>9);

		// HRTmon config
		adr = (unsigned char *)(((0xa10000 + 20)&0x7fffff)^HOSTMAP_ADDR);

		*adr++=0x00; *adr++=0x80; *adr++=0x00; *adr++=0x00;
		//      data = 0x00800000; // mon_size, 4 bytes
		*adr++ =0x00; // col0h, 1 byte
		*adr++ =0x5a; // col0l, 1 byte
		*adr++ =0x0f; // col1h, 1 byte
		*adr++ =0xff; // col1l, 1 byte
		*adr++ =0xff; // right, 1 byte
		*adr++ =0x00; // keyboard, 1 byte
		*adr++ =0xff; // key, 1 byte
		*adr++ =config.enable_ide ? 0xff : 0; // ide, 1 byte
		*adr++ =0xff; // a1200, 1 byte
		*adr++ =config.chipset&CONFIG_AGA ? 0xff : 0; // aga, 1 byte
		*adr++ =0xff; // insert, 1 byte
		*adr++ =0x0f; // delay, 1 byte
		*adr++ =0xff; // lview, 1 byte
		*adr++ =0x00; // cd32, 1 byte
		*adr++ =config.chipset&CONFIG_NTSC ? 1 : 0; // screenmode, 1 byte
		*adr++ =0xff; // novbr, 1 byte
		*adr++ =0; // entered, 1 byte
		*adr++ =1; // hexmode, 1 byte

		adr = (unsigned char *)(((0xa10000 + 68) & 0x7fffff) ^ HOSTMAP_ADDR);
		data = ((config.memory&0x3) + 1) * 512 * 1024; // maxchip, 4 bytes TODO is this correct?
		*adr++=(data>>24)&0xff;
		*adr++=(data>>16)&0xff;
		*adr++=(data>>8)&0xff;
		*adr++=(data>>0)&0xff;

		return(1);
	} else {
	  ClearError(ERROR_FILESYSTEM);
	  puts("\nhrtmon.rom not found!\n");
	  return(0);
	}
  return(0);
}


void SetConfigurationFilename(int config)
{
	configuration_slot=config;
	if(config)
		snprintf(configfilename,sizeof(configfilename),"MINMGAA%dCFG",config);
	else
		strcpy(configfilename,"MINMGAA CFG");
}



unsigned char ConfigurationExists(char *filename)
{
	if(!filename)
		filename=configfilename;	// Use slot-based filename if none provided.
	ChangeDirectory(0); // Config files always live in the root directory
    if (FileOpen(&file, filename))
    {
		return(1);
	}
	ClearError(ERROR_FILESYSTEM);
	return(0);
}


static const char config_id[] = "MNMGCFGA"; /* New signature for AGA core */

unsigned char CheckConfiguration(fileTYPE *cfgfile)
{
	unsigned char sector_buffer[1024];       // sector buffer - room for two consecutive sectors...
	if(cfgfile)
	{
		configTYPE *tmpconf=(configTYPE *)&sector_buffer;
        if (cfgfile->size <= sizeof(config))
        {
            if(FileRead(cfgfile, sector_buffer))
			{
				// A few sanity checks...
				if(tmpconf->floppy.drives>4)
					return(0);

	            // check file id and version
	            if (strncmp(tmpconf->id, config_id, sizeof(config.id)) != 0)
					return(0);

	            if(tmpconf->version>CONFIG_VERSION)
					return(0); // Config file is too new

				return(1);
			}
        }
	}
	return(0);
}


unsigned char LoadConfiguration(fileTYPE *cfgfile)
{
	int slot_based=cfgfile==NULL;
	int updatekickstart=0;
	int result=0;
	unsigned int key;
	unsigned char sector_buffer[1024];       // sector buffer - room for two consecutive sectors...

	if(!cfgfile)
	{
		cfgfile=&file;
		ChangeDirectory(0); // Slot-based config files always live in the root directory.
		if(!FileOpen(cfgfile,configfilename))
			cfgfile=0;
	}

    // load configuration data
    if(cfgfile)
    {
		configTYPE *tmpconf=(configTYPE *)&sector_buffer;
		BootPrint("Opened configuration file\n");
        INFO("Configuration file size: %lu\n", cfgfile->size);
        if (cfgfile->size <= sizeof(config))
        {
            if(!FileRead(cfgfile, sector_buffer))
				return(0);

			// A few more sanity checks...
			if(tmpconf->floppy.drives<=4)
			{
				// If either the old config and new config have a different kickstart file,
				// or this is the first boot, we need to upload a kickstart image.
				if(strncmp(tmpconf->kickstart.name,config.kickstart.name,8)!=0)
					updatekickstart=true;
				result=1; // We successfully loaded the config.
			}
			else
				BootPrint("Config file sanity check failed!\n");

            // check file id and version
            if (strncmp(tmpconf->id, config_id, sizeof(config.id)) != 0)
				result=0;

            if(tmpconf->version<CONFIG_VERSION_EXTROM)
			{
				BootPrint("Config file predates ExtROM support");
				strncpy(tmpconf->extrom.name, "EXTENDED", sizeof(config.extrom.name));
			}
            if(tmpconf->version<CONFIG_VERSION_ROMPATH)
			{
				BootPrint("Config file predates ROM Path support");
				tmpconf->kickdir=0;
				tmpconf->hdfdir[0]=tmpconf->hdfdir[1]=tmpconf->hdfdir[2]=tmpconf->hdfdir[3]=0;
				tmpconf->secondaryhardfile[0].enabled=0;
				tmpconf->secondaryhardfile[0].present=0;
				tmpconf->secondaryhardfile[0].name[0]=0;
				tmpconf->secondaryhardfile[0].long_name[0]=0;
				tmpconf->secondaryhardfile[1].enabled=0;
				tmpconf->secondaryhardfile[1].present=0;
				tmpconf->secondaryhardfile[1].name[0]=0;
				tmpconf->secondaryhardfile[1].long_name[0]=0;
			}
            if(tmpconf->version<CONFIG_VERSION_ROMPATH)
			{
				BootPrint("Config file predates Drivesounds support");
				tmpconf->drivesounds=0;
			}
			if(tmpconf->version>CONFIG_VERSION)
			{
				BootPrint("Wrong configuration file format!\n");
				result=0;
			}

			tmpconf->version=CONFIG_VERSION;
			if(result)
                memcpy((void*)&config, (void*)sector_buffer, sizeof(config));
        }
    }
    if(!result)
	{
        BootPrint("Config loading failed - using defaults\n");
		ClearError(ERROR_FILESYSTEM);
		// set default configuration
		memset((void*)&config, 0, sizeof(config));	// Finally found default config bug - params were reversed!
		strncpy(config.id, config_id, sizeof(config.id));
		strncpy(config.kickstart.name, "KICK    ", sizeof(config.kickstart.name));
		config.version = CONFIG_VERSION;
		config.misc = 1<<(PLATFORM_SCANDOUBLER);  // platform register - enable scandoubler by default
		config.kickstart.long_name[0] = 0;
		config.memory = 0x15;
		config.cpu = 0;
		config.chipset = 0;
		config.x_offset = 166;
		config.y_offset = 47;
		config.video_mode = 0;
		config.floppy.speed=CONFIG_FLOPPY2X;
		config.floppy.drives=1;
		config.enable_ide=0;
		config.hardfile[0].enabled = 1;
		strncpy(config.hardfile[0].name, "HARDFILE", sizeof(config.hardfile[0].name));
		config.hardfile[0].long_name[0]=0;
		strncpy(config.hardfile[1].name, "HARDFILE", sizeof(config.hardfile[1].name));
		config.hardfile[1].long_name[0]=0;
		config.hardfile[1].enabled = 2;	// Default is access to entire SD card
		updatekickstart=true;

		/* Version 2 configuration fields */
		strncpy(config.extrom.name, "EXTENDED", sizeof(config.extrom.name));

		BootPrint("Defaults set\n");
	}

    if(result)
    {
        active_configuration_slot=slot_based ? configuration_slot : -1;
        if(!slot_based)
        {
            if(cfgfile->long_name[0])
            {
                strncpy(active_configuration_name, cfgfile->long_name, CONFIG_TITLE_STORAGE_LENGTH);
                active_configuration_name[CONFIG_TITLE_STORAGE_LENGTH]=0;
            }
            else
            {
                unsigned int length=8;
                while(length && cfgfile->name[length-1]==' ') --length;
                memcpy(active_configuration_name, cfgfile->name, length);
                strcpy(active_configuration_name+length, ".CFG");
            }
        }
    }
    else
    {
        active_configuration_slot=-1;
        strcpy(active_configuration_name, "Built-in defaults");
    }
    return(result);
}


int ApplyConfiguration(char reloadkickstart, char applydrives, char ignoreoverclock)
{
	int rstval=0;
	int result=0;
	int romsize=0;
	int unit;
	char s[40];
//	INFO("c1: %x\n",CheckSum());

	// Whether or not we uploaded a kickstart image we now need to set various parameters from the config.

	if(applydrives)
	{
		for(unit=0;unit<HDF_COUNT;unit++)
		{
			if(OpenHardfile(unit))
			{
			//		INFO("c2: %x\n",CheckSum());
				switch(hdf[unit].type) // Customise message for SD card access
				{
					case (HDF_FILE | HDF_SYNTHRDB):
						snprintf(s, 32, "\nHardfile 0 (with fake RDB): %.8s.%.3s", hdf[unit].file.name, &hdf[unit].file.name[8]);
						break;
					case HDF_FILE:
						snprintf(s, 32, "\nHardfile 0: %.8s.%.3s", hdf[unit].file.name, &hdf[unit].file.name[8]);
						break;
					case HDF_CARD:
						snprintf(s, 32, "\nHardfile 0: using entire SD card");
						break;
					default:
						snprintf(s, 32, "\nHardfile 0: using SD card partition %d",hdf[unit].type-HDF_CARD);	// Number from 1
						break;
				}
				BootPrint(s);
				snprintf(s, 32, "CHS: %u.%u.%u", hdf[unit].cylinders, hdf[unit].heads, hdf[unit].sectors);
				BootPrint(s);
				snprintf(s, 32, "Size: %lu MB", ((((unsigned long) hdf[unit].cylinders) * hdf[unit].heads * hdf[unit].sectors) >> 11));
				BootPrint(s);
				snprintf(s, 32, "Offset: %ld", hdf[unit].offset);
				BootPrint(s);
			//		INFO("c3: %x\n",CheckSum());
			}
		}
		ConfigIDE(config.enable_ide&1, config.hardfile[0].present && config.hardfile[0].enabled,
			config.hardfile[1].present && config.hardfile[1].enabled);
		ConfigIDE((config.enable_ide>>1)|2, config.secondaryhardfile[0].present && config.secondaryhardfile[0].enabled,
			config.secondaryhardfile[1].present && config.secondaryhardfile[1].enabled);
	}

    int cpu = config.cpu;

    if (ignoreoverclock)
        cpu = cpu & ~CONFIG_OVERCLOCK;

    // restore default offset values when invalid
    if (config.x_offset == 0 || config.y_offset == 0) {
		config.x_offset = 166;
		config.y_offset = 48;
    }

    ConfigCPU(cpu);
    ConfigMemory(config.memory);
    ConfigChipset(config.chipset);
    ConfigFloppy(config.floppy.drives, config.floppy.speed);
    ConfigVideoOffset(config.x_offset, config.y_offset, config.video_mode);
    ConfigVideo(config.filter.hires, config.filter.lores, config.scanlines, config.video_mode);
    ConfigMisc(config.misc);

    if (reloadkickstart) {
		EnableOsd();
		SPI(OSD_CMD_RST);
		rstval |= (SPI_RST_CPU | SPI_CPU_HLT);
		SPI(rstval);
		DisableOsd();
		SPIN; SPIN; SPIN; SPIN;
		UploadActionReplay();
		if (romsize=UploadKickstart(config.kickdir,config.kickstart.name))
		{
			result=1;
		}
		else
		{
			strcpy(config.kickstart.name, "KICK    ");
			result=UploadKickstart(config.kickdir,config.kickstart.name);
		}
		if(result && romsize<1024)
		{
			/* Attempt to upload an extended ROM, but only if the kickstart file is less than a megabyte */
			if(!UploadExtROM(config.extromdir,config.extrom.name))
			{
				strcpy(config.extrom.name, "EXTENDED");
				result=UploadExtROM(config.extromdir,config.extrom.name);
			}
			ClearError(ERROR_FILESYSTEM); /* We don't need to report a missing ExtROM yet */
		}
    }
	return(result);
}


unsigned char SaveConfiguration(fileTYPE *cfgfile)
{
	unsigned char sector_buffer[1024];       // sector buffer - room for two consecutive sectors...
	if(!cfgfile)
	{
		cfgfile=&file;
		ChangeDirectory(0); // Slot-based config files always live in the root directory.
		if(!FileOpen(cfgfile,configfilename))
			cfgfile=0;
	}

    // save configuration data
    if (cfgfile)
    {
        if (file.size != sizeof(config))
        {
            file.size = sizeof(config);
            if (!UpdateEntry(&file))
                return(0);
        }

        memset((void*)&sector_buffer, 0, sizeof(sector_buffer));
        memcpy((void*)&sector_buffer, (void*)&config, sizeof(config));
        FileWrite(&file, sector_buffer);
        return(1);
    }
    else
    {
		ClearError(ERROR_FILESYSTEM);
        INFO("Configuration file not found!\n");
        INFO("Trying to create a new one...\n");
        strncpy(file.name, configfilename, 11);
        file.attributes = 0;
        file.size = sizeof(config);
        INFO("Config size is %x (%x) - address is %x\n",sizeof(config),file.size,&config);
        if (FileCreate(0, &file))
        {
            INFO("File created.\n");
            INFO("Trying to write new data...\n");
            memset((void*)sector_buffer, 0, sizeof(sector_buffer));
            memcpy((void*)sector_buffer, (void*)&config, sizeof(config));

            if (FileWrite(&file, sector_buffer))
            {
                INFO("File written successfully.\n");
                return(1);
            }
            else
                ERR("File write failed!\n");
        }
        else
            ERR("File creation failed!\n");
    }
    return(0);
}

