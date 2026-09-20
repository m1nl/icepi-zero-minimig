#include <stdio.h>

#include "hardware.h"
#include "interrupts.h"
#include "amiga_rawkey.h"
#include "c64keys.h"

#define QUAL_SPECIAL 0x8000	/* Key emits a different keycode if shift is held */
#define QUAL_LAYERKEY 0x4000 /* This key causes layers to switch */
#define QUAL_ALTLAYER 0x2000 /* Last keydown event happened while ctrl was held */
#define QUAL_LSHIFT 0x100
#define QUAL_RSHIFT 0x200
#define QUAL_CTRL 0x400
#define QUAL_BLOCKLAYER 0x800	/* R Amiga key or R Alt key - used to cancel layer shifting with quals */
#define QUAL_MASK 0x7f00

/*
Need to support multiple layers.
Ideally want shift keypresses to transfer between layers.
Need to make the layer sticky when a key is pressed, so the
key release event always matches the key press event.
The keytable currently contains 32-bit ints so plenty of room
for storing layer details in the map.
If just two layers will be sufficient, could simply store a second
entry shifted left 16 bits, accessed when the "Fn" key is held.
Use Run/Stop as an "Fn" key
*/


struct c64keyboard c64keys;


struct keyspecial
{
	unsigned char unshifted,shifted;
};

struct keyspecial specialtable[]=
{
	{RK_Right,RK_Left},	/* cursor keys */
	{RK_Down,RK_Up},
	{RK_F1,RK_F2},	/* F keys */
	{RK_F3,RK_F4},
	{RK_F5,RK_F6},
	{RK_F7,RK_F8}
};

#define LAYER(x,y) ((x&0xffff)<<16)|(y)

unsigned int keytable[]=
{
	RK_BackSpace, /* $00	Inst/Del */
	LAYER(RK_Enter,RK_Return), /* $01	Return */
	LAYER(QUAL_BLOCKLAYER|RK_RAmiga,QUAL_SPECIAL|0), /* $02	Crsr l/r	- special handling needed */
	LAYER(RK_Help,QUAL_SPECIAL|5), /* $03	F7/F8 */
	LAYER(RK_F9,QUAL_SPECIAL|2), /* $04	F1/F2 */
	LAYER(RK_F10,QUAL_SPECIAL|3), /* $05	F3/F4 */
	QUAL_SPECIAL|4, /* $06	F5/F6 */
	LAYER(QUAL_BLOCKLAYER|RK_RAlt,QUAL_SPECIAL|1), /* $07	Crsr u/d	- special handling needed */

	RK_3,  /* $08	3 */
	RK_W, /* $09	W */
	RK_A, /* $0A	A */
	RK_4, /* $0B	4 */
	RK_Z, /* $0C	Z */
	RK_S, /* $0D	S */
	RK_E, /* $0E	E */
	LAYER(QUAL_BLOCKLAYER|RK_LAlt,QUAL_LSHIFT|RK_LShift), /* $0F	Left Shift - special handling needed */

	RK_5, /* $10	5 */
	RK_R, /* $11	R */
	RK_D, /* $12	D */
	RK_6, /* $13	6 */
	RK_C, /* $14	C */
	RK_F, /* $15	F */
	RK_T, /* $16	T */
	RK_X, /* $17	X */

	LAYER(RK_NK7,RK_7), /* $18	7 */
	RK_Y, /* $19	Y */
	RK_G, /* $1A	G */
	LAYER(RK_NK8,RK_8), /* $1B	8 */
	RK_B, /* $1C	B */
	RK_H, /* $1D	H */
	LAYER(RK_NK4,RK_U), /* $1E	U */
	RK_V, /* $1F	V */

	LAYER(RK_NK9,RK_9), /* $20	9 */
	LAYER(RK_NK5,RK_I), /* $21	I */
	LAYER(RK_NK1,RK_J), /* $22	J */
	LAYER(RK_NKSlash,RK_0), /* $23	0 */
	LAYER(RK_NK0,RK_M), /* $24	M */
	LAYER(RK_NK2,RK_K), /* $25	K */
	LAYER(RK_NK6,RK_O), /* $26	O */
	RK_N, /* $27	N */

	RK_Equals, /* $28	+ */
	LAYER(RK_NKAsterisk,RK_P), /* $29	P */
	LAYER(RK_NK3,RK_L), /* $2A	L */
	RK_Minus, /* $2B	− */
	LAYER(RK_Point,RK_Period), /* $2C	> */
	LAYER(RK_NKMinus,RK_Semicolon), /* $2D	[ */
	LAYER(RK_NKLeftBracket,RK_LeftBrace), /* $2E	@ */
	RK_Comma, /* $2F	< */
	
	RK_BackSlash, /* $30	£ */
	LAYER(RK_NKRightBracket,RK_RightBrace), /* $31	* */
	RK_Apostrophe, /* $32	] */
	RK_Delete, /* $33	Clr/ Home */
	QUAL_RSHIFT|RK_RShift, /* $34	Right shift - special handling needed */
	LAYER(RK_RightIntl,RK_Tick), /* $35	= */
	RK_LeftIntl, /* $36	↑ */
	LAYER(RK_NKPlus,RK_Slash), /* $37	? */

	RK_1, /* $38	1 */
	LAYER(RK_MinimigMenu,RK_Esc), /* $39	← */
	LAYER(RK_Tab,QUAL_CTRL|RK_Ctrl), /* $3A	Control */
	RK_2, /* $3B	2 */
	RK_Space, /* $3C	Space */
	QUAL_BLOCKLAYER|RK_LAmiga, /* $3D	Commodore */
	RK_Q, /* $3E	Q */
	QUAL_LAYERKEY  /* $3F	Run/Stop */
};


