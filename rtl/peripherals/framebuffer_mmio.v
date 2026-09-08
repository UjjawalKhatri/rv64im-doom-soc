// ============================================================================
// Module: framebuffer_mmio
// Description: Framebuffer MMIO Bridge + VGA Scanout Controller
// Base address: 0x2000_0000
// CPU writes 8-bit pixel index to FB_BASE + offset
// VGA scanout reads pixel, looks up 24-bit RGB via DOOM palette ROM
// Outputs 4-bit R/G/B for ZedBoard onboard VGA (12-bit color)
// Compatible with Xilinx Vivado Synthesis & ZedBoard Implementation
// ============================================================================
`timescale 1ns / 1ps

module framebuffer_mmio (
    input  wire        clk,
    input  wire        reset,

    // MMIO Bus Interface (CPU side)
    input  wire        mmio_valid,
    input  wire        mmio_we,
    input  wire [16:0] mmio_addr,      // Byte address within FB region (17 bits: 0..131071)
    input  wire [63:0] mmio_wdata,
    input  wire [7:0]  mmio_wstrb,
    output wire [63:0] mmio_rdata,
    output wire        mmio_ready,

    // VGA Timing Interface
    input  wire        vga_active,
    input  wire [9:0]  vga_pixel_x,
    input  wire [9:0]  vga_pixel_y,
    input  wire        pixel_tick,

    // VGA Color Output (4-bit per channel for ZedBoard)
    output wire [3:0]  vga_r,
    output wire [3:0]  vga_g,
    output wire [3:0]  vga_b
);

    // CPU-side framebuffer address (byte address → pixel index)
    wire [15:0] cpu_fb_addr = mmio_addr[15:0];  // Direct byte address = pixel index
    // mmio_addr[16] selects the palette window (0x2001_0000+). Keep framebuffer
    // writes confined to the lower 64 KB so a palette write cannot corrupt a pixel.
    wire        cpu_fb_we   = mmio_valid && mmio_we && !mmio_addr[16];

    // VGA-side: map 640x480 display coordinates to 320x200 DOOM coordinates
    // 2x integer scaling with vertical centering (40 pixel border top/bottom)
    wire [8:0] doom_x = vga_pixel_x[9:1];        // x / 2
    wire [8:0] doom_y_raw = vga_pixel_y - 10'd40; // Centered vertically
    wire [7:0] doom_y = doom_y_raw[8:1];          // (y - 40) / 2

    // Check if within DOOM active area (320x200, centered in 640x480)
    wire doom_active = vga_active &&
                       (vga_pixel_x < 10'd640) &&
                       (vga_pixel_y >= 10'd40) && (vga_pixel_y < 10'd440) &&
                       (doom_x < 9'd320) && (doom_y < 8'd200);

    // VGA scanout address: y * 320 + x
    wire [15:0] vga_fb_addr = doom_active ? ({8'b0, doom_y} * 16'd320 + {7'b0, doom_x}) : 16'b0;

    // Framebuffer pixel data from VGA port
    wire [7:0] vga_pixel_index;

    // Extract the correct byte from mmio_wdata based on mmio_addr[2:0] (LSU alignment)
    wire [7:0]  cpu_fb_wdata = (mmio_wdata >> (8 * mmio_addr[2:0])) & 8'hFF;

    // Dual-Port BRAM Framebuffer
    framebuffer_dp_ram fb_ram_inst (
        .clk_a(clk),
        .we_a(cpu_fb_we),
        .addr_a(cpu_fb_addr),
        .din_a(cpu_fb_wdata),
        .dout_a(),                 // CPU read port unused - see note below

        .clk_b(clk),
        .addr_b(vga_fb_addr),
        .dout_b(vga_pixel_index)
    );

    // ------------------------------------------------------------------------
    // The framebuffer is WRITE-ONLY from the CPU side.
    //
    // Nothing reads it: sw/src/vga.c and doomgeneric_rv64.c only ever store to
    // FB_BASE, and the core does not stall on MMIO reads at all (memory_stall
    // gates on is_ddr_data, and the framebuffer is not in the DDR range), so a
    // load from here could never have returned correct data in the first place.
    //
    // It is not free, though. Wiring dout_a back into mmio_rdata put the BRAM
    // output register directly into the core's load-return mux, and from there
    // into the forwarding path and the ALU carry chain. That dead path was the
    // WORST setup path in both the 100 MHz and the 75 MHz builds:
    //
    //   FB_inst/fb_ram_inst/fb_mem_reg_*/CLKARDCLK -> ... -> core_inst/EXMEM_*
    //   15.238 ns @ 100 MHz   /   15.038 ns @ 75 MHz, 22 logic levels
    //
    // Returning a constant removes it entirely. Reads still complete in one
    // cycle so the interconnect handshake is unchanged; they just read as 0
    // instead of as garbage.
    // ------------------------------------------------------------------------
    assign mmio_ready = mmio_valid;
    assign mmio_rdata = 64'b0;

    // ========================================================================
    // DOOM Default Palette ROM (256 entries × 24-bit RGB)
    // DOOM PLAYPAL palette 0 - EXACT 256 entries extracted from doom1.wad.
    // Do not hand-edit: regenerate from the WAD's PLAYPAL lump if it changes.
    // Index 176..191 is the red ramp used by the menu/big font; index 4 is white.
    // ========================================================================
    reg [23:0] palette [0:255];

    initial begin
        // Format: {R[7:0], G[7:0], B[7:0]}
        palette[  0] = 24'h000000; palette[  1] = 24'h1F170B; palette[  2] = 24'h170F07; palette[  3] = 24'h4B4B4B;
        palette[  4] = 24'hFFFFFF; palette[  5] = 24'h1B1B1B; palette[  6] = 24'h131313; palette[  7] = 24'h0B0B0B;
        palette[  8] = 24'h070707; palette[  9] = 24'h2F371F; palette[ 10] = 24'h232B0F; palette[ 11] = 24'h171F07;
        palette[ 12] = 24'h0F1700; palette[ 13] = 24'h4F3B2B; palette[ 14] = 24'h473323; palette[ 15] = 24'h3F2B1B;
        palette[ 16] = 24'hFFB7B7; palette[ 17] = 24'hF7ABAB; palette[ 18] = 24'hF3A3A3; palette[ 19] = 24'hEB9797;
        palette[ 20] = 24'hE78F8F; palette[ 21] = 24'hDF8787; palette[ 22] = 24'hDB7B7B; palette[ 23] = 24'hD37373;
        palette[ 24] = 24'hCB6B6B; palette[ 25] = 24'hC76363; palette[ 26] = 24'hBF5B5B; palette[ 27] = 24'hBB5757;
        palette[ 28] = 24'hB34F4F; palette[ 29] = 24'hAF4747; palette[ 30] = 24'hA73F3F; palette[ 31] = 24'hA33B3B;
        palette[ 32] = 24'h9B3333; palette[ 33] = 24'h972F2F; palette[ 34] = 24'h8F2B2B; palette[ 35] = 24'h8B2323;
        palette[ 36] = 24'h831F1F; palette[ 37] = 24'h7F1B1B; palette[ 38] = 24'h771717; palette[ 39] = 24'h731313;
        palette[ 40] = 24'h6B0F0F; palette[ 41] = 24'h670B0B; palette[ 42] = 24'h5F0707; palette[ 43] = 24'h5B0707;
        palette[ 44] = 24'h530707; palette[ 45] = 24'h4F0000; palette[ 46] = 24'h470000; palette[ 47] = 24'h430000;
        palette[ 48] = 24'hFFEBDF; palette[ 49] = 24'hFFE3D3; palette[ 50] = 24'hFFDBC7; palette[ 51] = 24'hFFD3BB;
        palette[ 52] = 24'hFFCFB3; palette[ 53] = 24'hFFC7A7; palette[ 54] = 24'hFFBF9B; palette[ 55] = 24'hFFBB93;
        palette[ 56] = 24'hFFB383; palette[ 57] = 24'hF7AB7B; palette[ 58] = 24'hEFA373; palette[ 59] = 24'hE79B6B;
        palette[ 60] = 24'hDF9363; palette[ 61] = 24'hD78B5B; palette[ 62] = 24'hCF8353; palette[ 63] = 24'hCB7F4F;
        palette[ 64] = 24'hBF7B4B; palette[ 65] = 24'hB37347; palette[ 66] = 24'hAB6F43; palette[ 67] = 24'hA36B3F;
        palette[ 68] = 24'h9B633B; palette[ 69] = 24'h8F5F37; palette[ 70] = 24'h875733; palette[ 71] = 24'h7F532F;
        palette[ 72] = 24'h774F2B; palette[ 73] = 24'h6B4727; palette[ 74] = 24'h5F4323; palette[ 75] = 24'h533F1F;
        palette[ 76] = 24'h4B371B; palette[ 77] = 24'h3F2F17; palette[ 78] = 24'h332B13; palette[ 79] = 24'h2B230F;
        palette[ 80] = 24'hEFEFEF; palette[ 81] = 24'hE7E7E7; palette[ 82] = 24'hDFDFDF; palette[ 83] = 24'hDBDBDB;
        palette[ 84] = 24'hD3D3D3; palette[ 85] = 24'hCBCBCB; palette[ 86] = 24'hC7C7C7; palette[ 87] = 24'hBFBFBF;
        palette[ 88] = 24'hB7B7B7; palette[ 89] = 24'hB3B3B3; palette[ 90] = 24'hABABAB; palette[ 91] = 24'hA7A7A7;
        palette[ 92] = 24'h9F9F9F; palette[ 93] = 24'h979797; palette[ 94] = 24'h939393; palette[ 95] = 24'h8B8B8B;
        palette[ 96] = 24'h838383; palette[ 97] = 24'h7F7F7F; palette[ 98] = 24'h777777; palette[ 99] = 24'h6F6F6F;
        palette[100] = 24'h6B6B6B; palette[101] = 24'h636363; palette[102] = 24'h5B5B5B; palette[103] = 24'h575757;
        palette[104] = 24'h4F4F4F; palette[105] = 24'h474747; palette[106] = 24'h434343; palette[107] = 24'h3B3B3B;
        palette[108] = 24'h373737; palette[109] = 24'h2F2F2F; palette[110] = 24'h272727; palette[111] = 24'h232323;
        palette[112] = 24'h77FF6F; palette[113] = 24'h6FEF67; palette[114] = 24'h67DF5F; palette[115] = 24'h5FCF57;
        palette[116] = 24'h5BBF4F; palette[117] = 24'h53AF47; palette[118] = 24'h4B9F3F; palette[119] = 24'h439337;
        palette[120] = 24'h3F832F; palette[121] = 24'h37732B; palette[122] = 24'h2F6323; palette[123] = 24'h27531B;
        palette[124] = 24'h1F4317; palette[125] = 24'h17330F; palette[126] = 24'h13230B; palette[127] = 24'h0B1707;
        palette[128] = 24'hBFA78F; palette[129] = 24'hB79F87; palette[130] = 24'hAF977F; palette[131] = 24'hA78F77;
        palette[132] = 24'h9F876F; palette[133] = 24'h9B7F6B; palette[134] = 24'h937B63; palette[135] = 24'h8B735B;
        palette[136] = 24'h836B57; palette[137] = 24'h7B634F; palette[138] = 24'h775F4B; palette[139] = 24'h6F5743;
        palette[140] = 24'h67533F; palette[141] = 24'h5F4B37; palette[142] = 24'h574333; palette[143] = 24'h533F2F;
        palette[144] = 24'h9F8363; palette[145] = 24'h8F7753; palette[146] = 24'h836B4B; palette[147] = 24'h775F3F;
        palette[148] = 24'h675333; palette[149] = 24'h5B472B; palette[150] = 24'h4F3B23; palette[151] = 24'h43331B;
        palette[152] = 24'h7B7F63; palette[153] = 24'h6F7357; palette[154] = 24'h676B4F; palette[155] = 24'h5B6347;
        palette[156] = 24'h53573B; palette[157] = 24'h474F33; palette[158] = 24'h3F472B; palette[159] = 24'h373F27;
        palette[160] = 24'hFFFF73; palette[161] = 24'hEBDB57; palette[162] = 24'hD7BB43; palette[163] = 24'hC39B2F;
        palette[164] = 24'hAF7B1F; palette[165] = 24'h9B5B13; palette[166] = 24'h874307; palette[167] = 24'h732B00;
        palette[168] = 24'hFFFFFF; palette[169] = 24'hFFDBDB; palette[170] = 24'hFFBBBB; palette[171] = 24'hFF9B9B;
        palette[172] = 24'hFF7B7B; palette[173] = 24'hFF5F5F; palette[174] = 24'hFF3F3F; palette[175] = 24'hFF1F1F;
        palette[176] = 24'hFF0000; palette[177] = 24'hEF0000; palette[178] = 24'hE30000; palette[179] = 24'hD70000;
        palette[180] = 24'hCB0000; palette[181] = 24'hBF0000; palette[182] = 24'hB30000; palette[183] = 24'hA70000;
        palette[184] = 24'h9B0000; palette[185] = 24'h8B0000; palette[186] = 24'h7F0000; palette[187] = 24'h730000;
        palette[188] = 24'h670000; palette[189] = 24'h5B0000; palette[190] = 24'h4F0000; palette[191] = 24'h430000;
        palette[192] = 24'hE7E7FF; palette[193] = 24'hC7C7FF; palette[194] = 24'hABABFF; palette[195] = 24'h8F8FFF;
        palette[196] = 24'h7373FF; palette[197] = 24'h5353FF; palette[198] = 24'h3737FF; palette[199] = 24'h1B1BFF;
        palette[200] = 24'h0000FF; palette[201] = 24'h0000E3; palette[202] = 24'h0000CB; palette[203] = 24'h0000B3;
        palette[204] = 24'h00009B; palette[205] = 24'h000083; palette[206] = 24'h00006B; palette[207] = 24'h000053;
        palette[208] = 24'hFFFFFF; palette[209] = 24'hFFEBDB; palette[210] = 24'hFFD7BB; palette[211] = 24'hFFC79B;
        palette[212] = 24'hFFB37B; palette[213] = 24'hFFA35B; palette[214] = 24'hFF8F3B; palette[215] = 24'hFF7F1B;
        palette[216] = 24'hF37317; palette[217] = 24'hEB6F0F; palette[218] = 24'hDF670F; palette[219] = 24'hD75F0B;
        palette[220] = 24'hCB5707; palette[221] = 24'hC34F00; palette[222] = 24'hB74700; palette[223] = 24'hAF4300;
        palette[224] = 24'hFFFFFF; palette[225] = 24'hFFFFD7; palette[226] = 24'hFFFFB3; palette[227] = 24'hFFFF8F;
        palette[228] = 24'hFFFF6B; palette[229] = 24'hFFFF47; palette[230] = 24'hFFFF23; palette[231] = 24'hFFFF00;
        palette[232] = 24'hA73F00; palette[233] = 24'h9F3700; palette[234] = 24'h932F00; palette[235] = 24'h872300;
        palette[236] = 24'h4F3B27; palette[237] = 24'h432F1B; palette[238] = 24'h372313; palette[239] = 24'h2F1B0B;
        palette[240] = 24'h000053; palette[241] = 24'h000047; palette[242] = 24'h00003B; palette[243] = 24'h00002F;
        palette[244] = 24'h000023; palette[245] = 24'h000017; palette[246] = 24'h00000B; palette[247] = 24'h000000;
        palette[248] = 24'hFF9F43; palette[249] = 24'hFFE74B; palette[250] = 24'hFF7BFF; palette[251] = 24'hFF00FF;
        palette[252] = 24'hCF00CF; palette[253] = 24'h9F009B; palette[254] = 24'h6F006B; palette[255] = 24'hA76B6B;
    end

    // ========================================================================
    // Runtime-writable palette port (CPU) - enables DOOM's I_SetPalette effects:
    // damage red flash, item-pickup gold, radiation-suit green, gamma changes.
    //
    //   Window : 0x2001_0000 + (index * 8),  index = 0..255
    //   Data   : 24-bit 0x00RRGGBB in the low bits of a 64-bit store (sd)
    //   Access : WRITE-ONLY (DOOM never reads the palette back)
    //
    // The initial block above still supplies power-on defaults, so the
    // bootloader's VGA text console has correct colours before DOOM runs.
    // ========================================================================
    wire       pal_we    = mmio_valid && mmio_we && mmio_addr[16];
    wire [7:0] pal_waddr = mmio_addr[10:3];   // 8-byte stride per entry

    always @(posedge clk) begin
        if (pal_we)
            palette[pal_waddr] <= mmio_wdata[23:0];
    end

    // Palette lookup: convert 8-bit pixel index to 24-bit RGB
    wire [23:0] pixel_rgb = palette[vga_pixel_index];

    // Output: truncate 8-bit channels to 4-bit for ZedBoard VGA (12-bit color)
    assign vga_r = doom_active ? pixel_rgb[23:20] : 4'b0;
    assign vga_g = doom_active ? pixel_rgb[15:12] : 4'b0;
    assign vga_b = doom_active ? pixel_rgb[7:4]   : 4'b0;

endmodule
