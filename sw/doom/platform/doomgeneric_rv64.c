// ============================================================================
// File: doomgeneric_rv64.c
// Description: Platform Glue Implementation for DOOM on RV64IM ZedBoard SoC
// Connects DoomGeneric engine to RV64 MMIO Framebuffer, Timer, and GPIOs
// ============================================================================

#include "doomgeneric.h"
#include "doomkeys.h"
#include "../include/soc_regs.h"
#include "../include/timer.h"
#include "../include/gpio.h"
#include "../include/vga.h"
#include "../include/vga_text.h"

// 320x200 8-bit Framebuffer pointer in MMIO space
#define FB_ADDR ((volatile uint8_t *)FB_BASE)

// ============================================================================
// Platform Initialization
// ============================================================================
extern void I_InitGraphics(void);

void DG_Init(void) {
    I_InitGraphics();
    // Milestone 0x10 (LD4 ON): DG_Init completed, entering D_DoomMain
    TRACE(0x10);
}

// ============================================================================
// Frame Rendering + Frame-rate measurement
//
// Perf block lives in spare DDR3 so it can be read over JTAG while the game
// runs (CPU 0x8053_0000 == physical 0x0053_0000):
//   [0] = FPS x100            [1] = total frames rendered
//   [2] = avg frame time (us) [3] = avg framebuffer blit time (us)
//   [4] = 0x50455246 ('PERF') magic, proves the block is live
//   [5] = elapsed us since the first frame   (whole run)
//   [6] = blit us accumulated over that span (whole run)
//
// [0]-[3] describe only the last FPS_WINDOW frames and swing by >2x with the
// scene, so they must NOT be used to compare two builds. Use [1] and [5] for
// that: average FPS = frames / (elapsed_us / 1e6).
//
// Frame time is measured end-of-blit to end-of-blit, so it includes game
// logic, the 3D renderer and the blit -- i.e. the real end-to-end frame rate.
// The blit is timed separately to show how much of a frame the 64000-byte
// framebuffer copy actually costs.
// ============================================================================
#define PERF_BLOCK ((volatile uint64_t *)0x80530000ULL)
#define FPS_WINDOW 32u

static uint32_t fps_count      = 0;
static uint64_t fps_win_start  = 0;
static uint64_t fps_blit_accum = 0;
static uint64_t fps_total      = 0;
static uint32_t fps_x100       = 0;
/* Whole-run accumulators. The windowed figure above covers only the last
   FPS_WINDOW frames, which makes it swing by more than 2x purely with what is
   on screen (title screen vs a busy room) - far more than the difference
   between two clock frequencies. These two make a scene-independent average
   possible, so builds at different clocks can actually be compared. */
static uint64_t fps_run_start  = 0;
static uint64_t fps_run_blit   = 0;

// Draw "FPS nn.n" into the top-left of the framebuffer (white on black).
// Costs ~9 glyphs x 64 px = ~576 byte stores, <1% of the 64000-byte blit.
static void draw_fps_overlay(void)
{
    char buf[12];
    uint32_t w = fps_x100 / 100u;
    uint32_t f = (fps_x100 % 100u) / 10u;
    int i = 0;

    buf[i++] = 'F'; buf[i++] = 'P'; buf[i++] = 'S'; buf[i++] = ' ';
    if (w >= 100u) buf[i++] = (char)('0' + (w / 100u) % 10u);
    if (w >= 10u)  buf[i++] = (char)('0' + (w / 10u) % 10u);
    buf[i++] = (char)('0' + (w % 10u));
    buf[i++] = '.';
    buf[i++] = (char)('0' + f);
    buf[i]   = '\0';

    // Index 0x80 is bright in BOTH the old (0xFFFFFF) and new (0xBFA78F)
    // palettes, so the overlay stays readable before and after the palette
    // bitstream rebuild. 0x00 is black in both.
    vga_text_set_color(0x80, 0x00);
    vga_text_set_cursor(0, 0);
    vga_text_puts(buf);
}

void DG_DrawFrame(void) {
    if (!DG_ScreenBuffer) return;

    // Milestone: Frame rendered! Record in DBG_STAGE and light up LEDs
    TRACE(0x7F);

    uint64_t t_blit0 = timer_get_us();

    // Fast 64-bit aligned DDR3 read + 8-byte unpacked store to Framebuffer MMIO
    volatile uint8_t *dst = (volatile uint8_t *)FB_BASE;
    const uint64_t *src64 = (const uint64_t *)DG_ScreenBuffer;

    for (int i = 0; i < 8000; i++) {
        uint64_t p = src64[i];
        int idx = i * 8;
        dst[idx + 0] = (uint8_t)(p);
        dst[idx + 1] = (uint8_t)(p >> 8);
        dst[idx + 2] = (uint8_t)(p >> 16);
        dst[idx + 3] = (uint8_t)(p >> 24);
        dst[idx + 4] = (uint8_t)(p >> 32);
        dst[idx + 5] = (uint8_t)(p >> 40);
        dst[idx + 6] = (uint8_t)(p >> 48);
        dst[idx + 7] = (uint8_t)(p >> 56);
    }

    uint64_t t_blit1 = timer_get_us();

    // ---- frame-rate accounting ----
    fps_blit_accum += (t_blit1 - t_blit0);
    fps_total++;
    fps_count++;

    if (fps_run_start != 0) fps_run_blit += (t_blit1 - t_blit0);

    if (fps_win_start == 0) {
        fps_win_start = t_blit1;            // first frame starts the window
        fps_run_start = t_blit1;            // ...and the whole-run average
    } else if (fps_count >= FPS_WINDOW) {
        uint64_t win = t_blit1 - fps_win_start;
        if (win > 0) {
            fps_x100 = (uint32_t)(((uint64_t)FPS_WINDOW * 100000000ULL) / win);
            PERF_BLOCK[0] = (uint64_t)fps_x100;
            PERF_BLOCK[1] = fps_total;
            PERF_BLOCK[2] = win / FPS_WINDOW;
            PERF_BLOCK[3] = fps_blit_accum / FPS_WINDOW;
            PERF_BLOCK[4] = 0x50455246ULL;  // 'PERF'
            // Whole-run figures: elapsed us since the first frame, and the
            // blit time accumulated over that same span. Divide frames by
            // elapsed for an average that does not depend on the scene.
            PERF_BLOCK[5] = t_blit1 - fps_run_start;
            PERF_BLOCK[6] = fps_run_blit;
        }
        fps_win_start  = t_blit1;
        fps_blit_accum = 0;
        fps_count      = 0;
    }

    if (fps_x100) draw_fps_overlay();
}

