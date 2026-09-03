#ifndef VGA_TEXT_H
#define VGA_TEXT_H

#include <stdint.h>
#include <stdarg.h>

// VGA Text Console Parameters
// Renders an 8x8 pixel font on the 320x200 framebuffer
// Grid: 40 columns x 25 rows
#define TEXT_COLS  40
#define TEXT_ROWS  25

void vga_text_init(uint8_t bg_color, uint8_t fg_color);
void vga_text_putc(char c);
void vga_text_puts(const char *str);
void vga_text_printf(const char *fmt, ...);
void vga_text_set_cursor(int col, int row);
void vga_text_set_color(uint8_t fg, uint8_t bg);
void vga_text_clear(void);

#endif /* VGA_TEXT_H */
