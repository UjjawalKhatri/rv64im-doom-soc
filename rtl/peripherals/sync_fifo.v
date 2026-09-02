// ============================================================================
// Module: sync_fifo
// Description: Parameterizable Synchronous FIFO (Single Clock Domain)
// Used for UART TX/RX data buffering
// Compatible with Xilinx Vivado Synthesis & ZedBoard Implementation
// ============================================================================
`timescale 1ns / 1ps

module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 16,
    parameter ADDR_WIDTH = 4   // log2(DEPTH)
)(
    input  wire                    clk,
    input  wire                    reset,
    input  wire                    push,
    input  wire [DATA_WIDTH-1:0]   din,
    input  wire                    pop,
    output wire [DATA_WIDTH-1:0]   dout,
    output wire                    full,
    output wire                    empty,
    output wire [ADDR_WIDTH:0]     count
);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [ADDR_WIDTH:0]   wr_ptr;
    reg [ADDR_WIDTH:0]   rd_ptr;

    wire [ADDR_WIDTH:0] fill_level = wr_ptr - rd_ptr;

    assign count = fill_level;
    assign full  = (fill_level == DEPTH);
    assign empty = (fill_level == 0);
    assign dout  = mem[rd_ptr[ADDR_WIDTH-1:0]];

    always @(posedge clk) begin
        if (reset) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            if (push && !full) begin
                mem[wr_ptr[ADDR_WIDTH-1:0]] <= din;
                wr_ptr <= wr_ptr + 1;
            end
            if (pop && !empty) begin
                rd_ptr <= rd_ptr + 1;
            end
        end
    end

endmodule
