# RV64IM DOOM SoC — Memory Map & Register Specification

The RV64IM processor uses a unified 64-bit physical address space spanning on-chip SRAMs, memory-mapped peripherals, the VGA framebuffer, and external DDR3 memory.

---

## 1. System Memory Map Summary

| Region Name | CPU Address Range | Physical Address (DDR3) | Size | Access | Description |
|---|---|---|---|---|---|
| **Boot BRAM** (instruction) | `0x0000_0000` – `0x0000_1FFF` | Internal BRAM | 8 KB | R/X | On-chip diagnostic bootloader & self-tests |
| **Local Data RAM** | `0x0000_0000` – `0x0000_1FFF` | Internal BRAM | 8 KB | R/W | Bootloader `.data` / `.bss` / stack — see note below |
| **GPIO MMIO** | `0x1000_1000` – `0x1000_100F` | Peripheral Register | 16 B | R/W | 8x LEDs (out), 8x Switches (in), 5x Buttons (in) |
| **Timer MMIO** | `0x1000_1018` – `0x1000_1027` | Peripheral Register | 16 B | R | 64-bit cycle counter & 64-bit microsecond timer |
| **AXI Telemetry** | `0x1000_1030` – `0x1000_103F` | Peripheral Register | 16 B | R | Last AR/B response status & read/write transaction counts |
| **UART MMIO** | `0x1000_4000` – `0x1000_400F` | Peripheral Register | 16 B | R/W | 115200 Baud 8N1 serial console transceiver |
| **VGA Framebuffer** | `0x2000_0000` – `0x2000_FFFF` | Dual-Port BRAM | 64 KB | W | 320x200x8bpp pixel memory (64,000 active bytes) |
| **Palette RAM** | `0x2001_0000` – `0x2001_07FF` | Dual-Port BRAM | 2 KB | W | 256 entries x 24-bit RGB (8-byte stride per color) |
| **DOOM Binary** | `0x8010_0000` – `0x8023_BB27` | `0x0010_0000` | ~1.3 MB | R/W/X | DOOM `.text`, `.rodata`, `.data`, `.bss` |
| **Debug Stage** | `0x8051_0000` – `0x8051_0007` | `0x0051_0000` | 8 B | R/W | Persistent milestone breadcrumb (survives warm CPU resets) |
| **Perf Block** | `0x8053_0000` – `0x8053_0037` | `0x0053_0000` | 56 B | R/W | Frame-rate telemetry block (FPS, frames, blit µs, magic) |
| **Stack Space** | grows down from `0x80FF_FFF0` | `0x00FF_FFF0` | — | R/W | Bare-metal C stack (`__stack_top` in `linker_ddr.ld`) |
| **In-Memory WAD** | `0x8100_0000` – `0x8140_0533` | `0x0100_0000` | 4.19 MB | R | In-memory `DOOM1.WAD` shareware game asset lump file |
| **Zone Memory Heap**| `0x8200_0000` – `0x82FF_FFFF` | `0x0200_0000` | 16 MB | R/W | DOOM dynamic memory allocator (`Z_Init` zone pool) |

> **Boot BRAM and Local Data RAM share one address range.** The core is a
> Harvard split below `0x1000_0000`: instruction fetch is served by the
> 8 KB array inside `instruction_fetch_unit.v` (initialised from
> `instructions.mem`) and loads/stores are served by the separate 8 KB array in
> `Data_Memory.v` (initialised from `data.mem`). `Data_Memory` decodes only
> `addr[12:0]`, so the region aliases every 8 KB up to `0x0FFF_FFFF`.
> `sw/linker/linker.ld` places the bootloader's `.text`, `.rodata`, `.data`,
> `.bss` and stack inside this single 8 KB window.

> **`0x1000_1040` is not reachable.** The interconnect's GPIO decode
> (`is_gpio`) tests only `addr[5:4] == 2'b00` and therefore also matches
> `0x40`–`0x4F`, shadowing the AXI `last_rdata` register that
> `soc_interconnect.v` decodes there. The GPIO input register wins the read
> mux. Reads of `0x1000_1040` return switch/button state, not AXI read data.

---

## 2. Register-Level Bit Definitions

### 2.1 GPIO MMIO (`0x1000_1000`)

Inputs and the LED register are **two separate registers**, not two fields of one.

