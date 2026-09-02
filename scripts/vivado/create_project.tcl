# ============================================================================
# File: create_project.tcl
# Description: Automated Vivado flow for RV64IM DOOM SoC on ZedBoard
# Builds complete Vivado project from source and generates bitstream.
# Target: Xilinx Zynq-7000 XC7Z020-CLG484-1 @ 100 MHz
# Usage:
#   vivado -mode batch -source scripts/vivado/create_project.tcl
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

file mkdir $build_dir
set proj_dir "$build_dir/$project_name"

puts "=================================================================="
puts "  BUILDING RV64IM DOOM SOC FOR ZEDBOARD (XC7Z020 @ 100 MHz)       "
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

# 6. Set top module
set_property top doom_soc_top [current_fileset]
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
puts "\n---> Step 2: Implementing Design & Closing Timing @ 100 MHz..."
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
set tns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]

puts "=================================================================="
puts "  IMPLEMENTATION & BITSTREAM GENERATION COMPLETE                  "
puts "  Final WNS (Setup Slack) : $wns ns"
puts "  Final WHS (Hold Slack)  : $tns ns"
puts "=================================================================="

# Copy final bitstream
set bit_file [glob -nocomplain "$proj_dir/${project_name}.runs/impl_1/*.bit"]
if {[file exists [lindex $bit_file 0]]} {
    file copy -force [lindex $bit_file 0] "$build_dir/doom_soc_top.bit"
    puts "  Bitstream copied to: $build_dir/doom_soc_top.bit"
}
