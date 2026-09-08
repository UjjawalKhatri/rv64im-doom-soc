// ============================================================================
// Module: clk_gen
// Description: System clock source for the DOOM SoC.
//
// USE_MMCM = 0 (default)
//     Straight passthrough of the 100 MHz Y9 board oscillator. Synthesises to
//     a plain wire - the design is bit-identical to having no clk_gen at all.
//
// USE_MMCM = 1
//     MMCM generates exactly 75.000 MHz from the 100 MHz input:
//         VCO      = 100 MHz * 9 / 1 = 900 MHz   (well inside the -1 range)
//         CLKOUT0  = 900 MHz / 12    = 75.000 MHz
//     CLKOUT_DIV picks the target off the 900 MHz VCO:
//         12 -> 75.000 MHz  (pair with PIXEL_DIV = 3)
//         18 -> 50.000 MHz  (pair with PIXEL_DIV = 2)
//     Both divide down to exactly 25 MHz, so vga_timing keeps its existing
//     640x480 timing. 60 MHz does not divide to 25 MHz at all and is not an
//     option at any divider.
//
// No PS7 reconfiguration is required for either setting: fclk_clk0 is unused,
// and hp0_aclk simply follows this clock (S_AXI_HP0 is happy well above
// 75 MHz). The XDC needs no change either - create_clock still constrains the
// 100 MHz input port and Vivado derives the MMCM output clock from it.
// ============================================================================
`timescale 1ns / 1ps

module clk_gen #(
    parameter integer USE_MMCM   = 0,
    // MMCM output divider off the 900 MHz VCO:
    //   12 -> 75.000 MHz     18 -> 50.000 MHz
    parameter integer CLKOUT_DIV = 12
)(
    input  wire clk_in,     // 100 MHz board oscillator (Y9)
    output wire clk_out,    // system clock: 100 MHz, or 75 MHz when USE_MMCM=1
    output wire locked      // hold the design in reset until this is high
);

generate
if (USE_MMCM == 0) begin : g_passthrough

    assign clk_out = clk_in;
    assign locked  = 1'b1;

end else begin : g_mmcm

    wire clkfb, clkfb_buf, clkout0;

    MMCME2_BASE #(
        .BANDWIDTH          ("OPTIMIZED"),
        .CLKIN1_PERIOD      (10.000),   // 100 MHz in
        .DIVCLK_DIVIDE      (1),
        .CLKFBOUT_MULT_F    (9.000),        // VCO = 900 MHz
        .CLKOUT0_DIVIDE_F   (CLKOUT_DIV),   // 900 / CLKOUT_DIV
        .CLKOUT0_DUTY_CYCLE (0.500),
        .CLKOUT0_PHASE      (0.000),
        .STARTUP_WAIT       ("FALSE")
    ) mmcm_inst (
        .CLKIN1   (clk_in),
        .CLKFBIN  (clkfb_buf),
        .CLKFBOUT (clkfb),
        .CLKFBOUTB(),
        .CLKOUT0  (clkout0),
        .CLKOUT0B (),
        .CLKOUT1  (), .CLKOUT1B(),
        .CLKOUT2  (), .CLKOUT2B(),
        .CLKOUT3  (), .CLKOUT3B(),
        .CLKOUT4  (), .CLKOUT5(), .CLKOUT6(),
        .LOCKED   (locked),
        .PWRDWN   (1'b0),
        .RST      (1'b0)
    );

    BUFG bufg_fb  (.I(clkfb),   .O(clkfb_buf));
    BUFG bufg_out (.I(clkout0), .O(clk_out));

end
endgenerate

endmodule