void c64keyboard_write(struct c64keyboard *r,int in)
{
/*	Can't wait for the ringbuffer to empty if we're going to fill it from
	within an interrupt.  We will have to accept that keystrokes will be lost
	in the unlikely event that we fill it quicker than we empty it. */
/*	while(r->out_hw==((r->out_cpu+1)&(RINGBUFFER_SIZE-1)))
		;
	DisableInterrupts(); */
	r->outbuf[r->out_cpu]=in;
	r->out_cpu=(r->out_cpu+1) & (C64KEY_RINGBUFFER_SIZE-1);
/*	EnableInterrupts(); */
}


void c64keys_inthandler()
{
	int i;
	int count=0;
	int idx=63;
	int nextframe=(c64keys.frame+4)%12;
	int prevframe=(c64keys.frame+8)%12;

	unsigned int aa;
	unsigned int ad;

	for(i=0;i<4;++i)
	{
		unsigned int t=HW_KEYBOARD(REG_KEYBOARD_WORD0+4*i);
		c64keys.keys[c64keys.frame+i]=t;
		while(t)	/* Count the number of set bits */
		{
			t&=t-1;
			++count;
		}
	}

	/* 	Very unlikely that more than four keys are depressed, so if that happens
		we're probably looking at interference from the joystick port. */
	if(count>=60)
	{
		for(i=0;i<4;++i)
		{
			int j;

			/*  Keystroke detection:
				The C64 keyboard shares lines with joystick port 1, so reading the keyboard robustly
				is difficult.  The above test filters out reading where a whole row is shorted to ground
				by the joystick, but we can still get transients if the joystick event happens while scanning the keyboard.
				We therefore filter the data with an edge-detection:

				nextframe contains the data from two frames ago, prevframe and c64frame are self-explanatory.
				Edge detection works like this:  (A is nextframe, B is prevframe, C is c64frame)
				A B C	Edge?
				0 0 0	0	- key is held down
				0 0 1	0	- key release
				0 1 0	0	- transient
				0 1 1	1	- key release, stable
				1 0 0	1	- key press, stable
				1 0 1	0	- transient keypress
				1 1 0	0	- keypress, not yet verified
				1 1 1	0	- key up.

				edge = (A^B) & (A^C)
			*/

			unsigned int changed=(c64keys.keys[nextframe+i]^c64keys.keys[prevframe+i])
										&(c64keys.keys[nextframe+i]^c64keys.keys[c64keys.frame+i]);
			unsigned int status=c64keys.keys[c64keys.frame+i];
			for(j=0;j<16;++j)
			{
				--idx;
				if(changed&0x8000)
				{
					int code=63-(i*16+j);	/* Fetch Amiga scancode for this key */
					int amicode;
					int amiqualup=0;
					int amiqualdown=0;
					int keyup=status&0x8000;
					c64keys.active=1;
					code=((code<<3)|(code>>3))&63;	/* bit numbers are transposed compared with c64 scancodes */
					amicode=keytable[code];

					/* Has the run/stop key (acting as Fn) been pressed? */
					if(amicode&QUAL_LAYERKEY)
					{
						if(keyup)	/* Key up? */
							c64keys.layer=0;
						else
							c64keys.layer=1;
					}
					else
					{
						/* If this is a keyup event, make sure it happens on the same layer as the corresponding keydown. */
						if(keyup) /* key up? */
						{
							if(amicode&QUAL_ALTLAYER) /* Was the keydown on the alternative layer? */
								amicode>>=16;
							keytable[code]&=~QUAL_ALTLAYER;
						}
						/* Otherwise generate a keydown for the appropriate layer */
						else if(c64keys.layer && (amicode>>16))
						{
							/* Cancel the second layer for non-qualifier keys if qualifiers are pressed */
						 	if (!(c64keys.qualifiers&QUAL_BLOCKLAYER) || ((amicode>>16)&QUAL_BLOCKLAYER))
							{
								keytable[code]|=QUAL_ALTLAYER;
								amicode>>=16;
							}
						}

						if(amicode&QUAL_SPECIAL)
						{
							/* If the key requires special handling, cancel any shifting before sending the key code
								unless both shift keys are down */
							int qual=QUAL_LSHIFT | QUAL_RSHIFT;
							if(keyup)
								qual&=amicode;
							else
							{
								/* On downstroke remember which qualifiers were held when the key was pressed. */
								amicode=(amicode&~qual); /* Mask off previous quals */
								qual&=c64keys.qualifiers;
								amicode|=qual;
								keytable[code]=amicode;
							}
							switch(c64keys.qualifiers&(QUAL_LSHIFT|QUAL_RSHIFT))
							{
								case 0:
									amicode=specialtable[amicode&0xff].unshifted;
									break;
								case QUAL_LSHIFT:
									amicode=specialtable[amicode&0xff].shifted;
									if(keyup)
										amiqualdown=0x60;
									else
										amiqualup=0x60|0x80;
									break;
								case QUAL_RSHIFT:
									amicode=specialtable[amicode&0xff].shifted;
									if(keyup)
										amiqualdown=0x61;
									else
										amiqualup=0x61|0x80;
									break;
								default:
									amicode=specialtable[amicode&0xff].shifted;
									break;
							}
						}
						if(keyup)
						{
							amicode|=0x80; /* Key up */
							c64keys.qualifiers&=(~amicode)&QUAL_MASK;
						}
						else
							c64keys.qualifiers|=amicode&QUAL_MASK;
						if(amiqualup)
							c64keyboard_write(&c64keys,amiqualup);
						c64keyboard_write(&c64keys,amicode);
						if(amiqualdown)
							c64keyboard_write(&c64keys,amiqualdown);
					}
				}
				changed<<=1;
				status<<=1;
			}
		}
		c64keys.frame=nextframe;
	}

	if(c64keys.out_hw!=c64keys.out_cpu)
	{
		HW_KEYBOARD(REG_KEYBOARD_OUT)=c64keys.outbuf[c64keys.out_hw];
		c64keys.out_hw=(c64keys.out_hw+1) & (C64KEY_RINGBUFFER_SIZE-1);
	}
}

int c64keyboard_checkreset()
{
	int result=0;
	DisableInterrupts();
	if(c64keys.active)
	{
		if((c64keys.qualifiers&QUAL_MASK)==(QUAL_LSHIFT|QUAL_RSHIFT|QUAL_CTRL))
			result=1;
		c64keys.active=0;
	}
	EnableInterrupts();
	return(result);
}

__constructor(101.c64keys) void c64keysconstructor()
{
	int i;
	for(i=0;i<8;++i)
		c64keys.keys[i]=0xffff;
	c64keys.frame=0;
	c64keys.layer=0;
	c64keys.qualifiers=0;
	c64keys.out_hw=0;
	c64keys.out_cpu=0;
}

