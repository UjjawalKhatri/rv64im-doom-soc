// ============================================================================
// Module: register_file
// Description: 32x64-bit Dual-Read Single-Write Register File with Internal Write-Bypass
// Enables same-cycle WB-to-ID forwarding for zero-latency register hazard resolution
// Compatible with Xilinx Vivado Synthesis & Implementation
// ============================================================================
`timescale 1ns / 1ps

module register_file (
    input  wire        clk,
    input  wire        reset,
    input  wire        reg_write_en,
    input  wire [4:0]  read_reg1,
    input  wire [4:0]  read_reg2,
    input  wire [4:0]  write_reg,
    input  wire [63:0] write_data,
    output wire [63:0] read_data1,
    output wire [63:0] read_data2
);

    reg [63:0] registers [0:31];
    integer i;

    // Asynchronous Read with Register File Write Bypass (WB-to-ID Same-Cycle Forwarding)
    assign read_data1 = (read_reg1 == 5'b0) ? 64'b0 :
                        ((read_reg1 == write_reg) && reg_write_en) ? write_data : registers[read_reg1];

    assign read_data2 = (read_reg2 == 5'b0) ? 64'b0 :
                        ((read_reg2 == write_reg) && reg_write_en) ? write_data : registers[read_reg2];

    initial begin
        for (i = 0; i < 32; i = i + 1) begin
            registers[i] = 64'b0;
        end
    end

    // Synchronous Write on posedge clk (clean RAM32M inference)
    always @(posedge clk) begin
        if (reg_write_en && (write_reg != 5'b0)) begin
            registers[write_reg] <= write_data;
        end
    end

endmodule
