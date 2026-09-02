// ============================================================================
// Module: timer_mmio
// Description: 64-bit Timer Peripheral for DOOM SoC
// Register Map:
//   +0x00 (Read): TIMER_CYCLES - 64-bit free-running cycle counter
//   +0x08 (Read): TIMER_US     - 64-bit microsecond counter (from 100 MHz)
// Used by DoomGeneric: DG_GetTicksMs() = TIMER_US / 1000
// Compatible with Xilinx Vivado Synthesis & ZedBoard Implementation
// ============================================================================
`timescale 1ns / 1ps

module timer_mmio #(
    parameter CLK_FREQ = 100_000_000   // 100 MHz system clock
)(
    input  wire        clk,
    input  wire        reset,

    // MMIO Bus Interface
    input  wire        mmio_valid,
    input  wire [3:0]  mmio_addr,     // Byte address within Timer region
    output reg  [63:0] mmio_rdata,
    output wire        mmio_ready
);

    // Free-running cycle counter (increments every clock)
    reg [63:0] cycle_counter;

    // Microsecond counter
    reg [63:0] us_counter;
    reg [6:0]  us_prescaler;   // Counts 0..99 for 100 MHz → 1 µs

    localparam US_DIVISOR = CLK_FREQ / 1_000_000;  // = 100 for 100 MHz

    assign mmio_ready = mmio_valid;

    always @(posedge clk) begin
        if (reset) begin
            cycle_counter <= 64'b0;
            us_counter    <= 64'b0;
            us_prescaler  <= 7'b0;
        end else begin
            // Cycle counter: always increments
            cycle_counter <= cycle_counter + 64'd1;

            // Microsecond counter: increment every US_DIVISOR clocks
            if (us_prescaler == US_DIVISOR - 1) begin
                us_prescaler <= 7'b0;
                us_counter   <= us_counter + 64'd1;
            end else begin
                us_prescaler <= us_prescaler + 7'd1;
            end
        end
    end

    // MMIO Read Mux
    always @(*) begin
        if (mmio_addr[3] == 1'b0)
            mmio_rdata = cycle_counter;    // +0x00: TIMER_CYCLES
        else
            mmio_rdata = us_counter;       // +0x08: TIMER_US
    end

endmodule
