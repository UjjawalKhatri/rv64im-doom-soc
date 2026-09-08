# ============================================================================
# read_fps.tcl - read DOOM's live frame-rate counters over JTAG.
#
# Run this WHILE the game is running. It does NOT reset the board:
#   C:\Xilinx\Vitis\2022.1\bin\xsdb.bat scripts/read_fps.tcl
#
# The perf block is written by DG_DrawFrame() every 32 frames at
# CPU 0x8053_0000 == physical 0x0053_0000.
# ============================================================================
connect
after 500
targets 1

proc rd32 {addr} {
    set v [lindex [mrd -value $addr 1] 0]
    return $v
}

set magic [rd32 0x00530020]

puts "=================================================================="
puts "  DOOM on RV64IM SoC - live frame-rate"
puts "=================================================================="
if {$magic != 0x50455246} {
    puts "  PERF block not live yet (magic = 0x[format %08X $magic])."
    puts "  Start the game and let it render >= 32 frames, then re-run."
} else {
    set fps100 [rd32 0x00530000]
    set frames [rd32 0x00530008]
    set ftime  [rd32 0x00530010]
    set btime  [rd32 0x00530018]
    set rtime  [expr {$ftime - $btime}]
    puts [format "  Frame rate       : %d.%02d FPS" [expr {$fps100/100}] [expr {$fps100%100}]]
    puts [format "  Avg frame time   : %6d us" $ftime]
    if {$ftime > 0} {
        puts [format "    - blit to FB   : %6d us  (%2d%%)  64000 byte MMIO stores" \
              $btime [expr {$btime*100/$ftime}]]
        puts [format "    - render+logic : %6d us  (%2d%%)  R_RenderPlayerView etc." \
              $rtime [expr {$rtime*100/$ftime}]]
    }
    puts [format "  Frames rendered  : %d" $frames]

    # ---- whole-run average (PERF[5], PERF[6]) --------------------------------
    # The figures above cover only the last 32 frames and swing by more than 2x
    # with what is on screen. Use THIS block to compare builds at different
    # clock frequencies - it averages over every frame since boot.
    set elapsed [rd32 0x00530028]
    set runblit [rd32 0x00530030]
    if {$elapsed > 0 && $frames > 1} {
        puts "------------------------------------------------------------------"
        puts "  WHOLE-RUN AVERAGE  (use this to compare builds, not the above)"
        set avg100  [expr {($frames * 100000000) / $elapsed}]
        set avgft   [expr {$elapsed / $frames}]
        set avgblit [expr {$runblit / $frames}]
        puts [format "  Average frame rate : %d.%02d FPS  over %d frames / %.1f s"               [expr {$avg100/100}] [expr {$avg100%100}] $frames               [expr {$elapsed / 1000000.0}]]
        puts [format "  Average frame time : %6d us" $avgft]
        puts [format "    - blit to FB     : %6d us  (%2d%%)   fixed 64000-byte workload"               $avgblit [expr {$avgblit*100/$avgft}]]
        puts [format "    - render+logic   : %6d us  (%2d%%)   scene dependent"               [expr {$avgft-$avgblit}] [expr {($avgft-$avgblit)*100/$avgft}]]
    } else {
        puts "------------------------------------------------------------------"
        puts "  Whole-run average not available - this doom.bin predates PERF[5]."
        puts "  Rebuild the software to compare builds across clock frequencies."
    }
}
puts "=================================================================="
