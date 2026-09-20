#ifndef C64KEYS_H
#define C64KEYS_H

#define C64KEY_RINGBUFFER_SIZE 16

struct c64keyboard
{
	int active;
	int frame;
	int layer;
	int qualifiers;
	unsigned short keys[12];
	volatile int out_hw;
	volatile int out_cpu;
	unsigned int outbuf[C64KEY_RINGBUFFER_SIZE];
};

extern struct c64keyboard c64keys;

void c64keyboard_init(struct c64keyboard *r);
void c64keyboard_write(struct c64keyboard *r,int in);
int c64keyboard_checkreset();
void c64keys_inthandler();

#endif
