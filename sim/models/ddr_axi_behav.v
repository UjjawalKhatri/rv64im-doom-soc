// ============================================================================
// Module: ddr_axi_behav
// Behavioral AXI3 slave modelling the PS7 S_AXI_HP0 -> DDR3 path for simulation.
// Matches the access pattern of native_axi_master.v:
//   - single outstanding transaction
//   - 64-bit single-beat (awlen/arlen = 0, awsize/arsize = 3'b011)
//   - write issues AW + W together, then waits for B
//   - read issues AR, then waits for R
// Configurable response latency (LAT cycles) to emulate DDR round-trip.
// Memory is a flat 64-bit word array; byte lane writes honour WSTRB.
// Physical byte address = araddr/awaddr (already remapped by the AXI master:
//   CPU 0x8xxx_xxxx -> phys 0x0xxx_xxxx). Word index = addr>>3.
// ============================================================================
`timescale 1ns / 1ps

module ddr_axi_behav #(
    parameter        MEMH      = "",     // optional $readmemh init file (64-bit words)
    parameter integer LAT      = 8,      // response latency in clocks
    parameter integer ADDR_BITS = 26     // 2^26 bytes = 64 MB modelled
)(
    input  wire        clk,
    input  wire        resetn,

    // Write address channel
    input  wire [31:0] awaddr,
    input  wire [3:0]  awlen,
    input  wire [2:0]  awsize,
    input  wire        awvalid,
    output reg         awready,

    // Write data channel
    input  wire [63:0] wdata,
    input  wire [7:0]  wstrb,
    input  wire        wlast,
    input  wire        wvalid,
    output reg         wready,

    // Write response channel
    output reg  [1:0]  bresp,
    output reg         bvalid,
    input  wire        bready,

    // Read address channel
    input  wire [31:0] araddr,
    input  wire [3:0]  arlen,
    input  wire [2:0]  arsize,
    input  wire        arvalid,
    output reg         arready,

    // Read data channel
    output reg  [63:0] rdata,
    output reg  [1:0]  rresp,
    output reg         rlast,
    output reg         rvalid,
    input  wire        rready
);

    localparam integer WORDS = (1 << (ADDR_BITS-3));
    reg [63:0] mem [0:WORDS-1];

    integer k;
    initial begin
        for (k = 0; k < WORDS; k = k + 1) mem[k] = 64'h0;
        if (MEMH != "") $readmemh(MEMH, mem);
    end

    // Simple single-outstanding FSM
    localparam S_IDLE = 3'd0,
               S_WLAT = 3'd1,   // write latency wait
               S_BRSP = 3'd2,   // drive bvalid
               S_RLAT = 3'd3,   // read latency wait
               S_RRSP = 3'd4;   // drive rvalid

    reg [2:0]  st;
    reg [31:0] addr_q;
    reg [63:0] wdata_q;
    reg [7:0]  wstrb_q;
    integer    cnt;

    wire [ADDR_BITS-4:0] widx = addr_q[ADDR_BITS-1:3];

    integer b;
    always @(posedge clk) begin
        if (!resetn) begin
            st      <= S_IDLE;
            awready <= 1'b0;
            wready  <= 1'b0;
            bvalid  <= 1'b0;
            bresp   <= 2'b00;
            arready <= 1'b0;
            rvalid  <= 1'b0;
            rlast   <= 1'b0;
            rresp   <= 2'b00;
            rdata   <= 64'h0;
            cnt     <= 0;
        end else begin
            case (st)
                S_IDLE: begin
                    bvalid <= 1'b0;
                    rvalid <= 1'b0;
                    // Write has priority (mirrors typical DDR ordering)
                    if (awvalid && wvalid) begin
                        awready <= 1'b1;
                        wready  <= 1'b1;
                        addr_q  <= awaddr;
                        wdata_q <= wdata;
                        wstrb_q <= wstrb;
                        cnt     <= LAT;
                        st      <= S_WLAT;
                    end else if (arvalid) begin
                        arready <= 1'b1;
                        addr_q  <= araddr;
                        cnt     <= LAT;
                        st      <= S_RLAT;
                    end
                end

                S_WLAT: begin
                    awready <= 1'b0;
                    wready  <= 1'b0;
                    if (cnt > 0) begin
                        cnt <= cnt - 1;
                    end else begin
                        // Commit the write with byte strobes
                        for (b = 0; b < 8; b = b + 1) begin
                            if (wstrb_q[b])
                                mem[widx][b*8 +: 8] <= wdata_q[b*8 +: 8];
                        end
                        bresp  <= 2'b00;
                        bvalid <= 1'b1;
                        st     <= S_BRSP;
                    end
                end

                S_BRSP: begin
                    if (bready) begin
                        bvalid <= 1'b0;
                        st     <= S_IDLE;
                    end
                end

                S_RLAT: begin
                    arready <= 1'b0;
                    if (cnt > 0) begin
                        cnt <= cnt - 1;
                    end else begin
                        rdata  <= mem[widx];
                        rresp  <= 2'b00;
                        rlast  <= 1'b1;
                        rvalid <= 1'b1;
                        st     <= S_RRSP;
                    end
                end

                S_RRSP: begin
                    if (rready) begin
                        rvalid <= 1'b0;
                        rlast  <= 1'b0;
                        st     <= S_IDLE;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
