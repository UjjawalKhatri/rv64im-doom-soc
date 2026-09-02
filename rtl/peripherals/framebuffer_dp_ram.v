// ============================================================================
// Module: framebuffer_dp_ram
// Description: True Dual-Port BRAM Framebuffer for DOOM SoC
// 320x200 = 64,000 entries x 8-bit indexed color
// Port A: CPU read/write (100 MHz system clock)
// Port B: VGA scanout read (100 MHz, pixel_tick gated)
// DOOM's native 8-bit palette index format
// Compatible with Xilinx Vivado Synthesis (infers BRAM)
// ============================================================================
`timescale 1ns / 1ps

module framebuffer_dp_ram (
    // Port A: CPU Side (100 MHz)
    input  wire        clk_a,
    input  wire        we_a,
    input  wire [15:0] addr_a,    // 0..63999 (320*200-1)
    input  wire [7:0]  din_a,
    output reg  [7:0]  dout_a,

    // Port B: VGA Scanout Side (100 MHz, read-only)
    input  wire        clk_b,
    input  wire [15:0] addr_b,
    output reg  [7:0]  dout_b
);

    // 64K x 8-bit = 512 Kbit = ~14 BRAM36K blocks
    (* ram_style = "block" *) reg [7:0] fb_mem [0:65535];

    // Initialize to black (index 0)
    integer i;
    initial begin
        for (i = 0; i < 65536; i = i + 1)
            fb_mem[i] = 8'h00;
    end

    // Port A: CPU read/write
    always @(posedge clk_a) begin
        if (we_a)
            fb_mem[addr_a] <= din_a;
        dout_a <= fb_mem[addr_a];
    end

    // Port B: VGA scanout read
    always @(posedge clk_b) begin
        dout_b <= fb_mem[addr_b];
    end

endmodule
