# ============================================================================
# File: ps7_preset.tcl
# Description: Configuration preset for Zynq-7000 Processing System on ZedBoard
# Configures 533 MHz DDR3 (512 MB), S_AXI_HP0 (64-bit), and 100 MHz PL clock
# ============================================================================

proc configure_zedboard_ps7 {ps7_cell} {
    set_property -dict [list \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} \
        CONFIG.PCW_USE_S_AXI_HP0 {1} \
        CONFIG.PCW_EN_CLK0_PORT {1} \
        CONFIG.PCW_EN_RST0_PORT {1} \
        CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} \
        CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41J128M16 HA-15E} \
        CONFIG.PCW_UIPARAM_DDR_DRAM_WIDTH {16 Bits} \
        CONFIG.PCW_UIPARAM_DDR_DEVICE_CAPACITY {2048 MBits} \
        CONFIG.PCW_UIPARAM_DDR_SPEED_BIN {DDR3_1066F} \
        CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} \
    ] $ps7_cell
}
