# ============================================================================
# measure_fps.tcl - take a COMPARABLE frame-rate measurement.
#
#   C:\Xilinx\Vitis\2022.1\bin\xsdb.bat scripts/measure_fps.tcl
#
# Why this exists
# ---------------
# read_fps.tcl gives you whatever the counters hold right now. That is fine for
# a liveness check, but useless for comparing two builds:
#
#   * PERF[0] covers only the last 32 frames. The same 75 MHz bitstream reported
#     6.57, 2.86, 3.30, 3.11, 2.80 and 6.18 FPS within a couple of minutes -
#     a 2.2x swing driven purely by what was on screen. The difference between
#     100 MHz and 50 MHz is about 1.4x, so scene variance swamps the effect.
#   * The whole-run average (PERF[5]) is scene-independent only once the run is
#     long enough. Read at 64 frames it is still dominated by the title screen.
#
# So this script waits until a fixed frame count and reports only then. Run it
# the same way for every bitstream and the numbers are comparable.
#
# Protocol - follow it identically for each build:
#   1. Program the bitstream, load doom_rv64.bin, boot into DOOM.
#   2. DO NOT TOUCH THE CONTROLS. Let the attract/demo loop play. Interactive
#      play is never reproducible; the demo loop is the same content every time.
#   3. Run this script. It blocks until TARGET_FRAMES and prints the average.
#
# The blit figure is the one to trust most: a fixed 64000-byte workload every
# frame, identical regardless of scene. It is the cleanest measure of how the
# fabric clock actually affects memory throughput.
# ============================================================================

set TARGET_FRAMES 1000
set POLL_SECONDS  10

connect
after 500
targets 1

proc rd {addr} { return [lindex [mrd -value $addr 1] 0] }

set PERF_FPS100  0x00530000
set PERF_FRAMES  0x00530008
set PERF_MAGIC   0x00530020
set PERF_ELAPSED 0x00530028
set PERF_RUNBLIT 0x00530030

if {[rd $PERF_MAGIC] != 0x50455246} {
    puts "PERF block is not live yet. Boot DOOM and let it render 32 frames first."
    exit
}
if {[rd $PERF_ELAPSED] == 0} {
    puts "This doom_rv64.bin predates PERF\[5\]. Rebuild the software (sw/build_doom.ps1)."
    exit
}

puts "=================================================================="
puts "  Waiting for $TARGET_FRAMES frames. Do not touch the controls."
puts "=================================================================="

set frames [rd $PERF_FRAMES]
while {$frames < $TARGET_FRAMES} {
    set elapsed [rd $PERF_ELAPSED]
    if {$elapsed > 0 && $frames > 0} {
        set rate [expr {($frames * 100000000) / $elapsed}]
        set eta  [expr {(($TARGET_FRAMES - $frames) * ($elapsed / $frames)) / 1000000}]
        puts [format "  %5d / %d frames   running avg %d.%02d FPS   ~%d s to go" \
              $frames $TARGET_FRAMES [expr {$rate/100}] [expr {$rate%100}] $eta]
    } else {
        puts [format "  %5d / %d frames" $frames $TARGET_FRAMES]
    }
    after [expr {$POLL_SECONDS * 1000}]
    set frames [rd $PERF_FRAMES]
}

set elapsed [rd $PERF_ELAPSED]
set runblit [rd $PERF_RUNBLIT]
set avg100  [expr {($frames * 100000000) / $elapsed}]
set avgft   [expr {$elapsed / $frames}]
set avgblit [expr {$runblit / $frames}]

puts ""
puts "=================================================================="
puts "  COMPARABLE MEASUREMENT"
puts "=================================================================="
puts [format "  Frames             : %d" $frames]
puts [format "  Wall time          : %.1f s" [expr {$elapsed / 1000000.0}]]
puts [format "  Average frame rate : %d.%02d FPS" [expr {$avg100/100}] [expr {$avg100%100}]]
puts [format "  Average frame time : %6d us" $avgft]
puts [format "    - blit to FB     : %6d us  (%2d%%)  <- fixed workload, trust this one" \
      $avgblit [expr {$avgblit*100/$avgft}]]
puts [format "    - render+logic   : %6d us  (%2d%%)" \
      [expr {$avgft-$avgblit}] [expr {($avgft-$avgblit)*100/$avgft}]]
puts "=================================================================="
puts "  Record this line for the build under test, then repeat the same"
puts "  procedure for the next bitstream."
puts "=================================================================="
