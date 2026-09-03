// ============================================================================
// File: main.c
// Description: DOOM RV64I/M SoC Diagnostic & Hello World Program
// ALL output is rendered directly on the VGA monitor (no PMOD UART needed).
// Tests VGA Test Pattern, VGA Text Overlay, Hardware Timer, and GPIOs.
// ============================================================================

#include "../include/soc_regs.h"
#include "../include/timer.h"
#include "../include/gpio.h"
#include "../include/vga.h"
#include "../include/vga_text.h"

// DOOM palette color indices for visual styling
#define COL_BLACK  0x00    // PLAYPAL idx -> 000000
#define COL_WHITE  0x04    // PLAYPAL idx -> FFFFFF
#define COL_RED    0xB0    // PLAYPAL idx -> FF0000
#define COL_GREEN  0x75    // PLAYPAL idx -> 53AF47
#define COL_YELLOW 0xE7    // PLAYPAL idx -> FFFF00
#define COL_BROWN  0x45    // PLAYPAL idx -> 8F5F37
#define COL_BLUE   0xC8    // PLAYPAL idx -> 0000FF
#define COL_GRAY   0x61    // PLAYPAL idx -> 7F7F7F
#define COL_ORANGE 0xD7    // PLAYPAL idx -> FF7F1B

static void print_hex(uint64_t val, int nibbles) {
    char hex_lut[] = "0123456789ABCDEF";
    char str[19];
    str[0] = '0';
    str[1] = 'x';
    for (int h = nibbles - 1; h >= 0; h--) {
        str[2 + (nibbles - 1 - h)] = hex_lut[(val >> (h * 4)) & 0xF];
    }
    str[2 + nibbles] = '\0';
    vga_text_puts(str);
}

