#ifndef SOC_REGS_H
#define SOC_REGS_H

#include <stdint.h>

/* ============================================================================
 * Memory-Mapped I/O (MMIO) Peripheral Base Addresses
 * Frozen Address Map per docs/memory_map.md and rtl/soc/soc_interconnect.v
 * ============================================================================ */

/* Framebuffer MMIO (64 KB Dual-Port BRAM, 320x200 8-bit Indexed Color) */
#define FB_BASE            0x20000000ULL
#define FB_PTR             ((volatile uint8_t *)(FB_BASE))
#define FB_WIDTH           320
#define FB_HEIGHT          200
#define FB_SIZE            (FB_WIDTH * FB_HEIGHT)

/* GPIO Controller (8 DIP Switches, 5 Push Buttons, 8 LEDs at 0x1000_1000) */
#define GPIO_BASE          0x10001000ULL
#define GPIO_REG_INPUTS    (*(volatile uint64_t *)(GPIO_BASE + 0x00))
#define GPIO_REG_LEDS      (*(volatile uint64_t *)(GPIO_BASE + 0x08))

/* 64-bit Hardware Real-Time Timer (at 0x1000_1018) */
#define TIMER_BASE         0x10001000ULL
#define TIMER_REG_CYCLES   (*(volatile uint64_t *)(TIMER_BASE + 0x18))
#define TIMER_REG_US       (*(volatile uint64_t *)(TIMER_BASE + 0x20))

/* UART 16550-compatible FIFO Controller (115200 Baud, 8N1 at 0x1000_4000) */
#define UART_BASE          0x10004000ULL
#define UART_REG_DATA      (*(volatile uint64_t *)(UART_BASE + 0x00))
#define UART_REG_STATUS    (*(volatile uint64_t *)(UART_BASE + 0x08))

#define UART_STATUS_TX_FULL   (1 << 0)
#define UART_STATUS_TX_EMPTY  (1 << 1)
#define UART_STATUS_RX_EMPTY  (1 << 2)
#define UART_STATUS_RX_FULL   (1 << 3)

/* Persistent DDR3 Hardware Debug Stage Scratchpad (Physical 0x00510000) */
#define DBG_STAGE_ADDR        0x80510000ULL
#define DBG_STAGE             (*(volatile uint64_t *)DBG_STAGE_ADDR)

#ifdef DEBUG_MILESTONES
#define TRACE(code) do { \
    DBG_STAGE = (uint64_t)(code); \
    GPIO_REG_LEDS = (uint64_t)(code); \
} while (0)
#else
#define TRACE(code) do { } while (0)
#endif

#endif /* SOC_REGS_H */
