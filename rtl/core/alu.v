// ============================================================================
// Module: alu_64_bit
// Description: High-Performance Synthesizable 64-bit / 32-bit Word ALU
// Optimized for FPGA Timing Closure (>100 MHz on Xilinx 7-Series / Zynq)
// ============================================================================
`timescale 1ns / 1ps

module alu_64_bit (
    input  wire [63:0] a,
    input  wire [63:0] b,
    input  wire [3:0]  opcode,
    input  wire        is_word_op,
    output wire [63:0] result,
    output wire        zero_flag,
    output wire        slt_flag,
    output wire        sltu_flag
);

    localparam ALU_AND  = 4'b0000;
    localparam ALU_OR   = 4'b0001;
    localparam ALU_ADD  = 4'b0010;
    localparam ALU_SUB  = 4'b0110;
    localparam ALU_XOR  = 4'b0011;
    localparam ALU_SLL  = 4'b0100;
    localparam ALU_SRL  = 4'b0101;
    localparam ALU_SRA  = 4'b0111;
    localparam ALU_SLT  = 4'b1000;
    localparam ALU_SLTU = 4'b1001;
    localparam ALU_PASS = 4'b1010;

    // Shift amount (capped at 5 bits for 32-bit word ops, 6 bits for 64-bit ops)
    wire [5:0] shamt = is_word_op ? {1'b0, b[4:0]} : b[5:0];

    // Shared 64-bit Adder / Subtractor
    wire [63:0] add_sub_res = (opcode == ALU_SUB) ? (a - b) : (a + b);

    // Comparators
    wire sltu_comp = (a < b);
    wire slt_comp  = (a[63] ^ b[63]) ? a[63] : sltu_comp;

    assign sltu_flag = sltu_comp;
    assign slt_flag  = slt_comp;

    // Left Shifter
    wire [63:0] sll_in  = is_word_op ? {{32{1'b0}}, a[31:0]} : a;
    wire [63:0] sll_res = sll_in << shamt;

    // Unified Right Shifter (Logical SRL & Arithmetic SRA)
    wire        sra_sign = (opcode == ALU_SRA) ? (is_word_op ? a[31] : a[63]) : 1'b0;
    wire [63:0] srl_in   = is_word_op ? {{32{sra_sign}}, a[31:0]} : a;
    wire [127:0] shift_ext = {{64{sra_sign}}, srl_in};
    wire [63:0] srl_sra_res = shift_ext[63+shamt -: 64];

    reg [63:0] raw_result;

    always @(*) begin
        case (opcode)
            ALU_ADD:  raw_result = add_sub_res;
            ALU_SUB:  raw_result = add_sub_res;
            ALU_AND:  raw_result = a & b;
            ALU_OR:   raw_result = a | b;
            ALU_XOR:  raw_result = a ^ b;
            ALU_SLL:  raw_result = sll_res;
            ALU_SRL:  raw_result = srl_sra_res;
            ALU_SRA:  raw_result = srl_sra_res;
            ALU_SLT:  raw_result = slt_comp ? 64'd1 : 64'd0;
            ALU_SLTU: raw_result = sltu_comp ? 64'd1 : 64'd0;
            ALU_PASS: raw_result = b;
            default:  raw_result = 64'b0;
        endcase
    end

    // Sign extension for 32-bit Word operations (ADDW, SUBW, SLLW, SRLW, SRAW, ADDIW, etc.)
    assign result = is_word_op ? {{32{raw_result[31]}}, raw_result[31:0]} : raw_result;
    assign zero_flag = (result == 64'b0);

endmodule
