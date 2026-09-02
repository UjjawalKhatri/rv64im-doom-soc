// ============================================================================
// Module: EX_MEM
// Description: Extended EX/MEM Pipeline Register with stall support
// Compatible with Xilinx Vivado Synthesis & Implementation
// ============================================================================
`timescale 1ns / 1ps

module EX_MEM (
    input  wire        clk,
    input  wire        reset,
    input  wire        stall,            // Freeze register state on memory stall
    input  wire        ex_valid,
    input  wire [1:0]  ex_wb_sel,
    input  wire        ex_reg_write_en,
    input  wire        ex_mem_read,
    input  wire        ex_mem_write,
    input  wire [2:0]  ex_funct3,
    input  wire [63:0] ex_alu_out,
    input  wire [63:0] ex_muldiv_out,
    input  wire [63:0] ex_pc_plus4,
    input  wire [63:0] ex_store_data,
    input  wire [4:0]  ex_rs2,
    input  wire [4:0]  ex_rd,

    output reg         mem_valid,
    output reg  [1:0]  mem_wb_sel,
    output reg         mem_reg_write_en,
    output reg         mem_mem_read,
    output reg         mem_mem_write,
    output reg  [2:0]  mem_funct3,
    output reg  [63:0] mem_alu_out,
    output reg  [63:0] mem_muldiv_out,
    output reg  [63:0] mem_pc_plus4,
    output reg  [63:0] mem_store_data,
    output reg  [4:0]  mem_rs2,
    output reg  [4:0]  mem_rd
);

    always @(posedge clk) begin
        if (reset) begin
            mem_valid        <= 1'b0;
            mem_wb_sel       <= 2'b0;
            mem_reg_write_en <= 1'b0;
            mem_mem_read     <= 1'b0;
            mem_mem_write    <= 1'b0;
            mem_funct3       <= 3'b0;
            mem_alu_out      <= 64'b0;
            mem_muldiv_out   <= 64'b0;
            mem_pc_plus4     <= 64'b0;
            mem_store_data   <= 64'b0;
            mem_rs2          <= 5'b0;
            mem_rd           <= 5'b0;
        end else if (!stall) begin
            mem_valid        <= ex_valid;
            mem_wb_sel       <= ex_wb_sel;
            mem_reg_write_en <= ex_reg_write_en;
            mem_mem_read     <= ex_mem_read;
            mem_mem_write    <= ex_mem_write;
            mem_funct3       <= ex_funct3;
            mem_alu_out      <= ex_alu_out;
            mem_muldiv_out   <= ex_muldiv_out;
            mem_pc_plus4     <= ex_pc_plus4;
            mem_store_data   <= ex_store_data;
            mem_rs2          <= ex_rs2;
            mem_rd           <= ex_rd;
        end
    end

endmodule
