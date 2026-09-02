// ============================================================================
// Module: rv64i_core_top
// Description: Top-Level Synthesizable 5-Stage RV64IM Pipelined Processor Core
// Full RV64I + RV64M Base Architecture with Hardware Multiplier & Divider
// DDR3 instruction fetch via instruction_fetch_unit (blueprint Sections 26-28)
// Compatible with Xilinx Vivado (Artix-7 / Kintex-7 / Zynq FPGAs)
// ============================================================================
`timescale 1ns / 1ps

module rv64i_core_top #(
    parameter MEM_FILE = "instructions.txt"
)(
    input  wire        clk,
    input  wire        reset,
    output wire [63:0] current_pc,
    output wire [31:0] current_instr,
    output wire [63:0] wb_result,
    output wire [4:0]  wb_reg_addr,
    output wire        wb_reg_we,
    output wire [63:0] perf_cycles,
    output wire [63:0] perf_retired,
    output wire [63:0] perf_stalls,
    output wire [63:0] perf_flushes,
    output wire [63:0] perf_cpi_x100,

    // External SoC Data Bus Interface
    output wire        data_req_valid,
    output wire        data_req_we,
    output wire [63:0] data_req_addr,
    output wire [63:0] data_req_wdata,
    output wire [7:0]  data_req_wstrb,
    input  wire [63:0] data_rsp_rdata,
    input  wire        data_rsp_ready,

    // External Instruction Fetch Interface (to DDR arbiter)
    output wire        instr_req_valid,
    output wire [63:0] instr_req_addr,
    input  wire        instr_req_ready,
    input  wire        instr_rsp_valid,
    input  wire [63:0] instr_rsp_rdata
);

    // ------------------------------------------------------------------------
    // Wires & Signals Definition
    // ------------------------------------------------------------------------

    // IF Stage Wires
    wire [63:0] pc_out;
    wire [63:0] pc_plus4;
    wire [63:0] pc_branch;
    wire [63:0] pc_next;
    wire [31:0] instr;
    wire        pc_write_en;
    wire        flush_sig;
    wire        if_id_write_en;

    // IF/ID Pipeline Register Wires
    wire        if_id_valid;
    wire [63:0] if_id_pc;
    wire [31:0] if_id_ins;

    // ID Stage Control & Decoder Wires
    wire        branch, jump, jalr, mem_read, mem_write, reg_write, is_word_op, is_muldiv;
    wire [1:0]  wb_sel, op_a_sel;
    wire [1:0]  alu_op;
    wire [3:0]  alu_ctrl_raw;

    // Control Bubble Wires
    wire        bubble_sel;
    wire        b_branch, b_jump, b_jalr, b_mem_read, b_mem_write, b_reg_write, b_is_word_op, b_is_muldiv;
    wire [1:0]  b_wb_sel, b_op_a_sel;
    wire        b_alu_src;
    wire [3:0]  b_alu_ctrl;
    wire [2:0]  b_funct3;

    // ID Register File & Immediate Generator Wires
    wire [63:0] rf_rdata1, rf_rdata2;
    wire [63:0] wb_write_data;
    wire [4:0]  wb_rd_sig;
    wire        wb_reg_write_sig;
    wire [63:0] imm;

    // ID/EX Pipeline Register Wires
    wire        ex_valid;
    wire [1:0]  ex_wb_sel, ex_op_a_sel;
    wire        ex_reg_write, ex_mem_read, ex_mem_write;
    wire        ex_branch, ex_jump, ex_jalr, ex_alu_src, ex_is_word_op, ex_is_muldiv;
    wire [3:0]  ex_alu_ctrl;
    wire [2:0]  ex_funct3;
    wire [63:0] ex_pc, ex_pc_plus4, ex_pc_imm, ex_data1, ex_data2, ex_imm;
    wire [4:0]  ex_rs1, ex_rs2, ex_rd;

    // EX Stage Execution, Forwarding, Branch & M-Extension Wires
    wire [1:0]  fwd_a, fwd_b;
    wire [63:0] ex_mem_fwd_val;
    wire [63:0] alu_a_raw, alu_b_pre, alu_a, alu_b;
    wire [63:0] alu_out;
    wire        alu_zero;
    wire        branch_cond_met;
    wire        redirect_taken;

    // RV64M Hardware Multiplier & Divider Wires
    wire        start_mul, start_div, mul_busy, mul_done, div_busy, div_done;
    wire [63:0] mul_result, div_result, muldiv_result;
    wire        execute_stall;
    wire        fetch_stall;   // From instruction fetch unit (DDR latency)
    wire        memory_stall;  // From DDR data load/store latency
    reg         muldiv_started;

    // DDR transaction completion latch: prevents MEM stage from re-issuing
    // a completed DDR data transaction when EX_MEM is frozen by fetch_stall.
    // This breaks the deadlock: D-side completes -> mem_ddr_done=1 ->
    // d_req_valid drops -> I-side wins arbiter -> fetch_stall clears ->
    // pipeline advances -> mem_ddr_done resets.
    reg         mem_ddr_done;
    wire        muldiv_done;

    // EX/MEM Pipeline Register Wires
    wire        mem_valid;
    wire [1:0]  mem_wb_sel;
    wire        mem_reg_write, mem_mem_read, mem_mem_write;
    wire [2:0]  mem_funct3;
    wire [63:0] mem_alu_out, mem_muldiv_out, mem_pc_plus4, mem_store_data;
    wire [4:0]  mem_rs2, mem_rd;

    // MEM Stage Memory, Subword Handling & Forwarding Wires
    wire        ld_sd_sel;
    wire [63:0] mem_write_data_final;
    wire [63:0] raw_mem_rdata;
    wire [63:0] mem_read_data;
    wire [7:0]  mem_wstrb;
    wire [63:0] mem_wdata_aligned;

    // MEM/WB Pipeline Register Wires
    wire        wb_valid;
    wire [1:0]  wb_wb_sel;
    wire [63:0] wb_mem_data, wb_alu_out, wb_muldiv_out, wb_pc_plus4;

    // Hazard Detection Wires
    wire        predicted_taken;

    // ------------------------------------------------------------------------
    // 1. INSTRUCTION FETCH (IF) STAGE
    // ------------------------------------------------------------------------

    // Branch / Jump Target Computation (JALR reuses alu_out masked, Branch/JAL uses pre-computed ex_pc_imm)
    assign pc_branch = ex_jalr ? (alu_out & ~64'h1) : ex_pc_imm;

    // Redirect Taken Decision (Branch Condition Met OR Jump Instruction)
    assign redirect_taken = (ex_branch && branch_cond_met) || ex_jump;

    // A redirect commits when it is allowed to flush the front-end. When it does,
    // the redirecting instruction in EX must latch into EX/MEM (completing its
    // link/writeback, e.g. JAL's ra=pc+4) even under fetch_stall; otherwise it is
    // flushed to a bubble and ra is silently dropped -> crash on the next ret.
    wire redirect_commit = redirect_taken && !execute_stall && !memory_stall;

    // Program Counter Unit
    pc PC_inst (
        .clk(clk),
        .reset(reset),
        .pc_write(pc_write_en),
        .redirect_taken(redirect_taken),
        .pc_branch(pc_branch),
        .pc_out(pc_out),
        .pc_plus4(pc_plus4)
    );

    // Instruction Fetch Unit (BRAM boot + DDR external fetch)
    instruction_fetch_unit #(
        .MEM_FILE(MEM_FILE)
    ) IFU_inst (
        .clk(clk),
        .reset(reset),
        .pc_addr(pc_out),
        .redirect(redirect_taken && !execute_stall && !memory_stall),
        .fetch_instr(instr),
        .fetch_stall(fetch_stall),
        .instr_req_valid(instr_req_valid),
        .instr_req_addr(instr_req_addr),
        .instr_req_ready(instr_req_ready),
        .instr_rsp_valid(instr_rsp_valid),
        .instr_rsp_rdata(instr_rsp_rdata)
    );

    // IF/ID Pipeline Register
    IF_ID IFID_inst (
        .clk(clk),
        .reset(reset),
        .flush(flush_sig),
        .IF_ID_write(if_id_write_en),
        .IF_ID_pc_in(pc_out),
        .IF_ID_Ins_in(instr),
        .IF_ID_valid_out(if_id_valid),
        .IF_ID_pc_out(if_id_pc),
        .IF_ID_Ins_out(if_id_ins)
    );

    // ------------------------------------------------------------------------
    // 2. INSTRUCTION DECODE (ID) STAGE
    // ------------------------------------------------------------------------

    // Main Control Unit (Decodes Opcode & Funct7)
    decode_control CTRL_inst (
        .opcode(if_id_ins[6:0]),
        .funct7(if_id_ins[31:25]),
        .Branch(branch),
        .Jump(jump),
        .Jalr(jalr),
        .MemRead(mem_read),
        .MemWrite(mem_write),
        .WbSel(wb_sel),
        .OpASel(op_a_sel),
        .ALUSrc(alu_src),
        .ALUOp(alu_op),
        .IsWordOp(is_word_op),
        .IsMulDiv(is_muldiv),
        .reg_write_en(reg_write)
    );

    // ALU Control Decoder
    alu_control ALUCTRL_inst (
        .ALUOp(alu_op),
        .Ins({if_id_ins[30], if_id_ins[14:12]}),
        .ALUSrc(alu_src),
        .ALUControl(alu_ctrl_raw)
    );

    // Control Bubble Mux (Injects NOP on stalls)
    control_bubble BUBBLE_inst (
        .branch_in(branch),
        .jump_in(jump),
        .jalr_in(jalr),
        .mem_read_in(mem_read),
        .mem_write_in(mem_write),
        .reg_write_in(reg_write),
        .wb_sel_in(wb_sel),
        .op_a_sel_in(op_a_sel),
        .alu_src_in(alu_src),
        .alu_ctrl_in(alu_ctrl_raw),
        .funct3_in(if_id_ins[14:12]),
        .is_word_op_in(is_word_op),
        .is_muldiv_in(is_muldiv),
        .sel(bubble_sel),
        .branch_out(b_branch),
        .jump_out(b_jump),
        .jalr_out(b_jalr),
        .mem_read_out(b_mem_read),
        .mem_write_out(b_mem_write),
        .reg_write_out(b_reg_write),
        .wb_sel_out(b_wb_sel),
        .op_a_sel_out(b_op_a_sel),
        .alu_src_out(b_alu_src),
        .alu_ctrl_out(b_alu_ctrl),
        .funct3_out(b_funct3),
        .is_word_op_out(b_is_word_op),
        .is_muldiv_out(b_is_muldiv)
    );

    // Register File
    register_file RF_inst (
        .clk(clk),
        .reset(reset),
        .reg_write_en(wb_reg_write_sig),
        .read_reg1(if_id_ins[19:15]),
        .read_reg2(if_id_ins[24:20]),
        .write_reg(wb_rd_sig),
        .write_data(wb_write_data),
        .read_data1(rf_rdata1),
        .read_data2(rf_rdata2)
    );

    // Immediate Generator
    Immediate_Generation IMMGEN_inst (
        .instr(if_id_ins),
        .imm(imm)
    );

    // ID/EX Pipeline Register
    ID_EX IDEX_inst (
        .clk(clk),
        .reset(reset),
        .flush(flush_sig),
        .hold(execute_stall || fetch_stall || memory_stall),
        .id_valid(if_id_valid),
        .id_wb_sel(b_wb_sel),
        .id_op_a_sel(b_op_a_sel),
        .id_reg_write_en(b_reg_write),
        .id_mem_read(b_mem_read),
        .id_mem_write(b_mem_write),
        .id_branch(b_branch),
        .id_jump(b_jump),
        .id_jalr(b_jalr),
        .id_alu_src(b_alu_src),
        .id_alu_ctrl(b_alu_ctrl),
        .id_funct3(b_funct3),
        .id_is_word_op(b_is_word_op),
        .id_is_muldiv(b_is_muldiv),
        .id_pc(if_id_pc),
        .id_pc_plus4(if_id_pc + 64'd4),
        .id_pc_imm(if_id_pc + imm),
        .id_data1(rf_rdata1),
        .id_data2(rf_rdata2),
        .id_imm(imm),
        // Forwarded EX operands, absorbed into ex_data1/ex_data2 while held so a
        // transiently-forwarded value is not lost if EX stalls past the producer.
        .fwd_data1(alu_a_raw),
        .fwd_data2(alu_b_pre),
        .id_rs1(if_id_ins[19:15]),
        .id_rs2(if_id_ins[24:20]),
        .id_rd(if_id_ins[11:7]),
        .ex_valid(ex_valid),
        .ex_wb_sel(ex_wb_sel),
        .ex_op_a_sel(ex_op_a_sel),
        .ex_reg_write_en(ex_reg_write),
        .ex_mem_read(ex_mem_read),
        .ex_mem_write(ex_mem_write),
        .ex_branch(ex_branch),
        .ex_jump(ex_jump),
        .ex_jalr(ex_jalr),
        .ex_alu_src(ex_alu_src),
        .ex_alu_ctrl(ex_alu_ctrl),
        .ex_funct3(ex_funct3),
        .ex_is_word_op(ex_is_word_op),
        .ex_is_muldiv(ex_is_muldiv),
        .ex_pc(ex_pc),
        .ex_pc_plus4(ex_pc_plus4),
        .ex_pc_imm(ex_pc_imm),
        .ex_data1(ex_data1),
        .ex_data2(ex_data2),
        .ex_imm(ex_imm),
        .ex_rs1(ex_rs1),
        .ex_rs2(ex_rs2),
        .ex_rd(ex_rd)
    );

    // ------------------------------------------------------------------------
    // 3. EXECUTE (EX) STAGE & RV64M EXTENSION
    // ------------------------------------------------------------------------

    // Forwarding Unit
    Forwarding_unit FWD_inst (
        .ex_rs1(ex_rs1),
        .ex_rs2(ex_rs2),
        .mem_rd(mem_rd),
        .wb_rd(wb_rd_sig),
        .mem_regwrite(mem_reg_write),
        .wb_regwrite(wb_reg_write_sig),
        .ForwardA(fwd_a),
        .ForwardB(fwd_b)
    );

    // EX/MEM Forwarding Value Mux (Handles ALU vs MEM vs PC+4 vs MULDIV WB types)
    assign ex_mem_fwd_val = (mem_wb_sel == 2'b01) ? mem_read_data :
                            (mem_wb_sel == 2'b10) ? mem_pc_plus4 :
                            (mem_wb_sel == 2'b11) ? mem_muldiv_out : mem_alu_out;

    // RAW Forwarding Muxes
    assign alu_a_raw = (fwd_a == 2'b10) ? ex_mem_fwd_val :
                       (fwd_a == 2'b01) ? wb_write_data : ex_data1;

    assign alu_b_pre = (fwd_b == 2'b10) ? ex_mem_fwd_val :
                       (fwd_b == 2'b01) ? wb_write_data : ex_data2;

    // Operand A Select (RS1 vs PC vs ZERO for LUI/AUIPC)
    assign alu_a = (ex_op_a_sel == 2'b01) ? ex_pc :
                   (ex_op_a_sel == 2'b10) ? 64'b0 : alu_a_raw;

    // ALUSrc Multiplexer (RS2 vs Immediate)
    assign alu_b = ex_alu_src ? ex_imm : alu_b_pre;

    wire alu_slt_flag;
    wire alu_sltu_flag;

    // 64-bit / 32-bit Word ALU
    alu_64_bit ALU_inst (
        .a(alu_a),
        .b(alu_b),
        .opcode(ex_alu_ctrl),
        .is_word_op(ex_is_word_op),
        .result(alu_out),
        .zero_flag(alu_zero),
        .slt_flag(alu_slt_flag),
        .sltu_flag(alu_sltu_flag)
    );

    // Dedicated High-Speed Parallel Branch Condition Unit
    branch_unit BRANCH_inst (
        .a(alu_a_raw),
        .b(alu_b_pre),
        .funct3(ex_funct3),
        .taken(branch_cond_met)
    );

    // ------------------------------------------------------------------------
    // RV64M Hardware Multiplier & Divider Integration
    // ------------------------------------------------------------------------

    assign muldiv_done = ex_funct3[2] ? div_done : mul_done;

    always @(posedge clk) begin
        if (reset) begin
            muldiv_started <= 1'b0;
        end else begin
            if (ex_is_muldiv && !muldiv_started) begin
                muldiv_started <= 1'b1;
            end else if (muldiv_done || !ex_is_muldiv) begin
                muldiv_started <= 1'b0;
            end
        end
    end

    assign start_mul = ex_valid && ex_is_muldiv && (!ex_funct3[2]) && (!muldiv_started);
    assign start_div = ex_valid && ex_is_muldiv && ( ex_funct3[2]) && (!muldiv_started);

    // Execute Stage Multicycle Stall
    assign execute_stall = ex_valid && ex_is_muldiv && (!muldiv_done);

    // Hardware Multiplier Instance
    rv64_multiplier MULT_inst (
        .clk(clk),
        .reset(reset),
        .start(start_mul),
        .op(ex_funct3),
        .is_word_op(ex_is_word_op),
        .a(alu_a_raw),
        .b(alu_b_pre),
        .busy(mul_busy),
        .done(mul_done),
        .result(mul_result)
    );

    // Hardware Divider Instance
    rv64_divider DIV_inst (
        .clk(clk),
        .reset(reset),
        .start(start_div),
        .op(ex_funct3),
        .is_word_op(ex_is_word_op),
        .a(alu_a_raw),
        .b(alu_b_pre),
        .busy(div_busy),
        .done(div_done),
        .result(div_result)
    );

    assign muldiv_result = ex_funct3[2] ? div_result : mul_result;

    // EX/MEM Pipeline Register
    EX_MEM EXMEM_inst (
        .clk(clk),
        .reset(reset),
        .stall(memory_stall || (fetch_stall && !redirect_commit)),
        .ex_valid(ex_valid && !execute_stall),
        .ex_wb_sel(ex_wb_sel),
        .ex_reg_write_en(ex_reg_write && !execute_stall),
        .ex_mem_read(ex_mem_read && !execute_stall),
        .ex_mem_write(ex_mem_write && !execute_stall),
        .ex_funct3(ex_funct3),
        .ex_alu_out(alu_out),
        .ex_muldiv_out(muldiv_result),
        .ex_pc_plus4(ex_pc_plus4),
        .ex_store_data(alu_b_pre),
        .ex_rs2(ex_rs2),
        .ex_rd(ex_rd),
        .mem_valid(mem_valid),
        .mem_wb_sel(mem_wb_sel),
        .mem_reg_write_en(mem_reg_write),
        .mem_mem_read(mem_mem_read),
        .mem_mem_write(mem_mem_write),
        .mem_funct3(mem_funct3),
        .mem_alu_out(mem_alu_out),
        .mem_muldiv_out(mem_muldiv_out),
        .mem_pc_plus4(mem_pc_plus4),
        .mem_store_data(mem_store_data),
        .mem_rs2(mem_rs2),
        .mem_rd(mem_rd)
    );

    // ------------------------------------------------------------------------
    // 4. MEMORY ACCESS (MEM) STAGE
    // ------------------------------------------------------------------------

    // Load-after-Store / WB-to-Store Forwarding
    ld_after_sd_forwarding LD_SD_FWD_inst (
        .wb_rd(wb_rd_sig),
        .sd_rs2(mem_rs2),
        .wb_reg_write(wb_reg_write_sig),
        .sd_mem_write(mem_mem_write),
        .ld_sd_sel(ld_sd_sel)
    );

    assign mem_write_data_final = ld_sd_sel ? wb_write_data : mem_store_data;

    // External MMIO vs Local Data Memory Decode
    wire is_mmio_addr = (mem_alu_out[31:28] >= 4'h1); // 0x1000_0000+ is external/MMIO
    wire is_ddr_data  = (mem_alu_out[31] == 1'b1);     // 0x8000_0000+ is DDR

    wire global_stall = execute_stall || fetch_stall || memory_stall;

    // Explicit DDR transaction completion tracking in MEM stage:
    // When a DDR data transaction completes but the pipeline is frozen by
    // fetch_stall, mem_ddr_completed prevents data_req_valid from re-asserting,
    // allowing the instruction fetch to use the DDR arbiter.
    reg        mem_ddr_completed;
    reg [63:0] mem_ddr_rdata_latch;

    always @(posedge clk) begin
        if (reset) begin
            mem_ddr_completed   <= 1'b0;
            mem_ddr_rdata_latch <= 64'b0;
        end else if (!global_stall) begin
            // Pipeline is advancing: reset completion state for new instruction
            mem_ddr_completed   <= 1'b0;
        end else if (data_rsp_ready && is_ddr_data && mem_valid && (mem_mem_read || mem_mem_write)) begin
            // DDR response arrived while pipeline was stalled: latch completion and read data
            mem_ddr_completed   <= 1'b1;
            mem_ddr_rdata_latch <= data_rsp_rdata;
        end
    end

    // D-side request is valid only if not yet completed for this instruction
    assign data_req_valid = mem_valid && (mem_mem_read || mem_mem_write) && is_mmio_addr && !mem_ddr_completed;
    assign data_req_we    = mem_mem_write;
    assign data_req_addr  = mem_alu_out;
    assign data_req_wdata = mem_wdata_aligned;
    assign data_req_wstrb = mem_wstrb;

    // Memory stall is active while waiting for DDR response and not yet completed
    assign memory_stall = mem_valid && (mem_mem_read || mem_mem_write) && is_ddr_data && !data_rsp_ready && !mem_ddr_completed;

    wire [63:0] local_mem_rdata;
    assign raw_mem_rdata = is_mmio_addr ? (mem_ddr_completed ? mem_ddr_rdata_latch : data_rsp_rdata) : local_mem_rdata;

    // Load/Store Subword Alignment & Strobe Unit
    load_store_unit LSU_inst (
        .addr_offset(mem_alu_out[2:0]),
        .funct3(mem_funct3),
        .mem_rdata(raw_mem_rdata),
        .store_wdata_in(mem_write_data_final),
        .load_data_out(mem_read_data),
        .store_wstrb(mem_wstrb),
        .store_wdata_out(mem_wdata_aligned)
    );

    // Byte-Strobe Data Memory (8KB) for local data (< 0x1000_0000)
    Data_Memory DMEM_inst (
        .clk(clk),
        .reset(reset),
        .MemRead(mem_mem_read && !is_mmio_addr),
        .MemWrite(mem_mem_write && !is_mmio_addr),
        .address(mem_alu_out[12:0]),
        .wstrb(mem_wstrb),
        .write_data(mem_wdata_aligned),
        .read_data(local_mem_rdata)
    );

    // MEM/WB Pipeline Register
    MEM_WB MEMWB_inst (
        .clk(clk),
        .reset(reset),
        .stall(memory_stall || (fetch_stall && !redirect_commit)),
        .mem_valid(mem_valid),
        .mem_wb_sel_in(mem_wb_sel),
        .wb_reg_write_en_in(mem_reg_write),
        .wb_mem_data_in(mem_read_data),
        .wb_alu_out_in(mem_alu_out),
        .wb_muldiv_out_in(mem_muldiv_out),
        .wb_pc_plus4_in(mem_pc_plus4),
        .wb_rd_in(mem_rd),
        .wb_valid(wb_valid),
        .wb_wb_sel(wb_wb_sel),
        .wb_reg_write_en(wb_reg_write_sig),
        .wb_mem_data(wb_mem_data),
        .wb_alu_out(wb_alu_out),
        .wb_muldiv_out(wb_muldiv_out),
        .wb_pc_plus4(wb_pc_plus4),
        .wb_rd(wb_rd_sig)
    );

    // ------------------------------------------------------------------------
    // 5. WRITE-BACK (WB) STAGE
    // ------------------------------------------------------------------------

    // Generalized Writeback Selector Mux (00: ALU, 01: MEM, 10: PC+4, 11: MULDIV)
    assign wb_write_data = (wb_wb_sel == 2'b01) ? wb_mem_data :
                           (wb_wb_sel == 2'b10) ? wb_pc_plus4 :
                           (wb_wb_sel == 2'b11) ? wb_muldiv_out : wb_alu_out;

    // ------------------------------------------------------------------------
    // 6. HAZARD DETECTION & PERFORMANCE COUNTERS
    // ------------------------------------------------------------------------

    hazard_detection_unit HDU_inst (
        .clk(clk),
        .reset(reset),
        .ex_mem_read(ex_mem_read),
        .cur_mem_write(mem_write),
        .cur_mem_read(mem_read),
        .execute_stall(execute_stall),
        .fetch_stall(fetch_stall),
        .memory_stall(memory_stall),
        .redirect_taken(redirect_taken),
        .branch_instr(ex_branch),
        .jump_instr(ex_jump),
        .branch_pc(ex_pc),
        .if_id_rs1(if_id_ins[19:15]),
        .if_id_rs2(if_id_ins[24:20]),
        .ex_rd(ex_rd),
        .pc_write(pc_write_en),
        .if_id_write(if_id_write_en),
        .bubble_sel(bubble_sel),
        .flush(flush_sig),
        .predicted_taken(predicted_taken)
    );

    perf_counters PERF_inst (
        .clk(clk),
        .reset(reset),
        .wb_valid(wb_valid),
        .wb_reg_write(wb_reg_write_sig),
        .wb_rd(wb_rd_sig),
        .stall_active(bubble_sel),
        .flush_active(flush_sig),
        .total_cycles(perf_cycles),
        .retired_instructions(perf_retired),
        .stall_cycles(perf_stalls),
        .flush_cycles(perf_flushes),
        .cpi_x100(perf_cpi_x100)
    );

    // Top-Level Output Assignments for Vivado Monitoring & Synthesis
    assign current_pc    = pc_out;
    assign current_instr = instr;
    assign wb_result     = wb_write_data;
    assign wb_reg_addr   = wb_rd_sig;
    assign wb_reg_we     = wb_reg_write_sig;

endmodule
