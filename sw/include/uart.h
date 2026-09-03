#ifndef UART_H
#define UART_H

#include <stdint.h>
#include <stddef.h>

void uart_init(void);
void uart_putc(char c);
void uart_puts(const char *str);
int  uart_has_char(void);
char uart_getc(void);
void uart_printf(const char *fmt, ...);

#endif /* UART_H */
