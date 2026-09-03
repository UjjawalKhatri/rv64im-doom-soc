#ifndef VGA_H
#define VGA_H

#include <stdint.h>

#define VGA_WIDTH  320
#define VGA_HEIGHT 200

void vga_clear(uint8_t color_idx);
void vga_draw_pixel(int x, int y, uint8_t color_idx);
void vga_draw_rect(int x, int y, int w, int h, uint8_t color_idx);
void vga_draw_test_pattern(void);

#endif /* VGA_H */
