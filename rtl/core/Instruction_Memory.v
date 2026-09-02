// ============================================================================
// Module: Instruction_Memory
// Description: 8KB Word-Addressed Instruction Memory (2048 x 32-bit words)
// High-performance Distributed RAM inference for single-cycle combinational fetch.
// 4-byte aligned indexing (addr[12:2]) completely eliminates 13-bit adder delays
// and 8192:1 byte mux trees, maximizing timing margin (WNS > 0).
// ============================================================================
`timescale 1ns / 1ps

module Instruction_Memory #(
    parameter MEM_FILE = "instructions.mem"
)(
    input  wire [63:0] addr,
    output wire [31:0] instr
);

    // 2048 words x 32 bits = 8192 bytes = 8 KB
    (* ram_style = "distributed" *) reg [31:0] memory [0:2047];

    initial begin
        $readmemh(MEM_FILE, memory);
    end

    // 4-byte instruction alignment: word index = addr[12:2]
    // Clean, direct 11-bit index with ZERO adders or byte reconstruction muxes
    wire [10:0] word_addr = addr[12:2];
    assign instr = memory[word_addr];

endmodule
