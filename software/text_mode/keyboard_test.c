#include <stdio.h>
#include <unistd.h>
#include "cy7c67200.h"
#include "io_handler.h"
#include "usb.h"
#include "usb_keyboard.h"

void usb_keyboard_on_keycode(alt_u8 keycode)
{
    static alt_u8 last_keycode = 0xff;

    if (keycode != last_keycode) {
        printf("USB HID keycode: 0x%02x\n", keycode);
        last_keycode = keycode;
    }
}

int main(void)
{
    printf("Running Lab 8 USB keyboard-only migration test...\n");
    printf("Watch HEX0/HEX1 for the HID keycode. A=04, B=05, Left=50, Right=4f.\n");
    printf("PIO self-test: HEX should count 00, 11, 22, ..., ff before USB setup.\n");

    for (alt_u8 value = 0; value != 0xff; value += 0x11) {
        *keycode_base = value;
        printf("PIO self-test keycode write: 0x%02x\n", value);
        usleep(150000);
    }
    *keycode_base = 0xff;
    printf("PIO self-test keycode write: 0xff\n");
    usleep(150000);
    *keycode_base = 0x00;

    IO_init();
    printf("HPI probe after IO_init: mailbox=0x%04x status=0x%04x\n",
           IO_read(HPI_MAILBOX), IO_read(HPI_STATUS));

    usb_keyboard_run();

    while (1) {
    }
}
