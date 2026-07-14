#include "usbhid.h"
#include "amiga_rawkey.h"
#include "c64keys.h"
#include "config.h"
#include "menu.h"
#include "osd.h"
#include "usbhid_keycodes.h"
#include <stdio.h>

#define BSWAP32(v)                                                                                                    \
    ((((v) & 0xff000000u) >> 24) | (((v) & 0x00ff0000u) >> 8) | (((v) & 0x0000ff00u) << 8) |                          \
     (((v) & 0x000000ffu) << 24))

#define KEYPAGES 5
static unsigned int usbhid_prevtable[KEYPAGES];
static unsigned int usbhid_keytable[KEYPAGES];

static int mouse_buttons0 = 0;

/* Gamepad button → Amiga raw key mapping */
static const struct {
    unsigned char bit;
    unsigned char ami;
} gamepad_keymap[] = {
    {6, RK_Space}, {7, RK_LAlt}, {13, RK_Comma}, {11, RK_Period}, {9, RK_Esc},
};

#define GAMEPAD_MAP_COUNT (sizeof(gamepad_keymap) / sizeof(gamepad_keymap[0]))

static unsigned int gamepad_prevbits[USBHID_PORTS];

int usbhid_testkey(unsigned char code) { return usbhid_keytable[code >> 5] & (1 << (code & 31)); }

static void usbhid_setkey(unsigned char code) { usbhid_keytable[code >> 5] |= 1 << (code & 31); }

static void usbhid_send(int type, int code) {
    int t = (type << 14) | (mouse_buttons0 << 8) | (code & 0xff);
    HW_KEYBOARD(REG_KEYBOARD_OUT) = t;
}

static void usbhid_handlekb(unsigned char *pkt) {
    int i, code;

    DBG("KB: mod=%02x keys=%02x %02x %02x %02x %02x %02x\n", pkt[0], pkt[2], pkt[3], pkt[4], pkt[5], pkt[6], pkt[7]);

    for (i = 0; i < KEYPAGES; ++i) {
        usbhid_prevtable[i] = usbhid_keytable[i];
        usbhid_keytable[i] = 0;
    }

    /* Ctrl-Amiga-Amiga reset combo */
    if (!(pkt[0] ^ (HIDQUAL_LCTRL | HIDQUAL_LALT | HIDQUAL_RALT)))
        OsdReset();

    /* Qualifier bits packed into page 4 (virtual keycodes 128-135) */
    usbhid_keytable[4] = pkt[0];

    /* Bytes 2-7: up to 6 simultaneous keycodes (boot protocol) */
    for (i = 0; i < 6; ++i) {
        unsigned char key = pkt[2 + i];
        if (key && key < 128)
            usbhid_setkey(key);
    }

    code = 0;
    for (i = 0; i < KEYPAGES; ++i) {
        unsigned int t = usbhid_prevtable[i] ^ usbhid_keytable[i];
        unsigned int k = usbhid_keytable[i];
        int j;
        for (j = 0; j < 32; ++j, t >>= 1, k >>= 1, ++code) {
            if (t & 1) {
                int ami = usb2ami[code];
                if (k & 1) {
                    DBG("KB: hid=%d ami=%02x down\n", code, ami);
                    usbhid_send(2, ami);
                } else {
                    DBG("KB: hid=%d ami=%02x up\n", code, ami);
                    usbhid_send(2, ami | 0x80);
                }
            }
        }
    }
}

static void usbhid_handlemouse(unsigned char *pkt) {
    DBG("MOUSE: btn=%02x dx=%d dy=%d\n", pkt[0], (signed char)pkt[1], (signed char)pkt[2]);

    mouse_buttons0 = pkt[0];
    usbhid_send(0, (signed char)pkt[1]); /* X */
    usbhid_send(1, (signed char)pkt[2]); /* Y */
}

static void usbhid_handlegamepad(int port, unsigned int status) {
    unsigned int game_bits = (status >> 16) & 0x3fff;
    unsigned int changed = gamepad_prevbits[port] ^ game_bits;
    unsigned int i;

    DBG("GAMEPAD port %d: game_bits=%04x changed=%04x\n", port, game_bits, changed);

    for (i = 0; i < GAMEPAD_MAP_COUNT; ++i) {
        unsigned int mask = 1u << gamepad_keymap[i].bit;
        if (changed & mask) {
            if (game_bits & mask) {
                DBG("GAMEPAD port %d: bit %d ami=%02x down\n", port, gamepad_keymap[i].bit, gamepad_keymap[i].ami);
                usbhid_send(2, gamepad_keymap[i].ami);
            } else {
                DBG("GAMEPAD port %d: bit %d ami=%02x up\n", port, gamepad_keymap[i].bit, gamepad_keymap[i].ami);
                usbhid_send(2, gamepad_keymap[i].ami | 0x80);
            }
        }
    }
    gamepad_prevbits[port] = game_bits;
}

static void usbhid_handleport(int port) {
    unsigned int status = HW_USBHID(port, REG_USBHID_STATUS);
    int typ;

    if (!(status & USBHID_STATUS_REPORT_READY))
        return;

    typ = status & USBHID_STATUS_TYPE_MASK;

    DBG("HID port %d: status=%08x typ=%d\n", port, status, typ);

    if (typ == KEYBOARD || typ == MOUSE) {
        unsigned char pkt[8];
        unsigned int *w = (unsigned int *)pkt;
        w[0] = BSWAP32(HW_USBHID(port, REG_USBHID_DATA_LO));
        w[1] = BSWAP32(HW_USBHID(port, REG_USBHID_DATA_HI));

        if (typ == KEYBOARD)
            usbhid_handlekb(pkt);
        else
            usbhid_handlemouse(pkt);

    } else if (typ == GAMEPAD && (config.joystick & 0x4) == 0) { // do map joystick in CD32 mode
        usbhid_handlegamepad(port, status);
    } else {
        DBG("HID port %d: ignoring typ=%d\n", port, typ);
    }

    /* ACK always, even for ignored types, to clear the ready flag */
    HW_USBHID_WRITE(port, REG_USBHID_STATUS, USBHID_STATUS_ACK);
}

__constructor(102.usbhid) void usbhid_init(void) { puts("USB HID init\n"); }

void usbhid_handle(void) {
    usbhid_handleport(0);
    usbhid_handleport(1);
}