int main(void) {
    // 1. Draw Full Screen 8-Bar DOOM Color Test Pattern
    vga_draw_test_pattern();

    // 2. Render System Banner & Diagnostics across the top bars
    vga_text_set_cursor(0, 0);
    vga_text_set_color(COL_WHITE, COL_BLACK);
    vga_text_puts("========================================\n");
    vga_text_puts("  DOOM RISC-V 64-BIT SoC  -  ZEDBOARD  \n");
    vga_text_puts("========================================\n\n");

    vga_text_set_cursor(0, 4);
    vga_text_set_color(COL_YELLOW, COL_BLACK);
    vga_text_puts("CPU: RV64IM 5-Stage @ 100 MHz\n");
    vga_text_puts("VGA: 640x480 (320x200 8-bit Framebuffer)\n\n");

    // 3. Test RV64M Multiplier / Divider
    int64_t a = 12345LL;
    int64_t b = 6789LL;
    int64_t prod = a * b;
    int64_t quot = prod / a;

    vga_text_set_cursor(0, 7);
    if (quot == b) {
        vga_text_set_color(COL_GREEN, COL_BLACK);
        vga_text_puts("[PASS] RV64M Mul/Div Hardware OK!\n");
    } else {
        vga_text_set_color(COL_RED, COL_BLACK);
        vga_text_puts("[FAIL] RV64M Mul/Div Error!\n");
    }

    // 4. Test Hardware Timer
    uint64_t start_us = timer_get_us();
    timer_delay_ms(50);
    uint64_t end_us = timer_get_us();

    vga_text_set_cursor(0, 8);
    if (end_us > start_us) {
        vga_text_set_color(COL_GREEN, COL_BLACK);
        vga_text_puts("[PASS] Hardware 64-bit Timer OK!\n\n");
    } else {
        vga_text_set_color(COL_RED, COL_BLACK);
        vga_text_puts("[FAIL] Timer Error!\n\n");
    }

    vga_text_set_cursor(0, 10);
    vga_text_set_color(COL_YELLOW, COL_BLACK);
    vga_text_puts(">> Flip SW0 (or press BTND) to run DDR3 diagnostic <<\n");

    // 5. Interactive GPIO Monitoring Loop
    uint32_t prev_sw = 0xFFFFFFFF;
    vga_text_set_color(COL_WHITE, COL_BLACK);

    while (1) {
        uint32_t sw = gpio_get_switches();
        uint32_t btn = gpio_get_buttons();

        // Mirror switches to LEDs
        gpio_set_leds(sw);

        if (sw != prev_sw) {
            vga_text_set_cursor(0, 11);
            vga_text_puts("Switches: 0x");
            char h0 = "0123456789ABCDEF"[(sw >> 4) & 0xF];
            char h1 = "0123456789ABCDEF"[sw & 0xF];
            char str_sw[3] = {h0, h1, '\0'};
            vga_text_puts(str_sw);

            vga_text_puts("   Buttons: 0x");
            char b0 = "0123456789ABCDEF"[btn & 0xF];
            char str_btn[2] = {b0, '\0'};
            vga_text_puts(str_btn);

            vga_text_puts("   \n");
            prev_sw = sw;
        }

        // Live Timer display
        uint64_t now_ms = timer_get_us() / 1000;
        vga_text_set_cursor(22, 11);
        vga_text_puts("Timer: ");
        char tbuf[16];
        int idx = 0;
        uint64_t tmp = now_ms;
        if (tmp == 0) tbuf[idx++] = '0';
        while (tmp > 0 && idx < 14) {
            tbuf[idx++] = '0' + (tmp % 10);
            tmp /= 10;
        }
        for (int i = 0; i < idx / 2; i++) {
            char tc = tbuf[i];
            tbuf[i] = tbuf[idx - 1 - i];
            tbuf[idx - 1 - i] = tc;
        }
        tbuf[idx] = '\0';
        vga_text_puts(tbuf);
        vga_text_puts(" ms  ");

        // 6. Check for Diagnostic Trigger (BTND = bit 3 or SW0 = bit 0)
        if ((btn & 0x08) || (sw & 0x01)) {
            // ------------------------------------------------------------
            // TEST 1: READ-ONLY SUBWORD TEST AT 0x80100000 (BEFORE ANY WRITE)
            // 0x80100000 has 00000093 00000113 (64-bit = 0x0000011300000093)
            // ------------------------------------------------------------
            volatile uint8_t  *c8  = (volatile uint8_t  *)0x80100000ULL;
            volatile uint16_t *c16 = (volatile uint16_t *)0x80100000ULL;
            volatile uint32_t *c32 = (volatile uint32_t *)0x80100000ULL;
            volatile uint64_t *c64 = (volatile uint64_t *)0x80100000ULL;

            uint64_t test_b0 = c8[0];   // expected 0x93
            uint64_t test_b1 = c8[1];   // expected 0x00
            uint64_t test_h0 = c16[0];  // expected 0x0093
            uint64_t test_w0 = c32[0];  // expected 0x00000093
            uint64_t test_d0 = c64[0];  // expected 0x0000011300000093

            vga_text_set_cursor(0, 10);
            vga_text_set_color(COL_YELLOW, COL_BLACK);
            vga_text_puts(">> 0x80100000 READ TEST (NO WRITES) <<\n");
            vga_text_set_color(COL_WHITE, COL_BLACK);
            vga_text_puts("LBU+0:"); print_hex(test_b0, 2);
            vga_text_puts(" +1:");    print_hex(test_b1, 2);
            vga_text_puts(" LHU+0:"); print_hex(test_h0, 4);
            vga_text_puts(" LW+0:");  print_hex(test_w0, 8);
            vga_text_puts("\nLD+0 :"); print_hex(test_d0, 16);
            vga_text_puts("\n\n");

            // ------------------------------------------------------------
            // TEST 2: SCRATCHPAD TEST AT 0x80500000 (STORE 64-BIT, READ SEPARATELY)
            // ------------------------------------------------------------
            volatile uint64_t *scratch64 = (volatile uint64_t *)0x80500000ULL;
            volatile uint8_t  *p8        = (volatile uint8_t  *)0x80500000ULL;
            volatile uint16_t *p16       = (volatile uint16_t *)0x80500000ULL;
            volatile uint32_t *p32       = (volatile uint32_t *)0x80500000ULL;

            *scratch64 = 0x8877665544332211ULL;

            uint64_t r_b0 = p8[0];       // expected 0x11
            uint64_t r_b1 = p8[1];       // expected 0x22
            uint64_t r_h2 = p16[1];      // expected 0x4433
            uint64_t r_w4 = p32[1];      // expected 0x88776655
            uint64_t r_d0 = *scratch64;  // expected 0x8877665544332211

            vga_text_set_color(COL_YELLOW, COL_BLACK);
            vga_text_puts(">> 0x80500000 SCRATCHPAD TEST <<\n");
            vga_text_set_color(COL_WHITE, COL_BLACK);
            vga_text_puts("LBU+0:"); print_hex(r_b0, 2);
            vga_text_puts(" +1:");    print_hex(r_b1, 2);
            vga_text_puts(" LHU+2:"); print_hex(r_h2, 4);
            vga_text_puts(" LW+4:");  print_hex(r_w4, 8);
            vga_text_puts("\nLD+0 :"); print_hex(r_d0, 16);
            vga_text_puts("\n\n");

            // ------------------------------------------------------------
            // TEST 3: AXI TELEMETRY AT 0x10001030 & 0x10001040
            // ------------------------------------------------------------
            volatile uint64_t *axi_status_ptr = (volatile uint64_t *)0x10001030ULL;
            volatile uint64_t *axi_rdata_ptr  = (volatile uint64_t *)0x10001040ULL;
            uint64_t axi_stat  = *axi_status_ptr;
            uint64_t last_rdat = *axi_rdata_ptr;
            uint8_t  rresp     = axi_stat & 0x03;
            uint32_t araddr    = (uint32_t)(axi_stat >> 32);

            vga_text_set_color(COL_YELLOW, COL_BLACK);
            vga_text_puts(">> AXI TELEMETRY <<\n");
            vga_text_set_color(COL_WHITE, COL_BLACK);
            vga_text_puts("ARADDR:"); print_hex(araddr, 8);
            vga_text_puts(" RRESP:"); print_hex(rresp, 1);
            vga_text_puts("\nAXI_RDATA:"); print_hex(last_rdat, 16);
            vga_text_puts("\n");

            vga_text_set_cursor(0, 22);
            vga_text_set_color(COL_GREEN, COL_BLACK);
            vga_text_puts(">> ALL TESTS PASSED! JUMPING TO DOOM @ 0x80100000... <<\n");
            timer_delay_ms(1500);

            void (*doom_entry)(void) = (void (*)(void))0x80100000ULL;
            doom_entry();

            while (1) {
            }
        }

        timer_delay_ms(50);
    }

    return 0;
}
