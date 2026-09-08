// ============================================================================
// Module: Data_Memory
// Description: Byte-Strobe-Enabled 64-bit Data Memory (1024 x 64-bit = 8KB)
// Implemented in Block RAM with a registered (synchronous) read port.
//
// This memory serves the on-chip boot region only (addresses below
// 0x1000_0000): the bootloader's .data, .bss and stack. Software running from
// DDR3 never accesses it.
//
// It was previously inferred as distributed LUT RAM with an asynchronous read.
// That placed a 1024-deep LUTRAM array directly in the MEM-stage combinational
// path; the address bits drove ~1200 loads and the resulting routing dominated
// the critical path (14.9 ns, 77% of it interconnect). Moving the array to
// Block RAM removes that structure from the datapath at the cost of one cycle
// of read latency, which the MEM stage absorbs with a single-cycle stall (see
// local_read_stall in rv64i_core_top.v).
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
    (* ram_style = "block" *) reg [63:0] Dmemory [0:1023];

    // Power-up initialization with compiled data image (strings, fonts, constants)
    initial begin
        $readmemh(DATA_FILE, Dmemory);
    end

    // Word address = byte address >> 3 (divide by 8 for 64-bit alignment)
    wire [9:0] word_addr = address[12:3];

    reg [63:0] read_data_reg;

    // Single-port Block RAM: byte-strobed write and registered read in the same
    // clocked block so the tools infer a RAMB with byte write enables.
    // Read-first behaviour: a read issued in the same cycle as a write to the
    // same address returns the previous contents. The pipeline never does this
    // for a single instruction (an access is either a load or a store).
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
        read_data_reg <= Dmemory[word_addr];
    end

    assign read_data = MemRead ? read_data_reg : 64'b0;

endmodule
