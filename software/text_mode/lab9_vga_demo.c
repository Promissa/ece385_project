#include <stdio.h>
#include "text_mode_vga_color.h"
#include "palette_test.h"

int main(void)
{
    printf("Running Lab 9 Week 2 teacher VGA demo...\n");
    paletteTest();
    textVGAColorScreenSaver();

    while (1) {
    }
}
