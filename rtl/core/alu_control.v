// ============================================================================
// Module: alu_control
// Description: Extended ALU Control Decoder supporting R-type, I-type, Shifts & Branch Ops
// Compatible with Xilinx Vivado Synthesis & Implementation
// ============================================================================
`timescale 1ns / 1ps

module alu_control (
    input  wire [1:0] ALUOp,
    input  wire [3:0] Ins,      // {funct7_5, funct3}
    input  wire       ALUSrc,   // 0 = R-type (funct7_5 used for SUB), 1 = I-type (funct7_5 ignored for ADD)
    output reg  [3:0] ALUControl
);

    wire       funct7_5 = Ins[3];
    wire [2:0] funct3   = Ins[2:0];

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

    always @(*) begin
        case (ALUOp)
            2'b00: begin
                // Loads, Stores, JAL, JALR address addition
                ALUControl = ALU_ADD;
            end

            2'b01: begin
                // Branch comparison (SUB)
                ALUControl = ALU_SUB;
            end

            2'b10: begin
                // R-type and I-type arithmetic / logical
                case (funct3)
                    3'b000: ALUControl = (funct7_5 && !ALUSrc) ? ALU_SUB : ALU_ADD;
                    3'b001: ALUControl = ALU_SLL;
                    3'b010: ALUControl = ALU_SLT;
                    3'b011: ALUControl = ALU_SLTU;
                    3'b100: ALUControl = ALU_XOR;
                    3'b101: ALUControl = funct7_5 ? ALU_SRA : ALU_SRL;
                    3'b110: ALUControl = ALU_OR;
                    3'b111: ALUControl = ALU_AND;
                    default: ALUControl = ALU_ADD;
                endcase
            end

            2'b11: begin
                // LUI / AUIPC direct pass
                ALUControl = ALU_PASS;
            end

            default: begin
                ALUControl = ALU_ADD;
            end
        endcase
    end

endmodule
