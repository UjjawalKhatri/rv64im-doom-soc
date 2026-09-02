// ============================================================================
// Module: pc
// Description: Program Counter for RV64I Pipelined Processor
// Direct synchronous branch redirect & increment logic for timing closure
// Compatible with Xilinx Vivado Synthesis & Implementation
// ============================================================================
`timescale 1ns / 1ps

module pc (
    input  wire        clk,
    input  wire        reset,
    input  wire        pc_write,
    input  wire        redirect_taken,
    input  wire [63:0] pc_branch,
    output reg  [63:0] pc_out,
    output wire [63:0] pc_plus4
);

    assign pc_plus4 = pc_out + 64'd4;

    always @(posedge clk) begin
        if (reset) begin
            pc_out <= 64'h0;
        end else if (pc_write) begin
            if (redirect_taken) begin
                pc_out <= pc_branch;
            end else begin
                pc_out <= pc_out + 64'd4;
            end
        end
    end

endmodule
