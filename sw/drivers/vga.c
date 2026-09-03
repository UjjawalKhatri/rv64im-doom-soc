#include "../include/vga.h"
#include "../include/soc_regs.h"

void vga_clear(uint8_t color_idx) {
    volatile uint8_t *fb = (volatile uint8_t *)FB_BASE;
    for (int i = 0; i < FB_SIZE; i += 8) {
        fb[i + 0] = color_idx;
        fb[i + 1] = color_idx;
        fb[i + 2] = color_idx;
        fb[i + 3] = color_idx;
        fb[i + 4] = color_idx;
        fb[i + 5] = color_idx;
        fb[i + 6] = color_idx;
        fb[i + 7] = color_idx;
    }
}

void vga_draw_pixel(int x, int y, uint8_t color_idx) {
    if (x >= 0 && x < VGA_WIDTH && y >= 0 && y < VGA_HEIGHT) {
        FB_PTR[y * VGA_WIDTH + x] = color_idx;
    }
}

void vga_draw_rect(int x, int y, int w, int h, uint8_t color_idx) {
    for (int dy = 0; dy < h; dy++) {
        int py = y + dy;
        if (py < 0 || py >= VGA_HEIGHT)
            continue;
        for (int dx = 0; dx < w; dx++) {
            int px = x + dx;
            if (px < 0 || px >= VGA_WIDTH)
                continue;
            FB_PTR[py * VGA_WIDTH + px] = color_idx;
        }
    }
}

void vga_draw_test_pattern(void) {
    // 1. Draw 8 Vertical Color Bars (Standard DOOM PLAYPAL Palette indices)
    // Indices: 0x00(Black), 0x28(Brown), 0x70(Red), 0x90(Orange), 0x78(Yellow), 0x74(Green), 0xc0(Blue), 0x04(White)
    uint8_t colors[8] = { 0x00, 0x28, 0x70, 0x90, 0x78, 0x74, 0xc0, 0x04 };
    int bar_width = VGA_WIDTH / 8; // 40 pixels per bar

    for (int bar = 0; bar < 8; bar++) {
        vga_draw_rect(bar * bar_width, 0, bar_width, 160, colors[bar]);
    }

    // 2. Draw Bottom Status Bar (Dark Gray 0x58)
    vga_draw_rect(0, 160, VGA_WIDTH, 40, 0x58);

    // 3. Draw a Centered Gold Accent Box (DOOM logo placeholder)
    vga_draw_rect(100, 170, 120, 20, 0x78);
}
