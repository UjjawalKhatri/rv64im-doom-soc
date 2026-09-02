// ============================================================================
// Module: ps7_wrapper
// Description: Zynq PS7 wrapper for ZedBoard DDR3 access from PL via S_AXI_HP0
// Instantiates the ps7_ip core (configured for ZedBoard DDR3 @ 533MHz, 32-bit, 512MB)
// ============================================================================
`timescale 1ns / 1ps

module ps7_wrapper (
    // DDR3 Physical Interface (directly to PS DDR controller pins)
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

    // Fixed IO (directly to PS fixed pins)
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,

    // Clock and Reset outputs to PL
    output wire        fclk_clk0,
    output wire        fclk_reset0_n,

    // S_AXI_HP0 Slave Interface (PL master → DDR3)
    input  wire        hp0_aclk,

    // Read Address
    input  wire [31:0] hp0_araddr,
    input  wire [1:0]  hp0_arburst,
    input  wire [3:0]  hp0_arcache,
    input  wire [5:0]  hp0_arid,
    input  wire [3:0]  hp0_arlen,
    input  wire [1:0]  hp0_arlock,
    input  wire [2:0]  hp0_arprot,
    input  wire [3:0]  hp0_arqos,
    output wire        hp0_arready,
    input  wire [2:0]  hp0_arsize,
    input  wire        hp0_arvalid,

    // Read Data
    output wire [63:0] hp0_rdata,
    output wire [5:0]  hp0_rid,
    output wire        hp0_rlast,
    input  wire        hp0_rready,
    output wire [1:0]  hp0_rresp,
    output wire        hp0_rvalid,

    // Write Address
    input  wire [31:0] hp0_awaddr,
    input  wire [1:0]  hp0_awburst,
    input  wire [3:0]  hp0_awcache,
    input  wire [5:0]  hp0_awid,
    input  wire [3:0]  hp0_awlen,
    input  wire [1:0]  hp0_awlock,
    input  wire [2:0]  hp0_awprot,
    input  wire [3:0]  hp0_awqos,
    output wire        hp0_awready,
    input  wire [2:0]  hp0_awsize,
    input  wire        hp0_awvalid,

    // Write Data
    input  wire [63:0] hp0_wdata,
    input  wire [5:0]  hp0_wid,
    input  wire        hp0_wlast,
    input  wire [7:0]  hp0_wstrb,
    input  wire        hp0_wvalid,
    output wire        hp0_wready,

    // Write Response
    output wire [5:0]  hp0_bid,
    output wire [1:0]  hp0_bresp,
    output wire        hp0_bvalid,
    input  wire        hp0_bready
);

    // ========================================================================
    // PS7 IP Core Instance
    // ========================================================================
    ps7_ip PS7_inst (
        // Clock & Reset
        .S_AXI_HP0_ACLK(hp0_aclk),
        .FCLK_CLK0(fclk_clk0),
        .FCLK_RESET0_N(fclk_reset0_n),

        // S_AXI_HP0 Read Address Channel
        .S_AXI_HP0_ARADDR(hp0_araddr),
        .S_AXI_HP0_ARBURST(hp0_arburst),
        .S_AXI_HP0_ARCACHE(hp0_arcache),
        .S_AXI_HP0_ARID(hp0_arid),
        .S_AXI_HP0_ARLEN(hp0_arlen),
        .S_AXI_HP0_ARLOCK(hp0_arlock),
        .S_AXI_HP0_ARPROT(hp0_arprot),
        .S_AXI_HP0_ARQOS(hp0_arqos),
        .S_AXI_HP0_ARREADY(hp0_arready),
        .S_AXI_HP0_ARSIZE(hp0_arsize),
        .S_AXI_HP0_ARVALID(hp0_arvalid),

        // S_AXI_HP0 Read Data Channel
        .S_AXI_HP0_RDATA(hp0_rdata),
        .S_AXI_HP0_RID(hp0_rid),
        .S_AXI_HP0_RLAST(hp0_rlast),
        .S_AXI_HP0_RREADY(hp0_rready),
        .S_AXI_HP0_RRESP(hp0_rresp),
        .S_AXI_HP0_RVALID(hp0_rvalid),
        .S_AXI_HP0_RDISSUECAP1_EN(1'b0),
        .S_AXI_HP0_RCOUNT(),
        .S_AXI_HP0_RACOUNT(),

        // S_AXI_HP0 Write Address Channel
        .S_AXI_HP0_AWADDR(hp0_awaddr),
        .S_AXI_HP0_AWBURST(hp0_awburst),
        .S_AXI_HP0_AWCACHE(hp0_awcache),
        .S_AXI_HP0_AWID(hp0_awid),
        .S_AXI_HP0_AWLEN(hp0_awlen),
        .S_AXI_HP0_AWLOCK(hp0_awlock),
        .S_AXI_HP0_AWPROT(hp0_awprot),
        .S_AXI_HP0_AWQOS(hp0_awqos),
        .S_AXI_HP0_AWREADY(hp0_awready),
        .S_AXI_HP0_AWSIZE(hp0_awsize),
        .S_AXI_HP0_AWVALID(hp0_awvalid),

        // S_AXI_HP0 Write Data Channel
        .S_AXI_HP0_WDATA(hp0_wdata),
        .S_AXI_HP0_WID(hp0_wid),
        .S_AXI_HP0_WLAST(hp0_wlast),
        .S_AXI_HP0_WREADY(hp0_wready),
        .S_AXI_HP0_WSTRB(hp0_wstrb),
        .S_AXI_HP0_WVALID(hp0_wvalid),
        .S_AXI_HP0_WRISSUECAP1_EN(1'b0),
        .S_AXI_HP0_WCOUNT(),
        .S_AXI_HP0_WACOUNT(),

        // S_AXI_HP0 Write Response Channel
        .S_AXI_HP0_BID(hp0_bid),
        .S_AXI_HP0_BREADY(hp0_bready),
        .S_AXI_HP0_BRESP(hp0_bresp),
        .S_AXI_HP0_BVALID(hp0_bvalid),

        // Dedicated DDR3 Physical Interface
        .DDR_Addr(DDR_addr),
        .DDR_BankAddr(DDR_ba),
        .DDR_CAS_n(DDR_cas_n),
        .DDR_CKE(DDR_cke),
        .DDR_Clk_n(DDR_ck_n),
        .DDR_Clk(DDR_ck_p),
        .DDR_CS_n(DDR_cs_n),
        .DDR_DM(DDR_dm),
        .DDR_DQ(DDR_dq),
        .DDR_DQS_n(DDR_dqs_n),
        .DDR_DQS(DDR_dqs_p),
        .DDR_DRSTB(DDR_reset_n),
        .DDR_ODT(DDR_odt),
        .DDR_RAS_n(DDR_ras_n),
        .DDR_WEB(DDR_we_n),
        .DDR_VRN(FIXED_IO_ddr_vrn),
        .DDR_VRP(FIXED_IO_ddr_vrp),

        // Dedicated Fixed IO Interface
        .MIO(FIXED_IO_mio),
        .PS_CLK(FIXED_IO_ps_clk),
        .PS_PORB(FIXED_IO_ps_porb),
        .PS_SRSTB(FIXED_IO_ps_srstb)
    );

endmodule
