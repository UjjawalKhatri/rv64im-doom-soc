// ============================================================================
// Module: soc_interconnect
// Description: DOOM SoC Address Decoder & Data Bus Interconnect
// Routes CPU data requests to peripherals and external DDR based on address:
//   0x1000_1xxx   → GPIO (and Timer at 0x1000_1018+)
//   0x1000_4xxx   → UART
//   0x2000_xxxx   → Framebuffer
//   0x8000_0000+  → External DDR3 (via DDR Arbiter D-side)
// V1: single outstanding transaction, combinational decode
// Compatible with Xilinx Vivado Synthesis & ZedBoard Implementation
// ============================================================================
`timescale 1ns / 1ps

module soc_interconnect (
    input  wire        clk,
    input  wire        reset,

    // CPU Data Bus (from core)
    input  wire        cpu_data_valid,
    input  wire        cpu_data_we,
    input  wire [63:0] cpu_data_addr,
    input  wire [63:0] cpu_data_wdata,
    input  wire [7:0]  cpu_data_wstrb,
    output reg  [63:0] cpu_data_rdata,
    output reg         cpu_data_ready,

    // GPIO Peripheral Interface
    output wire        gpio_valid,
    output wire        gpio_we,
    output wire [3:0]  gpio_addr,
    output wire [63:0] gpio_wdata,
    input  wire [63:0] gpio_rdata,
    input  wire        gpio_ready,

    // Timer Peripheral Interface
    output wire        timer_valid,
    output wire [3:0]  timer_addr,
    input  wire [63:0] timer_rdata,
    input  wire        timer_ready,

    // UART Peripheral Interface
    output wire        uart_valid,
    output wire        uart_we,
    output wire [3:0]  uart_addr,
    output wire [63:0] uart_wdata,
    input  wire [63:0] uart_rdata,
    input  wire        uart_ready,

    // Framebuffer Peripheral Interface
    output wire        fb_valid,
    output wire        fb_we,
    output wire [16:0] fb_addr,
    output wire [63:0] fb_wdata,
    output wire [7:0]  fb_wstrb,
    input  wire [63:0] fb_rdata,
    input  wire        fb_ready,

    // DDR Data Interface (to DDR Arbiter D-side)
    output wire        ddr_valid,
    output wire        ddr_we,
    output wire [63:0] ddr_addr,
    output wire [63:0] ddr_wdata,
    output wire [7:0]  ddr_wstrb,
    input  wire [63:0] ddr_rdata,
    input  wire        ddr_ready,

    // AXI Telemetry / Diagnostic Inputs
    input  wire [1:0]  axi_last_rresp,
    input  wire [1:0]  axi_last_bresp,
    input  wire [31:0] axi_last_araddr,
    input  wire [31:0] axi_last_awaddr,
    input  wire [31:0] axi_rd_count,
    input  wire [31:0] axi_wr_count,
    input  wire [63:0] axi_last_rdata
);

    // ========================================================================
    // Address Decode Logic
    // ========================================================================
    // Top bit and nibble determine major region:
    //   addr[31]    == 1'b1 → DDR memory (0x8000_0000 .. 0xFFFF_FFFF)
    //   addr[31:28] == 4'h1 → MMIO peripherals (0x1000_xxxx)
    //   addr[31:28] == 4'h2 → Framebuffer (0x2000_xxxx)
    //
    // Within MMIO (0x1000_xxxx), addr[15:12] selects peripheral:
    //   addr[15:12] == 4'h1 → GPIO (0x1000_1000..0x1000_100F)
    //                          Timer sits at 0x1000_1018..0x1000_1027
    //                          Differentiate by addr[5:3]
    //   addr[15:12] == 4'h4 → UART  (0x1000_4000..0x1000_400F)

    wire is_ddr  = (cpu_data_addr[31] == 1'b1);
    wire is_mmio = (cpu_data_addr[31:28] == 4'h1);
    wire is_fb   = (cpu_data_addr[31:28] == 4'h2);

    // Sub-decode within MMIO region
    wire is_gpio_region    = is_mmio && (cpu_data_addr[15:12] == 4'h1);
    wire is_timer          = is_gpio_region && ((cpu_data_addr[5:3] == 3'b011) || (cpu_data_addr[5:3] == 3'b100)); // 0x18..0x27 → Timer
    wire is_gpio           = is_gpio_region && (cpu_data_addr[5:4] == 2'b00);  // 0x00..0x0F → GPIO
    wire is_axi_status     = is_gpio_region && (cpu_data_addr[6:3] == 4'b0110); // 0x30..0x37 → AXI Status
    wire is_axi_stats      = is_gpio_region && (cpu_data_addr[6:3] == 4'b0111); // 0x38..0x3F → AXI Stats
    wire is_axi_last_rdata = is_gpio_region && (cpu_data_addr[6:3] == 4'b1000); // 0x40..0x47 → AXI last_rdata
    wire is_uart           = is_mmio && (cpu_data_addr[15:12] == 4'h4);

    // Route valid/we/addr/wdata to selected peripheral
    assign gpio_valid  = cpu_data_valid && is_gpio;
    assign gpio_we     = cpu_data_we;
    assign gpio_addr   = cpu_data_addr[3:0];
    assign gpio_wdata  = cpu_data_wdata;

    assign timer_valid = cpu_data_valid && is_timer;
    assign timer_addr  = (cpu_data_addr[5:3] == 3'b100) ? 4'h8 : 4'h0;

    assign uart_valid  = cpu_data_valid && is_uart;
    assign uart_we     = cpu_data_we;
    assign uart_addr   = cpu_data_addr[3:0];
    assign uart_wdata  = cpu_data_wdata;

    assign fb_valid    = cpu_data_valid && is_fb;
    assign fb_we       = cpu_data_we;
    assign fb_addr     = cpu_data_addr[16:0];
    assign fb_wdata    = cpu_data_wdata;
    assign fb_wstrb    = cpu_data_wstrb;

    assign ddr_valid   = cpu_data_valid && is_ddr;
    assign ddr_we      = cpu_data_we;
    assign ddr_addr    = cpu_data_addr;
    assign ddr_wdata   = cpu_data_wdata;
    assign ddr_wstrb   = cpu_data_wstrb;

    // Mux read data and ready from selected peripheral back to CPU
    always @(*) begin
        cpu_data_rdata = 64'hDEAD_DEAD_DEAD_DEAD;  // Default: unmapped address
        cpu_data_ready = 1'b0;

        if (is_gpio) begin
            cpu_data_rdata = gpio_rdata;
            cpu_data_ready = gpio_ready;
        end else if (is_timer) begin
            cpu_data_rdata = timer_rdata;
            cpu_data_ready = timer_ready;
        end else if (is_axi_status) begin
            cpu_data_rdata = {axi_last_araddr, 14'b0, axi_last_bresp, 14'b0, axi_last_rresp};
            cpu_data_ready = 1'b1;
        end else if (is_axi_stats) begin
            cpu_data_rdata = {axi_wr_count, axi_rd_count};
            cpu_data_ready = 1'b1;
        end else if (is_axi_last_rdata) begin
            cpu_data_rdata = axi_last_rdata;
            cpu_data_ready = 1'b1;
        end else if (is_uart) begin
            cpu_data_rdata = uart_rdata;
            cpu_data_ready = uart_ready;
        end else if (is_fb) begin
            cpu_data_rdata = fb_rdata;
            cpu_data_ready = fb_ready;
        end else if (is_ddr) begin
            cpu_data_rdata = ddr_rdata;
            cpu_data_ready = ddr_ready;
        end else if (cpu_data_valid) begin
            // Unmapped address: respond immediately to avoid hang
            cpu_data_ready = 1'b1;
        end
    end

endmodule
