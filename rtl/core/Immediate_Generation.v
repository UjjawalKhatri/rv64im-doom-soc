// ============================================================================
// Module: Immediate_Generation
// Description: Extended Immediate Generator supporting I, S, B, U, J, and OP-IMM-32
// Compatible with Xilinx Vivado Synthesis & Implementation
// ============================================================================
`timescale 1ns / 1ps

module Immediate_Generation (
    input  wire [31:0] instr,
    output reg  [63:0] imm
);

    wire [6:0] opcode = instr[6:0];

    localparam I_TYPE    = 7'b0010011; // addi, slli, srli, srai, slti
    localparam OP_IMM_32 = 7'b0011011; // addiw, slliw, srliw, sraiw
    localparam LOAD_TYPE = 7'b0000011; // lb, lh, lw, ld, lbu, lhu, lwu
    localparam S_TYPE    = 7'b0100011; // sb, sh, sw, sd
    localparam B_TYPE    = 7'b1100011; // beq, bne, blt, bge, bltu, bgeu
    localparam JAL_TYPE  = 7'b1101111; // jal
    localparam JALR_TYPE = 7'b1100111; // jalr
    localparam LUI_TYPE  = 7'b0110111; // lui
    localparam AUIPC_TYPE= 7'b0010111; // auipc

    always @(*) begin
        case (opcode)
            I_TYPE, OP_IMM_32, LOAD_TYPE, JALR_TYPE: begin
                // Sign-extended 12-bit immediate [31:20]
                imm = {{52{instr[31]}}, instr[31:20]};
            end

            S_TYPE: begin
                // Store immediate [31:25] & [11:7]
                imm = {{52{instr[31]}}, instr[31:25], instr[11:7]};
            end

            B_TYPE: begin
                // Branch immediate: 13-bit formatted -> sign extended to 64 bits
                imm = {{51{instr[31]}}, instr[31], instr[7], instr[30:25], instr[11:8], 1'b0};
            end

            LUI_TYPE, AUIPC_TYPE: begin
                // Upper 20-bit immediate [31:12] shifted left by 12, sign-extended to 64 bits
                imm = {{32{instr[31]}}, instr[31:12], 12'b0};
            end

            JAL_TYPE: begin
                // J-type immediate: 21-bit formatted -> sign extended to 64 bits
                imm = {{43{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0};
            end

            default: begin
                imm = 64'b0;
            end
        endcase
    end

endmodule
