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
    // Address-class decode, computed in EX from alu_out and pipelined here so
    // the MEM stage does not have to decode mem_alu_out combinationally. This
    // keeps the address decode off the MEM -> forwarding -> branch -> PC path.
    input  wire        ex_is_mmio_addr,
    input  wire        ex_is_ddr_data,

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
    output reg  [4:0]  mem_rd,
    output wire        mem_is_mmio_addr,
    output wire        mem_is_ddr_data
);

    // ------------------------------------------------------------------------
    // These two decode bits are logically identical to bits of mem_alu_out
    // (is_ddr_data == mem_alu_out[31]), and they are captured from the same
    // source with the same enable. Vivado spotted that and merged them away:
    // Without the attributes below neither mem_is_ddr_data_reg nor
    // mem_is_mmio_addr_reg appears in the netlist at all: Vivado's
    // equivalent-register-removal pass deletes them and the MEM stage reads
    // mem_alu_out_reg[31] instead - a net carrying fanout 140 that costs
    // 0.843 ns just to leave the flop.
    //
    // Pipelining the decode therefore achieved nothing on its own; no separate
    // flop was ever built, so there was no fanout to reduce. Blocking the merge
    // gives these bits their own low-fanout drivers.
    //
    // EQUIVALENT_REGISTER_REMOVAL and MAX_FANOUT have to be used together here:
    // MAX_FANOUT replicates the driver, and without the first attribute the
    // equivalent-register pass would simply merge the replicas straight back.
    // ------------------------------------------------------------------------
    // NOTE: do NOT put MAX_FANOUT on mem_alu_out. This was measured: at a limit
    // of 50 Vivado replicated the 64-bit bus into 345 flops (5.4x) and worst
    // negative slack went BACKWARDS, from -0.661 ns to -1.209 ns. The extra
    // cells cost more in local routing congestion than the lower fanout saved.
    // Its net D[4] does carry fanout 190 for 0.733 ns on the critical path, but
    // driver replication is not the remedy.

    (* EQUIVALENT_REGISTER_REMOVAL = "no", MAX_FANOUT = 25 *) reg mem_is_mmio_addr_q;
    (* EQUIVALENT_REGISTER_REMOVAL = "no", MAX_FANOUT = 25 *) reg mem_is_ddr_data_q;

    assign mem_is_mmio_addr = mem_is_mmio_addr_q;
    assign mem_is_ddr_data  = mem_is_ddr_data_q;

    // The capture enable fans out to every flop in this stage. Left as a bare
    // !stall it routed as a single net with fanout 577, costing 1.592 ns on the
    // worst path; MAX_FANOUT makes Vivado replicate the driver. The attribute
    // has to live here - putting it on `stall` in rv64i_core_top does not
    // reach the enable net synthesis builds inside this module.
    (* MAX_FANOUT = 50 *) wire capture_en = !stall;

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
            mem_is_mmio_addr_q <= 1'b0;
            mem_is_ddr_data_q  <= 1'b0;
        end else if (capture_en) begin
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
            mem_is_mmio_addr_q <= ex_is_mmio_addr;
            mem_is_ddr_data_q  <= ex_is_ddr_data;
        end
    end

endmodule