// ============================================================================
// Timing Hooks
// ============================================================================
void DG_SleepMs(uint32_t ms) {
    timer_delay_ms(ms);
}

uint32_t DG_GetTicksMs(void) {
    return timer_get_ms();
}

// ============================================================================
// Input Handling: Map ZedBoard Hardware Buttons & Switches to DOOM Keys
// ============================================================================
// ZedBoard Buttons:
//   BTNU (bit 0): Up / Move Forward
//   BTNL (bit 1): Left / Turn Left
//   BTNR (bit 2): Right / Turn Right
//   BTND (bit 3): Down / Move Backward
// ZedBoard Switches:
//   SW0 (bit 0): Fire (Ctrl)
//   SW1 (bit 1): Open / Use (Space)
//   SW2 (bit 2): ENTER  - menu select (activates "New Game", skill, etc.)
//   SW3 (bit 3): ESCAPE - open/close menu, back out of a submenu
//   SW7        : reserved by the SoC top level for the PC debug LED view

static uint8_t prev_buttons = 0;
static uint8_t prev_switches = 0;

int DG_GetKey(int *pressed, unsigned char *key) {
    uint8_t cur_buttons = gpio_get_buttons();
    uint8_t cur_switches = gpio_get_switches();

    // 1. Check BTNU (Move Forward)
    if ((cur_buttons & 0x01) != (prev_buttons & 0x01)) {
        *pressed = (cur_buttons & 0x01) ? 1 : 0;
        *key = KEY_UPARROW;
        prev_buttons ^= 0x01;
        return 1;
    }

    // 2. Check BTND (Move Backward)
    if ((cur_buttons & 0x08) != (prev_buttons & 0x08)) {
        *pressed = (cur_buttons & 0x08) ? 1 : 0;
        *key = KEY_DOWNARROW;
        prev_buttons ^= 0x08;
        return 1;
    }

    // 3. Check BTNL (Turn Left)
    if ((cur_buttons & 0x02) != (prev_buttons & 0x02)) {
        *pressed = (cur_buttons & 0x02) ? 1 : 0;
        *key = KEY_LEFTARROW;
        prev_buttons ^= 0x02;
        return 1;
    }

    // 4. Check BTNR (Turn Right)
    if ((cur_buttons & 0x04) != (prev_buttons & 0x04)) {
        *pressed = (cur_buttons & 0x04) ? 1 : 0;
        *key = KEY_RIGHTARROW;
        prev_buttons ^= 0x04;
        return 1;
    }

    // 5. Check SW0 (Fire / Ctrl)
    if ((cur_switches & 0x01) != (prev_switches & 0x01)) {
        *pressed = (cur_switches & 0x01) ? 1 : 0;
        *key = KEY_FIRE;
        prev_switches ^= 0x01;
        return 1;
    }

    // 6. Check SW1 (Use / Open Door / Space)
    if ((cur_switches & 0x02) != (prev_switches & 0x02)) {
        *pressed = (cur_switches & 0x02) ? 1 : 0;
        *key = KEY_USE;
        prev_switches ^= 0x02;
        return 1;
    }

    // 7. Check SW2 (Menu Select / ENTER) - needed to activate "New Game" etc.
    //    Switches are level-held: flipping UP sends the key press (which is what
    //    DOOM's menu acts on), flipping DOWN sends the release.
    if ((cur_switches & 0x04) != (prev_switches & 0x04)) {
        *pressed = (cur_switches & 0x04) ? 1 : 0;
        *key = KEY_ENTER;
        prev_switches ^= 0x04;
        return 1;
    }

    // 8. Check SW3 (Menu Back / ESCAPE) - opens/closes the menu in-game
    if ((cur_switches & 0x08) != (prev_switches & 0x08)) {
        *pressed = (cur_switches & 0x08) ? 1 : 0;
        *key = KEY_ESCAPE;
        prev_switches ^= 0x08;
        return 1;
    }

    return 0; // No key event
}

void DG_SetWindowTitle(const char *title) {
    (void)title; // Unused in bare-metal
}
