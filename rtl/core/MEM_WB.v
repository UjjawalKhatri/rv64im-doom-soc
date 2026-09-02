// ============================================================================
// Module: MEM_WB
// Description: Extended MEM/WB Pipeline Register with stall/bubble support
// Compatible with Xilinx Vivado Synthesis & Implementation
// ============================================================================
`timescale 1ns / 1ps

module MEM_WB (
    input  wire        clk,
    input  wire        reset,
    input  wire        stall,            // Bubble MEM/WB while memory stage is stalling
    input  wire        mem_valid,
    input  wire [1:0]  mem_wb_sel_in,
    input  wire        wb_reg_write_en_in,
    input  wire [63:0] wb_mem_data_in,
    input  wire [63:0] wb_alu_out_in,
    input  wire [63:0] wb_muldiv_out_in,
    input  wire [63:0] wb_pc_plus4_in,
    input  wire [4:0]  wb_rd_in,

    output reg         wb_valid,
    output reg  [1:0]  wb_wb_sel,
    output reg         wb_reg_write_en,
    output reg  [63:0] wb_mem_data,
    output reg  [63:0] wb_alu_out,
    output reg  [63:0] wb_muldiv_out,
    output reg  [63:0] wb_pc_plus4,
    output reg  [4:0]  wb_rd
);

    always @(posedge clk) begin
        if (reset) begin
            wb_valid        <= 1'b0;
            wb_wb_sel       <= 2'b0;
            wb_reg_write_en <= 1'b0;
            wb_mem_data     <= 64'b0;
            wb_alu_out      <= 64'b0;
            wb_muldiv_out   <= 64'b0;
            wb_pc_plus4     <= 64'b0;
            wb_rd           <= 5'b0;
        end else if (stall) begin
            // Insert bubble into WB stage while MEM is stalled waiting for DDR
            wb_valid        <= 1'b0;
            wb_reg_write_en <= 1'b0;
        end else begin
            wb_valid        <= mem_valid;
            wb_wb_sel       <= mem_wb_sel_in;
            wb_reg_write_en <= wb_reg_write_en_in;
            wb_mem_data     <= wb_mem_data_in;
            wb_alu_out      <= wb_alu_out_in;
            wb_muldiv_out   <= wb_muldiv_out_in;
            wb_pc_plus4     <= wb_pc_plus4_in;
            wb_rd           <= wb_rd_in;
        end
    end

endmodule
