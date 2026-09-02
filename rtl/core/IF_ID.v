// ============================================================================
// Module: IF_ID
// Description: IF/ID Pipeline Register with NOP flush on reset
// Compatible with Xilinx Vivado Synthesis & Implementation
// ============================================================================
`timescale 1ns / 1ps

module IF_ID (
    input  wire        clk,
    input  wire        reset,
    input  wire        flush,
    input  wire        IF_ID_write,
    input  wire [63:0] IF_ID_pc_in,
    input  wire [31:0] IF_ID_Ins_in,
    output reg         IF_ID_valid_out,
    output reg  [63:0] IF_ID_pc_out,
    output reg  [31:0] IF_ID_Ins_out
);

    always @(posedge clk) begin
        if (reset) begin
            IF_ID_valid_out <= 1'b0;
            IF_ID_pc_out    <= 64'b0;
            IF_ID_Ins_out   <= 32'h00000013; // NOP instruction (addi x0, x0, 0)
        end else if (flush) begin
            IF_ID_valid_out <= 1'b0;
            IF_ID_Ins_out   <= 32'h00000013; // NOP instruction
        end else if (IF_ID_write) begin
            IF_ID_valid_out <= 1'b1;
            IF_ID_pc_out    <= IF_ID_pc_in;
            IF_ID_Ins_out   <= IF_ID_Ins_in;
        end
    end

endmodule
