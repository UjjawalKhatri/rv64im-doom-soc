// ============================================================================
// tb_vga_div - Directed check on the vga_timing PIXEL_DIV parameter.
//
// 640x480@60 needs a 25 MHz pixel clock. The divider must produce exactly one
// pixel_tick every PIXEL_DIV system clocks, so that:
//     hsync period = 800 pixels  = 32.000 us  (25.000 MHz, not the 25.175 ideal)
//     vsync period = 525 lines   = 16.800 ms  (59.52 Hz)
// regardless of whether the system clock is 100 MHz (div 4) or 75 MHz (div 3).
// ============================================================================
`timescale 1ns / 1ps

module tb_vga_div;

    reg clk100 = 1'b0, clk75 = 1'b0, clk50 = 1'b0, reset = 1'b1;

    always #5.000  clk100 = ~clk100;  // 100.000 MHz
    always #6.667  clk75  = ~clk75;   //  74.996 MHz
    always #10.000 clk50  = ~clk50;   //  50.000 MHz

    wire hs4, vs4, av4, pt4;  wire [9:0] px4, py4;
    wire hs3, vs3, av3, pt3;  wire [9:0] px3, py3;
    wire hs2, vs2, av2, pt2;  wire [9:0] px2, py2;

    vga_timing #(.PIXEL_DIV(4)) DUT100 (
        .clk_100mhz(clk100), .reset(reset), .hsync(hs4), .vsync(vs4),
        .active_video(av4), .pixel_x(px4), .pixel_y(py4), .pixel_tick(pt4));

    vga_timing #(.PIXEL_DIV(3)) DUT75 (
        .clk_100mhz(clk75), .reset(reset), .hsync(hs3), .vsync(vs3),
        .active_video(av3), .pixel_x(px3), .pixel_y(py3), .pixel_tick(pt3));

    vga_timing #(.PIXEL_DIV(2)) DUT50 (
        .clk_100mhz(clk50), .reset(reset), .hsync(hs2), .vsync(vs2),
        .active_video(av2), .pixel_x(px2), .pixel_y(py2), .pixel_tick(pt2));

    // ---- pixel_tick duty: count ticks over a fixed window ----
    integer ticks4 = 0, ticks3 = 0;
    always @(posedge clk100) if (!reset && pt4) ticks4 = ticks4 + 1;
    always @(posedge clk75)  if (!reset && pt3) ticks3 = ticks3 + 1;

    // ---- measure hsync / vsync periods (falling edge to falling edge) ----
    real h4_prev = 0.0, h4_per = 0.0, v4_prev = 0.0, v4_per = 0.0;
    real h3_prev = 0.0, h3_per = 0.0, v3_prev = 0.0, v3_per = 0.0;
    real h2_prev = 0.0, h2_per = 0.0, v2_prev = 0.0, v2_per = 0.0;

    always @(negedge hs4) begin
        if (h4_prev != 0.0) h4_per = $realtime - h4_prev;
        h4_prev = $realtime;
    end
    always @(negedge vs4) begin
        if (v4_prev != 0.0) v4_per = $realtime - v4_prev;
        v4_prev = $realtime;
    end
    always @(negedge hs3) begin
        if (h3_prev != 0.0) h3_per = $realtime - h3_prev;
        h3_prev = $realtime;
    end
    always @(negedge vs3) begin
        if (v3_prev != 0.0) v3_per = $realtime - v3_prev;
        v3_prev = $realtime;
    end

    always @(negedge hs2) begin
        if (h2_prev != 0.0) h2_per = $realtime - h2_prev;
        h2_prev = $realtime;
    end
    always @(negedge vs2) begin
        if (v2_prev != 0.0) v2_per = $realtime - v2_prev;
        v2_prev = $realtime;
    end

    integer errors = 0;

    task chk_real(input [255:0] name, input real got, input real want, input real tol);
        begin
            if (got < want - tol || got > want + tol) begin
                $display("  FAIL  %0s: got %0.3f us, expected %0.3f us", name, got/1000.0, want/1000.0);
                errors = errors + 1;
            end else begin
                $display("  PASS  %0s: %0.3f us (expected %0.3f us)", name, got/1000.0, want/1000.0);
            end
        end
    endtask

    initial begin
        $display("=== tb_vga_div: VGA pixel-clock divider parameterization ===");
        repeat (20) @(posedge clk100);
        reset = 1'b0;

        // Two full frames so both hsync and vsync periods are measured.
        #34_000_000;   // 34 ms

        $display("");
        $display("-- PIXEL_DIV=4 @ 100 MHz --");
        chk_real("hsync period", h4_per,    32_000.0,   40.0);
        chk_real("vsync period", v4_per, 16_800_000.0, 5_000.0);

        $display("");
        $display("-- PIXEL_DIV=3 @ 75 MHz --");
        chk_real("hsync period", h3_per,    32_000.0,   40.0);
        chk_real("vsync period", v3_per, 16_800_000.0, 5_000.0);

        $display("");
        $display("-- PIXEL_DIV=2 @ 50 MHz --");
        chk_real("hsync period", h2_per,    32_000.0,   40.0);
        chk_real("vsync period", v2_per, 16_800_000.0, 5_000.0);

        $display("");
        $display("-- pixel_tick duty over the run --");
        // 34 ms of 100 MHz = 3.4e6 clocks; /4 = 850k ticks (+/- reset slop)
        if (ticks4 < 845_000 || ticks4 > 855_000) begin
            $display("  FAIL  div4 tick count = %0d (expected ~850000)", ticks4);
            errors = errors + 1;
        end else
            $display("  PASS  div4 tick count = %0d (~1 in 4)", ticks4);
        // 34 ms of 75 MHz = 2.55e6 clocks; /3 = 850k ticks
        if (ticks3 < 845_000 || ticks3 > 855_000) begin
            $display("  FAIL  div3 tick count = %0d (expected ~850000)", ticks3);
            errors = errors + 1;
        end else
            $display("  PASS  div3 tick count = %0d (~1 in 3)", ticks3);

        $display("");
        if (errors == 0)
            $display("=== tb_vga_div: ALL CHECKS PASSED ===");
        else
            $display("=== tb_vga_div: %0d CHECK(S) FAILED ===", errors);
        $finish;
    end

endmodule
