// ============================================================================
// Module: vga_timing
// Description: VGA 640x480 @ 60 Hz Timing Generator
// Pixel clock: 25 MHz (derived from 100 MHz via divide-by-4)
// Outputs sync signals, active video flag, and pixel coordinates
// Compatible with Xilinx Vivado Synthesis & ZedBoard Implementation
// ============================================================================
`timescale 1ns / 1ps

module vga_timing (
    input  wire        clk_100mhz,
    input  wire        reset,

    // VGA Sync Outputs
    output reg         hsync,
    output reg         vsync,
    output wire        active_video,
    output reg  [9:0]  pixel_x,
    output reg  [9:0]  pixel_y,

    // Pixel clock enable (active 1 out of every 4 clocks)
    output wire        pixel_tick
);

    // 640x480 @ 60 Hz VGA Timing Parameters (25.175 MHz pixel clock)
    // Using 25 MHz (100/4) which is close enough for all monitors
    localparam H_ACTIVE  = 640;
    localparam H_FP      = 16;    // Front porch
    localparam H_SYNC    = 96;    // Sync pulse
    localparam H_BP      = 48;    // Back porch
    localparam H_TOTAL   = H_ACTIVE + H_FP + H_SYNC + H_BP; // 800

    localparam V_ACTIVE  = 480;
    localparam V_FP      = 10;
    localparam V_SYNC    = 2;
    localparam V_BP      = 33;
    localparam V_TOTAL   = V_ACTIVE + V_FP + V_SYNC + V_BP; // 525

    // Pixel clock divider: 100 MHz / 4 = 25 MHz
    reg [1:0] clk_div;

    assign pixel_tick = (clk_div == 2'b00);

    always @(posedge clk_100mhz) begin
        if (reset)
            clk_div <= 2'b0;
        else
            clk_div <= clk_div + 2'd1;
    end

    // Horizontal and Vertical Counters
    reg [9:0] h_count;
    reg [9:0] v_count;

    always @(posedge clk_100mhz) begin
        if (reset) begin
            h_count <= 10'b0;
            v_count <= 10'b0;
        end else if (pixel_tick) begin
            if (h_count == H_TOTAL - 1) begin
                h_count <= 10'b0;
                if (v_count == V_TOTAL - 1)
                    v_count <= 10'b0;
                else
                    v_count <= v_count + 10'd1;
            end else begin
                h_count <= h_count + 10'd1;
            end
        end
    end

    // Sync signal generation (active LOW for VGA standard)
    always @(posedge clk_100mhz) begin
        if (reset) begin
            hsync   <= 1'b1;
            vsync   <= 1'b1;
            pixel_x <= 10'b0;
            pixel_y <= 10'b0;
        end else if (pixel_tick) begin
            // HSYNC: active during sync pulse region
            hsync <= ~((h_count >= H_ACTIVE + H_FP) && (h_count < H_ACTIVE + H_FP + H_SYNC));

            // VSYNC: active during sync pulse region
            vsync <= ~((v_count >= V_ACTIVE + V_FP) && (v_count < V_ACTIVE + V_FP + V_SYNC));

            // Pixel coordinates (only valid during active region)
            pixel_x <= h_count;
            pixel_y <= v_count;
        end
    end

    // Active video region flag
    assign active_video = (h_count < H_ACTIVE) && (v_count < V_ACTIVE);

endmodule
