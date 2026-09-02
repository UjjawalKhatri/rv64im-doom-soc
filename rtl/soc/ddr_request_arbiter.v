// ============================================================================
// Module: ddr_request_arbiter
// Description: Arbitrates between I-side (instruction fetch) and D-side
// (load/store) requests for the unified DDR3 memory controller.
// D-side is prioritized because data stalls freeze pipeline progress.
// The deadlock (where fetch_stall freezes EX_MEM, causing d_req_valid
// to stay asserted and starve I-side) is solved at the pipeline level
// via a mem_ddr_done latch in rv64i_core_top.v.
// Per blueprint Section 38.
// ============================================================================
`timescale 1ns / 1ps

module ddr_request_arbiter (
    input  wire        clk,
    input  wire        reset,

    // I-side (instruction fetch) request/response
    input  wire        i_req_valid,
    input  wire [63:0] i_req_addr,
    output wire        i_req_ready,
    output wire        i_rsp_valid,
    output wire [63:0] i_rsp_rdata,

    // D-side (data load/store) request/response
    input  wire        d_req_valid,
    input  wire        d_req_we,
    input  wire [63:0] d_req_addr,
    input  wire [63:0] d_req_wdata,
    input  wire [7:0]  d_req_wstrb,
    output wire        d_req_ready,
    output wire        d_rsp_valid,
    output wire [63:0] d_rsp_rdata,

    // Downstream DDR port (to AXI master)
    output reg         ddr_req_valid,
    output reg         ddr_req_we,
    output reg  [63:0] ddr_req_addr,
    output reg  [63:0] ddr_req_wdata,
    output reg  [7:0]  ddr_req_wstrb,
    input  wire        ddr_req_ready,
    input  wire        ddr_rsp_valid,
    input  wire [63:0] ddr_rsp_rdata
);

    // ========================================================================
    // Arbiter FSM
    // ========================================================================
    localparam ARB_IDLE     = 2'd0;
    localparam ARB_WAIT_RSP = 2'd1;

    reg [1:0] arb_state;
    reg       owner_is_d;

    // Ready when in IDLE state and downstream AXI master is ready
    assign d_req_ready = (arb_state == ARB_IDLE) && ddr_req_ready;
    assign i_req_ready = (arb_state == ARB_IDLE) && !d_req_valid && ddr_req_ready;

    // Response routing: only the active owner gets the response
    assign i_rsp_valid = (arb_state == ARB_WAIT_RSP) && !owner_is_d && ddr_rsp_valid;
    assign i_rsp_rdata = ddr_rsp_rdata;

    assign d_rsp_valid = (arb_state == ARB_WAIT_RSP) && owner_is_d && ddr_rsp_valid;
    assign d_rsp_rdata = ddr_rsp_rdata;

    // ========================================================================
    // Sequential Arbiter Logic
    // ========================================================================
    always @(posedge clk) begin
        if (reset) begin
            arb_state     <= ARB_IDLE;
            owner_is_d    <= 1'b0;
            ddr_req_valid <= 1'b0;
            ddr_req_we    <= 1'b0;
            ddr_req_addr  <= 64'b0;
            ddr_req_wdata <= 64'b0;
            ddr_req_wstrb <= 8'b0;
        end else begin
            case (arb_state)
                ARB_IDLE: begin
                    ddr_req_valid <= 1'b0;

                    // Priority 1: D-side request
                    if (d_req_valid && ddr_req_ready) begin
                        ddr_req_valid <= 1'b1;
                        ddr_req_we    <= d_req_we;
                        ddr_req_addr  <= d_req_addr;
                        ddr_req_wdata <= d_req_wdata;
                        ddr_req_wstrb <= d_req_wstrb;
                        owner_is_d    <= 1'b1;
                        arb_state     <= ARB_WAIT_RSP;
                    end
                    // Priority 2: I-side request
                    else if (i_req_valid && ddr_req_ready) begin
                        ddr_req_valid <= 1'b1;
                        ddr_req_we    <= 1'b0; // I-side is always read
                        ddr_req_addr  <= i_req_addr;
                        ddr_req_wdata <= 64'b0;
                        ddr_req_wstrb <= 8'b0;
                        owner_is_d    <= 1'b0;
                        arb_state     <= ARB_WAIT_RSP;
                    end
                end

                ARB_WAIT_RSP: begin
                    // Always clear valid in WAIT state since AXI master captures on first cycle
                    ddr_req_valid <= 1'b0;

                    if (ddr_rsp_valid) begin
                        arb_state <= ARB_IDLE;
                    end
                end

                default: arb_state <= ARB_IDLE;
            endcase
        end
    end

endmodule
