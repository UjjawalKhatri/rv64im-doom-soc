# RV64IM DOOM SoC — Performance Analysis & Optimization Roadmap

This document details the measured performance metrics of bare-metal DOOM running on the custom 64-bit RISC-V SoC at 100.00 MHz, derives the architectural cycle costs, and outlines a prioritized roadmap for future performance enhancements.

---

## 1. Measured Baseline Performance

Performance measurements were captured via the hardware 64-bit microsecond timer (`0x10001018`) and telemetry block (`0x80530000`), read live over JTAG using `scripts/jtag/read_fps.tcl`:

| Metric | Measured Value | Percentage of Frame |
|---|---|---|
| **Sustained Frame Rate** | **2.59 FPS** | — |
| **Total Frame Duration** | **385,971 µs** (385.97 ms) | 100.00% |
| **3D Rendering & Game Logic** | **354,771 µs** (354.77 ms) | **91.92%** |
| **Framebuffer Blit (`I_FinishUpdate`)** | **31,200 µs** (31.20 ms) | **8.08%** |
| **Active Clock Frequency** | **100.00 MHz** | 10.0 ns cycle period |
| **Total Clock Cycles per Frame** | **38,597,100 cycles** | — |

---

## 2. Derivation of Blit Latency (48.75 Cycles per Store)

The software blit routine (`DG_DrawFrame` in `sw/doom/platform/doomgeneric_rv64.c`) transfers the 320x200 8-bit off-screen rendering buffer located in DDR3 to the on-chip VGA framebuffer at MMIO address `0x20000000`.

$$\text{Active Frame Buffer Pixels} = 320 \times 200 = 64,000\text{ bytes}$$

Because the framebuffer dual-port BRAM write port is byte-wide (8 bits), the blitter unpacks 64-bit words read from DDR and issues 64,000 separate store instructions (`SB`).

$$\text{Total Cycles Elapsed in Blit} = 31,200\text{ µs} \times 100\text{ MHz} = 3,120,000\text{ cycles}$$

$$\text{Cycle Cost per Byte Store} = \frac{3,120,000\text{ cycles}}{64,000\text{ stores}} = \mathbf{48.75\text{ cycles per store}}$$

### Why is an On-Chip SRAM Store Costing 48.75 Cycles?

The destination BRAM has a single-cycle write latency (`ready = 1` immediately). The reason the loop takes 48.75 cycles per store is that **the processor is fetch-bound**:
1. The blit loop instructions reside in DDR3 memory (`0x80100000+`).
2. Without an L1 instruction cache, the processor must fetch the loop body instructions (`LD`, `SRLI`, `SB`, `ADDI`, `BNE`) across the AXI3 bus from external DDR3 for every iteration.
3. Each sequential DDR3 AXI access experiences ~15–20 cycles of memory controller latency.
4. Consequently, the CPU spends 95% of the blit loop stalled on instruction fetch, proving that the blit is limited by front-end memory bandwidth rather than write bandwidth.

---

## 3. Why the Machine is Fetch-Bound

The DOOM engine spends **91.92%** of its frame time inside the software rasterizer (`R_DrawColumn`, `R_DrawSpan`, BSP tree traversal, and wall clipping).

- **High Instruction Fetch Pressure:**
  Every branch, jump, or line buffer miss forces a DDR round-trip across the `S_AXI_HP0` port.
- **Arbiter Contention:**
  When DOOM accesses textures and geometry data from DDR, the `ddr_request_arbiter` prioritizes data memory access. This starves the instruction fetch unit, causing front-end stalls to ripple backward through the entire pipeline.
- **ALU Throughput is Not the Bottleneck:**
  The hardware multiplier executes 64-bit multiplications in 3 cycles, and the ALU executes all standard arithmetic in 1 cycle. The core computes fast enough; it simply spends the vast majority of its execution cycles waiting for instructions to arrive from DDR3.

---

## 4. Prioritized Optimization Roadmap

### Tier 0: Expose Hardware Performance Counters to MMIO (Zero Hardware Cost)
The core already instantiates `perf_counters.v` internally, tracking:
- `perf_cycles`: Total elapsed clock cycles
- `perf_retired`: Total architectural instructions committed
- `perf_stalls`: Cycles where pipeline was frozen by hazard/memory stalls
- `perf_flushes`: Cycles consumed by branch/redirect pipeline flushes
- `perf_cpi_x100`: Calculated Cycles Per Instruction ($\times 100$)

**Action:** Connect these counter signals to the SoC interconnect at address `0x10001050`. This will allow software to directly measure the architectural CPI and stall breakdown without external logic analyzers.

---

### Tier 1: Implement an L1 Instruction Cache (Estimated 5x–10x Speedup $\to$ 13–26 FPS)
**The single most impactful architectural enhancement.**
- **Specification:**
  - Direct-mapped or 2-way set associative.
  - Size: 4 KB to 8 KB (fits comfortably within unused on-chip 7-series Block RAMs).
  - Line size: 32 bytes (4 words of 64 bits), utilizing AXI burst reads (`INCR4`).
- **Impact:**
  DOOM's inner rasterization loops (`R_DrawColumn` and `R_DrawSpan`) are tight routines of fewer than 50 instructions. Once resident in cache, inner loop fetches will execute with **0-cycle penalty**.
- **Expected Frame Rate:** **13 to 26 FPS**, achieving near-arcade fluid gameplay.

---

### Tier 2: Widen Framebuffer Write Port to 64-Bit with Byte Strobes
Currently, `framebuffer_mmio.v` receives `mmio_wstrb[7:0]`, but `framebuffer_dp_ram.v` is configured with an 8-bit data width, requiring 64,000 separate store instructions.
- **Action:**
  Configure `framebuffer_dp_ram` as a 64-bit wide RAM with 8 individual byte write enables (`WREN[7:0]`).
- **Software Modification:**
  The blit loop can write 64-bit doublewords directly (`SD`), reducing total store operations from 64,000 to **8,000 stores per frame** (8x reduction).
- **Impact:** Cuts framebuffer blit time from 31.2 ms down to ~4 ms.

---

### Tier 3: Add a Store Buffer and Texture Read Cache (D-Cache)
- A 4-entry coalescing write buffer to decouple store latency from LSU stalls.
- A 2 KB direct-mapped D-cache for read-only texture and palette lookup tables.

---

### Tier 4: Software-Only Optimizations (Zero Hardware Changes)
1. **Compiler Optimization Flags:**
   Benchmark compiling with `-Os` (optimize for size) versus `-O2`. On a fetch-bound processor without an I-cache, smaller binary footprint often outperforms aggressive unrolling because it reduces DDR fetch traffic.
2. **Loop Alignment:**
   Apply `-falign-loops=8` to align branch targets with 64-bit fetch boundaries.
3. **DOOM Low-Detail Mode:**
   Toggle DOOM's native low-detail rasterizer (`detailLevel = 1`), which renders pixels as 2x2 blocks. This cuts texture fetch operations in half.
4. **Selective HUD Redraw:**
   Skip redrawing the status bar (`ST_Drawer`) on frames where health, armor, and ammo have not changed.

---

### Tier 5: Fabric Clock Frequency Scaling
Timing analysis on the ZedBoard (`xc7z020clg484-1`) reports `WNS = +0.42 ns` at 100 MHz. While the fabric can be scaled to 110–120 MHz, clock scaling yields only sublinear improvements while the processor remains bottlenecked by DDR3 latency. Fabric frequency should be increased only after implementing the L1 instruction cache.
