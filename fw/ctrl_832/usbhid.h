#ifndef USBHID_H
#define USBHID_H

#define USBHID_PORTS 2
#define USBHID_KEYPAGES 5

#define USBHIDBASE0 0x0fffff60

#define HW_USBHID0(reg) *(volatile unsigned int *)(USBHIDBASE0 + (reg))
#define HW_USBHID1(reg) *(volatile unsigned int *)(USBHIDBASE1 + (reg))
#define HW_USBHID(port, reg) ((port) == 0 ? HW_USBHID0(reg) : HW_USBHID1(reg))
#define HW_USBHID_WRITE(port, reg, val)                                                                               \
    do {                                                                                                              \
        if ((port) == 0)                                                                                              \
            HW_USBHID0(reg) = (val);                                                                                  \
        else                                                                                                          \
            HW_USBHID1(reg) = (val);                                                                                  \
    } while (0)

/* Register byte offsets — addr[3:2] selects register in VHDL */
#define REG_USBHID_STATUS 0x00
#define REG_USBHID_DATA_LO 0x04
#define REG_USBHID_DATA_HI 0x08

/* Status register — read */
#define USBHID_STATUS_TYPE_MASK 0x3    /* bits [1:0]: device type */
#define USBHID_STATUS_REPORT_READY 0x4 /* bit 2: new report available */

/* Status register — write */
#define USBHID_STATUS_ACK 0x4 /* write bit 2 to acknowledge */

#define USBHIDBASE1 0x0fffff50

enum hidtype { USBHID_NONE = 0, USBHID_KEYBOARD = 1, USBHID_MOUSE = 2, USBHID_GAMEPAD = 3 };

extern unsigned int usbhid_keytable[USBHID_KEYPAGES];
extern unsigned char usbhid_typ[USBHID_PORTS];

static inline int usbhid_test_key(unsigned char code) { return usbhid_keytable[code >> 5] & (1 << (code & 31)); }
static inline char usbhid_get_typ(unsigned int port) { return usbhid_typ[port % USBHID_PORTS]; }

void usbhid_init(void);
void usbhid_handle(void);

#endif
