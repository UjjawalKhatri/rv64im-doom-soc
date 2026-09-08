# RV64IM DOOM SoC — Hardware Architecture Specification

This document details the microarchitecture of the custom 64-bit RISC-V (RV64IM) processor and system-on-chip designed to run bare-metal id Software DOOM on the Digilent ZedBoard (Xilinx Zynq-7000 XC7Z020-CLG484-1 FPGA).

---

## 1. Top-Level System Architecture

The SoC integrates a custom in-order 5-stage RV64IM processor core, an AXI3 high-performance memory subsystem, on-chip SRAMs, memory-mapped peripherals, and an autonomous dual-port VGA display controller.

### Top-Level Structural Block Diagram

```mermaid
graph TD
    subgraph Core ["RV64IM 5-Stage Core (100 MHz)"]
        IF["IF Stage<br/>PC & Line Buffer"] --> ID["ID Stage<br/>Decoder & RegFile"]
        ID --> EX["EX Stage<br/>64b ALU & Mul/Div"]
        EX --> MEM["MEM Stage<br/>Load/Store Unit"]
        MEM --> WB["WB Stage<br/>RegFile Commit"]
        HZ["Hazard Unit"] -. Stalls .-> IF
        HZ -. Stalls .-> ID
        FW["Forwarding Unit"] -. Operands .-> EX
    end

    subgraph MemoryFabric ["Memory Interconnect & Arbiter"]
        IC["soc_interconnect<br/>Address Decoder"]
        ARB["ddr_request_arbiter<br/>Fixed-Priority (D-Side First)"]
        AXIM["native_axi_master<br/>AXI3 64-bit Master"]
    end

    subgraph PS7 ["Xilinx Zynq PS7 & DDR3"]
        HP0["S_AXI_HP0 Port<br/>64-bit @ 100 MHz"]
        DDR["512 MB DDR3 DRAM<br/>Physical base: 0x0000_0000"]
    end

    subgraph Peripherals ["On-Chip Peripherals & Display"]
        BOOT["Boot BRAM (8 KB)<br/>0x0000_0000"]
        GPIO["GPIO MMIO<br/>LEDs / Switches / BTNs"]
        TMR["Timer MMIO<br/>64b Cycles & Microseconds"]
        UART["UART MMIO<br/>115200 8N1"]
        FB["Framebuffer DP-BRAM (64 KB)<br/>320x200x8bpp"]
        PAL["Palette RAM (2 KB)<br/>256x24-bit RGB"]
        VGA["VGA Controller<br/>640x480 @ 60 Hz (2x Scale)"]
    end

    IF -- "Instr Request" --> ARB
    MEM -- "Data Request" --> IC
    IC -- "DDR Requests" --> ARB
    IC -- "MMIO Requests" --> BOOT
    IC -- "MMIO Requests" --> GPIO
    IC -- "MMIO Requests" --> TMR
    IC -- "MMIO Requests" --> UART
    IC -- "MMIO Requests" --> FB
    IC -- "MMIO Requests" --> PAL
    ARB --> AXIM
    AXIM --> HP0
    HP0 --> DDR
    FB --> VGA
    PAL --> VGA
    VGA --> DAC["ZedBoard ADV7125 / Resistor DAC -> VGA Port"]
```

---

## 2. Processor Pipeline Architecture

The CPU is a classic 5-stage in-order RISC-V processor implementing the unprivileged `RV64I` base integer instruction set and the `M` standard extension for integer multiplication and division.

### 2.1 Pipeline Stages & Contracts

