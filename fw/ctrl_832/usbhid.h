#ifndef USBHID_H
#define USBHID_H

#define USBHID_PORTS 2

#define USBHIDBASE0 0x0fffff60
#define USBHIDBASE1 0x0fffff50

#define HW_USBHID0(reg) *(volatile unsigned int *)(USBHIDBASE0 + (reg))
#define HW_USBHID1(reg) *(volatile unsigned int *)(USBHIDBASE1 + (reg))
#define HW_USBHID(port, reg)            ((port) == 0 ? HW_USBHID0(reg) : HW_USBHID1(reg))
#define HW_USBHID_WRITE(port, reg, val) do { if ((port) == 0) HW_USBHID0(reg) = (val); else HW_USBHID1(reg) = (val); } while (0)

/* Register byte offsets — addr[3:2] selects register in VHDL */
#define REG_USBHID_STATUS  0x00
#define REG_USBHID_DATA_LO 0x04
#define REG_USBHID_DATA_HI 0x08

/* Status register — read */
#define USBHID_STATUS_TYPE_MASK    0x3  /* bits [1:0]: device type */
#define USBHID_STATUS_REPORT_READY 0x4  /* bit 2: new report available */

/* Status register — write */
#define USBHID_STATUS_ACK          0x4  /* write bit 2 to acknowledge */

enum hidtype { NONE = 0, KEYBOARD = 1, MOUSE = 2, GAMEPAD = 3 };

int  usbhid_testkey(unsigned char code);
void usbhid_init(void);
void usbhid_handle(void);

#endif
