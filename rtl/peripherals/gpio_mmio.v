// ============================================================================
// Module: gpio_mmio
// Description: GPIO Peripheral for ZedBoard
// Register Map:
//   +0x00 (Read):  GPIO_INPUT  - {19'b0, buttons[4:0], switches[7:0]}
//   +0x08 (R/W):   GPIO_LED    - {56'b0, leds[7:0]}
// Compatible with Xilinx Vivado Synthesis & ZedBoard Implementation
// ============================================================================
`timescale 1ns / 1ps

module gpio_mmio (
    input  wire        clk,
    input  wire        reset,

    // MMIO Bus Interface
    input  wire        mmio_valid,
    input  wire        mmio_we,
    input  wire [3:0]  mmio_addr,
    input  wire [63:0] mmio_wdata,
    output reg  [63:0] mmio_rdata,
    output wire        mmio_ready,

    // Physical GPIO Pins
    input  wire [7:0]  gpio_switches,
    input  wire [4:0]  gpio_buttons,
    output reg  [7:0]  gpio_leds
);

    assign mmio_ready = mmio_valid;

    // Synchronize external inputs (double-flop)
    reg [7:0] sw_sync1, sw_sync2;
    reg [4:0] btn_sync1, btn_sync2;

    always @(posedge clk) begin
        if (reset) begin
            sw_sync1  <= 8'b0;
            sw_sync2  <= 8'b0;
            btn_sync1 <= 5'b0;
            btn_sync2 <= 5'b0;
        end else begin
            sw_sync1  <= gpio_switches;
            sw_sync2  <= sw_sync1;
            btn_sync1 <= gpio_buttons;
            btn_sync2 <= btn_sync1;
        end
    end

    // LED output register
    always @(posedge clk) begin
        if (reset) begin
            gpio_leds <= 8'b0;
        end else if (mmio_valid && mmio_we && mmio_addr[3]) begin
            // Write to +0x08: GPIO_LED
            gpio_leds <= mmio_wdata[7:0];
        end
    end

    // MMIO Read Mux
    always @(*) begin
        if (mmio_addr[3] == 1'b0)
            mmio_rdata = {51'b0, btn_sync2, sw_sync2};   // +0x00: GPIO_INPUT
        else
            mmio_rdata = {56'b0, gpio_leds};              // +0x08: GPIO_LED
    end

endmodule
