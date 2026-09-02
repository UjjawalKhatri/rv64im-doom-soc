// ============================================================================
// Module: ld_after_sd_forwarding
// Description: Forwarding from WB stage result to EX/MEM store data (fixes load-then-store & JAL-then-store)
// Compatible with Xilinx Vivado Synthesis & Implementation
// ============================================================================
`timescale 1ns / 1ps

module ld_after_sd_forwarding (
    input  wire [4:0] wb_rd,
    input  wire [4:0] sd_rs2,
    input  wire       wb_reg_write,
    input  wire       sd_mem_write,
    output wire       ld_sd_sel
);

    assign ld_sd_sel = wb_reg_write && sd_mem_write &&
                       (wb_rd != 5'b0) && (wb_rd == sd_rs2);

endmodule
