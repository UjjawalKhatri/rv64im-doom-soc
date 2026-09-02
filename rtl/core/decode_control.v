// ============================================================================
// Module: decode_control
// Description: Decoded Control Unit for Full RV64I + RV64M Base Architecture
// Decodes Opcode and Funct7 to generate Control Bundle, Operand Selects & Writeback Selects
// ============================================================================
`timescale 1ns / 1ps

module decode_control (
    input  wire [6:0] opcode,
    input  wire [6:0] funct7,
    output reg        Branch,
    output reg        Jump,
    output reg        Jalr,
    output reg        MemRead,
    output reg        MemWrite,
    output reg  [1:0] WbSel,      // 2'b00: ALU, 2'b01: MEM, 2'b10: PC+4, 2'b11: MULDIV
    output reg  [1:0] OpASel,     // 2'b00: RS1, 2'b01: PC,   2'b10: ZERO
    output reg        ALUSrc,     // 0: RS2, 1: IMM
    output reg  [1:0] ALUOp,      // 2'b00: ADD, 2'b01: Branch, 2'b10: R/I-Type
    output reg        IsWordOp,   // 1 for 32-bit Word Ops (OP-32, OP-IMM-32)
    output reg        IsMulDiv,   // 1 for RV64M Multiplier/Divider Ops
    output reg        reg_write_en
);

    localparam R_TYPE       = 7'b0110011;
    localparam I_TYPE       = 7'b0010011;
    localparam OP_32_TYPE   = 7'b0111011; // ADDW, SUBW, SLLW, SRLW, SRAW, MULW, DIVW...
    localparam OP_IMM_32    = 7'b0011011; // ADDIW, SLLIW, SRLIW, SRAIW
    localparam LOAD_TYPE    = 7'b0000011; // LB, LH, LW, LD, LBU, LHU, LWU
    localparam S_TYPE       = 7'b0100011; // SB, SH, SW, SD
    localparam B_TYPE       = 7'b1100011; // BEQ, BNE, BLT, BGE, BLTU, BGEU
    localparam JAL_TYPE     = 7'b1101111; // JAL
    localparam JALR_TYPE    = 7'b1100111; // JALR
    localparam LUI_TYPE     = 7'b0110111; // LUI
    localparam AUIPC_TYPE   = 7'b0010111; // AUIPC

    localparam WB_ALU    = 2'b00;
    localparam WB_MEM    = 2'b01;
    localparam WB_PC4    = 2'b10;
    localparam WB_MULDIV = 2'b11;

    localparam OP_A_RS1  = 2'b00;
    localparam OP_A_PC   = 2'b01;
    localparam OP_A_ZERO = 2'b10;

    always @(*) begin
        // Default values
        Branch       = 1'b0;
        Jump         = 1'b0;
        Jalr         = 1'b0;
        MemRead      = 1'b0;
        MemWrite     = 1'b0;
        WbSel        = WB_ALU;
        OpASel       = OP_A_RS1;
        ALUSrc       = 1'b0;
        ALUOp        = 2'b00;
        IsWordOp     = 1'b0;
        IsMulDiv     = 1'b0;
        reg_write_en = 1'b0;

        case (opcode)
            R_TYPE: begin
                reg_write_en = 1'b1;
                OpASel       = OP_A_RS1;
                ALUSrc       = 1'b0;
                ALUOp        = 2'b10;
                if (funct7 == 7'b0000001) begin
                    IsMulDiv = 1'b1;
                    WbSel    = WB_MULDIV;
                end else begin
                    WbSel    = WB_ALU;
                end
            end

            I_TYPE: begin
                reg_write_en = 1'b1;
                WbSel        = WB_ALU;
                OpASel       = OP_A_RS1;
                ALUSrc       = 1'b1;
                ALUOp        = 2'b10;
            end

            OP_32_TYPE: begin
                reg_write_en = 1'b1;
                OpASel       = OP_A_RS1;
                ALUSrc       = 1'b0;
                ALUOp        = 2'b10;
                IsWordOp     = 1'b1;
                if (funct7 == 7'b0000001) begin
                    IsMulDiv = 1'b1;
                    WbSel    = WB_MULDIV;
                end else begin
                    WbSel    = WB_ALU;
                end
            end

            OP_IMM_32: begin
                reg_write_en = 1'b1;
                WbSel        = WB_ALU;
                OpASel       = OP_A_RS1;
                ALUSrc       = 1'b1;
                ALUOp        = 2'b10;
                IsWordOp     = 1'b1;
            end

            LOAD_TYPE: begin
                reg_write_en = 1'b1;
                MemRead      = 1'b1;
                WbSel        = WB_MEM;
                OpASel       = OP_A_RS1;
                ALUSrc       = 1'b1;
                ALUOp        = 2'b00;
            end

            S_TYPE: begin
                MemWrite     = 1'b1;
                OpASel       = OP_A_RS1;
                ALUSrc       = 1'b1;
                ALUOp        = 2'b00;
            end

            B_TYPE: begin
                Branch       = 1'b1;
                OpASel       = OP_A_RS1;
                ALUSrc       = 1'b0;
                ALUOp        = 2'b01;
            end

            JAL_TYPE: begin
                Jump         = 1'b1;
                reg_write_en = 1'b1;
                WbSel        = WB_PC4;
                OpASel       = OP_A_PC;
                ALUSrc       = 1'b1;
                ALUOp        = 2'b00;
            end

            JALR_TYPE: begin
                Jump         = 1'b1;
                Jalr         = 1'b1;
                reg_write_en = 1'b1;
                WbSel        = WB_PC4;
                OpASel       = OP_A_RS1;
                ALUSrc       = 1'b1;
                ALUOp        = 2'b00;
            end

            LUI_TYPE: begin
                reg_write_en = 1'b1;
                WbSel        = WB_ALU;
                OpASel       = OP_A_ZERO; // 0 + IMM
                ALUSrc       = 1'b1;
                ALUOp        = 2'b00;    // ADD
            end

            AUIPC_TYPE: begin
                reg_write_en = 1'b1;
                WbSel        = WB_ALU;
                OpASel       = OP_A_PC;   // PC + IMM
                ALUSrc       = 1'b1;
                ALUOp        = 2'b00;    // ADD
            end

            default: begin
                // Defaults
            end
        endcase
    end

endmodule
