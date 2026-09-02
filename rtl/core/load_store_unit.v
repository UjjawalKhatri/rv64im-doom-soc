// ============================================================================
// Module: load_store_unit
// Description: RV64 Load/Store Byte Extraction, Sign Extension & Strobe Gen
// Supports LB, LH, LW, LD, LBU, LHU, LWU, SB, SH, SW, SD
// ============================================================================
`timescale 1ns / 1ps

module load_store_unit (
    input  wire [2:0]  addr_offset,   // address[2:0]
    input  wire [2:0]  funct3,
    input  wire [63:0] mem_rdata,     // 64-bit aligned read data from memory
    input  wire [63:0] store_wdata_in,// unaligned store data from regfile/forwarding
    output reg  [63:0] load_data_out, // extracted & sign/zero extended load result
    output reg  [7:0]  store_wstrb,   // 8-bit byte write strobes for memory
    output reg  [63:0] store_wdata_out// shifted store data aligned to byte lanes
);

    // ------------------------------------------------------------------------
    // 1. Load Data Handling (Extraction & Extension)
    // ------------------------------------------------------------------------
    wire [63:0] shifted_rdata = mem_rdata >> (8 * addr_offset);

    wire [7:0]  byte_val = shifted_rdata[7:0];
    wire [15:0] half_val = shifted_rdata[15:0];
    wire [31:0] word_val = shifted_rdata[31:0];

    always @(*) begin
        case (funct3)
            3'b000:  load_data_out = {{56{byte_val[7]}}, byte_val}; // LB
            3'b001:  load_data_out = {{48{half_val[15]}}, half_val};// LH
            3'b010:  load_data_out = {{32{word_val[31]}}, word_val};// LW
            3'b011:  load_data_out = shifted_rdata;                 // LD
            3'b100:  load_data_out = {56'b0, byte_val};             // LBU
            3'b101:  load_data_out = {48'b0, half_val};             // LHU
            3'b110:  load_data_out = {32'b0, word_val};             // LWU
            default: load_data_out = shifted_rdata;
        endcase
    end

    // ------------------------------------------------------------------------
    // 2. Store Strobe & Data Alignment Handling
    // ------------------------------------------------------------------------
    always @(*) begin
        store_wdata_out = store_wdata_in << (8 * addr_offset);
        case (funct3)
            3'b000:  store_wstrb = 8'b00000001 << addr_offset;      // SB
            3'b001:  store_wstrb = 8'b00000011 << addr_offset;      // SH
            3'b010:  store_wstrb = 8'b00001111 << addr_offset;      // SW
            3'b011:  store_wstrb = 8'b11111111;                     // SD
            default: store_wstrb = 8'b11111111;
        endcase
    end

endmodule
