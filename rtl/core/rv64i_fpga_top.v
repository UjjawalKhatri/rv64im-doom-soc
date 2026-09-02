// ============================================================================
// Module: rv64i_fpga_top
// Description: FPGA Synthesis Top-Level Wrapper for Artix-7 / Basys3 / Nexys4
// Resolves I/O pin overutilization for hardware implementation
// Compatible with Xilinx Vivado Synthesis, Placement & Routing
// ============================================================================
`timescale 1ns / 1ps

module rv64i_fpga_top (
    input  wire        clk,
    input  wire        reset,
    input  wire [3:0]  switches, // Select debug output on LEDs
    output reg  [15:0] leds      // 16 onboard FPGA LEDs
);

    // Internal 64-bit Core Signals
    wire [63:0] current_pc;
    wire [31:0] current_instr;
    wire [63:0] wb_result;
    wire [4:0]  wb_reg_addr;
    wire        wb_reg_we;
    wire [63:0] perf_cycles;
    wire [63:0] perf_retired;
    wire [63:0] perf_stalls;
    wire [63:0] perf_flushes;
    wire [63:0] perf_cpi_x100;

    // Instantiate Full RV64I Processor Core
    rv64i_core_top #(
        .MEM_FILE("instructions.txt")
    ) core_inst (
        .clk(clk),
        .reset(reset),
        .current_pc(current_pc),
        .current_instr(current_instr),
        .wb_result(wb_result),
        .wb_reg_addr(wb_reg_addr),
        .wb_reg_we(wb_reg_we),
        .perf_cycles(perf_cycles),
        .perf_retired(perf_retired),
        .perf_stalls(perf_stalls),
        .perf_flushes(perf_flushes),
        .perf_cpi_x100(perf_cpi_x100),
        .data_req_valid(),
        .data_req_we(),
        .data_req_addr(),
        .data_req_wdata(),
        .data_req_wstrb(),
        .data_rsp_rdata(64'b0),
        .data_rsp_ready(1'b1)
    );

    // Multiplex internal 64-bit performance/register data to 16 FPGA LEDs based on switches
    always @(*) begin
        case (switches)
            4'b0000: leds = current_pc[15:0];       // Switch 0: Program Counter
            4'b0001: leds = current_instr[15:0];    // Switch 1: Current Instruction (lower 16 bits)
            4'b0010: leds = wb_result[15:0];        // Switch 2: Write-Back Data Result
            4'b0011: leds = perf_cycles[15:0];      // Switch 3: Total Clock Cycles
            4'b0100: leds = perf_retired[15:0];     // Switch 4: Retired Instructions
            4'b0101: leds = perf_stalls[15:0];      // Switch 5: Load-Use Hazard Stall Cycles
            4'b0110: leds = perf_flushes[15:0];     // Switch 6: Branch Flush Cycles
            4'b0111: leds = perf_cpi_x100[15:0];    // Switch 7: CPI (e.g. 125 = 1.25 CPI)
            default: leds = wb_result[15:0];
        endcase
    end

endmodule
