# RV64IM DOOM SoC — Memory Map & Register Specification

The RV64IM processor uses a unified 64-bit physical address space spanning on-chip SRAMs, memory-mapped peripherals, the VGA framebuffer, and external DDR3 memory.

---

## 1. System Memory Map Summary

| Region Name | Virtual Address Range (CPU) | Physical Address (DDR3) | Size | Access | Description |
|---|---|---|---|---|---|
| **Boot BRAM** | `0x0000_0000` – `0x0000_1FFF` | Internal BRAM | 8 KB | R/W/X | On-chip diagnostic bootloader & self-tests |
| **Local Data RAM** | `0x0000_2000` – `0x0000_3FFF` | Internal BRAM | 8 KB | R/W | Scratchpad SRAM for bootloader variables |
| **GPIO MMIO** | `0x1000_1000` – `0x1000_100F` | Peripheral Register | 16 B | R/W | 8x LEDs (out), 8x Switches (in), 5x Buttons (in) |
| **Timer MMIO** | `0x1000_1018` – `0x1000_1027` | Peripheral Register | 16 B | R | 64-bit cycle counter & 64-bit microsecond timer |
| **AXI Telemetry** | `0x1000_1030` – `0x1000_1047` | Peripheral Register | 24 B | R | Read/write transaction counts & bus error status |
| **UART MMIO** | `0x1000_4000` – `0x1000_400F` | Peripheral Register | 16 B | R/W | 115200 Baud 8N1 serial console transceiver |
| **VGA Framebuffer** | `0x2000_0000` – `0x2000_FFFF` | Dual-Port BRAM | 64 KB | R/W | 320x200x8bpp pixel memory (64,000 active bytes) |
| **Palette RAM** | `0x2001_0000` – `0x2001_07FF` | Dual-Port BRAM | 2 KB | W | 256 entries x 24-bit RGB (8-byte stride per color) |
| **DOOM Binary** | `0x8010_0000` – `0x8050_FFFF` | `0x1010_0000` | ~4 MB | R/W/X | DOOM code segment (`.text`), `.rodata`, `.data`, `.bss` |
| **Debug Stage** | `0x8051_0000` – `0x8051_0007` | `0x1051_0000` | 8 B | R/W | Persistent milestone breadcrumb (survives warm CPU resets) |
| **Perf Block** | `0x8053_0000` – `0x8053_0027` | `0x1053_0000` | 40 B | R/W | Frame-rate telemetry block (FPS, frames, blit µs, magic) |
| **Stack Space** | `0x80FF_0000` – `0x80FF_FFFF` | `0x10FF_0000` | 64 KB | R/W | Bare-metal C stack (Initial Stack Pointer: `0x80FF_FFF0`) |
| **In-Memory WAD** | `0x8100_0000` – `0x8143_FFFF` | `0x1080_0000` | 4.19 MB | R | In-memory `DOOM1.WAD` shareware game asset lump file |
| **Zone Memory Heap**| `0x8200_0000` – `0x8300_0000` | `0x1200_0000` | 16 MB | R/W | DOOM dynamic memory allocator (`Z_Init` zone pool) |

---

## 2. Register-Level Bit Definitions

### 2.1 GPIO MMIO (`0x1000_1000`)

```
Offset 0x00: GPIO_DATA (Read / Write)
┌───────────────┬────────────┬─────────────┬─────────────┐
│ Bits [63:21]  │ Bits[20:16]│ Bits [15:8] │ Bits [7:0]  │
├───────────────┼────────────┼─────────────┼─────────────┤
│ Reserved (0)  │ BTN[4:0]   │ SW[7:0]     │ LED[7:0]    │
│               │ (Read-Only)│ (Read-Only) │ (Read/Write)│
└───────────────┴────────────┴─────────────┴─────────────┘
```

- `LED[7:0]` (Bits 7:0): Controls the 8 green LEDs (`LD0`–`LD7`).
- `SW[7:0]` (Bits 15:8): Reflects status of the 8 slide switches (`SW0`–`SW7`).
- `BTN[4:0]` (Bits 20:16): Reflects status of pushbuttons:
  - Bit 16: Center (`BTNC`)
  - Bit 17: Down (`BTND`)
  - Bit 18: Left (`BTNL`)
  - Bit 19: Right (`BTNR`)
  - Bit 20: Up (`BTNU`)

