#include "../include/uart.h"
#include "../include/soc_regs.h"
#include <stdarg.h>

void uart_init(void) {
    // Hardware auto-initializes at 115200 baud on 100 MHz clock
}

void uart_putc(char c) {
    // Non-blocking write: if TX FIFO is full, do not stall CPU pipeline
    if (!(UART_REG_STATUS & UART_STATUS_TX_FULL)) {
        UART_REG_DATA = (uint64_t)(uint8_t)c;
    }
}

void uart_puts(const char *str) {
    while (*str) {
        if (*str == '\n')
            uart_putc('\r');
        uart_putc(*str++);
    }
}

int uart_has_char(void) {
    // Return 1 if RX FIFO is NOT empty
    return !(UART_REG_STATUS & UART_STATUS_RX_EMPTY);
}

char uart_getc(void) {
    while (!uart_has_char())
        ;
    return (char)(UART_REG_DATA & 0xFF);
}

static void print_num(uint64_t num, int base, int is_signed) {
    char buf[64];
    int i = 0;

    if (is_signed && (int64_t)num < 0) {
        uart_putc('-');
        num = (uint64_t)(-(int64_t)num);
    }

    if (num == 0) {
        uart_putc('0');
        return;
    }

    while (num > 0) {
        int rem = num % base;
        buf[i++] = (rem < 10) ? ('0' + rem) : ('a' + rem - 10);
        num /= base;
    }

    while (i > 0) {
        uart_putc(buf[--i]);
    }
}

void uart_printf(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);

    while (*fmt) {
        if (*fmt == '%') {
            fmt++;
            switch (*fmt) {
                case 's': {
                    const char *s = va_arg(args, const char *);
                    uart_puts(s ? s : "(null)");
                    break;
                }
                case 'd':
                    print_num((uint64_t)va_arg(args, int64_t), 10, 1);
                    break;
                case 'u':
                    print_num(va_arg(args, uint64_t), 10, 0);
                    break;
                case 'x':
                case 'p':
                    print_num(va_arg(args, uint64_t), 16, 0);
                    break;
                case 'c':
                    uart_putc((char)va_arg(args, int));
                    break;
                case '%':
                    uart_putc('%');
                    break;
                default:
                    uart_putc('%');
                    uart_putc(*fmt);
                    break;
            }
        } else {
            if (*fmt == '\n')
                uart_putc('\r');
            uart_putc(*fmt);
        }
        fmt++;
    }

    va_end(args);
}
