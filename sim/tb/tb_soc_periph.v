// ============================================================================
// Module: tb_soc_periph
// Description: Comprehensive Testbench for DOOM SoC Interconnect & Peripherals
// Tests:
//   1. SoC Interconnect Address Decoding & Read/Write Muxing
//   2. GPIO MMIO (Switches, Buttons, LEDs)
//   3. 64-bit Timer MMIO (Cycle Counter & Microsecond Prescaler)
//   4. UART MMIO (TX, RX, FIFOs, Loopback @ 115200 Baud)
//   5. Framebuffer MMIO & VGA Dual-Port BRAM Scanout with DOOM Palette Lookup
//   6. Unmapped Address Graceful Termination
// Compatible with Xilinx Vivado Simulator (XSim)
// ============================================================================
`timescale 1ns / 1ps

module tb_soc_periph;

    reg clk;
    reg reset;

    // CPU Data Bus Master Signals
    reg         cpu_valid;
    reg         cpu_we;
    reg  [63:0] cpu_addr;
    reg  [63:0] cpu_wdata;
    reg  [7:0]  cpu_wstrb;
    wire [63:0] cpu_rdata;
    wire        cpu_ready;

    // GPIO Physical Pins
    reg  [7:0]  switches;
    reg  [4:0]  buttons;
    wire [7:0]  leds;

    // UART Physical Pins
    wire        uart_tx;
    wire        uart_rx;

    // Loopback UART TX directly to RX
    assign uart_rx = uart_tx;

    // VGA Physical Pins
    wire [3:0]  vga_r;
    wire [3:0]  vga_g;
    wire [3:0]  vga_b;
    wire        vga_hsync;
    wire        vga_vsync;

    // Interconnect Peripheral Wires
    wire        gpio_valid, gpio_we, gpio_ready;
    wire [3:0]  gpio_addr;
    wire [63:0] gpio_wdata, gpio_rdata;

    wire        timer_valid, timer_ready;
    wire [3:0]  timer_addr;
    wire [63:0] timer_rdata;

    wire        uart_valid_w, uart_we_w, uart_ready_w;
    wire [3:0]  uart_addr_w;
    wire [63:0] uart_wdata_w, uart_rdata_w;

    wire        fb_valid, fb_we, fb_ready;
    wire [16:0] fb_addr;
    wire [63:0] fb_wdata, fb_rdata;
    wire [7:0]  fb_wstrb;

    wire        vga_active;
    wire [9:0]  vga_pixel_x, vga_pixel_y;
    wire        pixel_tick;

    // ------------------------------------------------------------------------
    // Module Instantiations
    // ------------------------------------------------------------------------

    // Interconnect
    soc_interconnect INTERCONNECT_inst (
        .clk(clk),
        .reset(reset),
        .cpu_data_valid(cpu_valid),
        .cpu_data_we(cpu_we),
        .cpu_data_addr(cpu_addr),
        .cpu_data_wdata(cpu_wdata),
        .cpu_data_wstrb(cpu_wstrb),
        .cpu_data_rdata(cpu_rdata),
        .cpu_data_ready(cpu_ready),
        .gpio_valid(gpio_valid),
        .gpio_we(gpio_we),
        .gpio_addr(gpio_addr),
        .gpio_wdata(gpio_wdata),
        .gpio_rdata(gpio_rdata),
        .gpio_ready(gpio_ready),
        .timer_valid(timer_valid),
        .timer_addr(timer_addr),
        .timer_rdata(timer_rdata),
        .timer_ready(timer_ready),
        .uart_valid(uart_valid_w),
        .uart_we(uart_we_w),
        .uart_addr(uart_addr_w),
        .uart_wdata(uart_wdata_w),
        .uart_rdata(uart_rdata_w),
        .uart_ready(uart_ready_w),
        .fb_valid(fb_valid),
        .fb_we(fb_we),
        .fb_addr(fb_addr),
        .fb_wdata(fb_wdata),
        .fb_wstrb(fb_wstrb),
        .fb_rdata(fb_rdata),
        .fb_ready(fb_ready)
    );

    // GPIO Peripheral
    gpio_mmio GPIO_inst (
        .clk(clk),
        .reset(reset),
        .mmio_valid(gpio_valid),
        .mmio_we(gpio_we),
        .mmio_addr(gpio_addr),
        .mmio_wdata(gpio_wdata),
        .mmio_rdata(gpio_rdata),
        .mmio_ready(gpio_ready),
        .gpio_switches(switches),
        .gpio_buttons(buttons),
        .gpio_leds(leds)
    );

    // Timer Peripheral (fast simulation prescaler: 100MHz clock)
    timer_mmio #(
        .CLK_FREQ(100_000_000)
    ) TIMER_inst (
        .clk(clk),
        .reset(reset),
        .mmio_valid(timer_valid),
        .mmio_addr(timer_addr),
        .mmio_rdata(timer_rdata),
        .mmio_ready(timer_ready)
    );

    // UART Peripheral (accelerated baud rate for simulation: 10_000_000 baud = 10 cycles/bit)
    uart_mmio #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(10_000_000)
    ) UART_inst (
        .clk(clk),
        .reset(reset),
        .mmio_valid(uart_valid_w),
        .mmio_we(uart_we_w),
        .mmio_addr(uart_addr_w),
        .mmio_wdata(uart_wdata_w),
        .mmio_rdata(uart_rdata_w),
        .mmio_ready(uart_ready_w),
        .uart_txd(uart_tx),
        .uart_rxd(uart_rx)
    );

    // VGA Timing Generator
    vga_timing VGA_TIMING_inst (
        .clk_100mhz(clk),
        .reset(reset),
        .hsync(vga_hsync),
        .vsync(vga_vsync),
        .active_video(vga_active),
        .pixel_x(vga_pixel_x),
        .pixel_y(vga_pixel_y),
        .pixel_tick(pixel_tick)
    );

    // Framebuffer MMIO Bridge & Palette ROM
    framebuffer_mmio FB_inst (
        .clk(clk),
        .reset(reset),
        .mmio_valid(fb_valid),
        .mmio_we(fb_we),
        .mmio_addr(fb_addr),
        .mmio_wdata(fb_wdata),
        .mmio_wstrb(fb_wstrb),
        .mmio_rdata(fb_rdata),
        .mmio_ready(fb_ready),
        .vga_active(vga_active),
        .vga_pixel_x(vga_pixel_x),
        .vga_pixel_y(vga_pixel_y),
        .pixel_tick(pixel_tick),
        .vga_r(vga_r),
        .vga_g(vga_g),
        .vga_b(vga_b)
    );

    // Clock: 100 MHz (10 ns period)
    always #5 clk = ~clk;

    // Helper Tasks for MMIO Read and Write
    task mmio_write(input [63:0] addr, input [63:0] data, input [7:0] strb);
    begin
        @(posedge clk);
        cpu_valid <= 1'b1;
        cpu_we    <= 1'b1;
        cpu_addr  <= addr;
        cpu_wdata <= data;
        cpu_wstrb <= strb;
        @(posedge clk);
        while (!cpu_ready) @(posedge clk);
        cpu_valid <= 1'b0;
        cpu_we    <= 1'b0;
    end
    endtask

    task mmio_read(input [63:0] addr, output [63:0] data);
    begin
        @(posedge clk);
        cpu_valid <= 1'b1;
        cpu_we    <= 1'b0;
        cpu_addr  <= addr;
        cpu_wstrb <= 8'b0;
        @(posedge clk);
        while (!cpu_ready) @(posedge clk);
        data = cpu_rdata;
        cpu_valid <= 1'b0;
    end
    endtask

    reg [63:0] read_val1;
    reg [63:0] read_val2;
    integer pass_count = 0;
    integer fail_count = 0;

    initial begin
        $display("==================================================================");
        $display("       STARTING SIMULATION: DOOM SOC PERIPHERALS & INTERCONNECT   ");
        $display("==================================================================");

        clk       = 0;
        reset     = 1;
        cpu_valid = 0;
        cpu_we    = 0;
        cpu_addr  = 0;
        cpu_wdata = 0;
        cpu_wstrb = 0;
        switches  = 8'h00;
        buttons   = 5'h00;

        #30;
        @(posedge clk);
        reset = 0;
        #20;
        $display("[TB] System Reset De-asserted at %0t ps\n", $time);

        // --------------------------------------------------------------------
        // TEST 1: GPIO MMIO (Switches, Buttons, LEDs)
        // --------------------------------------------------------------------
        $display("--- TEST 1: GPIO MMIO ---");
        // Write LEDs = 0xA5
        mmio_write(64'h1000_1008, 64'hA5, 8'hFF);
        #10;
        if (leds == 8'hA5) begin
            $display("[PASS] GPIO LED Write: leds = 0x%02h", leds);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] GPIO LED Write: expected 0xA5, got 0x%02h", leds);
            fail_count = fail_count + 1;
        end

        // Readback LEDs from GPIO_LED register
        mmio_read(64'h1000_1008, read_val1);
        if (read_val1[7:0] == 8'hA5) begin
            $display("[PASS] GPIO LED Readback: 0x%02h", read_val1[7:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] GPIO LED Readback: expected 0xA5, got 0x%02h", read_val1[7:0]);
            fail_count = fail_count + 1;
        end

        // Set switches = 0x5C, buttons = 0x13
        switches = 8'h5C;
        buttons  = 5'h13;
        #30; // Wait 3 clocks for double-flop synchronizer
        mmio_read(64'h1000_1000, read_val1);
        if (read_val1[7:0] == 8'h5C && read_val1[12:8] == 5'h13) begin
            $display("[PASS] GPIO Switch/Button Read: sw=0x%02h, btn=0x%02h", read_val1[7:0], read_val1[12:8]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] GPIO Switch/Button Read: expected sw=0x5C btn=0x13, got 0x%016h", read_val1);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 2: Timer MMIO (Cycle Counter & Microsecond Counter)
        // --------------------------------------------------------------------
        $display("\n--- TEST 2: 64-bit Timer MMIO ---");
        mmio_read(64'h1000_1018, read_val1); // Read TIMER_CYCLES
        repeat(50) @(posedge clk);
        mmio_read(64'h1000_1018, read_val2); // Read TIMER_CYCLES again
        if (read_val2 > read_val1) begin
            $display("[PASS] TIMER_CYCLES incremented: val1=%0d, val2=%0d, delta=%0d", 
                     read_val1, read_val2, read_val2 - read_val1);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] TIMER_CYCLES did not increment: val1=%0d, val2=%0d", read_val1, read_val2);
            fail_count = fail_count + 1;
        end

        // Wait 150 clocks for microsecond counter to increment
        repeat(150) @(posedge clk);
        mmio_read(64'h1000_1020, read_val1); // Read TIMER_US (sitting at +0x08 from base 0x1000_1018)
        if (read_val1 > 0) begin
            $display("[PASS] TIMER_US microsecond counter: %0d us", read_val1);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] TIMER_US did not increment: %0d", read_val1);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 3: UART MMIO (TX, RX, Loopback, Status Register)
        // --------------------------------------------------------------------
        $display("\n--- TEST 3: UART MMIO & FIFO Loopback ---");
        // Read UART Status (+0x08 -> 0x1000_4008)
        mmio_read(64'h1000_4008, read_val1);
        $display("[INFO] Initial UART Status: 0x%02h (TX_EMPTY=%b, RX_EMPTY=%b)", 
                 read_val1[3:0], read_val1[1], read_val1[2]);

        // Send byte 'D' (0x44) to UART_DATA (0x1000_4000)
        mmio_write(64'h1000_4000, 64'h44, 8'hFF);
        $display("[INFO] Wrote byte 0x44 ('D') to UART TX FIFO");

        // Wait for UART TX -> RX transmission (10 bits * 10 cycles/bit + margin = ~150 cycles)
        repeat(200) @(posedge clk);

        // Read UART Status again: RX_EMPTY should now be 0
        mmio_read(64'h1000_4008, read_val1);
        $display("[INFO] Post-transfer UART Status: 0x%02h (RX_EMPTY=%b)", read_val1[3:0], read_val1[2]);

        // Read received byte from UART_DATA (0x1000_4000)
        mmio_read(64'h1000_4000, read_val2);
        if (read_val2[7:0] == 8'h44) begin
            $display("[PASS] UART Loopback received byte: 0x%02h ('%c')", read_val2[7:0], read_val2[7:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] UART Loopback expected 0x44, got 0x%02h", read_val2[7:0]);
            fail_count = fail_count + 1;
        end

        // Send a second byte 'M' (0x4D)
        mmio_write(64'h1000_4000, 64'h4D, 8'hFF);
        repeat(200) @(posedge clk);
        mmio_read(64'h1000_4000, read_val2);
        if (read_val2[7:0] == 8'h4D) begin
            $display("[PASS] UART Loopback second byte: 0x%02h ('%c')", read_val2[7:0], read_val2[7:0]);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] UART Loopback second byte: expected 0x4D, got 0x%02h", read_val2[7:0]);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 4: Framebuffer MMIO & VGA Palette Lookup
        // --------------------------------------------------------------------
        $display("\n--- TEST 4: Framebuffer MMIO & VGA Dual-Port BRAM ---");
        // Write pixel index 40 (0x28 - Bright Red in DOOM palette: RGB=0xDB0000 -> R=0xD, G=0x0, B=0x0)
        // at pixel (0, 0) -> address 0x2000_0000
        mmio_write(64'h2000_0000, 64'h28, 8'hFF);

        // Write pixel index 16 (0x10 - Dark Green in DOOM palette: RGB=0x2F3F1F -> R=0x2, G=0x3, B=0x1)
        // at pixel (1, 0) -> address 0x2000_0001
        // framebuffer_mmio extracts the byte lane selected by mmio_addr[2:0]
        // (cpu_fb_wdata = mmio_wdata >> (8 * mmio_addr[2:0])), matching what the
        // core's LSU puts on the bus for an `sb`. This raw bus driver has to do
        // the same, so the pixel byte is shifted into lane 1 for byte address 1.
        mmio_write(64'h2000_0001, 64'h10 << 8, 8'hFF);

        // The framebuffer is WRITE-ONLY from the CPU side and reads back as 0.
        //
        // This testbench drives the MMIO bus directly and honours mmio_ready, so
        // it *could* have read the BRAM back. The core cannot: memory_stall gates
        // on is_ddr_data, and the framebuffer is not in the DDR range, so a real
        // load samples the bus a cycle before the BRAM output is valid. The read
        // port was therefore never usable from software, and no software uses it
        // (sw/src/vga.c and doomgeneric_rv64.c only ever store to FB_BASE).
        //
        // Keeping it wired was expensive: it put the BRAM output register into
        // the core's load-return mux, the forwarding path and the ALU carry
        // chain, which was the worst setup path in both the 100 MHz and 75 MHz
        // builds. It is now tied to zero. VGA scanout uses port B and is
        // unaffected - TEST 4b below proves written pixels still reach the
        // screen, which is the property that actually matters here.
        mmio_read(64'h2000_0000, read_val1);
        if (read_val1 == 64'h0) begin
            $display("[PASS] Framebuffer is write-only: read returned 0x%016h as designed", read_val1);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Framebuffer read should be tied to 0, got 0x%016h", read_val1);
            fail_count = fail_count + 1;
        end

        // Writes must still complete in one cycle (the interconnect handshake is
        // unchanged) - a hang here would mean mmio_ready regressed.
        mmio_write(64'h2000_0002, 64'h7F << 16, 8'hFF);   // lane 2 for byte address 2
        mmio_read(64'h2000_0001, read_val2);
        if (read_val2 == 64'h0) begin
            $display("[PASS] Framebuffer writes still handshake cleanly after read-port removal");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Framebuffer read should be tied to 0, got 0x%016h", read_val2);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // TEST 4b: VGA scanout - do written pixels actually reach the screen?
        //
        // This replaces the old CPU-readback test with the real end-to-end
        // property: CPU write -> BRAM port A -> BRAM port B -> palette -> RGB.
        //
        // Scanout maps 640x480 to 320x200 with 2x scaling and a 40-line top
        // border:  doom_x = vga_pixel_x / 2,  doom_y = (vga_pixel_y - 40) / 2.
        // So DOOM pixel (0,0) is scanned at (0,40) and (1,0) at (2,40). Rather
        // than simulate 1.28 ms of real scanout to get there, force the
        // coordinates directly.
        //
        // Expected colours come from the real DOOM PLAYPAL table:
        //   palette[0x28] = 0x6B0F0F -> r=0x6 g=0x0 b=0x0
        //   palette[0x10] = 0xFFB7B7 -> r=0xF g=0xB b=0xB
        // (vga_r/g/b take the top nibble of each 8-bit channel.)
        // --------------------------------------------------------------------
        $display("\n--- TEST 4b: VGA Scanout (CPU write -> BRAM -> palette -> RGB) ---");

        force vga_active  = 1'b1;
        force vga_pixel_x = 10'd0;
        force vga_pixel_y = 10'd40;
        repeat (3) @(posedge clk);
        #1;
        if (vga_r == 4'h6 && vga_g == 4'h0 && vga_b == 4'h0) begin
            $display("[PASS] Scanout DOOM(0,0) index 0x28 -> RGB %0h%0h%0h (palette 0x6B0F0F)",
                     vga_r, vga_g, vga_b);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Scanout DOOM(0,0): expected r=6 g=0 b=0, got r=%0h g=%0h b=%0h",
                     vga_r, vga_g, vga_b);
            fail_count = fail_count + 1;
        end

        force vga_pixel_x = 10'd2;
        repeat (3) @(posedge clk);
        #1;
        if (vga_r == 4'hF && vga_g == 4'hB && vga_b == 4'hB) begin
            $display("[PASS] Scanout DOOM(1,0) index 0x10 -> RGB %0h%0h%0h (palette 0xFFB7B7)",
                     vga_r, vga_g, vga_b);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Scanout DOOM(1,0): expected r=F g=B b=B, got r=%0h g=%0h b=%0h",
                     vga_r, vga_g, vga_b);
            fail_count = fail_count + 1;
        end

        // Outside the DOOM window the output must blank to black.
        force vga_active = 1'b0;
        repeat (2) @(posedge clk);
        #1;
        if (vga_r == 4'h0 && vga_g == 4'h0 && vga_b == 4'h0) begin
            $display("[PASS] Scanout blanks to black outside the active DOOM window");
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Scanout should blank to black, got r=%0h g=%0h b=%0h",
                     vga_r, vga_g, vga_b);
            fail_count = fail_count + 1;
        end

        release vga_active;
        release vga_pixel_x;
        release vga_pixel_y;

        // --------------------------------------------------------------------
        // TEST 5: Unmapped Address Graceful Handshake
        // --------------------------------------------------------------------
        $display("\n--- TEST 5: Unmapped Address Handling ---");
        mmio_read(64'h3000_0000, read_val1);
        if (read_val1 == 64'hDEAD_DEAD_DEAD_DEAD) begin
            $display("[PASS] Unmapped address 0x3000_0000 returned 0x%016h and completed immediately", read_val1);
            pass_count = pass_count + 1;
        end else begin
            $display("[FAIL] Unmapped address returned unexpected 0x%016h", read_val1);
            fail_count = fail_count + 1;
        end

        // --------------------------------------------------------------------
        // FINAL SUMMARY
        // --------------------------------------------------------------------
        $display("\n==================================================================");
        $display("                   PERIPHERAL VERIFICATION SUMMARY               ");
        $display("==================================================================");
        $display("  PASSED TESTS : %0d", pass_count);
        $display("  FAILED TESTS : %0d", fail_count);
        if (fail_count == 0)
            $display("  STATUS       : ALL SOC PERIPHERAL TESTS PASSED SUCCESSFULLY! :)");
        else
            $display("  STATUS       : SOME TESTS FAILED! CHECK OUTPUT ABOVE.");
        $display("==================================================================");

        $finish;
    end

endmodule