```mermaid
sequenceDiagram
    participant IF as Instruction Fetch (IF)
    participant ID as Instruction Decode (ID)
    participant EX as Execute (EX)
    participant MEM as Memory Access (MEM)
    participant WB as Writeback (WB)

    Note over IF: Fetches 32-bit instruction from Line Buffer or DDR.<br/>Computes sequential PC+4 or latches redirect target.
    IF->>ID: IF/ID Pipeline Register (Latches PC, Instruction)
    Note over ID: Decodes opcode, reads 32x64-bit RegFile,<br/>generates immediate, detects load-use hazards.
    ID->>EX: ID/EX Pipeline Register (Latches Operands & Controls)
    Note over EX: Executes ALU operations, branches, M-extension<br/>multiplies and divides (both multi-cycle).<br/>Absorbs forwarded operands when held.
    EX->>MEM: EX/MEM Pipeline Register (Latches Result, Store Data)<br/>Forces redirect_commit when branch/jump taken.
    Note over MEM: Formats load/store addresses, manages subword sign/zero<br/>extension, interfaces to SoC interconnect bus.
    MEM->>WB: MEM/WB Pipeline Register (Latches MemData or ALU Result)
    Note over WB: Writes committed result to architectural Register File.<br/>Updates hardware performance counters.
```

### 2.2 Pipeline Hazard & Forwarding Contracts

1. **Forwarding Paths:**
   - `EX/MEM` $\to$ `EX`: Resolves 1-cycle data hazards (ALU-to-ALU dependencies).
   - `MEM/WB` $\to$ `EX`: Resolves 2-cycle data hazards (ALU/Load-to-ALU dependencies).
   - `WB` $\to$ `MEM` store data (`ld_after_sd_forwarding`): when a store sitting in `MEM` sources its data from a register being written back this cycle (`wb_rd == mem_rs2`), the write-back value is substituted for the stale `mem_store_data`. This is what makes `ld`/`jal` immediately followed by a dependent `sd` commit the right value.

2. **Load-Use Interlock:**
   When an instruction in `ID` depends on a load currently in `EX` (`ex_mem_read == 1`, `ex_rd != x0`):
   - On `ex_rd == id_rs1`, the Hazard Unit always stalls.
   - On `ex_rd == id_rs2`, it stalls **unless** the consumer is itself a load or store. A dependent store does not need the value in `EX` — only as store data in `MEM` — where the `WB` $\to$ `MEM` path above supplies it, so the bubble is skipped.
   - When it stalls, it asserts `bubble_sel = 1` and de-asserts `pc_write` and `if_id_write`, injecting a NOP into `ID/EX` for one cycle while holding the dependent instruction in `ID`.

