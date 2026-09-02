// ============================================================================
// Module: instruction_fetch_unit
// Description: Instruction Fetch Unit with BRAM boot + DDR external fetch
// Handles both local BRAM (boot region < 0x8000_0000) and external DDR
// (>= 0x8000_0000) instruction fetch with a 64-bit line buffer.
// Epoch-based redirect handling discards stale DDR responses.
// Per blueprint Sections 26-28.
// ============================================================================
`timescale 1ns / 1ps

module instruction_fetch_unit #(
    parameter MEM_FILE = "instructions.mem"
)(
    input  wire        clk,
    input  wire        reset,

    // PC interface
    input  wire [63:0] pc_addr,

    // Pipeline redirect (from EX stage)
    input  wire        redirect,

    // Output to IF/ID
    output wire [31:0] fetch_instr,
    output wire        fetch_stall,    // Hold pipeline when waiting for DDR

    // External instruction memory req/rsp (to DDR arbiter)
    output reg         instr_req_valid,
    output reg  [63:0] instr_req_addr,
    input  wire        instr_req_ready,
    input  wire        instr_rsp_valid,
    input  wire [63:0] instr_rsp_rdata
);

    // ========================================================================
    // Local Boot BRAM (8KB, addresses 0x0000_0000 to 0x0000_1FFF)
    // Serves the diagnostic bootloader instantly (combinational read)
    // ========================================================================
    (* ram_style = "distributed" *) reg [31:0] boot_mem [0:2047];

    initial begin
        $readmemh(MEM_FILE, boot_mem);
    end

    wire [10:0] bram_word_addr = pc_addr[12:2];
    wire [31:0] bram_instr = boot_mem[bram_word_addr];

    // ========================================================================
    // Address region decode
    // ========================================================================
    wire is_ddr_addr = (pc_addr[31] == 1'b1);  // >= 0x8000_0000

    // ========================================================================
    // 64-bit Line Buffer (caches 2 x 32-bit instructions from DDR)
    // ========================================================================
    reg        line_valid;
    reg [63:0] line_addr_base;  // 8-byte aligned base address of cached line
    reg [63:0] line_data;

    wire [63:0] pc_aligned = {pc_addr[63:3], 3'b000};  // 8-byte aligned
    wire        line_hit   = line_valid && (line_addr_base[31:3] == pc_addr[31:3]);

    // Select instruction from line buffer based on pc[2]
    wire [31:0] line_instr = pc_addr[2] ? line_data[63:32] : line_data[31:0];

    // ========================================================================
    // Epoch counter for redirect handling
    // When a redirect occurs while a DDR fetch is in-flight, the response
    // from the old address must be discarded. We toggle an epoch bit on
    // each redirect and tag requests with the current epoch.
    // ========================================================================
    reg epoch;
    reg req_epoch;

    // ========================================================================
    // Fetch FSM
    // ========================================================================
    localparam FSM_IDLE = 2'd0;
    localparam FSM_REQ  = 2'd1;
    localparam FSM_WAIT = 2'd2;

    reg [1:0] fsm_state;

    // Combinational output logic
    wire ddr_miss = is_ddr_addr && !line_hit;

    assign fetch_instr = is_ddr_addr ? line_instr : bram_instr;
    assign fetch_stall = ddr_miss;

    // One-shot edge detection for redirect to prevent multiple epoch increments while EX is held
    reg redirect_prev;
    always @(posedge clk) begin
        if (reset) redirect_prev <= 1'b0;
        else redirect_prev <= redirect;
    end
    wire redirect_edge = redirect && !redirect_prev;

    // Sequential FSM Logic
    always @(posedge clk) begin
        if (reset) begin
            fsm_state       <= FSM_IDLE;
            line_valid      <= 1'b0;
            line_addr_base  <= 64'b0;
            line_data       <= 64'b0;
            epoch           <= 1'b0;
            req_epoch       <= 1'b0;
            instr_req_valid <= 1'b0;
            instr_req_addr  <= 64'b0;
        end else begin
            // Epoch toggle on new redirect edge
            if (redirect_edge) begin
                epoch      <= ~epoch;
                line_valid <= 1'b0;  // Invalidate line buffer on redirect
            end

            case (fsm_state)
                FSM_IDLE: begin
                    if (ddr_miss && !redirect) begin
                        // Issue DDR fetch request for the aligned 8-byte block
                        instr_req_valid <= 1'b1;
                        instr_req_addr  <= pc_aligned;
                        req_epoch       <= epoch;
                        fsm_state       <= FSM_REQ;
                    end else begin
                        instr_req_valid <= 1'b0;
                    end
                end

                FSM_REQ: begin
                    if (redirect) begin
                        // Abandon request on redirect
                        instr_req_valid <= 1'b0;
                        fsm_state       <= FSM_IDLE;
                    end else if (instr_req_ready) begin
                        // Arbiter accepted request: clear valid pulse and wait for data
                        instr_req_valid <= 1'b0;
                        fsm_state       <= FSM_WAIT;
                    end else begin
                        // Hold valid high until arbiter is ready
                        instr_req_valid <= 1'b1;
                    end
                end

                FSM_WAIT: begin
                    // Clear pulse valid (latched by arbiter)
                    instr_req_valid <= 1'b0;

                    // Process response
                    if (instr_rsp_valid) begin
                        if (req_epoch == epoch && !redirect) begin
                            // Valid response: fill line buffer
                            line_valid     <= 1'b1;
                            line_addr_base <= instr_req_addr;
                            line_data      <= instr_rsp_rdata;
                        end
                        // Stale or redirected: discard silently
                        fsm_state <= FSM_IDLE;
                    end
                end

                default: fsm_state <= FSM_IDLE;
            endcase
        end
    end

endmodule