```
Offset 0x00: GPIO_INPUT (Read-Only)
┌───────────────────────────┬──────────────┬─────────────┐
│ Bits [63:13]              │ Bits [12:8]  │ Bits [7:0]  │
├───────────────────────────┼──────────────┼─────────────┤
│ Reserved (0)              │ BTN[4:0]     │ SW[7:0]     │
└───────────────────────────┴──────────────┴─────────────┘

Offset 0x08: GPIO_LED (Read / Write)
┌───────────────────────────────────────────┬─────────────┐
│ Bits [63:8]                               │ Bits [7:0]  │
├───────────────────────────────────────────┼─────────────┤
│ Reserved (0)                              │ LED[7:0]    │
└───────────────────────────────────────────┴─────────────┘
```

- `SW[7:0]` (`+0x00`, bits 7:0): the 8 slide switches (`SW0`–`SW7`), double-flop synchronised.
- `BTN[4:0]` (`+0x00`, bits 12:8): pushbuttons, double-flop synchronised, in ZedBoard XDC port order:
  - Bit 8: Up (`BTNU`, pin T18)
  - Bit 9: Left (`BTNL`, pin N15)
  - Bit 10: Right (`BTNR`, pin R18)
  - Bit 11: Down (`BTND`, pin R16)
  - Bit 12: tied to `0` — `BTNC` is wired to the top-level `reset` port, not to GPIO
- `LED[7:0]` (`+0x08`, bits 7:0): the 8 green LEDs (`LD0`–`LD7`).

> The physical LEDs are muxed at the top level: with `SW7` **down** they show
> this register; with `SW7` **up** they show live `current_pc[9:2]`.

### 2.2 Timer MMIO (`0x1000_1018`)

- **`0x1000_1018` — `TIMER_CYCLES` (64-bit Read-Only):**
  Free-running counter incrementing once per fabric clock (10.0 ns per tick in the 100 MHz build).
- **`0x1000_1020` — `TIMER_US` (64-bit Read-Only):**
  Microsecond timer, prescaled by `CLK_HZ / 1_000_000` (100 at 100 MHz, 75 at
  75 MHz, 50 at 50 MHz) so a tick is 1.0 µs at every supported fabric clock.
  Used by `DG_GetTicksMs()` and by all frame-rate measurement.

> `timer_mmio` takes its divisor from the `CLK_HZ` parameter threaded down from
> `doom_soc_top`. `scripts/vivado/create_project.tcl` sets `CLK_HZ` alongside
> `USE_MMCM` and `PIXEL_DIV` for each target, so the microsecond tick stays
> correct across the 100/75/50 MHz builds — which is what makes the
> multi-frequency benchmark comparable.

### 2.3 UART MMIO (`0x1000_4000`)

The UART decodes on `addr[3]` only: `+0x00`–`+0x07` is the data register, `+0x08`–`+0x0F` is status.

- **`0x1000_4000` — `UART_DATA` (Read/Write, byte in bits [7:0]):**
  Write: enqueues a character into the 16-deep TX FIFO. Read: **pops** a character from the RX FIFO.
- **`0x1000_4008` — `UART_STATUS` (Read-Only):**
  - Bit 0: `TX_FULL` (TX FIFO cannot accept another byte)
  - Bit 1: `TX_EMPTY` (TX FIFO drained)
  - Bit 2: `RX_EMPTY` (no received byte available)
  - Bit 3: `RX_FULL` (RX FIFO full)

> Reading `0x1000_4004` does **not** return status — `addr[3]` is 0, so it
> decodes as `UART_DATA` and pops the RX FIFO. Use `+0x08`, as `soc_regs.h` does.

> The UART block is instantiated but its TX/RX pins are not brought out in
> `doom_soc_zedboard.xdc` (no Pmod USB-UART on the bring-up bench). All
> diagnostic output goes to the VGA text console instead.

### 2.4 VGA Palette RAM (`0x2001_0000`)

The hardware palette table is addressed with an **8-byte stride per color index** (`index << 3`):

$$\text{MMIO Address} = \text{0x2001\_0000} + (\text{Color Index} \times 8)$$