### 2.2 Timer MMIO (`0x1000_1018`)

- **`0x1000_1018` — `CYCLE_COUNT_LO` / `HI` (64-bit Read-Only):**
  Free-running 64-bit hardware clock cycle counter incrementing at 100.00 MHz (10.0 ns per tick).
- **`0x1000_1020` — `US_TIMER_LO` / `HI` (64-bit Read-Only):**
  Hardware microsecond timer incrementing every 100 clock cycles (1.0 µs per tick). Used by DOOM engine for `I_GetTime()` and benchmark calculations.

### 2.3 UART MMIO (`0x1000_4000`)

- **`0x1000_4000` — `UART_DATA` (8-bit Read/Write):**
  Write: Enqueues a character into the TX FIFO. Read: Dequeues a received character from the RX FIFO.
- **`0x1000_4004` — `UART_STATUS` (32-bit Read-Only):**
  - Bit 0: `TX_BUSY` (1 = TX shift register is active).
  - Bit 1: `RX_VALID` (1 = RX character available in receive buffer).

### 2.4 VGA Palette RAM (`0x2001_0000`)

The hardware palette table is addressed with an **8-byte stride per color index** (`index << 3`):

$$\text{MMIO Address} = \text{0x2001\_0000} + (\text{Color Index} \times 8)$$

```
Offset (index * 8): PALETTE_COLOR_ENTRY
┌───────────────┬──────────────┬──────────────┬──────────────┐
│ Bits [63:24]  │ Bits [23:16] │ Bits [15:8]  │ Bits [7:0]   │
├───────────────┼──────────────┼──────────────┼──────────────┤
│ Reserved (0)  │ Blue [7:0]   │ Green [7:0]  │ Red [7:0]    │
└───────────────┴──────────────┴──────────────┴──────────────┘
```

Writing a 32-bit or 64-bit value to this location updates the corresponding entry in the dual-port palette RAM. The VGA scanout hardware automatically samples this RAM during active display lines.

### 2.5 Software Performance Telemetry Block (`0x8053_0000`)

Located in physical DDR3, this 40-byte structure is updated at the end of each frame by `doomgeneric_rv64.c` and is read by JTAG scripts (`scripts/jtag/read_fps.tcl`):

| Offset | Field Name | Type | Description |
|---|---|---|---|
| `+0x00` | `magic` | `uint32_t` | Magic identifier: `0x50534644` (`"DFSP"`) |
| `+0x04` | `frame_count` | `uint32_t` | Total frames rendered since startup |
| `+0x08` | `fps_x100` | `uint32_t` | Frame rate scaled by 100 (e.g. `259` = 2.59 FPS) |
| `+0x0C` | `frame_time_us` | `uint32_t` | Total frame duration in microseconds |
| `+0x10` | `blit_time_us` | `uint32_t` | Framebuffer blit duration in microseconds |
| `+0x14` | `render_time_us`| `uint32_t` | 3D engine render & tick duration in microseconds |
| `+0x18` | `reserved[4]` | `uint32_t` | Future expansion (CPI, stall cycles) |

---

## 3. Address Decoding & Alignment Rules

1. **Subword Access Alignment:**
   - Byte accesses (`LB`, `LBU`, `SB`): Any byte boundary.
   - Halfword accesses (`LH`, `LHU`, `SH`): Aligned to 2-byte boundary (`addr[0] == 0`).
   - Word accesses (`LW`, `LWU`, `SW`): Aligned to 4-byte boundary (`addr[1:0] == 00`).
   - Doubleword accesses (`LD`, `SD`): Aligned to 8-byte boundary (`addr[2:0] == 000`).
2. **Unaligned Memory Access Policy:**
   Unaligned accesses in software are handled by compiler-generated byte sequence unpack routines; hardware does not generate traps, but misaligned multi-byte accesses will truncate lower address bits in the memory stage.
3. **Physical Address Translation:**
   CPU memory accesses to the `0x8000_0000` space are translated in hardware by `native_axi_master.v`:
   $$\text{AXI\_ADDR} = \text{CPU\_ADDR} - \text{0x7000\_0000}$$
   This places `0x8010_0000` (CPU) cleanly at `0x1010_0000` (Physical DDR3).
