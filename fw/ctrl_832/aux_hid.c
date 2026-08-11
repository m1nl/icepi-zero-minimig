#include "aux_hid.h"
#include "aux_spi.h"
#include "c64keys.h"
#include "config.h"
#include "osd.h"
#include "usbhid.h"
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

static inline void aux_joy_send(unsigned char index, unsigned short joy) {
    // reverse index by default, to make joystick 2 to
    // the default one unless USB HID already handles it
#if USBHID_PORTS >= 2
    if (usbhid_get_typ(1) != USBHID_GAMEPAD)
#endif
        index += 1;

    if (index & 0x01)
        HW_KEYBOARD(REG_JOYSTICK_1_OUT) = joy;
    else
        HW_KEYBOARD(REG_JOYSTICK_0_OUT) = joy;
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
    aux_hid_send(0, MouseScale((signed char)p[1])); /* X */
    aux_hid_send(1, MouseScale((signed char)p[2])); /* Y */
}

// Amiga joystick (from LSB)
// RLDU ABYX RB LB EJECT(ESC) OSD(MINIMIG-CUSTOM)
// X-Input -> LB  = 0x1
//         -> RB  = 0x2
//         -> STA = 0x8
//         -> SEL = 0x4

#define JOY_XINPUT_LB 0x1
#define JOY_XINPUT_RB 0x2

#define JOY_XINPUT_SEL 0x4
#define JOY_XINPUT_STA 0x8

#define JOY_AMIGA_RB 0x100
#define JOY_AMIGA_LB 0x200
#define JOY_AMIGA_ESC 0x400
#define JOY_AMIGA_OSD 0x800

static void aux_hid_handlejoy(const unsigned char *p) {
    DBG("AUX JOY: index=%02x joy=%02x ax=%02x ay=%02x btn_extra=%02x\n", p[0], p[1], p[2], p[3], p[4]);

    unsigned short joy = (unsigned short)p[1];

    if (p[4] & JOY_XINPUT_LB)
        joy |= JOY_AMIGA_LB;
    if (p[4] & JOY_XINPUT_RB)
        joy |= JOY_AMIGA_RB;
    if (p[4] & JOY_XINPUT_SEL)
        joy |= JOY_AMIGA_ESC;
    if (p[4] & JOY_XINPUT_STA)
        joy |= JOY_AMIGA_OSD;

    aux_joy_send(p[0], joy);
}

__constructor(102.aux_hid) void aux_hid_init(void) {
    aux_mouse_buttons0 = 0;
    aux_qual = 0;

    puts("AUX HID init\n");
}

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
        case SPI_HID_JOYSTICK:
            if (len >= 7)
                aux_hid_handlejoy(&buf[2]);
            break;
        default:
            DBG("AUX HID: ignoring type=%d\n", buf[1]);
            break;
    }
}
