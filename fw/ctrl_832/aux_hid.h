#ifndef AUX_HID_H
#define AUX_HID_H

/* Wire protocol used by the external MCU sending HID reports over the AUX SPI link. */
#define SPI_TARGET_HID 1
#define SPI_HID_KEYBOARD 1
#define SPI_HID_MOUSE 2
#define SPI_HID_JOYSTICK 3

void aux_hid_init(void);
void aux_hid_handle(void);

#endif
