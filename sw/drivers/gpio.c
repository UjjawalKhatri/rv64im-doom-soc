#include "../include/gpio.h"
#include "../include/soc_regs.h"

void gpio_set_leds(uint8_t val) {
    GPIO_REG_LEDS = (uint64_t)val;
}

uint8_t gpio_get_switches(void) {
    return (uint8_t)(GPIO_REG_INPUTS & 0xFF);
}

uint8_t gpio_get_buttons(void) {
    return (uint8_t)((GPIO_REG_INPUTS >> 8) & 0x1F);
}
