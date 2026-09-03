# DOOM Source Engine Port & Provenance

This directory contains the DOOM source code adapted for the bare-metal RV64IM ZedBoard SoC.

## Provenance & Licences

1. **Original DOOM**:
   - Copyright (C) 1993-1996 by **id Software, Inc.**
   - Released under the **GNU General Public License v2.0 (GPL-2.0)**.
2. **Chocolate Doom**:
   - Copyright (C) 2005-2014 by **Simon Howard** and contributors.
   - Clean-room historical preservation and refactoring under GPL-2.0.
3. **DoomGeneric**:
   - Developed by **ozkl** as a lightweight, single-file platform abstraction layer for DOOM.
4. **RV64IM ZedBoard Platform Layer** (`platform/`):
   - Developed as part of the RV64IM DOOM SoC project.
   - Connects the DoomGeneric API (`DG_DrawFrame`, `DG_GetKey`, `DG_GetTicksMs`, `DG_SleepMs`) to the custom RV64IM memory-mapped I/O peripherals:
     - 320x200 8-bit Framebuffer at `0x2000_0000`
     - Hardware Palette RAM at `0x2001_0000`
     - 64-bit Microsecond Timer at `0x1000_1018`
     - GPIO Buttons & Switches at `0x1000_1000`

## Game Assets (IWAD)

Under id Software's licensing terms, the game code is open-source (GPL-2.0), but the game data files (`.wad`) are proprietary copyrighted assets.

- To run this port, obtain the legal shareware IWAD (`doom1.wad`).
- You can run `tools/get_wad.ps1` to download the shareware WAD automatically, or copy your own purchased `doom.wad` / `doom2.wad` into this directory.
- `*.wad` files are explicitly excluded from this git repository via `.gitignore`.
