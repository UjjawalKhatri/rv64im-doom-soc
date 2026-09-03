#ifndef GPIO_H
#define GPIO_H

#include <stdint.h>

void    gpio_set_leds(uint8_t val);
uint8_t gpio_get_switches(void);
uint8_t gpio_get_buttons(void);

#endif /* GPIO_H */
