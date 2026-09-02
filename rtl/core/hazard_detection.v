// ============================================================================
// Module: hazard_detection_unit
// Description: Hazard Detection Unit with load-use stalls, branch flushes,
// EX multicycle stalls, fetch stalls (DDR), and memory stalls (DDR data).
// Per blueprint Section 12: separate stall causes.
// Compatible with Xilinx Vivado Synthesis & Implementation
// ============================================================================
`timescale 1ns / 1ps

module hazard_detection_unit (
    input  wire        clk,
    input  wire        reset,
    input  wire        ex_mem_read,
    input  wire        cur_mem_write,
    input  wire        cur_mem_read,
    input  wire        execute_stall, // Stall from multicycle EX stage (Multiplier/Divider)
    input  wire        fetch_stall,   // Stall from instruction fetch unit (DDR latency)
    input  wire        memory_stall,  // Stall from data memory (DDR load/store latency)
    input  wire        redirect_taken, // branch_taken || jump (resolved in EX)
    input  wire        branch_instr,
    input  wire        jump_instr,
    input  wire [63:0] branch_pc,
    input  wire [4:0]  if_id_rs1,
    input  wire [4:0]  if_id_rs2,
    input  wire [4:0]  ex_rd,
    output reg         pc_write,
    output reg         if_id_write,
    output reg         bubble_sel,
    output reg         flush,
    output wire        predicted_taken
);

    // 16-entry 2-bit saturating counter Branch History Table (BHT) scaffolding
    reg [1:0] bht [0:15];
    integer idx;
    wire [3:0] bht_index = branch_pc[5:2];

    assign predicted_taken = bht[bht_index][1];

    always @(posedge clk) begin
        if (reset) begin
            for (idx = 0; idx < 16; idx = idx + 1) begin
                bht[idx] <= 2'b01; // Weakly Not Taken
            end
        end else if (branch_instr && !execute_stall && !fetch_stall && !memory_stall) begin
            case (bht[bht_index])
                2'b00: bht[bht_index] <= redirect_taken ? 2'b01 : 2'b00;
                2'b01: bht[bht_index] <= redirect_taken ? 2'b10 : 2'b00;
                2'b10: bht[bht_index] <= redirect_taken ? 2'b11 : 2'b01;
                2'b11: bht[bht_index] <= redirect_taken ? 2'b11 : 2'b10;
            endcase
        end
    end

    // Global back-stall: any of execute, fetch, or memory stall freezes the pipeline
    wire global_stall = execute_stall || fetch_stall || memory_stall;

    always @(*) begin
        pc_write    = 1'b1;
        if_id_write = 1'b1;
        bubble_sel  = 1'b0;
        flush       = 1'b0;

        // Priority 1: Resolved branch / jump redirect from EX stage
        // A resolved architectural redirect must NEVER be blocked by a speculative front-end fetch stall.
        if (redirect_taken && !execute_stall && !memory_stall) begin
            pc_write    = 1'b1;
            if_id_write = 1'b1;
            flush       = 1'b1;
            bubble_sel  = 1'b0;
        end
        // Priority 2: Architectural multicycle execute or memory data stall
        else if (execute_stall || memory_stall) begin
            pc_write    = 1'b0;
            if_id_write = 1'b0;
            bubble_sel  = 1'b0;
            flush       = 1'b0;
        end
        // Priority 3: Front-end instruction fetch stall (waiting for DDR line refill)
        else if (fetch_stall) begin
            pc_write    = 1'b0;
            if_id_write = 1'b0;
            bubble_sel  = 1'b0;
            flush       = 1'b0;
        end
        // Priority 4: Load-use hazard detection
        else if (ex_mem_read && (ex_rd != 5'b0) &&
            ((ex_rd == if_id_rs1) ||
             ((ex_rd == if_id_rs2) && !(cur_mem_read || cur_mem_write)))) begin
            pc_write    = 1'b0;
            if_id_write = 1'b0;
            bubble_sel  = 1'b1;
            flush       = 1'b0;
        end
    end

endmodule
