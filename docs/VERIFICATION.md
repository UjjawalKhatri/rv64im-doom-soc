# RV64IM DOOM SoC — Verification & Simulation Guide

This document describes the simulation testbenches, verification strategies, and regression suites used to validate the custom 64-bit RISC-V processor and peripheral subsystem.

---

## 1. Testbench Suite Overview

The verification environment consists of three complementary testbenches targeting different layers of the microarchitecture:

| Testbench File | Target Module | Scope of Verification | Execution Command |
|---|---|---|---|
| `sim/tb/tb_rv64i_core.v` | `rv64i_core_top` | Full 5-stage CPU datapath, hazard interlocks, forwarding, Fibonacci sequence, arithmetic instructions | `powershell sim/scripts/run_core_sim.ps1` |
| `sim/tb/tb_doom_min.v` | Core + Arbiter + AXI + DDR | Cycle-accurate reproduction of deep pipeline hazards: link register drop (`redirect_commit`), operand decay on hold, AXI3 handshakes | `powershell sim/scripts/run_min_sim.ps1` |
| `sim/tb/tb_soc_periph.v` | `doom_soc_top` (Fabric) | Peripheral MMIO address decoders, UART baud rate, 64-bit timer, dual-port VGA timing raster, and palette RAM writes | Vivado GUI / Headless |

---

## 2. Testbench Specifications & Evidence

### 2.1 Core Datapath Verification (`tb_rv64i_core.v`)

**Objective:**
Verifies that the RV64I execution pipeline correctly computes mathematical sequences, manages register file dependencies, and retires instructions without hazard stalls or spurious flushes.

**Workload:**
Executes an assembly program calculating the Fibonacci sequence up to 10 iterations (`sim/programs/fibonacci_instructions.txt`), writing calculated terms sequentially into Data Memory.

**Key Signals Monitored:**
- `clk`, `reset`
- `current_pc`: Architectural instruction address
- `current_instr`: 32-bit decoded instruction word
- `wb_reg_we`, `wb_reg_addr`, `wb_result`: Architectural register writeback commit
- `perf_cycles`, `perf_retired`, `perf_cpi_x100`: Hardware performance counters

**Verification Output:**
```
==================================================================
  RV64I Core Simulation Finished Successfully!
  Fibonacci Sequence Verified in Data Memory.
  Total Cycles: 142 | Instructions Retired: 118 | CPI: 1.20
==================================================================
```

---

### 2.2 Minimal SoC Reproduction Testbench (`tb_doom_min.v`)

**Objective:**
Recreates the exact multi-cycle asynchronous timing interactions between the CPU, DDR arbiter, native AXI master, and DDR3 DRAM controller without requiring 20-minute FPGA synthesis runs.

**Architecture:**
Instantiates `rv64i_core_top`, `soc_interconnect`, `ddr_request_arbiter`, `native_axi_master`, and the behavioral DDR3 slave model (`sim/models/ddr_axi_behav.v`).

**Reproduction Programs (`sim/programs/min_test.S`):**
1. **Link Register Drop (Issue #7):**
   Executes a subroutine call (`JAL x1, subroutine`) immediately followed by an instruction fetch miss to DDR.
   - *Pre-fix Behavior:* `ra` (register `x1`) remained `0x0000000000000000` because `fetch_stall` froze `EX/MEM` while the front-end was flushed. Subroutine returned to `0x00000000` (reboot loop).
   - *Post-fix Behavior:* `redirect_commit` forces `EX/MEM` to latch the `JAL`. Testbench validates `ra = 0x80000014` before `subroutine` executes.
2. **Forwarded Operand Decay (Issue #8):**
   Generates an ALU dependency where instruction A produces `0x00C0FFEE` into `x7`, and instruction B (`SD x7, 0(x8)`) requires this value while held in `EX` across multiple DDR stall cycles.
   - *Pre-fix Behavior:* Forwarding select expired after cycle 1, causing `x7` to revert to `0x00000000` when written to memory.
   - *Post-fix Behavior:* ID/EX register absorbs the forwarded operand into `ex_data2`. Memory write confirms `0x00C0FFEE` committed to DRAM.

---

### 2.3 Peripheral Subsystem Testbench (`tb_soc_periph.v`)

**Objective:**
Verifies memory-mapped peripheral address decoding, VGA video raster generation, and hardware palette updates.

**Key Checks:**
- **VGA Timing Controller:** Verifies negative-polarity horizontal sync (31.468 kHz) and vertical sync (59.94 Hz), confirming exact pulse widths (HSYNC = 96 clocks, VSYNC = 2 lines).
- **Dual-Port Framebuffer Arbitration:** Validates simultaneous write access on Port A (100 MHz CPU clock) and read access on Port B (100 MHz domain with 25 MHz pixel enable) with zero data corruption.
- **Palette RAM Decode:** Writes to `0x2001_0000 + (index * 8)` and validates that the RGB888 color table updates immediately.

---

## 3. Running Headless Regressions

All simulations can be executed non-interactively using PowerShell or Vivado XSim:

```powershell
# 1. Run the Minimal SoC Pipeline Hazard Regression Suite
powershell -ExecutionPolicy Bypass -File sim/scripts/run_min_sim.ps1

# 2. Run the RV64I Core Mathematical Regression
powershell -ExecutionPolicy Bypass -File sim/scripts/run_core_sim.ps1
```

Both scripts automatically compile the assembly test payloads, invoke `xvlog` and `xelab`, run `xsim` in batch mode, and evaluate assertion results.
