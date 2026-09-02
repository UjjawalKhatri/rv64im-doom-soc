// ============================================================================
// Module: control
// Description: Main Control Unit supporting R, I, Load, Store, Branch, JAL, JALR, LUI, AUIPC
// Compatible with Xilinx Vivado Synthesis & Implementation
// ============================================================================
`timescale 1ns / 1ps

module control (
    input  wire [6:0] opcode,
    output reg        Branch,
    output reg        Jump,
    output reg        Jalr,
    output reg        MemRead,
    output reg        MemToReg,
    output reg  [1:0] ALUOp,
    output reg        MemWrite,
    output reg        ALUSrc,
    output reg        reg_write_en
);

    localparam R_TYPE    = 7'b0110011;
    localparam I_TYPE    = 7'b0010011;
    localparam LOAD_TYPE = 7'b0000011;
    localparam S_TYPE    = 7'b0100011;
    localparam B_TYPE    = 7'b1100011;
    localparam JAL_TYPE  = 7'b1101111;
    localparam JALR_TYPE = 7'b1100111;
    localparam LUI_TYPE  = 7'b0110111;
    localparam AUIPC_TYPE= 7'b0010111;

    always @(*) begin
        // Default control outputs
        Branch       = 1'b0;
        Jump         = 1'b0;
        Jalr         = 1'b0;
        MemRead      = 1'b0;
        MemToReg     = 1'b0;
        ALUOp        = 2'b00;
        MemWrite     = 1'b0;
        ALUSrc       = 1'b0;
        reg_write_en = 1'b0;

        case (opcode)
            R_TYPE: begin
                reg_write_en = 1'b1;
                ALUOp        = 2'b10;
            end

            I_TYPE: begin
                reg_write_en = 1'b1;
                ALUSrc       = 1'b1;
                ALUOp        = 2'b10;
            end

            LOAD_TYPE: begin
                reg_write_en = 1'b1;
                MemRead      = 1'b1;
                MemToReg     = 1'b1;
                ALUSrc       = 1'b1;
                ALUOp        = 2'b00;
            end

            S_TYPE: begin
                MemWrite     = 1'b1;
                ALUSrc       = 1'b1;
                ALUOp        = 2'b00;
            end

            B_TYPE: begin
                Branch       = 1'b1;
                ALUOp        = 2'b01;
            end

            JAL_TYPE: begin
                Jump         = 1'b1;
                reg_write_en = 1'b1;
            end

            JALR_TYPE: begin
                Jump         = 1'b1;
                Jalr         = 1'b1;
                reg_write_en = 1'b1;
                ALUSrc       = 1'b1;
            end

            LUI_TYPE, AUIPC_TYPE: begin
                reg_write_en = 1'b1;
                ALUSrc       = 1'b1;
                ALUOp        = 2'b11;
            end

            default: begin
                // All controls default to 0
            end
        endcase
    end

endmodule
