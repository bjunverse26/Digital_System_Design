#============================================================================
# Project     : SRCNN_88
# File        : run_tb.tcl
# Purpose     : Non-project Vivado batch simulation flow for tb_SRCNN_88.
#
# Usage:
#   vivado -nolog -nojournal -notrace -mode batch \
#     -source ./05_SRCNN_88/scripts/run_tb.tcl
#
# Useful options:
#   -tclargs --keep     Keep sim_work after the run for debugging.
#   -tclargs --help     Print this help text.
#
# Notes:
#   - This is a non-project flow. It does not modify the Vivado .xpr.
#   - The script exits with code 0 on PASS and 1 on FAIL.
#   - Temporary simulation files are isolated under 05_SRCNN_88/sim_work/run_*.
#============================================================================

#----------------------------------------------------------------------------
# Argument parsing
#----------------------------------------------------------------------------

set keep_work 0

foreach arg $argv {
    switch -- $arg {
        "--keep" {
            set keep_work 1
        }
        "--help" {
            puts "SRCNN_88 batch simulation"
            puts ""
            puts "Usage:"
            puts "  vivado -nolog -nojournal -notrace -mode batch -source ./05_SRCNN_88/scripts/run_tb.tcl"
            puts ""
            puts "Options:"
            puts "  --keep    Keep the current 05_SRCNN_88/sim_work/run_* directory after the run."
            puts "  --help    Print this message."
            exit 0
        }
        default {
            puts "ERROR: Unknown option: $arg"
            puts "Run with --help for usage."
            exit 1
        }
    }
}

#----------------------------------------------------------------------------
# Directory layout
#----------------------------------------------------------------------------

set script_dir [file dirname [file normalize [info script]]]
set srcnn_dir  [file normalize [file join $script_dir ".."]]
set work_root  [file normalize [file join $srcnn_dir "sim_work"]]
set run_tag    [format "run_%s_%s" [clock format [clock seconds] -format "%Y%m%d_%H%M%S"] [pid]]
set work_dir   [file normalize [file join $work_root $run_tag]]

set rtl_dir [file join $srcnn_dir "rtl"]
set tb_dir  [file join $srcnn_dir "tb"]

#----------------------------------------------------------------------------
# Source manifest
#----------------------------------------------------------------------------

set rtl_files [list \
    [file join $rtl_dir "srcnn88_simple_dual_port_bram.v"] \
    [file join $rtl_dir "srcnn88_line_buffer.v"] \
    [file join $rtl_dir "srcnn88_pe.v"] \
    [file join $rtl_dir "srcnn88_post_process.v"] \
    [file join $rtl_dir "srcnn88_weight_bias_rom.v"] \
    [file join $rtl_dir "srcnn88_controller.v"] \
    [file join $rtl_dir "srcnn88_top.v"] \
]

set tb_file  [file join $tb_dir "tb_SRCNN_88.v"]
set top_name "tb_SRCNN_88"

#----------------------------------------------------------------------------
# Helper procedures
#----------------------------------------------------------------------------

proc assert_file_exists {path} {
    if {![file exists $path]} {
        puts "ERROR: Required file does not exist:"
        puts "  $path"
        exit 1
    }
}

proc run_cmd {args} {
    if {[catch {exec {*}$args} result options]} {
        puts $result
        return -code error $result
    }

    return $result
}

proc print_tb_summary {text} {
    foreach line [split $text "\n"] {
        if {[regexp {\[TB\]} $line]} {
            puts $line
        }
    }
}

proc print_banner {text} {
    puts ""
    puts "============================================================================"
    puts $text
    puts "============================================================================"
}

proc remove_dir_if_empty {path} {
    if {[file exists $path] && [llength [glob -nocomplain -directory $path *]] == 0} {
        file delete -force $path
    }
}

#----------------------------------------------------------------------------
# Pre-flight checks
#----------------------------------------------------------------------------

foreach file_path $rtl_files {
    assert_file_exists $file_path
}
assert_file_exists $tb_file

#----------------------------------------------------------------------------
# Run simulation
#----------------------------------------------------------------------------

print_banner "SRCNN_88 batch simulation start"

file mkdir $work_root
file mkdir $work_dir
cd $work_dir

if {[catch {
    puts ""
    puts "\[RUN\] xvlog"
    run_cmd xvlog {*}$rtl_files $tb_file
    puts "\[OK \] xvlog"

    puts ""
    puts "\[RUN\] xelab"
    run_cmd xelab $top_name
    puts "\[OK \] xelab"

    puts ""
    puts "\[RUN\] xsim"
    set sim_output [run_cmd xsim $top_name -runall]
    print_tb_summary $sim_output

    if {[string first {[TB][PASS]} $sim_output] < 0} {
        error {Simulation finished without [TB][PASS].}
    }

    puts "\[OK \] xsim"
} result]} {
    print_banner "SRCNN_88 simulation FAILED"
    puts "Reason:"
    puts "  $result"
    puts ""
    puts "Debug files were kept in:"
    puts "  $work_dir"
    exit 1
}

if {$keep_work} {
    print_banner "SRCNN_88 simulation PASSED"
    puts "Temporary simulation files were kept in:"
    puts "  $work_dir"
} else {
    file delete -force $work_dir
    remove_dir_if_empty $work_root
    print_banner "SRCNN_88 simulation PASSED"
    puts "Temporary simulation files were removed."
}

exit 0
