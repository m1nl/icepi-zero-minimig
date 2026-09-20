#ifndef HARDWARE_H
#define HARDWARE_H

#include "spi.h"

/* 0x680000 is 0xe80000 in Amiga space */
#define HOSTMAP_ADDR 0x680000

#define DISKLED_ON  // *AT91C_PIOA_SODR = DISKLED;
#define DISKLED_OFF // *AT91C_PIOA_CODR = DISKLED;

#define AUDIO (*(volatile unsigned char *)0x0fffffb3)
#define AUDIOF_CLEAR 2
#define AUDIOF_ENA 1
#define AUDIOF_AMIGA 2

/* AUDIO_BUFFER at host address 0x70000, is 0xef0000 in Amiga space */
#define AUDIO_BUFFER 0x70000
/* We have two alternating buffers of this size */
#define AUDIO_BUFFER_SIZE 0x8000

#define HW_SPI(x) (*(volatile unsigned char *)(0x0fffffe0 + x))
#define HW_SPI_CS 7
#define HW_SPI_DATA 3
#define HW_SPI_SPEED 11

#define RS232(x) (*(volatile unsigned char *)0x0ffffff3) = x

// TIMER ticks every 1/44100, so 1 tick is ~22.68us
// on HW side, timer is 24-bit so extend it by 8 bits
#define HW_TIMER ((*(volatile unsigned long *)0x0fffffd0) << 8)
#define TIMER_MS_TO_TICKS(x) ((unsigned long)(x) * 11290UL)

#define SPIN                                                                                                          \
    {                                                                                                                 \
        int v = HW_TIMER;                                                                                             \
        v = HW_TIMER;                                                                                                 \
        v = HW_TIMER;                                                                                                 \
        v = HW_TIMER;                                                                                                 \
    }; // Waste a few cycles to let the FPGA catch up

#define KEYBOARDBASE 0x0fffff90
#define HW_KEYBOARD(x) *(volatile unsigned short *)(KEYBOARDBASE + x)

#define REG_KEYBOARD_WORD0 2
#define REG_KEYBOARD_WORD1 6
#define REG_KEYBOARD_WORD2 0xa
#define REG_KEYBOARD_WORD3 0xe

#define REG_KEYBOARD_OUT 2
#define REG_JOYSTICK_0_OUT 6
#define REG_JOYSTICK_1_OUT 10

#define EnableCard() HW_SPI(HW_SPI_CS) = 0x02
#define DisableCard() HW_SPI(HW_SPI_CS) = 0x03
#define EnableUIO() HW_SPI(HW_SPI_CS) = 0x08
#define DisableUIO() HW_SPI(HW_SPI_CS) = 0x09
#define EnableFpga() HW_SPI(HW_SPI_CS) = 0x10
#define DisableFpga() HW_SPI(HW_SPI_CS) = 0x11
#define EnableOsd() HW_SPI(HW_SPI_CS) = 0x20
#define DisableOsd() HW_SPI(HW_SPI_CS) = 0x21
#define EnableDMode() HW_SPI(HW_SPI_CS) = 0x40
#define DisableDMode() HW_SPI(HW_SPI_CS) = 0x41
#define EnableRTC() HW_SPI(HW_SPI_CS) = 0x80
#define DisableRTC() HW_SPI(HW_SPI_CS) = 0x81

#define SPI_slow() HW_SPI(HW_SPI_SPEED) = 0x3f
#define SPI_fast() HW_SPI(HW_SPI_SPEED) = 0x1

// Yuk.  The following monstrosity does a dummy read from the timer register, writes, then reads from
// the SPI register.  Doing it this way works around a timing issue with ADF writing when GCC optimisation is turned
// on.
// #define SPI(x) (*(volatile unsigned short *)0xDEE010,*(volatile unsigned char *)0xda4000=x,*(volatile unsigned char
// *)0xda4000)

#define SPI(x) (HW_SPI(HW_SPI_DATA) = x, HW_SPI(HW_SPI_DATA))
#define RDSPI HW_SPI(HW_SPI_DATA)

#define HW_AUX_SPI *(volatile unsigned int *)(0x0fffff40)

// A 16-bit register for platform-specific config.
#define PLATFORM (*(volatile unsigned short *)0x0fffffc2)

#define PLATFORM_MENUBUTTON 0
#define PLATFORM_32MEG 1
#define PLATFORM_SPIRTC 2
#define PLATFORM_RECONFIG 3
#define PLATFORM_IECSERIAL 4
#define PLATFORM_CLOCKPORT 5
#define PLATFORM_C64CARTRIDGE 6
#define PLATFORM_HRTMONCART 7
#define PLATFORM_VIDEO_FILTER 8
#define PLATFORM_AUDIO 9
#define PLATFORM_AMIGAHOST 10
#define PLATFORM_USBHID 11
#define PLATFORM_AUXSPI 12
#define PLATFORM_UART 13

// On write:
//   Bit 0 -> Scandoubler enable
//   Bit 8 -> Reconfig, if supported.

#define PLATFORM_SCANDOUBLER 0
#define PLATFORM_INVERTSYNC 1

// Write to this register to reconfigure the FPGA on devices which support such operations.
#define RECONFIGURE (*(volatile unsigned short *)0xDEE016)

#define RAMFUNC // Used by ARM

#define SPI_RST_USR 0x1
#define SPI_RST_CPU 0x2
#define SPI_CPU_HLT 0x4

static inline unsigned long CheckButton(void) { return (PLATFORM & (1 << PLATFORM_MENUBUTTON)) == 0; }

static inline unsigned long GetTimer(unsigned short offset_ms) {
    unsigned long now = HW_TIMER;
    if (offset_ms != 0) {
        now += TIMER_MS_TO_TICKS(offset_ms);
    }
    return now;
}

static inline int CheckTimer(unsigned long deadline) {
    unsigned long now = HW_TIMER;
    return (long)(now - deadline) >= 0;
}

static inline void WaitTimer(unsigned short delay_ms) {
    unsigned long deadline = GetTimer(delay_ms);
    while (!CheckTimer(deadline))
        ;
}

static inline void ConfigMisc(unsigned short misc) { PLATFORM = misc; }

static inline void Reconfigure() { PLATFORM = (1 << PLATFORM_RECONFIG); }

static inline void SendKeypress(unsigned char ami, unsigned short delay_ms) {
    int t = (2 << 14) | ((unsigned int)ami);
    HW_KEYBOARD(REG_KEYBOARD_OUT) = t;
    WaitTimer(delay_ms);
    t = (2 << 14) | ((unsigned int)(ami | 0x80));
    HW_KEYBOARD(REG_KEYBOARD_OUT) = t;
    WaitTimer(delay_ms);
}

void EnableIECSerial();
void DisableIECSerial();

#endif
