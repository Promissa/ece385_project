#include <stdio.h>
#include "text_mode_vga_color.h"
#include "usb_keyboard.h"

static const char *hid_key_name(alt_u8 keycode)
{
    switch (keycode) {
    case 0x00: return "released";
    case 0x04: return "A";
    case 0x05: return "B";
    case 0x06: return "C";
    case 0x07: return "D";
    case 0x08: return "E";
    case 0x09: return "F";
    case 0x0A: return "G";
    case 0x0B: return "H";
    case 0x0C: return "I";
    case 0x0D: return "J";
    case 0x0E: return "K";
    case 0x0F: return "L";
    case 0x10: return "M";
    case 0x11: return "N";
    case 0x12: return "O";
    case 0x13: return "P";
    case 0x14: return "Q";
    case 0x15: return "R";
    case 0x16: return "S";
    case 0x17: return "T";
    case 0x18: return "U";
    case 0x19: return "V";
    case 0x1A: return "W";
    case 0x1B: return "X";
    case 0x1C: return "Y";
    case 0x1D: return "Z";
    case 0x1E: return "1";
    case 0x1F: return "2";
    case 0x20: return "3";
    case 0x21: return "4";
    case 0x22: return "5";
    case 0x23: return "6";
    case 0x24: return "7";
    case 0x25: return "8";
    case 0x26: return "9";
    case 0x27: return "0";
    case 0x28: return "Enter";
    case 0x29: return "Esc";
    case 0x2A: return "Backspace";
    case 0x2B: return "Tab";
    case 0x2C: return "Space";
    case 0x4F: return "Right";
    case 0x50: return "Left";
    case 0x51: return "Down";
    case 0x52: return "Up";
    default: return "other";
    }
}

static void init_cga_palette(void)
{
    for (int i = 0; i < 16; i++) {
        setColorPalette(i, colors[i].red, colors[i].green, colors[i].blue);
    }
}

void usb_keyboard_on_keycode(alt_u8 keycode)
{
    char line[80];

    textVGADrawColorText("                                                                    ", 0, 5, 0, 15);
    snprintf(line, sizeof(line), "USB HID keycode: 0x%02x  key: %s", keycode, hid_key_name(keycode));
    textVGADrawColorText(line, 0, 5, 0, 15);
}

int main(void)
{
    printf("Running Lab 9 VGA + USB keyboard integration test...\n");

    init_cga_palette();
    textVGAColorClr();
    textVGADrawColorText("Lab 9 VGA + USB keyboard integration", 0, 0, 0, 15);
    textVGADrawColorText("Plug a USB keyboard into the DE2-115 USB-OTG port.", 0, 2, 0, 10);
    textVGADrawColorText("HEX0/HEX1 and this line show the current HID keycode.", 0, 3, 0, 10);
    usb_keyboard_on_keycode(0);

    usb_keyboard_run();

    while (1) {
    }
}
