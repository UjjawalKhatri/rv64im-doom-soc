# ============================================================================
# File: program_and_load.tcl
# Description: Combined XSDB JTAG Script:
#              1. System Reset PS7 & PL
#              2. Initialize PS7 DDR3 Controller (ps7_init)
#              3. Program FPGA Bitstream (doom_soc_top.bit)
#              4. Load DOOM Binary -> DDR3 @ 0x00100000 (via CoreSight DAP)
#              5. Load DOOM1.WAD -> DDR3 @ 0x01000000 (via CoreSight DAP)
#              6. Release PL Reset (ps7_post_config)
# ============================================================================

connect
after 1000

# Helper to find file in common relative locations
proc find_file {candidates desc} {
    foreach path $candidates {
        if {[file exists $path]} {
            return $path
        }
    }
    puts "WARNING: Could not find $desc. Searched: $candidates"
    return [lindex $candidates 0]
}

set ps7_init_file [find_file [list "scripts/jtag/ps7_init.tcl" "ps7_init.tcl" "../jtag/ps7_init.tcl"] "ps7_init.tcl"]
set bit_file      [find_file [list "build/doom_soc_top.bit" "doom_soc_top.bit" "../../build/doom_soc_top.bit"] "bitstream"]
set bin_file      [find_file [list "sw/build/doom_rv64.bin" "doom_rv64.bin" "../../sw/build/doom_rv64.bin"] "DOOM binary"]
# sw/doom/doom1.wad is where tools/get_wad.ps1 puts it; the rest are fallbacks
# for a manually placed copy.
set wad_file      [find_file [list "sw/doom/doom1.wad" \
                                   "doom1.wad" \
                                   "sw/doom/doomgeneric/doom1.wad" \
                                   "../../sw/doom/doom1.wad" \
                                   "../../doom1.wad"] "DOOM1.WAD"]

# Step 1: System Reset into clean state
puts "=================================================================="
puts "  Step 1: System Resetting PS7 and PL..."
puts "=================================================================="
targets -set -filter {name =~ "ARM*#0"}
rst -system
after 1000

# Step 2: Initialize PS7 DDR Controller
puts "=================================================================="
puts "  Step 2: Initializing PS7 DDR Controller with $ps7_init_file..."
puts "=================================================================="
source $ps7_init_file
ps7_init
after 500

# Step 3: Program FPGA while PL reset is still asserted
puts "=================================================================="
puts "  Step 3: Programming FPGA Fabric with $bit_file..."
puts "=================================================================="
targets -set -filter {name =~ "xc7z020*"}
fpga $bit_file
after 500

# Step 4: Load DOOM Binary and WAD to DDR3 via CoreSight DAP (bypasses ARM cache)
puts "=================================================================="
puts "  Step 4: Loading DOOM Binary -> DDR3 @ 0x00100000 ($bin_file)..."
puts "=================================================================="
targets -set -filter {name =~ "CoreSight DAP*"}
dow -data $bin_file 0x00100000

puts "=================================================================="
puts "  Step 5: Loading DOOM1.WAD -> DDR3 @ 0x01000000 ($wad_file)..."
puts "=================================================================="
dow -data $wad_file 0x01000000

# Step 6: Verify DDR3 Contents
puts "=================================================================="
puts "  Step 6: Verifying DDR3 Contents via JTAG..."
puts "=================================================================="
puts "Binary Header: [mrd 0x00100000 4]"
puts "WAD Header:    [mrd 0x01000000 4]"

# Step 7: Release PL (ps7_post_config unlocks level shifters and deasserts FCLK_RESET0_N)
puts "=================================================================="
puts "  Step 7: Releasing PL Reset & Enabling Level Shifters..."
puts "=================================================================="
targets -set -filter {name =~ "ARM*#0"}
ps7_post_config
after 500

puts "=================================================================="
puts "  ALL DONE! Press BTND or flip SW0 to launch DOOM!"
puts "=================================================================="