3. **Operand Absorption on Hold (Issue #8 Resolution):**
   When `fetch_stall` or `memory_stall` freezes the `ID/EX` pipeline register, active forwarding conditions from instructions in `MEM` or `WB` can expire as those producing instructions retire.
   - **Contract:** while `ID_EX` is held (`hold == 1`, `flush == 0`), it writes the *post-forwarding* operands back into itself every cycle:

     ```verilog
     end else begin          // held in EX
         ex_data1 <= fwd_data1;   // = alu_a_raw, the forwarding mux output
         ex_data2 <= fwd_data2;   // = alu_b_pre
     end
     ```

   - When no forwarding is active the mux already selects `ex_dataN`, so this is a harmless self-assign. When forwarding *is* active it makes the value permanent.
   - Once forwarding drops to `00` in a later stall cycle, `EX` reads the absorbed value instead of a stale register-file read, eliminating operand decay.

4. **Committing Redirect under Fetch Stall (Issue #7 Resolution):**
   When a control-flow transfer occurs (`JAL`, `JALR`, or taken branch):
   - The front-end is flushed (`flush_sig = redirect_taken`), and the PC redirects to the target.
   - If the front-end stalls on DDR fetch latency (`fetch_stall == 1`), `EX/MEM` must not be frozen.
   - **Contract:** The `redirect_commit` signal overrides `fetch_stall` for the `EX/MEM` write enable:
     $$\text{ex\_mem\_reg\_write\_en} = \neg\text{stall\_mem} \land (\neg\text{fetch\_stall} \lor \text{redirect\_commit})$$
   - This guarantees that link-register writebacks (`ra <= PC + 4`) are preserved and successfully reach `WB`.

---

## 3. DDR3 Memory Subsystem & Arbitration

The system uses the 512 MB on-board DDR3 DRAM connected to the Zynq Processing System (PS). Communication between the programmable logic (PL) and DDR controller passes through the 64-bit high-performance AXI3 slave port `S_AXI_HP0`.

```mermaid
graph LR
    IFU["Instruction Fetch Unit<br/>(64-bit Line Buffer)"] -- "i_req [63:0]" --> ARB["ddr_request_arbiter<br/>(Priority to LSU)"]
    LSU["Load/Store Unit<br/>(Byte Strobes)"] -- "d_req [63:0]" --> ARB
    ARB -- "ddr_req [63:0]" --> AXI["native_axi_master<br/>(Single-Outstanding)"]
    AXI -- "AXI3 64-bit HP0" --> PS7["Zynq PS7 HP0 & DDR Controller"]
    PS7 --> DDR["512 MB Physical DDR3"]
    ARB -. "i_rsp [63:0]" .-> IFU
    ARB -. "d_rsp [63:0]" .-> LSU
```

### 3.1 Structural Components

- **Instruction Fetch Unit (`rtl/core/instruction_fetch_unit.v`):**
  Integrates a single 64-bit line buffer holding one 8-byte-aligned pair of instructions. A fetch whose `pc[31:3]` matches the buffered line resolves in 0 cycles, so a straight-line pair of instructions costs one DDR round trip rather than two. Any other address is a miss: the unit asserts `fetch_stall`, requests the aligned 8-byte block from the DDR arbiter, and tags the request with an epoch bit so a response arriving after a branch redirect is discarded. This is a line buffer, not a cache — there is no tag array and no second entry, which is why the roadmap's L1 I-cache is the single largest available speedup.
- **Load/Store Unit (`rtl/core/load_store_unit.v`):**
  Generates 64-bit memory requests with 8-bit byte-enable strobes (`d_req_wstrb[7:0]`) for byte (`SB`), halfword (`SH`), word (`SW`), and doubleword (`SD`) stores. Handles sign-extension for `LB`, `LH`, `LW`, `LD` and zero-extension for `LBU`, `LHU`, `LWU`.
- **DDR Request Arbiter (`rtl/soc/ddr_request_arbiter.v`):**
  Multiplexes the asynchronous instruction fetch requests (`i_req`) and data memory requests (`d_req`).
  - **Policy:** Data requests are prioritized over instruction fetches to prevent the LSU from blocking the execution pipeline.
  - **Handshake Latch:** Uses an atomic `mem_ddr_completed` register to ensure that multi-cycle AXI completions assert `d_rsp_valid` for exactly one clock cycle, preventing spurious multiple releases.
- **Native AXI Master (`rtl/soc/native_axi_master.v`):**
  Translates native single-beat requests into AXI3 read/write transactions (`AW`, `W`, `B`, `AR`, `R`).
  - Implements a single-outstanding transaction state machine.
  - **Address Remapping:** Clears bit 31 of the CPU address, mapping the DDR window `0x8000_0000`–`0xFFFF_FFFF` onto physical PS DDR3 `0x0000_0000`–`0x7FFF_FFFF` (`phys_addr = {1'b0, req_addr[30:3], 3'b000}`). The low `[2:0]` bits are forced to zero because AXI3 `AxSIZE = 3'b011` requires 8-byte-aligned addresses; byte lanes are selected by `WSTRB` on writes and by the LSU on reads.

---

## 4. Video Display Pipeline & Framebuffer

```mermaid
graph LR
    CPU["CPU Blitter<br/>(0x2000_0000)"] -- "Byte Writes" --> FB["Dual-Port BRAM<br/>(64 KB, 320x200x8bpp)"]
    CPU -- "Palette Update<br/>(0x2001_0000)" --> PAL["Palette Dual-Port RAM<br/>(256 x 24b RGB888)"]
    FB -- "Pixel Index [7:0]" --> PAL
    VGA_GEN["VGA Timing Gen<br/>(640x480 @ 60Hz)"] -- "Read Addr (2x Scale)" --> FB
    PAL -- "RGB888 -> RGB444" --> DAC["12-bit ADV7125 DAC / Resistor Ladder"]
    DAC --> MON["VGA Monitor"]
```

### 4.1 Framebuffer Memory Architecture

- **True Dual-Port Block RAM (`rtl/peripherals/framebuffer_dp_ram.v`):**
  - **Capacity:** 64 KB (64,000 active bytes).
  - **Port A (CPU MMIO Write Path):**
    - Address: `0x2000_0000`–`0x2000_FA00`.
    - Clock: 100 MHz system clock (`clk`).
    - Write access: Byte-wide writes from CPU software blitter.
  - **Port B (VGA Scanout Read Path):**
    - Clock: 100 MHz domain with 25 MHz pixel-enable strobe (`pixel_tick`).
    - Read access: Continuous raster scan addressing. Zero contention or bus wait-states with CPU writes.

### 4.2 Hardware Palette RAM

- Located at MMIO base `0x2001_0000` (stride: 8 bytes per palette entry).
- Holds 256 color entries, each consisting of 24-bit RGB888:
  - Byte 0: Red intensity (`0x00`–`0xFF`)
  - Byte 1: Green intensity (`0x00`–`0xFF`)
  - Byte 2: Blue intensity (`0x00`–`0xFF`)
- **Dynamic Palette Updates:** Writing to `0x2001_0000 + (index * 8)` immediately updates the hardware lookup table. This powers in-game damage flashes (red tint), radiation suit effects (green tint), bonus item pickups (yellow tint), and gamma-correction ramps via `I_SetPalette()`.

### 4.3 Integer Scaling & Raster Timing (640x480 @ 60 Hz)

```
Horizontal Timing (25.000 MHz pixel clock, 31.25 kHz line rate):
├────── Active Video (640 px) ──────┤─ FP (16) ─├─ Sync (96) ─├─ BP (48) ─┤
│ 320 framebuffer pixels, 2x clocks │           │ (Negative)  │            │
└───────────────────────────────────┴───────────┴─────────────┴────────────┘

Vertical Timing (525 total lines, 59.52 Hz refresh rate):
├─ Top Border (40) ─┼───── Active DOOM Area (400) ─────┼─ Bot Border (40) ─┼─ FP (10) ─┼─ Sync (2) ─┼─ BP (33) ─┤
│ Solid Black       │ 200 rows displayed 2 lines each  │ Solid Black       │           │ (Negative) │           │
└───────────────────┴──────────────────────────────────┴───────────────────┴───────────┴────────────┴───────────┘
```

The pixel address into framebuffer RAM is derived combinationally:
$$\text{FB\_ADDR} = \left(\left\lfloor \frac{\text{pixel\_y} - 40}{2} \right\rfloor \times 320\right) + \left\lfloor \frac{\text{pixel\_x}}{2} \right\rfloor$$

When `pixel_y < 40` or `pixel_y \ge 440`, video output is clamped to black (`0x000`), achieving letterbox centering.

---

## 5. Clocking, Reset & Constraints

- **Primary Clock:** `FCLK_CLK0` (100.00 MHz) generated by the Zynq Processing System PLL.
- **Pixel Clock:** 25.00 MHz generated by an internal synchronous 2-bit counter in `vga_timing.v`, running in phase with the 100 MHz fabric clock.
- **Reset Network:** Active-low reset `FCLK_RESET0_N` from the PS7 combined with user center pushbutton `BTNC` (debounced and inverted).
- **Timing Constraints (`constraints/doom_soc_zedboard.xdc`):**
  - Clock period constraint: `10.0 ns` (100.00 MHz).
  - Target device: `xc7z020clg484-1`.
  - Achieved Worst Negative Slack (WNS): `+0.42 ns` (Timing Met, zero negative slack across all paths).
