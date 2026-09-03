#!/usr/bin/env python3
# ============================================================================
# File: extract_playpal.py
# Description: Extracts the 256-color PLAYPAL palette lump from a DOOM WAD
# and formats it as Verilog palette assignments for framebuffer_mmio.v.
# ============================================================================

import sys
import struct
import argparse

def extract_palette(wad_path, palette_idx=0):
    with open(wad_path, 'rb') as f:
        wad = f.read()

    if len(wad) < 12:
        print("Error: File is too small to be a valid WAD.", file=sys.stderr)
        sys.exit(1)

    magic = wad[0:4].decode('ascii', errors='ignore')
    if magic not in ('IWAD', 'PWAD'):
        print(f"Error: Invalid WAD magic: {magic}", file=sys.stderr)
        sys.exit(1)

    numlumps, infotableofs = struct.unpack('<II', wad[4:12])

    playpal_offset = None
    for i in range(numlumps):
        entry = wad[infotableofs + i*16 : infotableofs + (i+1)*16]
        filepos, size, name = struct.unpack('<II8s', entry)
        lump_name = name.split(b'\x00')[0].decode('ascii', errors='ignore')
        if lump_name == 'PLAYPAL':
            playpal_offset = filepos
            break

    if playpal_offset is None:
        print("Error: PLAYPAL lump not found in WAD.", file=sys.stderr)
        sys.exit(1)

    palette_start = playpal_offset + (palette_idx * 256 * 3)
    raw_palette = wad[palette_start : palette_start + 256 * 3]

    print(f"// ============================================================================")
    print(f"// DOOM PLAYPAL Palette {palette_idx} (Extracted from {wad_path})")
    print(f"// Format: 256 entries x 24-bit RGB ({{R[7:0], G[7:0], B[7:0]}})")
    print(f"// ============================================================================")
    for c in range(0, 256, 4):
        line = []
        for k in range(4):
            idx = c + k
            r, g, b = raw_palette[idx*3 : (idx+1)*3]
            line.append(f"palette[{idx:3d}] = 24'h{r:02X}{g:02X}{b:02X};")
        print(" ".join(line))

def main():
    parser = argparse.ArgumentParser(description="Extract PLAYPAL palette from DOOM WAD.")
    parser.add_argument("wad", nargs="?", default="sw/doom/doom1.wad", help="Path to DOOM WAD file")
    parser.add_argument("--palette", type=int, default=0, help="Palette index (0 = default normal palette)")
    args = parser.parse_args()

    extract_palette(args.wad, args.palette)

if __name__ == "__main__":
    main()
