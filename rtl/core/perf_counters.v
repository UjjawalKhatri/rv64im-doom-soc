// ============================================================================
// Module: perf_counters
// Description: Hardware Performance Counter Module for Pipeline Analysis
// Optimized for Vivado FPGA timing closure (no dividers in RTL)
// ============================================================================
`timescale 1ns / 1ps

module perf_counters (
    input  wire        clk,
    input  wire        reset,
    input  wire        wb_valid,
    input  wire        wb_reg_write,
    input  wire [4:0]  wb_rd,
    input  wire        stall_active,
    input  wire        flush_active,

    output reg  [63:0] total_cycles,
    output reg  [63:0] retired_instructions,
    output reg  [63:0] stall_cycles,
    output reg  [63:0] flush_cycles,
    output wire [63:0] cpi_x100
);

    always @(posedge clk) begin
        if (reset) begin
            total_cycles         <= 64'd0;
            retired_instructions <= 64'd0;
            stall_cycles         <= 64'd0;
            flush_cycles         <= 64'd0;
        end else begin
            total_cycles <= total_cycles + 64'd1;

            if (stall_active)
                stall_cycles <= stall_cycles + 64'd1;

            if (flush_active)
                flush_cycles <= flush_cycles + 64'd1;

            if (wb_valid && !stall_active)
                retired_instructions <= retired_instructions + 64'd1;
        end
    end

    assign cpi_x100 = 64'd0;

endmodule
