#include <stdio.h>

#include "interrupts.h"

#include "akiko.h"

void akiko_inthandler()
{
	unsigned int aa;
	unsigned int ad;

	aa=HW_AKIKO(REG_AKIKO_ADDR);
	ad=HW_AKIKO(REG_AKIKO_DATA);
	if(aa&AKIKO_REQ)
	{
//		if(aa&AKIKO_WRITE)
//			printf("Akiko write: %x, %x\n",aa,ad);
//		else
//			printf("Akiko read: %x\n",aa);
		HW_AKIKO(REG_AKIKO_DATA)=0;
	}

}

__constructor(101.akiko) void akikoconstructor()
{
}

