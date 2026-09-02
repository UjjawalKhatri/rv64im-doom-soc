// ============================================================================
// Module: native_axi_master
// Description: Translates simple req/rsp memory interface to AXI3 protocol
// for Zynq PS7 S_AXI_HP0 access to DDR3. Per blueprint Section 37.
// V1: single outstanding read or write, 64-bit data, no bursts.
// Address remapping: CPU addr[31]=1 → AXI addr[31]=0 (0x8xxx → 0x0xxx)
// ============================================================================
`timescale 1ns / 1ps

module native_axi_master (
    input  wire        clk,
    input  wire        resetn,   // Active-low reset (matches AXI convention)

    // Simple CPU-side req/rsp interface
    input  wire        req_valid,
    input  wire        req_we,
    input  wire [63:0] req_addr,
    input  wire [63:0] req_wdata,
    input  wire [7:0]  req_wstrb,
    output wire        req_ready,
    output reg         rsp_valid,
    output reg  [63:0] rsp_rdata,

    // AXI3 Master Interface (to PS7 S_AXI_HP0)
    // Write Address Channel
    output wire [5:0]  m_axi_awid,
    output reg  [31:0] m_axi_awaddr,
    output wire [3:0]  m_axi_awlen,
    output wire [2:0]  m_axi_awsize,
    output wire [1:0]  m_axi_awburst,
    output wire [1:0]  m_axi_awlock,
    output wire [3:0]  m_axi_awcache,
    output wire [2:0]  m_axi_awprot,
    output wire [3:0]  m_axi_awqos,
    output reg         m_axi_awvalid,
    input  wire        m_axi_awready,

    // Write Data Channel
    output wire [5:0]  m_axi_wid,
    output reg  [63:0] m_axi_wdata,
    output reg  [7:0]  m_axi_wstrb,
    output wire        m_axi_wlast,
    output reg         m_axi_wvalid,
    input  wire        m_axi_wready,

    // Write Response Channel
    input  wire [5:0]  m_axi_bid,
    input  wire [1:0]  m_axi_bresp,
    input  wire        m_axi_bvalid,
    output wire        m_axi_bready,

    // Read Address Channel
    output wire [5:0]  m_axi_arid,
    output reg  [31:0] m_axi_araddr,
    output wire [3:0]  m_axi_arlen,
    output wire [2:0]  m_axi_arsize,
    output wire [1:0]  m_axi_arburst,
    output wire [1:0]  m_axi_arlock,
    output wire [3:0]  m_axi_arcache,
    output wire [2:0]  m_axi_arprot,
    output wire [3:0]  m_axi_arqos,
    output reg         m_axi_arvalid,
    input  wire        m_axi_arready,

    // Read Data Channel
    input  wire [5:0]  m_axi_rid,
    input  wire [63:0] m_axi_rdata,
    input  wire [1:0]  m_axi_rresp,
    input  wire        m_axi_rlast,
    input  wire        m_axi_rvalid,
    output wire        m_axi_rready,

    // Diagnostic / Telemetry Outputs (Exposed to MMIO)
    output reg  [1:0]  last_rresp,
    output reg  [1:0]  last_bresp,
    output reg  [31:0] last_araddr,
    output reg  [31:0] last_awaddr,
    output reg  [31:0] axi_rd_count,
    output reg  [31:0] axi_wr_count,
    output reg  [31:0] axi_err_count,
    output reg  [63:0] last_rdata
);

    // ========================================================================
    // Fixed AXI3 parameters for single-beat 64-bit transactions
    // ========================================================================
    assign m_axi_awid    = 6'b000000;
    assign m_axi_awlen   = 4'b0000;    // 1 beat (AXI3: len 0 = 1 beat)
    assign m_axi_awsize  = 3'b011;     // 8 bytes (64-bit) per beat
    assign m_axi_awburst = 2'b01;      // INCR
    assign m_axi_awlock  = 2'b00;      // Normal
    assign m_axi_awcache = 4'b0000;    // Device non-bufferable (strict DDR3 ordering)
    assign m_axi_awprot  = 3'b000;     // Unprivileged
    assign m_axi_awqos   = 4'b0000;    // No QoS

    assign m_axi_wid     = 6'b000000;
    assign m_axi_wlast   = 1'b1;       // Single beat, always last

    assign m_axi_arid    = 6'b000000;
    assign m_axi_arlen   = 4'b0000;    // 1 beat
    assign m_axi_arsize  = 3'b011;     // 8 bytes (64-bit) per beat
    assign m_axi_arburst = 2'b01;      // INCR
    assign m_axi_arlock  = 2'b00;      // Normal
    assign m_axi_arcache = 4'b0000;    // Device non-bufferable (strict DDR3 ordering)
    assign m_axi_arprot  = 3'b000;     // Unprivileged
    assign m_axi_arqos   = 4'b0000;    // No QoS

    // ========================================================================
    // Address remapping: CPU 0x8xxx_xxxx → PS DDR 0x0xxx_xxxx
    // For 64-bit AXI transactions (AxSIZE = 3'b011), AxADDR must be 8-byte aligned.
    // Byte offsets [2:0] are handled exclusively via WSTRB (write) and LSU (read).
    // ========================================================================
    wire [31:0] phys_addr = {1'b0, req_addr[30:3], 3'b000};

    // ========================================================================
    // FSM States
    // ========================================================================
    localparam AXI_IDLE    = 3'd0;
    localparam AXI_RD_ADDR = 3'd1;
    localparam AXI_RD_DATA = 3'd2;
    localparam AXI_WR_ADDR = 3'd3;
    localparam AXI_WR_RESP = 3'd4;

    reg [2:0] axi_state;

    // Ready to accept whenever in IDLE state (no circular req_valid dependency)
    assign req_ready = (axi_state == AXI_IDLE);

    // Keep RREADY and BREADY asserted strictly during active response phases
    assign m_axi_rready = (axi_state == AXI_RD_DATA);
    assign m_axi_bready = (axi_state == AXI_WR_RESP);

    // ========================================================================
    // FSM
    // ========================================================================
    always @(posedge clk) begin
        if (!resetn) begin
            axi_state     <= AXI_IDLE;
            m_axi_arvalid <= 1'b0;
            m_axi_araddr  <= 32'b0;
            m_axi_awvalid <= 1'b0;
            m_axi_awaddr  <= 32'b0;
            m_axi_wvalid  <= 1'b0;
            m_axi_wdata   <= 64'b0;
            m_axi_wstrb   <= 8'b0;
            rsp_valid     <= 1'b0;
            rsp_rdata     <= 64'b0;
            last_rresp    <= 2'b00;
            last_bresp    <= 2'b00;
            last_araddr   <= 32'b0;
            last_awaddr   <= 32'b0;
            axi_rd_count  <= 32'b0;
            axi_wr_count  <= 32'b0;
            axi_err_count <= 32'b0;
            last_rdata    <= 64'b0;
        end else begin
            // Default: deassert response pulse
            rsp_valid <= 1'b0;

            case (axi_state)
                AXI_IDLE: begin
                    if (req_valid) begin
                        if (req_we) begin
                            // Write: issue AW + W simultaneously
                            m_axi_awvalid <= 1'b1;
                            m_axi_awaddr  <= phys_addr;
                            m_axi_wvalid  <= 1'b1;
                            m_axi_wdata   <= req_wdata;
                            m_axi_wstrb   <= req_wstrb;
                            last_awaddr   <= phys_addr;
                            axi_state     <= AXI_WR_ADDR;
                        end else begin
                            // Read: issue AR
                            m_axi_arvalid <= 1'b1;
                            m_axi_araddr  <= phys_addr;
                            last_araddr   <= phys_addr;
                            axi_state     <= AXI_RD_ADDR;
                        end
                    end
                end

                // ============================================================
                // Read path
                // ============================================================
                AXI_RD_ADDR: begin
                    if (m_axi_arready) begin
                        m_axi_arvalid <= 1'b0;
                        axi_state     <= AXI_RD_DATA;
                    end
                end

                AXI_RD_DATA: begin
                    if (m_axi_rvalid) begin
                        rsp_valid     <= 1'b1;
                        rsp_rdata     <= m_axi_rdata;
                        last_rdata    <= m_axi_rdata;
                        last_rresp    <= m_axi_rresp;
                        axi_rd_count  <= axi_rd_count + 1'b1;
                        if (m_axi_rresp != 2'b00) begin
                            axi_err_count <= axi_err_count + 1'b1;
                        end
                        axi_state     <= AXI_IDLE;
                    end
                end

                // ============================================================
                // Write path
                // ============================================================
                AXI_WR_ADDR: begin
                    if (m_axi_awready) m_axi_awvalid <= 1'b0;
                    if (m_axi_wready)  m_axi_wvalid  <= 1'b0;

                    if ((!m_axi_awvalid || m_axi_awready) &&
                        (!m_axi_wvalid  || m_axi_wready)) begin
                        m_axi_awvalid <= 1'b0;
                        m_axi_wvalid  <= 1'b0;
                        axi_state     <= AXI_WR_RESP;
                    end
                end

                AXI_WR_RESP: begin
                    if (m_axi_bvalid) begin
                        rsp_valid     <= 1'b1;
                        rsp_rdata     <= 64'b0;
                        last_bresp    <= m_axi_bresp;
                        axi_wr_count  <= axi_wr_count + 1'b1;
                        if (m_axi_bresp != 2'b00) begin
                            axi_err_count <= axi_err_count + 1'b1;
                        end
                        axi_state     <= AXI_IDLE;
                    end
                end

                default: axi_state <= AXI_IDLE;
            endcase
        end
    end

endmodule
