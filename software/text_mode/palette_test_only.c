#include <stdio.h>
#include <unistd.h>
#include "palette_test.h"

int main(void)
{
    printf("Running paletteTest() only. Watch the first VGA text row cycle colors.\n");

    while (1) {
        paletteTest();
        usleep(200000);
    }
}
