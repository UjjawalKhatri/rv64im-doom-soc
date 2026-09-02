// ============================================================================
// Module: Forwarding_unit
// Description: 3-way Forwarding Unit for RAW hazards (EX/MEM -> EX and MEM/WB -> EX)
// Compatible with Xilinx Vivado Synthesis & Implementation
// ============================================================================
`timescale 1ns / 1ps

module Forwarding_unit (
    input  wire [4:0] ex_rs1,
    input  wire [4:0] ex_rs2,
    input  wire [4:0] mem_rd,
    input  wire [4:0] wb_rd,
    input  wire       mem_regwrite,
    input  wire       wb_regwrite,
    output reg  [1:0] ForwardA,
    output reg  [1:0] ForwardB
);

    always @(*) begin
        ForwardA = 2'b00;
        ForwardB = 2'b00;

        // ForwardA hazard check
        if (mem_regwrite && (mem_rd != 5'b0) && (mem_rd == ex_rs1)) begin
            ForwardA = 2'b10; // Forward from EX/MEM
        end else if (wb_regwrite && (wb_rd != 5'b0) && (wb_rd == ex_rs1)) begin
            ForwardA = 2'b01; // Forward from MEM/WB
        end

        // ForwardB hazard check
        if (mem_regwrite && (mem_rd != 5'b0) && (mem_rd == ex_rs2)) begin
            ForwardB = 2'b10; // Forward from EX/MEM
        end else if (wb_regwrite && (wb_rd != 5'b0) && (wb_rd == ex_rs2)) begin
            ForwardB = 2'b01; // Forward from MEM/WB
        end
    end

endmodule
