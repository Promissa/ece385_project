/*
 * text_mode_vga_color.c
 * Minimal driver for text mode VGA support
 * This is for Week 2, with color support
 *
 *  Created on: Oct 25, 2021
 *      Author: zuofu
 */

#include <system.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <alt_types.h>
#include "text_mode_vga_color.h"

void textVGAColorClr()
{
    for (int i = 0; i < (ROWS * COLUMNS) * 2; i++) {
        vga_ctrl->VRAM[i] = 0x00;
    }
}

void textVGADrawColorText(char *str, int x, int y, alt_u8 background, alt_u8 foreground)
{
    int i = 0;
    while (str[i] != 0) {
        vga_ctrl->VRAM[(y * COLUMNS + x + i) * 2] = foreground << 4 | background;
        vga_ctrl->VRAM[(y * COLUMNS + x + i) * 2 + 1] = str[i];
        i++;
    }
}

void setColorPalette(alt_u8 color, alt_u8 red, alt_u8 green, alt_u8 blue)
{
    alt_u8 word_index = (color >> 1) & 0x7;
    alt_u32 rgb = (((alt_u32)red & 0x0F) << 8) |
                  (((alt_u32)green & 0x0F) << 4) |
                  ((alt_u32)blue & 0x0F);
    alt_u32 word = vga_ctrl->PALETTE[word_index];

    if (color & 0x1) {
        word = (word & ~(0x0FFFu << 13)) | (rgb << 13);
    } else {
        word = (word & ~(0x0FFFu << 1)) | (rgb << 1);
    }

    vga_ctrl->PALETTE[word_index] = word;
}


void textVGAColorScreenSaver()
{
    // This is the function you call for your week 2 demo
    char color_string[80];
    int fg, bg, x, y;
    textVGAColorClr();
    // initialize palette
    for (int i = 0; i < 16; i++) {
        setColorPalette(i, colors[i].red, colors[i].green, colors[i].blue);
    }
    while (1) {
        fg = rand() % 16;
        bg = rand() % 16;
        while (fg == bg) {
            fg = rand() % 16;
            bg = rand() % 16;
        }
        sprintf(color_string, "Drawing %s text with %s background", colors[fg].name, colors[bg].name);
        x = rand() % (80 - strlen(color_string));
        y = rand() % 30;
        textVGADrawColorText(color_string, x, y, bg, fg);
        usleep(100000);
    }
}
