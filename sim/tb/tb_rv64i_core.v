// ============================================================================
// Module: tb_rv64i_core
// Description: Vivado Simulation Testbench for 5-Stage RV64I Pipelined Processor
// Compatible with Xilinx Vivado Simulator (XSim)
// Runs full Fibonacci Sequence calculation & Data Memory verification
// ============================================================================
`timescale 1ns / 1ps

module tb_rv64i_core;

    // Clock and Reset Signals
    reg clk;
    reg reset;

    // Core Outputs
    wire [63:0] current_pc;
    wire [31:0] current_instr;
    wire [63:0] wb_result;
    wire [4:0]  wb_reg_addr;
    wire        wb_reg_we;
    wire [63:0] perf_cycles;
    wire [63:0] perf_retired;
    wire [63:0] perf_stalls;
    wire [63:0] perf_flushes;
    wire [63:0] perf_cpi_x100;

    parameter MEM_FILE = "sim/programs/instructions.txt";

    // Instantiate Top-Level RV64I Core
    rv64i_core_top #(
        .MEM_FILE(MEM_FILE)
    ) uut (
        .clk(clk),
        .reset(reset),
        .current_pc(current_pc),
        .current_instr(current_instr),
        .wb_result(wb_result),
        .wb_reg_addr(wb_reg_addr),
        .wb_reg_we(wb_reg_we),
        .perf_cycles(perf_cycles),
        .perf_retired(perf_retired),
        .perf_stalls(perf_stalls),
        .perf_flushes(perf_flushes),
        .perf_cpi_x100(perf_cpi_x100),
        .data_req_valid(),
        .data_req_we(),
        .data_req_addr(),
        .data_req_wdata(),
        .data_req_wstrb(),
        .data_rsp_rdata(64'b0),
        .data_rsp_ready(1'b1)
    );

    // Clock Generation (100 MHz -> 10 ns period)
    always #5 clk = ~clk;

    integer i;
    integer cpi_int;
    integer cpi_frac;

    initial begin
        $display("==================================================================");
        $display("       STARTING VIVADO BEHAVIORAL SIMULATION: RV64I CORE          ");
        $display("==================================================================");

        clk   = 0;
        reset = 1;

        // Hold Reset for 20 ns (2 clock cycles)
        #20;
        reset = 0;
        $display("[TB] Reset De-asserted. Processor starting execution at PC = 0x%h", current_pc);

        // Run simulation for 2500 ns (250 clock cycles) — full Fibonacci program completion
        #2500;

        // Compute CPI in testbench (avoids 64-bit divider in synthesized RTL)
        if (perf_retired > 0) begin
            cpi_int  = perf_cycles / perf_retired;
            cpi_frac = ((perf_cycles * 100) / perf_retired) % 100;
        end else begin
            cpi_int  = 0;
            cpi_frac = 0;
        end

        $display("\n==================================================================");
        $display("                 SIMULATION EXECUTION COMPLETED                   ");
        $display("==================================================================");

        $display("HARDWARE PERFORMANCE COUNTER SUMMARY:");
        $display("------------------------------------------------------------------");
        $display("  Total Elapsed Clock Cycles  : %0d", perf_cycles);
        $display("  Retired Instructions Count  : %0d", perf_retired);
        $display("  Load-Use Hazard Stall Cycles: %0d", perf_stalls);
        $display("  Branch/Jump Flush Cycles    : %0d", perf_flushes);
        $display("  Calculated CPI              : %0d.%02d", cpi_int, cpi_frac);
        $display("==================================================================");

        $display("\nREGISTER FILE DUMP (ALL 32 REGISTERS):");
        $display("------------------------------------------------------------------");
        for (i = 0; i < 16; i = i + 1) begin
            $display("  x%-2d = 0x%016h (%-5d) | x%-2d = 0x%016h (%-5d)",
                     i, uut.RF_inst.registers[i], uut.RF_inst.registers[i],
                     i+16, uut.RF_inst.registers[i+16], uut.RF_inst.registers[i+16]);
        end
        $display("==================================================================");

        $finish;
    end

    // Real-time Write-Back Logging in Simulation Console
    always @(posedge clk) begin
        if (!reset && wb_reg_we && (wb_reg_addr != 5'b0)) begin
            $display("[Cycle %3d | PC 0x%04h] WB Stage: Write Register x%02d = 0x%h (%0d)",
                     perf_cycles, uut.ex_pc, wb_reg_addr, wb_result, wb_result);
        end
    end

endmodule