```
Offset (index * 8): PALETTE_COLOR_ENTRY   —   0x00RRGGBB
┌───────────────┬──────────────┬──────────────┬──────────────┐
│ Bits [63:24]  │ Bits [23:16] │ Bits [15:8]  │ Bits [7:0]   │
├───────────────┼──────────────┼──────────────┼──────────────┤
│ Reserved (0)  │ Red [7:0]    │ Green [7:0]  │ Blue [7:0]   │
└───────────────┴──────────────┴──────────────┴──────────────┘
```

Red occupies the **most** significant channel byte. This matches
`framebuffer_mmio.v` (`vga_r = pixel_rgb[23:20]`, `vga_b = pixel_rgb[7:4]`), the
`24'hRRGGBB` power-on PLAYPAL table, and the write in `I_SetPalette`:

```c
hw_palette[i] = ((uint64_t)colors[i].r << 16)
              | ((uint64_t)colors[i].g <<  8)
              |  (uint64_t)colors[i].b;
```

The port is **write-only** — DOOM never reads the palette back. Writing a 64-bit
value updates the entry on the next clock; the VGA scanout samples this RAM
combinationally during active display lines. Only the top 4 bits of each channel
reach the ZedBoard's 12-bit RGB444 VGA connector.

### 2.5 Software Performance Telemetry Block (`0x8053_0000`)

Located in physical DDR3 at `0x0053_0000` (`0x8053_0000` CPU space), this 56-byte structure is updated every 32 frames by `doomgeneric_rv64.c` and is read by JTAG scripts (`scripts/jtag/read_fps.tcl`):

| Offset | Field Name | Type | Description |
|---|---|---|---|
| `+0x00` | `fps_x100` | `uint64_t` | Frame rate scaled by 100 over the last 32 frames (e.g. `259` = 2.59 FPS) |
| `+0x08` | `frame_count` | `uint64_t` | Total frames rendered since startup |
| `+0x10` | `frame_time_us` | `uint64_t` | Average frame duration over the last 32 frames in microseconds |
| `+0x18` | `blit_time_us` | `uint64_t` | Average framebuffer blit duration over the last 32 frames in microseconds |
| `+0x20` | `magic` | `uint64_t` | Magic identifier: `0x50455246` (`"PERF"`) |
| `+0x28` | `elapsed_run_us`| `uint64_t` | Total elapsed microseconds since the first rendered frame |
| `+0x30` | `blit_run_us` | `uint64_t` | Cumulative blit duration across the entire run in microseconds |

---

## 3. Address Decoding & Alignment Rules

1. **Subword Access Alignment:**
   - Byte accesses (`LB`, `LBU`, `SB`): Any byte boundary.
   - Halfword accesses (`LH`, `LHU`, `SH`): Aligned to 2-byte boundary (`addr[0] == 0`).
   - Word accesses (`LW`, `LWU`, `SW`): Aligned to 4-byte boundary (`addr[1:0] == 00`).
   - Doubleword accesses (`LD`, `SD`): Aligned to 8-byte boundary (`addr[2:0] == 000`).
2. **Unaligned Memory Access Policy:**
   Unaligned accesses in software are handled by compiler-generated byte sequence unpack routines; hardware does not generate traps. Misaligned multi-byte accesses are **not** supported: `load_store_unit.v` builds the strobe as `wstrb << addr[2:0]`, so a store that straddles an 8-byte boundary has its high bytes shifted out and silently dropped. All software here is compiled with naturally-aligned accesses only.
3. **Physical Address Translation:**
   CPU accesses to the `0x8000_0000` space are translated in hardware by
   `native_axi_master.v`, which simply clears bit 31:

   ```verilog
   wire [31:0] phys_addr = {1'b0, req_addr[30:3], 3'b000};
   ```

   $$\text{AXI\_ADDR} = \text{CPU\_ADDR} - \text{0x8000\_0000}$$

   So `0x8010_0000` (CPU) lands at `0x0010_0000` in PS DDR3, `0x8053_0000` at
   `0x0053_0000`, and `0x8100_0000` at `0x0100_0000`. This is the mapping the
   JTAG tooling assumes — `program_and_load.tcl` downloads the DOOM binary to
   `0x00100000` and the WAD to `0x01000000`, and `read_fps.tcl` reads the perf
   block at `0x00530000`.

   Note that AXI addresses are forced 8-byte aligned (`[2:0]` zeroed); byte
   lanes are selected by `WSTRB` on writes and by the LSU on reads.
