# ============================================================================
# File: create_project.tcl
# Description: Automated Vivado flow for RV64IM DOOM SoC on ZedBoard
# Builds complete Vivado project from source and generates bitstream.
# Target: Xilinx Zynq-7000 XC7Z020-CLG484-1
# Usage:
#   vivado -mode batch -source scripts/vivado/create_project.tcl
#   vivado -mode batch -source scripts/vivado/create_project.tcl -tclargs <name> <dir> <MHz>
#
# The third argument selects the fabric clock: 100, 75 or 50 MHz.
#
#   100  runs straight off the ZedBoard's Y9 oscillator.
#    75  and 50 derive the clock from an MMCM (see rtl/soc/clk_gen.v). Both
#        divide to exactly 25 MHz for VGA, so display timing is unchanged;
#        60 MHz is not offered because it cannot produce 25 MHz by any integer
#        divide.
#
# CLK_HZ must track the real clock or timer_mmio's microsecond prescaler is
# wrong, which silently corrupts the on-board frame-rate measurement.
# ============================================================================

set project_name "rv64im_doom_soc_proj"
set target_part  "xc7z020clg484-1"
set origin_dir   [file normalize [file dirname [info script]]/../..]
set build_dir    "$origin_dir/build"

# Parse optional arguments: -tclargs <project_name> <output_dir>
if { $argc > 0 } {
    set project_name [lindex $argv 0]
}
if { $argc > 1 } {
    set build_dir [file normalize [lindex $argv 1]]
}

# Fabric clock selection -> top-level generics on doom_soc_top.
set target_mhz 100
if { $argc > 2 } {
    set target_mhz [lindex $argv 2]
}
switch -- $target_mhz {
    100     { set soc_generics {USE_MMCM=0 CLK_HZ=100000000 PIXEL_DIV=4} }
    75      { set soc_generics {USE_MMCM=1 CLK_HZ=75000000  PIXEL_DIV=3 CLKOUT_DIV=12} }
    50      { set soc_generics {USE_MMCM=1 CLK_HZ=50000000  PIXEL_DIV=2 CLKOUT_DIV=18} }
    default {
        puts "ERROR: unsupported clock '$target_mhz'. Choose 100, 75 or 50."
        exit 1
    }
}

file mkdir $build_dir
set proj_dir "$build_dir/$project_name"

puts "=================================================================="
puts "  BUILDING RV64IM DOOM SOC FOR ZEDBOARD (XC7Z020 @ $target_mhz MHz)"
puts "  Generics: $soc_generics                                          "
puts "  Repository Root: $origin_dir                                    "
puts "  Project Directory: $proj_dir                                    "
puts "=================================================================="

# 1. Create project
create_project $project_name $proj_dir -part $target_part -force
set_property target_language Verilog [current_project]

# 2. Add RTL Sources
add_files -norecurse [glob -nocomplain "$origin_dir/rtl/core/*.v"]
add_files -norecurse [glob -nocomplain "$origin_dir/rtl/soc/*.v"]
add_files -norecurse [glob -nocomplain "$origin_dir/rtl/peripherals/*.v"]

# 3. Add Memory Initialization Files for BRAM ($readmemh)
if {[file exists "$origin_dir/sw/build/instructions.mem"]} {
    add_files -norecurse "$origin_dir/sw/build/instructions.mem"
    set_property file_type {Memory Initialization Files} [get_files *instructions.mem]
}
if {[file exists "$origin_dir/data.mem"]} {
    add_files -norecurse "$origin_dir/data.mem"
    set_property file_type {Memory Initialization Files} [get_files *data.mem]
}

# 4. Add Physical Pin & Timing Constraints
add_files -fileset constrs_1 -norecurse "$origin_dir/constraints/doom_soc_zedboard.xdc"

# 4. Add Simulation Sources
add_files -fileset sim_1 -norecurse [glob -nocomplain "$origin_dir/sim/tb/*.v"]
add_files -fileset sim_1 -norecurse [glob -nocomplain "$origin_dir/sim/models/*.v"]

# 5. Programmatically create PS7 Block Design with S_AXI_HP0
create_bd_design "ps7_zed"
set ps7_cell [create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 ps7]
source "$origin_dir/scripts/vivado/ps7_preset.tcl"
configure_zedboard_ps7 $ps7_cell

catch {
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config {make_external "FIXED_IO, DDR" apply_board_preset "1" Master "Disable" Slave "Disable"} \
        [get_bd_cells ps7]
}

generate_target all [get_files *ps7_zed.bd]
make_wrapper -files [get_files *ps7_zed.bd] -top -import

# 6. Set top module and the clock generics chosen above
set_property top doom_soc_top [current_fileset]
set_property generic $soc_generics [get_filesets sources_1]
set_property top tb_doom_min [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

# 7. Synthesis with rebuilt hierarchy
puts "\n---> Step 1: Synthesizing Design..."
set_property -name {STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY} -value {rebuilt} -objects [get_runs synth_1]
launch_runs synth_1 -jobs 8
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

# 8. Implementation with timing optimization
puts "\n---> Step 2: Implementing Design & Closing Timing @ $target_mhz MHz..."
set_property STRATEGY Performance_Explore [get_runs impl_1]
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation failed!"
    exit 1
}

# 9. Timing & Utilization Summary
open_run impl_1
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]

puts "=================================================================="
puts "  IMPLEMENTATION & BITSTREAM GENERATION COMPLETE                  "
puts "  Final WNS (Setup Slack) : $wns ns"
puts "  Final WHS (Hold Slack)  : $whs ns"
puts "=================================================================="

# Copy final bitstream
set bit_file [glob -nocomplain "$proj_dir/${project_name}.runs/impl_1/*.bit"]
if {[file exists [lindex $bit_file 0]]} {
    if {$target_mhz == 100} {
        set out_bit "$build_dir/doom_soc_top.bit"
    } else {
        set out_bit "$build_dir/doom_soc_top_${target_mhz}mhz.bit"
    }
    file copy -force [lindex $bit_file 0] $out_bit
    puts "  Bitstream copied to: $out_bit"
}
