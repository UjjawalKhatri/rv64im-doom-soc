# RV64IM DOOM SoC — Verification & Simulation Guide

This document describes the simulation testbenches, verification strategies, and regression suites used to validate the custom 64-bit RISC-V processor and peripheral subsystem.

---

## 1. Testbench Suite Overview

The verification environment consists of four complementary testbenches targeting different layers of the microarchitecture. **`sim/scripts/run_all.ps1` is the single entry point** — it runs all four and prints one PASS/FAIL summary:

| Testbench File | Device Under Test | Scope of Verification | Runner |
|---|---|---|---|
| `sim/tb/tb_rv64i_core.v` | `rv64i_core_top` | Full 5-stage CPU datapath, hazard interlocks, forwarding, Fibonacci sequence, arithmetic instructions | `run_core_sim.ps1` |
| `sim/tb/tb_doom_min.v` | Core + interconnect + arbiter + AXI master + behavioural DDR | Cycle-accurate reproduction of deep pipeline hazards: link register drop (`redirect_commit`), operand decay on hold, AXI3 handshakes | `run_min_sim.ps1` |
| `sim/tb/tb_soc_periph.v` | `soc_interconnect` + peripherals | MMIO address decode, GPIO, 64-bit timer, UART loopback, framebuffer write path, VGA scanout and palette lookup, unmapped-address behaviour | `run_all.ps1` |
| `sim/tb/tb_vga_div.v` | `vga_timing` | Pixel-clock divider and 640x480 raster timing at `PIXEL_DIV` = 4 / 3 / 2 (100 / 75 / 50 MHz) | `run_all.ps1` |

> `tb_soc_periph` instantiates the interconnect and peripherals directly rather
> than `doom_soc_top`. The top level pulls in `clk_gen` (MMCM primitive) and
> `ps7_wrapper` (the PS7 IP), neither of which elaborates in a plain XSim RTL
> run, so `run_all.ps1` excludes those three files from the peripheral regression.

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
  Retired Instructions Count  : 169
  Calculated CPI              : 1.47
```

`run_all.ps1` asserts on the retired-instruction count (`169`), so a datapath
regression that silently drops or duplicates a commit fails the suite.

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

**Key Checks (13 assertions, all passing):**
- **GPIO:** LED register write and read-back at `+0x08`; switch/button read at `+0x00`.
- **Timer:** `TIMER_CYCLES` advances monotonically; `TIMER_US` ticks at the prescaled microsecond rate.
- **UART:** TX-to-RX loopback of two bytes through both 16-deep FIFOs.
- **Framebuffer:** confirms the CPU read port is intentionally removed — reads return `0` and writes still complete the handshake in one cycle. (Returning a constant took a dead 15.2 ns BRAM-to-EX/MEM path out of the critical path; see `framebuffer_mmio.v`.)
- **VGA scanout + palette:** drives raster coordinates and checks that DOOM pixel indices map through the palette to the expected RGB444 output, and that the raster blanks to black outside the centred 320x200 window.
- **Unmapped address:** `0x3000_0000` returns `0xDEADDEADDEADDEAD` and completes immediately rather than hanging the bus.

**Raster timing** is covered separately by `tb_vga_div`, which measures the
generated waveform at all three fabric clocks:

```
-- PIXEL_DIV=4 @ 100 MHz --   hsync 32.000 us   vsync 16800.000 us
-- PIXEL_DIV=3 @  75 MHz --   hsync 32.002 us   vsync 16800.840 us
-- PIXEL_DIV=2 @  50 MHz --   hsync 32.000 us   vsync 16800.000 us
```

A 32.000 µs line and an 800-clock line total put the design at **31.25 kHz
horizontal / 59.52 Hz vertical**, from an exactly-25.000 MHz pixel clock rather
than the nominal 25.175 MHz. That is ~0.8% slow against the VESA 640x480@60
spec and inside the capture range of every monitor used during bring-up.

---

## 3. Running Headless Regressions

Run everything with one command:

```powershell
powershell -ExecutionPolicy Bypass -File sim/scripts/run_all.ps1
```

```
==================================================================
  REGRESSION SUMMARY
==================================================================
  Core pipeline (tb_rv64i_core)      PASS
  Minimal SoC (tb_doom_min)          PASS
  Peripherals (tb_soc_periph)        PASS
  VGA divider (tb_vga_div)           PASS
==================================================================
  ALL REGRESSIONS PASSED
```

The runner assembles the test payloads, invokes `xvlog` / `xelab` / `xsim` in
batch mode, pattern-matches each testbench's assertions, and exits non-zero if
any regression fails — so it drops straight into CI. Individual suites can still
be run on their own:

```powershell
powershell -ExecutionPolicy Bypass -File sim/scripts/run_min_sim.ps1
powershell -ExecutionPolicy Bypass -File sim/scripts/run_core_sim.ps1
```

**Toolchain:** verified against Vivado 2022.1 (XSim) and
`riscv64-unknown-elf-gcc` 10.2.0. Vivado is located via `$env:VIVADO_DIR`, then
`vivado` on `PATH`, then `C:\Xilinx\Vivado\2022.1\bin`; the RISC-V toolchain via
`$env:RISCV_TOOLCHAIN` on the same fallback pattern.
