#include "audio.h"
#include "hardware.h"


int audio_busy(int buffer)
{
	return((AUDIO&1)==buffer);
}


void audio_start()
{
	AUDIO=AUDIOF_ENA;
}


void audio_stop()
{
	AUDIO=AUDIOF_CLEAR;
}

void audio_clear()
{
	unsigned char *p=(unsigned char *)AUDIO_BUFFER;
	int i;
	AUDIO=AUDIOF_CLEAR;
	for(i=0;i<AUDIO_BUFFER_SIZE*2;++i)
	{
		p[i]=0;
	}
	AUDIO=AUDIOF_ENA;
	i=TIMER;
	while(TIMER==i)
		;
	AUDIO=AUDIOF_CLEAR;
}

