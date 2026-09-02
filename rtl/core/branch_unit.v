// ============================================================================
// Module: branch_unit
// Description: Ultra-High-Speed 64-bit Parallel Partitioned Branch Unit
// Uses dual 32-bit parallel comparators to cut CARRY chain delay in half
// Supports BEQ, BNE, BLT, BGE, BLTU, BGEU based on funct3
// ============================================================================
`timescale 1ns / 1ps

module branch_unit (
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire [2:0]  funct3,
    output reg         taken
);

    // Parallel 32-bit partitioned comparison (evaluates high and low 32-bits concurrently)
    wire eq_hi  = (a[63:32] == b[63:32]);
    wire eq_lo  = (a[31:0]  == b[31:0]);
    wire is_equal = eq_hi & eq_lo;

    wire less_hi = (a[63:32] < b[63:32]);
    wire less_lo = (a[31:0]  < b[31:0]);
    wire less_unsigned = less_hi | (eq_hi & less_lo);

    // Signed comparison: if sign bits differ, negative (sign=1) is smaller
    wire less_signed = (a[63] ^ b[63]) ? a[63] : less_unsigned;

    always @(*) begin
        case (funct3)
            3'b000:  taken = is_equal;             // BEQ
            3'b001:  taken = ~is_equal;            // BNE
            3'b100:  taken = less_signed;          // BLT
            3'b101:  taken = ~less_signed;         // BGE
            3'b110:  taken = less_unsigned;        // BLTU
            3'b111:  taken = ~less_unsigned;       // BGEU
            default: taken = 1'b0;
        endcase
    end

endmodule
