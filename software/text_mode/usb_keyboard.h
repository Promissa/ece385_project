#ifndef USB_KEYBOARD_H_
#define USB_KEYBOARD_H_

#include "alt_types.h"

int usb_keyboard_run(void);
void usb_keyboard_on_keycode(alt_u8 keycode);

#endif
