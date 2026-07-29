#include "aux_hid.h"
#include "aux_spi.h"
#include "c64keys.h"
#include "config.h"
#include "osd.h"
#include <stdio.h>

/* Defined in usbhid_keycodes.h, which is only ever #included from usbhid.c
 * (it defines the array, not just declares it). Forward-declare instead of
 * including that header here to avoid a duplicate-definition link error. */
extern const unsigned short usb2ami[256];

#define MISS 0xff

/* Keyboard reports encode modifiers as raw bit index (0-7) + 0x68, see notes. */
#define AUX_HID_MOD_BASE 0x68

static int aux_mouse_buttons0 = 0;
static unsigned char aux_qual = 0;

static inline void aux_hid_send(int type, int code) {
    int t = (type << 14) | (aux_mouse_buttons0 << 8) | (code & 0xff);
    HW_KEYBOARD(REG_KEYBOARD_OUT) = t;
}

static void aux_hid_handlekb(const unsigned char *p) {
    unsigned char code = p[0];
    unsigned char is_break = code & 0x80;
    unsigned char raw = code & 0x7f;
    unsigned short ami;

    if (raw >= AUX_HID_MOD_BASE && raw < AUX_HID_MOD_BASE + 8) {
        unsigned char bit = raw - AUX_HID_MOD_BASE;

        if (is_break)
            aux_qual &= ~(1 << bit);
        else
            aux_qual |= (1 << bit);

        /* Ctrl-Amiga-Amiga reset combo (LCtrl + LAlt + RAlt), same as usbhid.c */
        if (!(aux_qual ^ 0x45))
            OsdReset();

        ami = usb2ami[0x80 + bit];
    } else {
        ami = usb2ami[raw];
    }

    if (ami == MISS)
        return;

    DBG("AUX KB: raw=%02x ami=%02x %s\n", raw, ami, is_break ? "up" : "down");
    aux_hid_send(2, is_break ? (ami | 0x80) : ami);
}

static void aux_hid_handlemouse(const unsigned char *p) {
    DBG("AUX MOUSE: btn=%02x dx=%d dy=%d\n", p[0], (signed char)p[1], (signed char)p[2]);

    aux_mouse_buttons0 = p[0];
    aux_hid_send(0, (signed char)p[1]); /* X */
    aux_hid_send(1, (signed char)p[2]); /* Y */
}

__constructor(102.aux_hid) void aux_hid_init(void) { puts("AUX HID init\n"); }

void aux_hid_handle(void) {
    unsigned char buf[AUX_SPI_BUFFER_SIZE];
    unsigned int len = AUX_SPI_BUFFER_SIZE;

    aux_spi_read((char *)buf, &len);

    if (len < 2 || buf[0] != SPI_TARGET_HID)
        return;

    switch (buf[1]) {
        case SPI_HID_KEYBOARD:
            if (len >= 4)
                aux_hid_handlekb(&buf[2]);
            break;
        case SPI_HID_MOUSE:
            if (len >= 5)
                aux_hid_handlemouse(&buf[2]);
            break;
        default:
            DBG("AUX HID: ignoring type=%d\n", buf[1]);
            break;
    }
}
