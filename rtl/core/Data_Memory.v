// ============================================================================
// Module: Data_Memory
// Description: Byte-Strobe-Enabled 64-bit Data Memory (1024 x 64-bit = 8KB)
// Uses Distributed RAM (LUTRAM) with combinational read for pipeline compatibility
// Single write port with byte strobes (wstrb) for SB, SH, SW, SD support
// Initialized via $readmemh with data.mem so .rodata (strings, fonts, constants)
// are present in memory at power-up.
// ============================================================================
`timescale 1ns / 1ps

module Data_Memory #(
    parameter DATA_FILE = "data.mem"
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        MemRead,
    input  wire        MemWrite,
    input  wire [12:0] address,     // 8KB byte address space
    input  wire [7:0]  wstrb,       // Byte write strobes
    input  wire [63:0] write_data,
    output wire [63:0] read_data
);

    // 1024 x 64-bit word-addressed memory (8192 bytes = 8KB)
    (* ram_style = "distributed" *) reg [63:0] Dmemory [0:1023];

    // Power-up initialization with compiled data image (strings, fonts, constants)
    initial begin
        $readmemh(DATA_FILE, Dmemory);
    end

    // Word address = byte address >> 3 (divide by 8 for 64-bit alignment)
    wire [9:0] word_addr = address[12:3];

    // Synchronous single-port write with byte strobes
    always @(posedge clk) begin
        if (MemWrite) begin
            if (wstrb[0]) Dmemory[word_addr][ 7: 0] <= write_data[ 7: 0];
            if (wstrb[1]) Dmemory[word_addr][15: 8] <= write_data[15: 8];
            if (wstrb[2]) Dmemory[word_addr][23:16] <= write_data[23:16];
            if (wstrb[3]) Dmemory[word_addr][31:24] <= write_data[31:24];
            if (wstrb[4]) Dmemory[word_addr][39:32] <= write_data[39:32];
            if (wstrb[5]) Dmemory[word_addr][47:40] <= write_data[47:40];
            if (wstrb[6]) Dmemory[word_addr][55:48] <= write_data[55:48];
            if (wstrb[7]) Dmemory[word_addr][63:56] <= write_data[63:56];
        end
    end

    // Combinational (asynchronous) read — required for pipeline MEM stage
    assign read_data = MemRead ? Dmemory[word_addr] : 64'b0;

endmodule
