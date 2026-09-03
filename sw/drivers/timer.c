#include "../include/timer.h"
#include "../include/soc_regs.h"

uint64_t timer_get_cycles(void) {
    return TIMER_REG_CYCLES;
}

uint64_t timer_get_us(void) {
    return TIMER_REG_US;
}

uint32_t timer_get_ms(void) {
    return (uint32_t)(TIMER_REG_US / 1000ULL);
}

void timer_delay_us(uint32_t us) {
    uint64_t start = timer_get_us();
    while ((timer_get_us() - start) < (uint64_t)us)
        ;
}

void timer_delay_ms(uint32_t ms) {
    timer_delay_us(ms * 1000U);
}
