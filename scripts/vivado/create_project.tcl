# ============================================================================
# File: create_project.tcl
# Description: Builds a complete, openable Vivado project for the RV64IM
#              DOOM SoC on the Digilent ZedBoard (Xilinx XC7Z020-CLG484-1).
#
# Usage:
#   # 1. Project only (~1 min). Browse sources, RTL schematic, elaborate.
#   vivado -mode batch -source scripts/vivado/create_project.tcl -tclargs \
#          rv64im_doom_soc_proj build 50 setup
#
#   # 2. Project + synthesis + implementation (~20-40 min).
#   #    Gives Device view, timing summary and utilization.
#   vivado -mode batch -source scripts/vivado/create_project.tcl -tclargs \
#          rv64im_doom_soc_proj build 50 impl
#
#   # 3. As above, plus a bitstream.
#   vivado -mode batch -source scripts/vivado/create_project.tcl -tclargs \
#          rv64im_doom_soc_proj build 50 all
#
#   # Defaults (no -tclargs): rv64im_doom_soc_proj, ./build, 100 MHz, impl
#
# tclargs: <project_name> <output_dir> <MHz: 100|75|50> <mode: setup|impl|all>
#
#   100  runs straight off the ZedBoard's Y9 100 MHz oscillator (no MMCM).
#    75  and 50 derive the clock from an MMCM (rtl/soc/clk_gen.v). Both divide
#        to exactly 25 MHz for VGA, so display timing is unchanged. 60 MHz is
#        not offered because it cannot produce 25 MHz by any integer divide.
#
# Only the 50 MHz build closes timing (WNS +0.972 ns). The 100 and 75 MHz
# builds are over-clocked and carry negative setup slack.
#
# CLK_HZ must track the real clock or timer_mmio's microsecond prescaler is
# wrong, which silently corrupts the on-board frame-rate measurement.
# ============================================================================

set project_name "rv64im_doom_soc_proj"
set target_part  "xc7z020clg484-1"
set origin_dir   [file normalize [file dirname [info script]]/../..]
set build_dir    "$origin_dir/build"
set target_mhz   100
set run_mode     "impl"

if { $argc > 0 } { set project_name [lindex $argv 0] }
if { $argc > 1 } { set build_dir    [file normalize [lindex $argv 1]] }
if { $argc > 2 } { set target_mhz   [lindex $argv 2] }
if { $argc > 3 } { set run_mode     [string tolower [lindex $argv 3]] }

switch -- $target_mhz {
    100 { set soc_generics {USE_MMCM=0 CLK_HZ=100000000 PIXEL_DIV=4} }
    75  { set soc_generics {USE_MMCM=1 CLK_HZ=75000000  PIXEL_DIV=3 CLKOUT_DIV=12} }
    50  { set soc_generics {USE_MMCM=1 CLK_HZ=50000000  PIXEL_DIV=2 CLKOUT_DIV=18} }
    default { return -code error "Unsupported clock '$target_mhz'. Choose 100, 75 or 50." }
}

if { [lsearch -exact {setup impl all} $run_mode] < 0 } {
    return -code error "Unsupported mode '$run_mode'. Choose setup, impl or all."
}

set proj_dir "$build_dir/$project_name"
file mkdir $build_dir

puts "=================================================================="
puts "  RV64IM DOOM SoC  ->  ZedBoard XC7Z020-CLG484-1"
puts "  Fabric clock : $target_mhz MHz"
puts "  Generics     : $soc_generics"
puts "  Mode         : $run_mode"
puts "  Repository   : $origin_dir"
puts "  Project      : $proj_dir"
puts "=================================================================="

# ---------------------------------------------------------------------------
# 1. Create the project
# ---------------------------------------------------------------------------
create_project $project_name $proj_dir -part $target_part -force
set_property target_language Verilog [current_project]

# The board part makes the ZedBoard preset available to the PS7 IP. Several
# vendor strings are tried because the board files ship under different names
# depending on which board store is installed. Not fatal if none match.
foreach bp {em.avnet.com:zed:part0:1.4 \
            digilentinc.com:zedboard:part0:1.1 \
            digilentinc.com:zedboard:part0:1.0} {
    if { ![catch { set_property board_part $bp [current_project] }] } {
        puts "INFO: board_part set to $bp"
        break
    }
}

# ---------------------------------------------------------------------------
# 2. RTL sources
# ---------------------------------------------------------------------------
foreach d {core soc peripherals} {
    set rtl_files [glob -nocomplain "$origin_dir/rtl/$d/*.v"]
    if { [llength $rtl_files] == 0 } {
        return -code error "No RTL found in rtl/$d"
    }
    add_files -norecurse $rtl_files
    puts "INFO: added [llength $rtl_files] source files from rtl/$d"
}

# ---------------------------------------------------------------------------
# 3. Zynq PS7
#
# rtl/soc/ps7_wrapper.v instantiates a module named `ps7_ip`, so the PS7 has
# to be an IP core carrying exactly that module name. A block design will not
# do: its generated module is named after the BD, so `ps7_ip` would stay
# undefined and synthesis would silently black-box it.
#
# The .xci is a Vivado build artifact and is not committed, so it is created
# here from scripts/vivado/ps7_preset.tcl. If a previously configured .xci is
# found next to the repo it is imported instead, which guarantees a DDR3
# configuration identical to the one the published bitstreams were built with.
# ---------------------------------------------------------------------------
set known_good_xci "$origin_dir/../RV64I_5stage_pipelined_processor/ip/ps7_ip/ps7_ip.xci"

