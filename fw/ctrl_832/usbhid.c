#include <stdio.h>
#include "usbhid.h"
#include "usbhid_keycodes.h"
#include "c64keys.h"
#include "menu.h"
#include "osd.h"

#define KEYPAGES 5
unsigned int usbhid_prevtable[KEYPAGES];
unsigned int usbhid_keytable[KEYPAGES];

struct usbhidport usbhid_ports[USBHID_PORTS];

static int mouse_buttons0=0;
static int mouse_buttons1=0;


static void usbhid_initport(struct usbhidport *port) {
	port->flags=0;
	port->type=NONE;
	port->ptr=0;
	port->serial=-1;
}

int usbhid_testkey(unsigned char code) {
	int t=usbhid_keytable[code>>5];
	return(t&(1<<(code&31)));
}

static void usbhid_setkey(unsigned char code) {
	usbhid_keytable[code>>5]|=1<<(code&31);
}

//		kbd_mouse_data <= c64_translated_key_stb ? c64_translated_key[7:0] : AMIGA_KEY;
//		kbd_mouse_type <= c64_translated_key_stb ? c64_translated_key[15:14] : 2'b00;
//		mouse0_buttons <= c64_translated_key_stb ? c64_translated_key[10:8] : 3'b000;
//		mouse1_buttons <= c64_translated_key_stb ? c64_translated_key[13:11] : 3'b000;
		
static void usbhid_send(int type,int code) {
	int t=type<<14;
	t|=mouse_buttons0<<8;
	t|=code;
	HW_KEYBOARD(REG_KEYBOARD_OUT)=t;
}

int joykeys_status;

/* Returns 1 if the code should be passed through to the core */
static int usbhid_joykeys(int code) {
	static char joyemu=0;
	int rc=osd_visible ? code : 0; // Swallow keycodes unless OSD is visible.

	if(code==HIDKEY_NUMLOCK) {
		joyemu ^=1;
		InfoMessage(joyemu ? "Joystick keys on" : "Joystick keys off");
		return(0);
	}

	if(!joyemu)
		return(1);

	switch(code) {
		case HIDKEY_UP :
			joykeys_status |= 8;
			return(rc);
			break;
		case HIDKEY_DOWN :
			joykeys_status |= 4;
			return(rc);
			break;
		case HIDKEY_LEFT :
			joykeys_status |= 2;
			return(rc);
			break;
		case HIDKEY_RIGHT :
			joykeys_status |= 1;
			return(rc);
			break;
		default : 
			break;
	}
	return(1);
}

static int usbhid_joyquals(int quals) {
	if(quals&HIDQUAL_LCTRL) {
		quals ^= HIDQUAL_LCTRL;
		joykeys_status |= 0x10;		
	}
	if(quals&HIDQUAL_LALT) {
		quals ^= HIDQUAL_LALT;
		joykeys_status |= 0x20;		
	}
	return(quals);
}

static void usbhid_handlekb(struct usbhidport *port) {
	int i;
	int code=0;
		
	for(i=0;i<KEYPAGES;++i) {
		usbhid_prevtable[i]=usbhid_keytable[i];
		usbhid_keytable[i]=0;
	}

	joykeys_status=0;

	/* Test for Ctrl-Amiga-Amiga key combo */
	if(!(port->pkt[0] ^ (HIDQUAL_LCTRL | HIDQUAL_LALT | HIDQUAL_RALT)))
		OsdReset();

	usbhid_keytable[4]=usbhid_joyquals(port->pkt[0]);
	for(i=0;i<6;++i) {
		int key=port->pkt[2+i];
		if(key && usbhid_joykeys(key) && key<128) {
			usbhid_setkey(key);
		}
	}

	HW_USBHID(REG_USBHID_JOYKEYS)=~joykeys_status;
	
	for(i=0;i<KEYPAGES;++i) {
		int t=usbhid_prevtable[i]^usbhid_keytable[i];
		int k=usbhid_keytable[i];
		int j;
		if(t) {
			for(j=0;j<32;++j) {
				if(t&1) {
					if(k&1) {
						usbhid_send(2,usb2ami[code]);
						printf("Key %d down\n",code);
					} else {
						usbhid_send(2,usb2ami[code]|0x80);
						printf("Key %d up\n",code);
					}
				}
				t>>=1;
				k>>=1;
				++code;
			}
		}	
		else
			code+=32;
	}

}

static void usbhid_handlemouse(struct usbhidport *port) {
	mouse_buttons0=port->pkt[0];
	usbhid_send(0,port->pkt[1]);
	usbhid_send(1,port->pkt[2]);
//	printf("Mouse buttons: %d, dx: %d, dy %d\n",(int)port->pkt[0],(int)port->pkt[1],(int)port->pkt[2]);
}

void usbhid_handleport(struct usbhidport *port,int v) {
	int serial=(v>>8) & 0xf;
	int pktype=(v>>12) & 3;
	if(port->serial!=serial) {
		port->ptr=0;
		port->serial=serial;
	}
	switch(pktype) {
		case 0:
			port->pkt[port->ptr++]=v&0xff;
			port->ptr&=0x7; // FIXME - might be better to clamp rather than wrap around?
			
			if((port->flags&3)==3) {
				switch(port->type) {
					case KEYBOARD:
						if(port->ptr==0)
							usbhid_handlekb(port);
						break;
					case MOUSE:
						if(port->ptr==3)
							usbhid_handlemouse(port);
						break;
					default:
						break;
				}
			}
			break;
			
		case 1:
			{
				int r=(v>>4) & 0xf;
				int b=v & 0xf;
				if(r==4 && port->pkt[b]==3)  // HID device?
					port->flags|=1;
				if(r==5 && port->pkt[b]==1)  // Boot protocol?
					port->flags|=2;
				if(r==6) {
					port->type=port->pkt[b];
					printf("P: %d, t: %d, f: %d\n",port==&usbhid_ports[0] ? 0 : 1,port->type, port->flags);
					InfoMessage(port->type==KEYBOARD ? "Keyboard connected" : port->type==MOUSE ? "Mouse connected" : "Unknown device connected");
				}
			}
			break;
			
		default:
			break;
	}
}

__constructor(102.usbhid) void usbhid_init() {
	usbhid_initport(&usbhid_ports[0]);
	usbhid_initport(&usbhid_ports[1]);
	puts("USB HID init\n");
	HW_USBHID(REG_USBHID_STATUS)=0; /* Trigger a reset */
}

void usbhid_handle()
{
	while(HW_USBHID(REG_USBHID_STATUS)&USBHID_STATUS_ATN) {
		int t=HW_USBHID(REG_USBHID_DATA);
		int port=(t>>14)&3;
//		printf("Port %d: %x\n",port,t&0xff);
		usbhid_handleport(&usbhid_ports[port],t);
	}
}

