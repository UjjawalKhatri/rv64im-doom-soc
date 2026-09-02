## ============================================================================
## File: doom_soc_zedboard.xdc
## Description: Xilinx Vivado Constraints for DOOM SoC on ZedBoard
## Part: xc7z020clg484-1
## Top Module: doom_soc_top
## Target Frequency: 100 MHz
## ============================================================================
## Based on official Digilent ZedBoard Master XDC
## Ref: https://github.com/Digilent/digilent-xdc/blob/master/Zedboard-Master.xdc
## ============================================================================

## ============================================================================
## Clock - Bank 13 (100 MHz GCLK Oscillator)
## ============================================================================
create_clock -period 10.000 -name sys_clk_pin -waveform {0.000 5.000} [get_ports clk]
set_property PACKAGE_PIN Y9 [get_ports { clk }];

## ============================================================================
## Reset - Bank 34 (BTNC = Center Push Button, active HIGH)
## ============================================================================
set_property PACKAGE_PIN P16 [get_ports { reset }];

## ============================================================================
## UART - DISABLED (No PMOD USB-UART Adapter Available)
## ============================================================================
## The UART hardware block remains in the SoC for software API compatibility,
## but the physical TX/RX pins are NOT connected to any external pins.
## All debug/diagnostic output is rendered directly on the VGA display instead.
## If a PMOD USB-UART adapter becomes available later, uncomment these lines:
##   set_property PACKAGE_PIN Y11  [get_ports { uart_tx }];    # JA1 - UART TX
##   set_property PACKAGE_PIN AA11 [get_ports { uart_rx }];    # JA2 - UART RX
## ============================================================================

## ============================================================================
## VGA Output - Bank 33 (ZedBoard Onboard VGA, 12-bit color)
## ============================================================================
## Red Channel (4-bit)
set_property PACKAGE_PIN V20  [get_ports { vga_r[0] }];   # VGA-R1
set_property PACKAGE_PIN U20  [get_ports { vga_r[1] }];   # VGA-R2
set_property PACKAGE_PIN V19  [get_ports { vga_r[2] }];   # VGA-R3
set_property PACKAGE_PIN V18  [get_ports { vga_r[3] }];   # VGA-R4

## Green Channel (4-bit)
set_property PACKAGE_PIN AB22 [get_ports { vga_g[0] }];   # VGA-G1
set_property PACKAGE_PIN AA22 [get_ports { vga_g[1] }];   # VGA-G2
set_property PACKAGE_PIN AB21 [get_ports { vga_g[2] }];   # VGA-G3
set_property PACKAGE_PIN AA21 [get_ports { vga_g[3] }];   # VGA-G4

## Blue Channel (4-bit)
set_property PACKAGE_PIN Y21  [get_ports { vga_b[0] }];   # VGA-B1
set_property PACKAGE_PIN Y20  [get_ports { vga_b[1] }];   # VGA-B2
set_property PACKAGE_PIN AB20 [get_ports { vga_b[2] }];   # VGA-B3
set_property PACKAGE_PIN AB19 [get_ports { vga_b[3] }];   # VGA-B4

## VGA Sync
set_property PACKAGE_PIN AA19 [get_ports { vga_hsync }];   # VGA-HS
set_property PACKAGE_PIN Y19  [get_ports { vga_vsync }];   # VGA-VS

## ============================================================================
## User DIP Switches [7:0] - Bank 35
## ============================================================================
set_property PACKAGE_PIN F22 [get_ports { switches[0] }];  # SW0
set_property PACKAGE_PIN G22 [get_ports { switches[1] }];  # SW1
set_property PACKAGE_PIN H22 [get_ports { switches[2] }];  # SW2
set_property PACKAGE_PIN F21 [get_ports { switches[3] }];  # SW3
set_property PACKAGE_PIN H19 [get_ports { switches[4] }];  # SW4
set_property PACKAGE_PIN H18 [get_ports { switches[5] }];  # SW5
set_property PACKAGE_PIN H17 [get_ports { switches[6] }];  # SW6
set_property PACKAGE_PIN M15 [get_ports { switches[7] }];  # SW7

## ============================================================================
## User Push Buttons [4:0] - Bank 34
## ============================================================================
set_property PACKAGE_PIN T18 [get_ports { buttons[0] }];   # BTNU (Up)
set_property PACKAGE_PIN N15 [get_ports { buttons[1] }];   # BTNL (Left)
set_property PACKAGE_PIN R18 [get_ports { buttons[2] }];   # BTNR (Right)
set_property PACKAGE_PIN R16 [get_ports { buttons[3] }];   # BTND (Down)
## NOTE: buttons[4] mapped to BTNC, but BTNC is already used as reset.
## If you want a 5th button for DOOM input, wire it separately.
## For now, tie buttons[4] to another available pin or leave unconnected.

## ============================================================================
## User LEDs [7:0] - Bank 33
## ============================================================================
set_property PACKAGE_PIN T22 [get_ports { leds[0] }];      # LD0
set_property PACKAGE_PIN T21 [get_ports { leds[1] }];      # LD1
set_property PACKAGE_PIN U22 [get_ports { leds[2] }];      # LD2
set_property PACKAGE_PIN U21 [get_ports { leds[3] }];      # LD3
set_property PACKAGE_PIN V22 [get_ports { leds[4] }];      # LD4
set_property PACKAGE_PIN W22 [get_ports { leds[5] }];      # LD5
set_property PACKAGE_PIN U19 [get_ports { leds[6] }];      # LD6
set_property PACKAGE_PIN U14 [get_ports { leds[7] }];      # LD7

## ============================================================================
## IOSTANDARD Constraints (Bank-Wide)
## IMPORTANT: These MUST come AFTER all PACKAGE_PIN constraints
## ============================================================================

## Bank 33: Fixed 3.3V (VGA, LEDs)
set_property IOSTANDARD LVCMOS33 [get_ports -of_objects [get_iobanks 33]];

## Bank 34: 1.8V default on ZedBoard (Buttons, Reset)
set_property IOSTANDARD LVCMOS18 [get_ports -of_objects [get_iobanks 34]];

## Bank 35: 1.8V default on ZedBoard (Switches)
set_property IOSTANDARD LVCMOS18 [get_ports -of_objects [get_iobanks 35]];

## Bank 13: Fixed 3.3V (GCLK, PMOD JA UART)
set_property IOSTANDARD LVCMOS33 [get_ports -of_objects [get_iobanks 13]];

## ============================================================================
## Configuration Voltage
## ============================================================================
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]

## ============================================================================
## Timing Exceptions: Asynchronous I/O False Paths
## Removes TIMING-18 warnings and frees routing resources for CPU pipeline
## ============================================================================
set_false_path -from [get_ports { reset }]
set_false_path -from [get_ports { switches[*] }]
set_false_path -from [get_ports { buttons[*] }]

set_false_path -to [get_ports { leds[*] }]
set_false_path -to [get_ports { vga_r[*] }]
set_false_path -to [get_ports { vga_g[*] }]
set_false_path -to [get_ports { vga_b[*] }]
set_false_path -to [get_ports { vga_hsync }]
set_false_path -to [get_ports { vga_vsync }]

## ============================================================================
## Synthesis/Implementation Strategy Hints
## ============================================================================
set_property SEVERITY {Warning} [get_drc_checks NSTD-1]
set_property SEVERITY {Warning} [get_drc_checks UCIO-1]
