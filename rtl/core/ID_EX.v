// ============================================================================
// Module: ID_EX
// Description: Extended ID/EX Pipeline Register with pre-computed PC+IMM target
// Compatible with Xilinx Vivado Synthesis & Implementation
// ============================================================================
`timescale 1ns / 1ps

module ID_EX (
    input  wire        clk,
    input  wire        reset,
    input  wire        flush,
    input  wire        hold,          // Freeze register state on multicycle execution stall
    input  wire        id_valid,
    input  wire [1:0]  id_wb_sel,
    input  wire [1:0]  id_op_a_sel,
    input  wire        id_reg_write_en,
    input  wire        id_mem_read,
    input  wire        id_mem_write,
    input  wire        id_branch,
    input  wire        id_jump,
    input  wire        id_jalr,
    input  wire        id_alu_src,
    input  wire [3:0]  id_alu_ctrl,
    input  wire [2:0]  id_funct3,
    input  wire        id_is_word_op,
    input  wire        id_is_muldiv,
    input  wire [63:0] id_pc,
    input  wire [63:0] id_pc_plus4,
    input  wire [63:0] id_pc_imm,
    input  wire [63:0] id_data1,
    input  wire [63:0] id_data2,
    input  wire [63:0] id_imm,
    input  wire [4:0]  id_rs1,
    input  wire [4:0]  id_rs2,
    input  wire [4:0]  id_rd,

    // Currently-forwarded EX operand values (alu_a_raw / alu_b_pre from the
    // forwarding muxes). While this register is HELD, these are absorbed into
    // ex_data1/ex_data2 -- see the hold branch below.
    input  wire [63:0] fwd_data1,
    input  wire [63:0] fwd_data2,

    output reg         ex_valid,
    output reg  [1:0]  ex_wb_sel,
    output reg  [1:0]  ex_op_a_sel,
    output reg         ex_reg_write_en,
    output reg         ex_mem_read,
    output reg         ex_mem_write,
    output reg         ex_branch,
    output reg         ex_jump,
    output reg         ex_jalr,
    output reg         ex_alu_src,
    output reg  [3:0]  ex_alu_ctrl,
    output reg  [2:0]  ex_funct3,
    output reg         ex_is_word_op,
    output reg         ex_is_muldiv,
    output reg  [63:0] ex_pc,
    output reg  [63:0] ex_pc_plus4,
    output reg  [63:0] ex_pc_imm,
    output reg  [63:0] ex_data1,
    output reg  [63:0] ex_data2,
    output reg  [63:0] ex_imm,
    output reg  [4:0]  ex_rs1,
    output reg  [4:0]  ex_rs2,
    output reg  [4:0]  ex_rd
);

    always @(posedge clk) begin
        if (reset) begin
            ex_valid        <= 1'b0;
            ex_wb_sel       <= 2'b0;
            ex_op_a_sel     <= 2'b0;
            ex_reg_write_en <= 1'b0;
            ex_mem_read     <= 1'b0;
            ex_mem_write    <= 1'b0;
            ex_branch       <= 1'b0;
            ex_jump         <= 1'b0;
            ex_jalr         <= 1'b0;
            ex_alu_src      <= 1'b0;
            ex_alu_ctrl     <= 4'b0;
            ex_funct3       <= 3'b0;
            ex_is_word_op   <= 1'b0;
            ex_is_muldiv    <= 1'b0;
            ex_pc           <= 64'b0;
            ex_pc_plus4     <= 64'b0;
            ex_pc_imm       <= 64'b0;
            ex_data1        <= 64'b0;
            ex_data2        <= 64'b0;
            ex_imm          <= 64'b0;
            ex_rs1          <= 5'b0;
            ex_rs2          <= 5'b0;
            ex_rd           <= 5'b0;
        end else if (flush) begin
            // On pipeline flush, only invalidate control signals (drastically cuts fanout & routing delay)
            ex_valid        <= 1'b0;
            ex_wb_sel       <= 2'b0;
            ex_op_a_sel     <= 2'b0;
            ex_reg_write_en <= 1'b0;
            ex_mem_read     <= 1'b0;
            ex_mem_write    <= 1'b0;
            ex_branch       <= 1'b0;
            ex_jump         <= 1'b0;
            ex_jalr         <= 1'b0;
            ex_is_muldiv    <= 1'b0;
        end else if (!hold) begin
            ex_valid        <= id_valid;
            ex_wb_sel       <= id_wb_sel;
            ex_op_a_sel     <= id_op_a_sel;
            ex_reg_write_en <= id_reg_write_en;
            ex_mem_read     <= id_mem_read;
            ex_mem_write    <= id_mem_write;
            ex_branch       <= id_branch;
            ex_jump         <= id_jump;
            ex_jalr         <= id_jalr;
            ex_alu_src      <= id_alu_src;
            ex_alu_ctrl     <= id_alu_ctrl;
            ex_funct3       <= id_funct3;
            ex_is_word_op   <= id_is_word_op;
            ex_is_muldiv    <= id_is_muldiv;
            ex_pc           <= id_pc;
            ex_pc_plus4     <= id_pc_plus4;
            ex_pc_imm       <= id_pc_imm;
            ex_data1        <= id_data1;
            ex_data2        <= id_data2;
            ex_imm          <= id_imm;
            ex_rs1          <= id_rs1;
            ex_rs2          <= id_rs2;
            ex_rd           <= id_rd;
        end else begin
            // ----------------------------------------------------------------
            // HELD in EX (fetch_stall / memory_stall / execute_stall).
            //
            // ex_data1/ex_data2 were captured in ID and may be STALE; the
            // forwarding muxes only patch them combinationally for the few
            // cycles the producer sits in MEM/WB. If this instruction is held
            // in EX across the producer's retirement (very common when a DDR
            // fetch stall freezes EX/MEM for many cycles), the forwarded value
            // disappears and the instruction latches a stale operand -- e.g. a
            // store writing 0 instead of the value a DDR load just produced.
            //
            // Absorb the forwarded operands so that once a value has been
            // forwarded in, it is retained permanently. When no forwarding is
            // active the mux selects ex_dataN, so this is a harmless self-assign.
            // ----------------------------------------------------------------
            ex_data1        <= fwd_data1;
            ex_data2        <= fwd_data2;
        end
    end

endmodule
