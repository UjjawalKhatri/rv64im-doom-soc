# ============================================================================
# read_stage.tcl - DOOM crash forensics
# Reads persistent DDR3 markers AFTER a crash WITHOUT resetting the board.
# Run this right after DOOM crashes back to the boot screen:
#   C:\Xilinx\Vitis\2022.1\bin\xsdb.bat scripts/read_stage.tcl
# DO NOT run program_and_load.tcl first - that resets DDR3 and wipes the marker.
# ============================================================================

connect
after 500

# Use the CoreSight DAP (target 1): reads PHYSICAL DDR3, bypassing ARM caches
targets 1

puts "=================================================================="
puts "  DOOM CRASH FORENSICS - persistent markers in physical DDR3"
puts "=================================================================="
puts "DBG_STAGE  (last milestone) @ 0x00510000 : [mrd 0x00510000 1]"
puts "DOOM header (should be 00000093 00000113) @ 0x00100000 : [mrd 0x00100000 2]"
puts "WAD  header (should be IWAD ...)          @ 0x01000000 : [mrd 0x01000000 2]"
puts "Zone base                                 @ 0x02000000 : [mrd 0x02000000 2]"
puts "=================================================================="
puts "  Milestone legend (last value DOOM reached before the crash):"
puts "    0x00 / stale = crashed before main() even ran"
puts "    0x01 = entered DOOM main()  (in doomgeneric_Create / early startup)"
puts "    0x10 = DG_Init + I_InitGraphics done, entering D_DoomMain (WAD/R_Init/P_Init)"
puts "    0x21 = about to call Z_Init  (crash here = inside Z_Init body)"
puts "    0xA1 = Z_Init BODY finished, about to return (crash here = at the return/epilogue)"
puts "    0x22 = Z_Init returned cleanly, crashed later in D_DoomMain"
puts "    0x7F = reached DG_DrawFrame - first frame copy to the framebuffer"
puts "=================================================================="
