// ============================================================================
// tb_doom_min - Minimal reproduction testbench for the ra-corruption bug.
// Wires the real PL datapath (core + interconnect + arbiter + native_axi_master)
// to a behavioral DDR slave, and boots a tiny program from BRAM that jumps into
// DDR (0x80000000) and performs: DDR store -> jal callee -> callee returns.
// Monitors the architectural ra (x1) and flags corruption / crash-to-0.
//
// Build/run (Vivado xsim), from project root:
//   xvlog -sv rtl/*.v rtl/soc/*.v rtl/periph/*.v tb/ddr_axi_behav.v tb/tb_doom_min.v
//   xelab -debug typical tb_doom_min -s minsim
//   xsim minsim -runall
// (Adjust rtl globbing to your file list; exclude ps7_wrapper.v - not used here.)
// ============================================================================
`timescale 1ns / 1ps

module tb_doom_min;

    reg clk = 0;
    reg reset = 1;
    always #5 clk = ~clk;   // 100 MHz

    // ---- Core <-> datapath wires ----
    wire [63:0] current_pc;
    wire [31:0] current_instr;
    wire [63:0] wb_result;
    wire [4:0]  wb_reg_addr;
    wire        wb_reg_we;
    wire [63:0] perf_cycles, perf_retired, perf_stalls, perf_flushes, perf_cpi_x100;

    wire        cpu_data_valid, cpu_data_we, cpu_data_ready;
    wire [63:0] cpu_data_addr, cpu_data_wdata, cpu_data_rdata;
    wire [7:0]  cpu_data_wstrb;

    wire        core_ireq_valid, core_ireq_ready, core_irsp_valid;
    wire [63:0] core_ireq_addr, core_irsp_rdata;

    // Memory initialization parameters (relative to repository root)
    parameter BOOT_MEM = "sim/programs/boot_stub.mem";
    parameter DDR_MEM  = "sim/programs/min_test.hex";

    rv64i_core_top #(.MEM_FILE(BOOT_MEM)) core_inst (
        .clk(clk), .reset(reset),
        .current_pc(current_pc), .current_instr(current_instr),
        .wb_result(wb_result), .wb_reg_addr(wb_reg_addr), .wb_reg_we(wb_reg_we),
        .perf_cycles(perf_cycles), .perf_retired(perf_retired),
        .perf_stalls(perf_stalls), .perf_flushes(perf_flushes), .perf_cpi_x100(perf_cpi_x100),
        .data_req_valid(cpu_data_valid), .data_req_we(cpu_data_we),
        .data_req_addr(cpu_data_addr), .data_req_wdata(cpu_data_wdata),
        .data_req_wstrb(cpu_data_wstrb), .data_rsp_rdata(cpu_data_rdata),
        .data_rsp_ready(cpu_data_ready),
        .instr_req_valid(core_ireq_valid), .instr_req_addr(core_ireq_addr),
        .instr_req_ready(core_ireq_ready), .instr_rsp_valid(core_irsp_valid),
        .instr_rsp_rdata(core_irsp_rdata)
    );

    // ---- Interconnect (peripherals tied off; test uses DDR only) ----
    wire        ic_ddr_valid, ic_ddr_we, ic_ddr_ready;
    wire [63:0] ic_ddr_addr, ic_ddr_wdata, ic_ddr_rdata;
    wire [7:0]  ic_ddr_wstrb;

    soc_interconnect ic (
        .clk(clk), .reset(reset),
        .cpu_data_valid(cpu_data_valid), .cpu_data_we(cpu_data_we),
        .cpu_data_addr(cpu_data_addr), .cpu_data_wdata(cpu_data_wdata),
        .cpu_data_wstrb(cpu_data_wstrb), .cpu_data_rdata(cpu_data_rdata),
        .cpu_data_ready(cpu_data_ready),
        .gpio_valid(), .gpio_we(), .gpio_addr(), .gpio_wdata(),
        .gpio_rdata(64'h0), .gpio_ready(1'b1),
        .timer_valid(), .timer_addr(), .timer_rdata(64'h0), .timer_ready(1'b1),
        .uart_valid(), .uart_we(), .uart_addr(), .uart_wdata(),
        .uart_rdata(64'h0), .uart_ready(1'b1),
        .fb_valid(), .fb_we(), .fb_addr(), .fb_wdata(), .fb_wstrb(),
        .fb_rdata(64'h0), .fb_ready(1'b1),
        .ddr_valid(ic_ddr_valid), .ddr_we(ic_ddr_we), .ddr_addr(ic_ddr_addr),
        .ddr_wdata(ic_ddr_wdata), .ddr_wstrb(ic_ddr_wstrb),
        .ddr_rdata(ic_ddr_rdata), .ddr_ready(ic_ddr_ready),
        .axi_last_rresp(2'b0), .axi_last_bresp(2'b0),
        .axi_last_araddr(32'b0), .axi_last_awaddr(32'b0),
        .axi_rd_count(32'b0), .axi_wr_count(32'b0), .axi_last_rdata(64'b0)
    );

    // ---- DDR Arbiter ----
    wire        arb_valid, arb_we, arb_ready, arb_rsp_valid;
    wire [63:0] arb_addr, arb_wdata, arb_rsp_rdata;
    wire [7:0]  arb_wstrb;

    ddr_request_arbiter arb (
        .clk(clk), .reset(reset),
        .i_req_valid(core_ireq_valid), .i_req_addr(core_ireq_addr),
        .i_req_ready(core_ireq_ready), .i_rsp_valid(core_irsp_valid),
        .i_rsp_rdata(core_irsp_rdata),
        .d_req_valid(ic_ddr_valid), .d_req_we(ic_ddr_we), .d_req_addr(ic_ddr_addr),
        .d_req_wdata(ic_ddr_wdata), .d_req_wstrb(ic_ddr_wstrb), .d_req_ready(),
        .d_rsp_valid(ic_ddr_ready), .d_rsp_rdata(ic_ddr_rdata),
        .ddr_req_valid(arb_valid), .ddr_req_we(arb_we), .ddr_req_addr(arb_addr),
        .ddr_req_wdata(arb_wdata), .ddr_req_wstrb(arb_wstrb), .ddr_req_ready(arb_ready),
        .ddr_rsp_valid(arb_rsp_valid), .ddr_rsp_rdata(arb_rsp_rdata)
    );

    // ---- Native AXI master + behavioral DDR ----
    wire [5:0]  awid, wid, bid, arid, rid;
    wire [31:0] awaddr, araddr;
    wire [3:0]  awlen, arlen;
    wire [2:0]  awsize, arsize;
    wire [1:0]  awburst, arburst, awlock, arlock, bresp, rresp;
    wire [3:0]  awcache, arcache, awqos, arqos;
    wire [2:0]  awprot, arprot;
    wire        awvalid, awready, wvalid, wready, wlast, bvalid, bready;
    wire        arvalid, arready, rvalid, rready, rlast;
    wire [63:0] wdata, rdata;
    wire [7:0]  wstrb;

    native_axi_master axim (
        .clk(clk), .resetn(!reset),
        .req_valid(arb_valid), .req_we(arb_we), .req_addr(arb_addr),
        .req_wdata(arb_wdata), .req_wstrb(arb_wstrb), .req_ready(arb_ready),
        .rsp_valid(arb_rsp_valid), .rsp_rdata(arb_rsp_rdata),
        .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
        .m_axi_awburst(awburst), .m_axi_awlock(awlock), .m_axi_awcache(awcache),
        .m_axi_awprot(awprot), .m_axi_awqos(awqos), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wid(wid), .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
        .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bid(bid), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
        .m_axi_arburst(arburst), .m_axi_arlock(arlock), .m_axi_arcache(arcache),
        .m_axi_arprot(arprot), .m_axi_arqos(arqos), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rid(rid), .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
        .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .last_rresp(), .last_bresp(), .last_araddr(), .last_awaddr(),
        .axi_rd_count(), .axi_wr_count(), .axi_err_count(), .last_rdata()
    );

    ddr_axi_behav #(.MEMH(DDR_MEM), .LAT(8), .ADDR_BITS(26)) ddr (
        .clk(clk), .resetn(!reset),
        .awaddr(awaddr), .awlen(awlen), .awsize(awsize), .awvalid(awvalid), .awready(awready),
        .wdata(wdata), .wstrb(wstrb), .wlast(wlast), .wvalid(wvalid), .wready(wready),
        .bresp(bresp), .bvalid(bvalid), .bready(bready),
        .araddr(araddr), .arlen(arlen), .arsize(arsize), .arvalid(arvalid), .arready(arready),
        .rdata(rdata), .rresp(rresp), .rlast(rlast), .rvalid(rvalid), .rready(rready)
    );

    // ---- Monitoring ----
    // Architectural ra = x1
    wire [63:0] ra = core_inst.RF_inst.registers[1];
    reg  [63:0] ra_prev;
    reg entered_ddr;

    initial begin
        $dumpfile("tb_doom_min.vcd");
        $dumpvars(0, tb_doom_min);
        ra_prev = 0;
        entered_ddr = 0;
        #40 reset = 0;
        $display("[TB] reset released");
        #200000;   // 20us cap
        $display("[TB] TIMEOUT - simulation cap reached");
        $finish;
    end

    // AXI read/write channel trace for the zone address (phys 0x02000000)
    always @(posedge clk) begin
        if (!reset) begin
            if (arvalid && arready)
                $display("[%0t] AXI AR: araddr=0x%08h", $time, araddr);
            if (rvalid)
                $display("[%0t] AXI R : rvalid=1 rready=%b rdata=0x%016h", $time, rready, rdata);
            if (awvalid && awready)
                $display("[%0t] AXI AW: awaddr=0x%08h wdata=0x%016h", $time, awaddr, wdata);
        end
    end

    // Load-data-capture trace: fires while the zone load (0x82000000) is in MEM
    always @(posedge clk) begin
        if (!reset && core_inst.mem_valid && (core_inst.mem_alu_out[31:0] == 32'h82000000)) begin
            $display("[%0t] LD-MEM: mvalid=%b mregwr=%b mrd=%0d mwbsel=%b rsp_rdy=%b mstall=%b fstall=%b read_data=0x%016h",
                $time, core_inst.mem_valid, core_inst.mem_reg_write, core_inst.mem_rd, core_inst.mem_wb_sel,
                core_inst.data_rsp_ready, core_inst.memory_stall, core_inst.fetch_stall, core_inst.mem_read_data);
        end
        // WB writes to t2 (x7)
        if (!reset && core_inst.wb_reg_write_sig && (core_inst.wb_rd_sig == 5'd7)) begin
            $display("[%0t] WB x7(t2): wbsel=%b data=0x%016h  regfile_x7=0x%016h", $time,
                core_inst.wb_wb_sel, core_inst.wb_write_data, core_inst.RF_inst.registers[7]);
        end
        // The store that reads x7: mem stage storing to phys 0x00020010
        if (!reset && core_inst.mem_valid && core_inst.mem_mem_write && (core_inst.mem_alu_out[31:0] == 32'h80020010)) begin
            $display("[%0t] SD uses x7: store_data=0x%016h regfile_x7=0x%016h", $time,
                core_inst.mem_store_data, core_inst.RF_inst.registers[7]);
        end
        // The store while it sits in EX: what operand does it actually latch/forward?
        if (!reset && core_inst.ex_mem_write && (core_inst.ex_rs2 == 5'd7)) begin
            $display("[%0t] SD-in-EX: ex_rs2=%0d ex_data2=0x%016h fwd_b=%b alu_b_pre=0x%016h | WB we=%b rd=%0d data=0x%016h | MEM rd=%0d regwr=%b read=%b | rf_x7=0x%016h",
                $time, core_inst.ex_rs2, core_inst.ex_data2, core_inst.fwd_b, core_inst.alu_b_pre,
                core_inst.wb_reg_write_sig, core_inst.wb_rd_sig, core_inst.wb_write_data,
                core_inst.mem_rd, core_inst.mem_reg_write, core_inst.mem_mem_read,
                core_inst.RF_inst.registers[7]);
        end
    end

    // Detailed pipeline trace once we enter DDR (disabled; set TRACE_PIPE=1 to enable)
    localparam TRACE_PIPE = 1;
    always @(posedge clk) begin
        if (TRACE_PIPE && !reset && entered_ddr && $time > 4100000) begin
            $display("[%0t] PC=%h I=%h op=%h | pcW=%b idW=%b bub=%b | mstall=%b fstall=%b | ID rs1=%0d rs2=%0d | EXrd=%0d mrd=%0d mread=%b",
                $time, current_pc[31:0], current_instr, core_inst.if_id_ins[6:0],
                core_inst.pc_write_en, core_inst.if_id_write_en, core_inst.bubble_sel,
                core_inst.memory_stall, core_inst.fetch_stall,
                core_inst.if_id_ins[19:15], core_inst.if_id_ins[24:20],
                core_inst.ex_rd, core_inst.mem_rd, core_inst.mem_mem_read);
        end
    end

    // Track when we start executing from DDR (PC >= 0x80000000)
    always @(posedge clk) begin
        if (!reset) begin
            if (current_pc[31] && !entered_ddr) begin
                entered_ddr <= 1'b1;
                $display("[%0t] ENTERED DDR: PC=0x%h", $time, current_pc);
            end
            // ra changes
            if (ra !== ra_prev) begin
                $display("[%0t] ra x1 : 0x%016h -> 0x%016h  (PC=0x%h)", $time, ra_prev, ra, current_pc);
                ra_prev <= ra;
            end
            // crash: PC fell back to boot region after running from DDR
            if (entered_ddr && !current_pc[31] && current_pc < 64'h1000) begin
                $display("[%0t] *** CRASH: PC returned to boot region 0x%h (ra=0x%016h) ***",
                         $time, current_pc, ra);
                $display("[TB] callee return corrupted ra -> jumped to bad address. Repro captured.");
                #50 $finish;
            end
            // success: reached the post-call 'done' loop (we tag it below)
        end
    end

    // Detect the callee's captured-ra store (sd s0,24(0x80030000) -> phys 0x30018)
    // and the success marker (sd 0x22 -> 0x80020008 -> phys 0x20008).
    always @(posedge clk) begin
        if (!reset && awvalid && wvalid && awready) begin
            if (awaddr == 32'h00030018)
                $display("[%0t] CALLEE captured incoming ra = 0x%016h (expect a real code addr in 0x8000xxxx)", $time, wdata);
            if (awaddr == 32'h00020008)
                $display("[%0t] SUCCESS: callee returned cleanly, post-call marker 0x%h written", $time, wdata);
            if (awaddr == 32'h02000000)
                $display("[%0t] ZONE WRITE issued to phys 0x02000000, data=0x%016h", $time, wdata);
            if (awaddr == 32'h00020010) begin
                $display("[%0t] TEST2 zone readback (ld of 0x82000000) = 0x%016h  %s",
                    $time, wdata, (wdata == 64'h00c0ffee) ? "PASS" : "*** FAIL (expect 0xc0ffee) ***");
            end
            if (awaddr == 32'h00020020) begin
                $display("[%0t] TEST3 load->ALU->store            = 0x%016h  %s",
                    $time, wdata, (wdata == 64'h1235) ? "PASS" : "*** FAIL (expect 0x1235) ***");
            end
            if (awaddr == 32'h00020028) begin
                $display("[%0t] TEST4 load->branch                = 0x%016h  %s",
                    $time, wdata, (wdata == 64'h0000a000) ? "PASS" : "*** FAIL (expect 0xa000) ***");
                #50 $finish;
            end
        end
    end

endmodule
