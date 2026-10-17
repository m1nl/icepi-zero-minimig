#include <stdio.h>

#include "errors.h"
#include "osd.h"

void ClearError(int category)
{
	int i,a,b;
	if(category!=ERROR_ALL)
	{
		ErrorMask&=~(1<<category);
		a=b=category;
	}
	else
	{
		a=0;
		b=ERROR_MAX;
		ErrorMask=0;
		ErrorFatal=0;
	}
	for(i=a;i<=b;++i)
	{
		Errors[i].string="";
		Errors[i].a=0;
		Errors[i].b=0;
		Errors[i].details=0;
		Errors[i].detail_count=0;
	}
}

void SetError(int errortype,const char *msg,int y,int z)
{
	/* A detailed pending report is a snapshot, retained until acknowledgement. */
	if ((ErrorMask & (1<<errortype)) && Errors[errortype].detail_count) return;
	ErrorMask|=(1<<errortype);
	Errors[errortype].string=msg;
	Errors[errortype].a=y;
	Errors[errortype].b=z;
	Errors[errortype].details=0;
	Errors[errortype].detail_count=0;
	printf("%s error: %s, %x, %x\n",ErrorMessages[errortype],msg,y,z);
}

void FatalError(int errortype,const char *msg,int y,int z)
{
	SetError(errortype,msg,y,z);
	ErrorFatal=1;
}

int ErrorFatal=0;
int ErrorMask=0;

char *ErrorMessages[ERROR_MAX+1]=
{
	"SD Card",
	"Filesystem",
	"Kickstart ROM",
	"Floppy emulation",
	"Harddrive emulation",
	"General Error"
};


struct Error Errors[ERROR_MAX+1];


/* Detail storage belongs to the reporter and remains valid until acknowledgement. */
void SetErrorDetails(int category, const char (*lines)[ERROR_DETAIL_WIDTH], unsigned int count)
{
	Errors[category].details=lines;
	Errors[category].detail_count=lines ? count : 0;
}

unsigned int ErrorPageCount(int category)
{
	unsigned int count=Errors[category].detail_count;
	return count ? (count+ERROR_DETAIL_ROWS-1)/ERROR_DETAIL_ROWS : 1;
}

/* Render all eight rows so stale text cannot survive a page/category change. */
void DrawErrorPage(int category, unsigned int page)
{
	char line[ERROR_DETAIL_WIDTH];
	unsigned int row, index, pages=ErrorPageCount(category);
	struct Error *error=&Errors[category];
	unsigned char inactive=!(ErrorMask & (1<<category));

	if (page>=pages) page=0;

	OsdSetTitle("Error",OSD_ARROW_LEFT|OSD_ARROW_RIGHT);
	OsdWrite(0,ErrorFatal ? "      *** FATAL ERROR ***" : "         *** ERROR ***",1,0);

	if (error->detail_count) {
		snprintf(line,sizeof(line)," %s %u/%u",ErrorMessages[category],page+1,pages);
		OsdWrite(1,line,0,inactive);
		snprintf(line,sizeof(line)," %s",error->string);
		OsdWrite(2,line,0,inactive);

		for (row=0;row<ERROR_DETAIL_ROWS;++row) {
			index=page*ERROR_DETAIL_ROWS+row;
			OsdWrite(row+3,index<error->detail_count ? (char*)error->details[index] : "",0,inactive);
		}
		OsdWrite(7,ErrorFatal ? " Reboot     < > details" : " OK         < > details",1,0);

	} else {
		OsdWrite(1,"",0,inactive);
		snprintf(line,sizeof(line)," %s",ErrorMessages[category]);
		OsdWrite(2,line,0,inactive);
		snprintf(line,sizeof(line)," %s",error->string);
		OsdWrite(3,line,0,inactive);
		snprintf(line,sizeof(line)," %x",error->a);
		OsdWrite(4,line,0,inactive);
		snprintf(line,sizeof(line)," %x",error->b);
		OsdWrite(5,line,0,inactive);
		OsdWrite(6,"",0,0);
		OsdWrite(7,ErrorFatal ? "           Reboot" : "             OK",1,0);
	}
}