if { [file exists $known_good_xci] } {
    puts "INFO: importing existing PS7 IP from $known_good_xci"
    import_ip -name ps7_ip $known_good_xci
} else {
    puts "INFO: generating PS7 IP (module ps7_ip) from ps7_preset.tcl"
    create_ip -name processing_system7 -vendor xilinx.com -library ip \
              -module_name ps7_ip -dir "$proj_dir/ip"
    source "$origin_dir/scripts/vivado/ps7_preset.tcl"
    configure_zedboard_ps7 [get_ips ps7_ip]
}

generate_target {synthesis instantiation_template} [get_files ps7_ip.xci]
catch { export_ip_user_files -of_objects [get_files ps7_ip.xci] -force -quiet }

# ---------------------------------------------------------------------------
# 4. BRAM initialisation images
#
# instruction_fetch_unit.v and Data_Memory.v $readmemh these at elaboration.
# They are products of sw/build/build.ps1 and are gitignored, so the project
# still builds without them - the boot BRAM just comes up empty.
# ---------------------------------------------------------------------------
set mem_missing 0
foreach m [list "$origin_dir/sw/build/instructions.mem" "$origin_dir/data.mem"] {
    if { [file exists $m] } {
        add_files -norecurse $m
        set_property file_type {Memory Initialization Files} [get_files $m]
        puts "INFO: added [file tail $m]"
    } else {
        puts "WARNING: [file tail $m] not found - run sw/build/build.ps1 first"
        set mem_missing 1
    }
}

# ---------------------------------------------------------------------------
# 5. Constraints and simulation sources
# ---------------------------------------------------------------------------
add_files -fileset constrs_1 -norecurse "$origin_dir/constraints/doom_soc_zedboard.xdc"

set sim_files [concat [glob -nocomplain "$origin_dir/sim/tb/*.v"] \
                      [glob -nocomplain "$origin_dir/sim/models/*.v"]]
if { [llength $sim_files] } {
    add_files -fileset sim_1 -norecurse $sim_files
    catch { set_property top tb_soc_periph [get_filesets sim_1] }
}

# ---------------------------------------------------------------------------
# 6. Top module, clock generics, run strategy
# ---------------------------------------------------------------------------
set_property top doom_soc_top [current_fileset]
set_property generic $soc_generics [get_filesets sources_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

set_property -name {STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY} -value {rebuilt} \
             -objects [get_runs synth_1]
set_property STRATEGY Performance_Explore [get_runs impl_1]

if { $run_mode eq "setup" } {
    puts "=================================================================="
    puts "  PROJECT CREATED - sources only, nothing has been built yet."
    puts ""
    puts "  Open:  $proj_dir/$project_name.xpr"
    puts ""
    puts "  Available now : source hierarchy; RTL Analysis -> Open Elaborated"
    puts "                  Design -> Schematic"
    puts "  Needs a run   : Device view, timing summary, utilization."
    puts "                  Flow Navigator -> Run Implementation, or re-run"
    puts "                  this script with mode 'impl'."
    puts "=================================================================="
    return
}

# ---------------------------------------------------------------------------
# 7. Synthesis
# ---------------------------------------------------------------------------
puts "\n---> Synthesising ..."
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if { [get_property PROGRESS [get_runs synth_1]] != "100%" } {
    puts "ERROR: synthesis failed."
    puts "       Log: $proj_dir/$project_name.runs/synth_1/runme.log"
    return -code error "Synthesis failed"
}

# ---------------------------------------------------------------------------
# 8. Implementation
# ---------------------------------------------------------------------------
if { $run_mode eq "all" } {
    set impl_target "write_bitstream"
} else {
    set impl_target "route_design"
}
puts "\n---> Implementing to $impl_target at $target_mhz MHz ..."
launch_runs impl_1 -to_step $impl_target -jobs 8
wait_on_run impl_1
if { [get_property PROGRESS [get_runs impl_1]] != "100%" } {
    puts "ERROR: implementation failed."
    puts "       Log: $proj_dir/$project_name.runs/impl_1/runme.log"
    return -code error "Implementation failed"
}

# ---------------------------------------------------------------------------
# 9. Reports
# ---------------------------------------------------------------------------
open_run impl_1
set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]

set rpt_dir "$build_dir/reports_${target_mhz}mhz"
file mkdir $rpt_dir
report_timing_summary -file "$rpt_dir/timing_summary.rpt"
report_utilization    -file "$rpt_dir/utilization.rpt"
write_checkpoint -force "$rpt_dir/doom_soc_top_routed.dcp"

puts "=================================================================="
puts "  BUILD COMPLETE @ $target_mhz MHz"
puts "  WNS (setup) : $wns ns"
puts "  WHS (hold)  : $whs ns"
if { $wns >= 0 } {
    puts "  STATUS      : TIMING MET"
} else {
    puts "  STATUS      : TIMING NOT MET (over-clocked build)"
}
puts "  Reports     : $rpt_dir"
puts ""
puts "  Open the project - the implemented run loads with it:"
puts "    $proj_dir/$project_name.xpr"
puts "=================================================================="

if { $run_mode eq "all" } {
    set bit_file [glob -nocomplain "$proj_dir/$project_name.runs/impl_1/*.bit"]
    if { [llength $bit_file] } {
        if { $target_mhz == 100 } {
            set out_bit "$build_dir/doom_soc_top.bit"
        } else {
            set out_bit "$build_dir/doom_soc_top_${target_mhz}mhz.bit"
        }
        file copy -force [lindex $bit_file 0] $out_bit
        puts "  Bitstream   : $out_bit"
    }
}

if { $mem_missing } {
    puts "  NOTE: boot BRAM images were missing, so a bitstream from this run"
    puts "        will not run the bootloader. Run sw/build/build.ps1 first."
}
