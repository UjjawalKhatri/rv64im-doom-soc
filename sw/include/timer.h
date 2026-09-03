#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>

uint64_t timer_get_cycles(void);
uint64_t timer_get_us(void);
uint32_t timer_get_ms(void);
void     timer_delay_ms(uint32_t ms);
void     timer_delay_us(uint32_t us);

#endif /* TIMER_H */
