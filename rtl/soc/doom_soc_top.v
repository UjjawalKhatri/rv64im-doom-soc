// ============================================================================
// Module: doom_soc_top
// Description: DOOM SoC Top-Level for ZedBoard (xc7z020clg484-1)
// Integrates RV64IM CPU core with SoC peripherals & DDR3 via Zynq PS7:
//   - RV64IM CPU Core (with DDR3 instruction fetch & data access)
//   - DDR Request Arbiter (I-side & D-side arbitration to DDR3)
//   - Native AXI Master (64-bit AXI3 bridge to PS7 S_AXI_HP0)
//   - Zynq PS7 Controller (512 MB DDR3 memory space @ 0x8000_0000)
//   - Framebuffer (320x200 x 8-bit indexed, DOOM palette ROM)
//   - VGA Timing & Scanout (640x480@60Hz, onboard 12-bit VGA connector)
//   - Timer (64-bit cycle + microsecond counters)
//   - GPIO (8 switches, 5 buttons, 8 LEDs)
//   - UART (115200 baud, soft MMIO interface)
// Compatible with Xilinx Vivado Synthesis & ZedBoard Implementation
// ============================================================================
`timescale 1ns / 1ps

module doom_soc_top #(
    parameter MEM_FILE = "instructions.mem",

    // ------------------------------------------------------------------------
    // PL fabric clock - single point of truth.
    //
    // Changing CLK_HZ requires two matching changes:
    //   1. PS7 FCLK_CLK0 (scripts/vivado/ps7_preset.tcl -> PCW_FPGA0_PERIPHERAL_FREQMHZ)
    //   2. PIXEL_DIV below, so CLK_HZ / PIXEL_DIV is ~25 MHz for 640x480@60:
    //        100 MHz -> 4      75 MHz -> 3      50 MHz -> 2
    //
    // CLK_HZ also feeds timer_mmio and uart_mmio. Keeping it here prevents the
    // failure mode where the fabric clock changes but timer_mmio does not, which
    // silently corrupts the microsecond counter (and the on-board FPS figure).
    // ------------------------------------------------------------------------
    parameter integer CLK_HZ    = 100_000_000,
    parameter integer PIXEL_DIV = 4,
    // 0 = run straight off the 100 MHz Y9 oscillator (synthesises to a wire).
    // 1 = MMCM down to 75.000 MHz. When flipping to 1 also set
    //     CLK_HZ = 75_000_000 and PIXEL_DIV = 3, or the timer and VGA lie.
    parameter integer USE_MMCM  = 0,
    // MMCM output divider off the 900 MHz VCO: 12 -> 75 MHz, 18 -> 50 MHz.
    parameter integer CLKOUT_DIV = 12
)(
    input  wire        clk,          // 100 MHz system clock (Y9)
    input  wire        reset,        // Active-high reset (BTNC - P16)

    // VGA (ZedBoard onboard VGA, 12-bit color)
    output wire [3:0]  vga_r,        // VGA Red
    output wire [3:0]  vga_g,        // VGA Green
    output wire [3:0]  vga_b,        // VGA Blue
    output wire        vga_hsync,    // VGA HSYNC (AA19)
    output wire        vga_vsync,    // VGA VSYNC (Y19)

    // GPIO
    input  wire [7:0]  switches,     // 8 slide switches
    input  wire [3:0]  buttons,      // 4 push buttons (BTNU, BTNL, BTNR, BTND) - BTNC is reset
    output wire [7:0]  leds,         // 8 user LEDs

    // Zynq PS7 Dedicated Physical Interface (DDR3 & Fixed IO)
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb
);

    // ========================================================================
    // System Clock: passthrough at 100 MHz, or MMCM-derived 75 MHz.
    // Every synchronous element below runs on sys_clk - never on `clk`.
    // ========================================================================
    wire sys_clk;
    wire clk_locked;

    clk_gen #(.USE_MMCM(USE_MMCM), .CLKOUT_DIV(CLKOUT_DIV)) CLKGEN_inst (
        .clk_in  (clk),
        .clk_out (sys_clk),
        .locked  (clk_locked)
    );

    // ========================================================================
    // System Reset: Hardware PS7 Reset + Physical BTNC Reset with 2-FF Synchronizer
    // Also held asserted until the MMCM reports lock (always true when USE_MMCM=0).
    // ========================================================================
    wire ps7_rst_n;
    reg  rst_sync_0, rst_sync_1;
    always @(posedge sys_clk or posedge reset or negedge ps7_rst_n) begin
        if (reset || !ps7_rst_n || !clk_locked) begin
            rst_sync_0 <= 1'b1;
            rst_sync_1 <= 1'b1;
        end else begin
            rst_sync_0 <= 1'b0;
            rst_sync_1 <= rst_sync_0;
        end
    end
    wire sys_reset = rst_sync_1;

    // AXI Telemetry / Diagnostic Signals
    wire [1:0]  axi_last_rresp, axi_last_bresp;
    wire [31:0] axi_last_araddr, axi_last_awaddr;
    wire [31:0] axi_rd_count, axi_wr_count, axi_err_count;

    // ========================================================================
    // CPU Core Signals
    // ========================================================================
    wire [63:0] current_pc;
    wire [31:0] current_instr;
    wire [63:0] wb_result;
    wire [4:0]  wb_reg_addr;
    wire        wb_reg_we;
    wire [63:0] perf_cycles, perf_retired, perf_stalls, perf_flushes, perf_cpi_x100;

    // CPU Core Data Bus Signals (Core ↔ Interconnect)
    wire        cpu_data_valid;
    wire        cpu_data_we;
    wire [63:0] cpu_data_addr;
    wire [63:0] cpu_data_wdata;
    wire [7:0]  cpu_data_wstrb;
    wire [63:0] cpu_data_rdata;
    wire        cpu_data_ready;

    // CPU Core Instruction Fetch Bus Signals (Core IFU ↔ DDR Arbiter)
    wire        core_instr_req_valid;
    wire [63:0] core_instr_req_addr;
    wire        core_instr_req_ready;
    wire        core_instr_rsp_valid;
    wire [63:0] core_instr_rsp_rdata;

    // ========================================================================
    // CPU Core Instance
    // ========================================================================
    rv64i_core_top #(
        .MEM_FILE(MEM_FILE)
    ) core_inst (
        .clk(sys_clk),
        .reset(sys_reset),
        .current_pc(current_pc),
        .current_instr(current_instr),
        .wb_result(wb_result),
        .wb_reg_addr(wb_reg_addr),
        .wb_reg_we(wb_reg_we),
        .perf_cycles(perf_cycles),
        .perf_retired(perf_retired),
        .perf_stalls(perf_stalls),
        .perf_flushes(perf_flushes),
        .perf_cpi_x100(perf_cpi_x100),
        // Data Bus
        .data_req_valid(cpu_data_valid),
        .data_req_we(cpu_data_we),
        .data_req_addr(cpu_data_addr),
        .data_req_wdata(cpu_data_wdata),
        .data_req_wstrb(cpu_data_wstrb),
        .data_rsp_rdata(cpu_data_rdata),
        .data_rsp_ready(cpu_data_ready),
        // Instruction Fetch Bus
        .instr_req_valid(core_instr_req_valid),
        .instr_req_addr(core_instr_req_addr),
        .instr_req_ready(core_instr_req_ready),
        .instr_rsp_valid(core_instr_rsp_valid),
        .instr_rsp_rdata(core_instr_rsp_rdata)
    );

    // ========================================================================
    // SoC Interconnect Wires
    // ========================================================================
    // GPIO Peripheral Wires
    wire        gpio_valid, gpio_we, gpio_ready;
    wire [3:0]  gpio_addr;
    wire [63:0] gpio_wdata, gpio_rdata;

    // Timer Peripheral Wires
    wire        timer_valid, timer_ready;
    wire [3:0]  timer_addr;
    wire [63:0] timer_rdata;

    // UART Peripheral Wires
    wire        uart_valid_w, uart_we_w, uart_ready_w;
    wire [3:0]  uart_addr_w;
    wire [63:0] uart_wdata_w, uart_rdata_w;

    // Framebuffer Peripheral Wires
    wire        fb_valid, fb_we, fb_ready;
    wire [16:0] fb_addr;
    wire [63:0] fb_wdata, fb_rdata;
    wire [7:0]  fb_wstrb;

    // DDR Data Bus Signals (Interconnect ↔ DDR Arbiter D-side)
    wire        interconnect_ddr_valid;
    wire        interconnect_ddr_we;
    wire [63:0] interconnect_ddr_addr;
    wire [63:0] interconnect_ddr_wdata;
    wire [7:0]  interconnect_ddr_wstrb;
    wire [63:0] interconnect_ddr_rdata;
    wire        interconnect_ddr_ready;

    // VGA Timing Wires
    wire        vga_active;
    wire [9:0]  vga_pixel_x, vga_pixel_y;
    wire        pixel_tick;

    // ========================================================================
    // SoC Interconnect
    // ========================================================================
    soc_interconnect INTERCONNECT_inst (
        .clk(sys_clk),
        .reset(sys_reset),
        // CPU Data Bus
        .cpu_data_valid(cpu_data_valid),
        .cpu_data_we(cpu_data_we),
        .cpu_data_addr(cpu_data_addr),
        .cpu_data_wdata(cpu_data_wdata),
        .cpu_data_wstrb(cpu_data_wstrb),
        .cpu_data_rdata(cpu_data_rdata),
        .cpu_data_ready(cpu_data_ready),
        // GPIO
        .gpio_valid(gpio_valid),
        .gpio_we(gpio_we),
        .gpio_addr(gpio_addr),
        .gpio_wdata(gpio_wdata),
        .gpio_rdata(gpio_rdata),
        .gpio_ready(gpio_ready),
        // Timer
        .timer_valid(timer_valid),
        .timer_addr(timer_addr),
        .timer_rdata(timer_rdata),
        .timer_ready(timer_ready),
        // UART
        .uart_valid(uart_valid_w),
        .uart_we(uart_we_w),
        .uart_addr(uart_addr_w),
        .uart_wdata(uart_wdata_w),
        .uart_rdata(uart_rdata_w),
        .uart_ready(uart_ready_w),
        // Framebuffer
        .fb_valid(fb_valid),
        .fb_we(fb_we),
        .fb_addr(fb_addr),
        .fb_wdata(fb_wdata),
        .fb_wstrb(fb_wstrb),
        .fb_rdata(fb_rdata),
        .fb_ready(fb_ready),
        // DDR Data Interface (0x8000_0000+)
        .ddr_valid(interconnect_ddr_valid),
        .ddr_we(interconnect_ddr_we),
        .ddr_addr(interconnect_ddr_addr),
        .ddr_wdata(interconnect_ddr_wdata),
        .ddr_wstrb(interconnect_ddr_wstrb),
        .ddr_rdata(interconnect_ddr_rdata),
        .ddr_ready(interconnect_ddr_ready),
        // AXI Telemetry Inputs
        .axi_last_rresp(axi_last_rresp),
        .axi_last_bresp(axi_last_bresp),
        .axi_last_araddr(axi_last_araddr),
        .axi_last_awaddr(axi_last_awaddr),
        .axi_rd_count(axi_rd_count),
        .axi_wr_count(axi_wr_count),
        .axi_last_rdata(axi_last_rdata)
    );

    // ========================================================================
    // DDR Request Arbiter (Arbitrates I-Fetch vs D-Access to DDR3)
    // ========================================================================
    wire        arb_ddr_req_valid;
    wire        arb_ddr_req_we;
    wire [63:0] arb_ddr_req_addr;
    wire [63:0] arb_ddr_req_wdata;
    wire [7:0]  arb_ddr_req_wstrb;
    wire        arb_ddr_req_ready;
    wire        arb_ddr_rsp_valid;
    wire [63:0] arb_ddr_rsp_rdata;

    ddr_request_arbiter DDR_ARBITER_inst (
        .clk(sys_clk),
        .reset(sys_reset),
        // I-side (Instruction fetch from Core IFU)
        .i_req_valid(core_instr_req_valid),
        .i_req_addr(core_instr_req_addr),
        .i_req_ready(core_instr_req_ready),
        .i_rsp_valid(core_instr_rsp_valid),
        .i_rsp_rdata(core_instr_rsp_rdata),
        // D-side (Data load/store from Interconnect)
        .d_req_valid(interconnect_ddr_valid),
        .d_req_we(interconnect_ddr_we),
        .d_req_addr(interconnect_ddr_addr),
        .d_req_wdata(interconnect_ddr_wdata),
        .d_req_wstrb(interconnect_ddr_wstrb),
        .d_req_ready(),
        .d_rsp_valid(interconnect_ddr_ready),
        .d_rsp_rdata(interconnect_ddr_rdata),
        // Downstream DDR port (to Native AXI Master)
        .ddr_req_valid(arb_ddr_req_valid),
        .ddr_req_we(arb_ddr_req_we),
        .ddr_req_addr(arb_ddr_req_addr),
        .ddr_req_wdata(arb_ddr_req_wdata),
        .ddr_req_wstrb(arb_ddr_req_wstrb),
        .ddr_req_ready(arb_ddr_req_ready),
        .ddr_rsp_valid(arb_ddr_rsp_valid),
        .ddr_rsp_rdata(arb_ddr_rsp_rdata)
    );

    // ========================================================================
    // Native AXI3 Master (Translates simple req/rsp into AXI3 for PS7 HP0)
    // ========================================================================
    wire [5:0]  axi_awid, axi_wid, axi_bid, axi_arid, axi_rid;
    wire [31:0] axi_awaddr, axi_araddr;
    wire [3:0]  axi_awlen, axi_arlen;
    wire [2:0]  axi_awsize, axi_arsize;
    wire [1:0]  axi_awburst, axi_arburst;
    wire [1:0]  axi_awlock, axi_arlock;
    wire [3:0]  axi_awcache, axi_arcache;
    wire [2:0]  axi_awprot, axi_arprot;
    wire [3:0]  axi_awqos, axi_arqos;
    wire        axi_awvalid, axi_awready;
    wire [63:0] axi_wdata, axi_rdata;
    wire [7:0]  axi_wstrb;
    wire        axi_wlast, axi_wvalid, axi_wready;
    wire [1:0]  axi_bresp, axi_rresp;
    wire        axi_bvalid, axi_bready;
    wire        axi_arvalid, axi_arready;
    wire        axi_rlast, axi_rvalid, axi_rready;

    native_axi_master AXI_MASTER_inst (
        .clk(sys_clk),
        .resetn(!sys_reset),
        // Simple CPU/Arbiter interface
        .req_valid(arb_ddr_req_valid),
        .req_we(arb_ddr_req_we),
        .req_addr(arb_ddr_req_addr),
        .req_wdata(arb_ddr_req_wdata),
        .req_wstrb(arb_ddr_req_wstrb),
        .req_ready(arb_ddr_req_ready),
        .rsp_valid(arb_ddr_rsp_valid),
        .rsp_rdata(arb_ddr_rsp_rdata),
        // AXI3 Master interface
        .m_axi_awid(axi_awid),
        .m_axi_awaddr(axi_awaddr),
        .m_axi_awlen(axi_awlen),
        .m_axi_awsize(axi_awsize),
        .m_axi_awburst(axi_awburst),
        .m_axi_awlock(axi_awlock),
        .m_axi_awcache(axi_awcache),
        .m_axi_awprot(axi_awprot),
        .m_axi_awqos(axi_awqos),
        .m_axi_awvalid(axi_awvalid),
        .m_axi_awready(axi_awready),
        .m_axi_wid(axi_wid),
        .m_axi_wdata(axi_wdata),
        .m_axi_wstrb(axi_wstrb),
        .m_axi_wlast(axi_wlast),
        .m_axi_wvalid(axi_wvalid),
        .m_axi_wready(axi_wready),
        .m_axi_bid(axi_bid),
        .m_axi_bresp(axi_bresp),
        .m_axi_bvalid(axi_bvalid),
        .m_axi_bready(axi_bready),
        .m_axi_arid(axi_arid),
        .m_axi_araddr(axi_araddr),
        .m_axi_arlen(axi_arlen),
        .m_axi_arsize(axi_arsize),
        .m_axi_arburst(axi_arburst),
        .m_axi_arlock(axi_arlock),
        .m_axi_arcache(axi_arcache),
        .m_axi_arprot(axi_arprot),
        .m_axi_arqos(axi_arqos),
        .m_axi_arvalid(axi_arvalid),
        .m_axi_arready(axi_arready),
        .m_axi_rid(axi_rid),
        .m_axi_rdata(axi_rdata),
        .m_axi_rresp(axi_rresp),
        .m_axi_rlast(axi_rlast),
        .m_axi_rvalid(axi_rvalid),
        .m_axi_rready(axi_rready),
        // Telemetry
        .last_rresp(axi_last_rresp),
        .last_bresp(axi_last_bresp),
        .last_araddr(axi_last_araddr),
        .last_awaddr(axi_last_awaddr),
        .axi_rd_count(axi_rd_count),
        .axi_wr_count(axi_wr_count),
        .axi_err_count(axi_err_count),
        .last_rdata(axi_last_rdata)
    );

    // ========================================================================
    // Zynq PS7 Wrapper (DDR3 Controller & S_AXI_HP0 Interface)
    // ========================================================================
    ps7_wrapper PS7_WRAPPER_inst (
        // Physical DDR3 & Fixed IO
        .DDR_addr(DDR_addr),
        .DDR_ba(DDR_ba),
        .DDR_cas_n(DDR_cas_n),
        .DDR_ck_n(DDR_ck_n),
        .DDR_ck_p(DDR_ck_p),
        .DDR_cke(DDR_cke),
        .DDR_cs_n(DDR_cs_n),
        .DDR_dm(DDR_dm),
        .DDR_dq(DDR_dq),
        .DDR_dqs_n(DDR_dqs_n),
        .DDR_dqs_p(DDR_dqs_p),
        .DDR_odt(DDR_odt),
        .DDR_ras_n(DDR_ras_n),
        .DDR_reset_n(DDR_reset_n),
        .DDR_we_n(DDR_we_n),
        .FIXED_IO_ddr_vrn(FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp(FIXED_IO_ddr_vrp),
        .FIXED_IO_mio(FIXED_IO_mio),
        .FIXED_IO_ps_clk(FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb(FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb(FIXED_IO_ps_srstb),
        // Clocks to PL
        .fclk_clk0(),
        .fclk_reset0_n(ps7_rst_n),
        // S_AXI_HP0 Slave (Connected to AXI Master)
        .hp0_aclk(sys_clk),
        .hp0_araddr(axi_araddr),
        .hp0_arburst(axi_arburst),
        .hp0_arcache(axi_arcache),
        .hp0_arid(axi_arid),
        .hp0_arlen(axi_arlen),
        .hp0_arlock(axi_arlock),
        .hp0_arprot(axi_arprot),
        .hp0_arqos(axi_arqos),
        .hp0_arready(axi_arready),
        .hp0_arsize(axi_arsize),
        .hp0_arvalid(axi_arvalid),
        .hp0_rdata(axi_rdata),
        .hp0_rid(axi_rid),
        .hp0_rlast(axi_rlast),
        .hp0_rready(axi_rready),
        .hp0_rresp(axi_rresp),
        .hp0_rvalid(axi_rvalid),
        .hp0_awaddr(axi_awaddr),
        .hp0_awburst(axi_awburst),
        .hp0_awcache(axi_awcache),
        .hp0_awid(axi_awid),
        .hp0_awlen(axi_awlen),
        .hp0_awlock(axi_awlock),
        .hp0_awprot(axi_awprot),
        .hp0_awqos(axi_awqos),
        .hp0_awready(axi_awready),
        .hp0_awsize(axi_awsize),
        .hp0_awvalid(axi_awvalid),
        .hp0_wdata(axi_wdata),
        .hp0_wid(axi_wid),
        .hp0_wlast(axi_wlast),
        .hp0_wstrb(axi_wstrb),
        .hp0_wvalid(axi_wvalid),
        .hp0_wready(axi_wready),
        .hp0_bid(axi_bid),
        .hp0_bresp(axi_bresp),
        .hp0_bvalid(axi_bvalid),
        .hp0_bready(axi_bready)
    );

    // ========================================================================
    // Peripheral Instances
    // ========================================================================

    // UART (115200 baud, 8N1) - Internal only (no PMOD connected)
    wire uart_tx_internal;
    wire uart_rx_internal = 1'b1;

    uart_mmio #(
        .CLK_FREQ(CLK_HZ),
        .BAUD_RATE(115200)
    ) UART_inst (
        .clk(sys_clk),
        .reset(reset),
        .mmio_valid(uart_valid_w),
        .mmio_we(uart_we_w),
        .mmio_addr(uart_addr_w),
        .mmio_wdata(uart_wdata_w),
        .mmio_rdata(uart_rdata_w),
        .mmio_ready(uart_ready_w),
        .uart_txd(uart_tx_internal),
        .uart_rxd(uart_rx_internal)
    );

    // Timer (64-bit cycle + microsecond counters)
    timer_mmio #(
        .CLK_FREQ(CLK_HZ)
    ) TIMER_inst (
        .clk(sys_clk),
        .reset(reset),
        .mmio_valid(timer_valid),
        .mmio_addr(timer_addr),
        .mmio_rdata(timer_rdata),
        .mmio_ready(timer_ready)
    );

    // GPIO LED output
    wire [7:0] gpio_led_out;

    // Multiplex physical ZedBoard LEDs:
    //   switches[7] == 0: Normal MMIO GPIO LED register
    //   switches[7] == 1: Direct CPU PC / WB debug monitoring
    assign leds = switches[7] ? current_pc[9:2] : gpio_led_out;

    // GPIO (switches, buttons, LEDs)
    gpio_mmio GPIO_inst (
        .clk(sys_clk),
        .reset(reset),
        .mmio_valid(gpio_valid),
        .mmio_we(gpio_we),
        .mmio_addr(gpio_addr),
        .mmio_wdata(gpio_wdata),
        .mmio_rdata(gpio_rdata),
        .mmio_ready(gpio_ready),
        .gpio_switches(switches),
        .gpio_buttons({1'b0, buttons}),  // Pad to 5-bit (BTNC is used as reset)
        .gpio_leds(gpio_led_out)
    );

    // VGA Timing Generator (640x480 @ 60Hz)
    vga_timing #(
        .PIXEL_DIV(PIXEL_DIV)
    ) VGA_TIMING_inst (
        .clk_100mhz(sys_clk),
        .reset(reset),
        .hsync(vga_hsync),
        .vsync(vga_vsync),
        .active_video(vga_active),
        .pixel_x(vga_pixel_x),
        .pixel_y(vga_pixel_y),
        .pixel_tick(pixel_tick)
    );

    // Framebuffer + Palette (320x200 x 8-bit indexed color)
    framebuffer_mmio FB_inst (
        .clk(sys_clk),
        .reset(reset),
        .mmio_valid(fb_valid),
        .mmio_we(fb_we),
        .mmio_addr(fb_addr),
        .mmio_wdata(fb_wdata),
        .mmio_wstrb(fb_wstrb),
        .mmio_rdata(fb_rdata),
        .mmio_ready(fb_ready),
        .vga_active(vga_active),
        .vga_pixel_x(vga_pixel_x),
        .vga_pixel_y(vga_pixel_y),
        .pixel_tick(pixel_tick),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b)
    );

endmodule
