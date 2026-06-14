#============================================================================
# Project     : SRCNN_84
# File        : save_impl_snapshot.tcl
# Purpose     : Save implementation results for the current SRCNN_84 build.
#
# Usage:
#   # From an already opened Vivado project:
#   source C:/DSD26_Termproject_Materials_260526/06_SRCNN_84/scripts/save_impl_snapshot.tcl
#
#   # Or from Vivado batch mode:
#   vivado -nolog -nojournal -notrace -mode batch \
#     -source ./06_SRCNN_84/scripts/save_impl_snapshot.tcl \
#     -tclargs --project ./00_RTL_Skeleton/dsd_termprj.xpr
#
# Useful options:
#   -tclargs --project <path>  Open the given Vivado project before saving.
#   -tclargs --run <name>      Implementation run to open. Default: impl_1.
#   -tclargs --tag <name>      Output filename prefix. Default: SRCNN_84.
#   -tclargs --out <path>      Snapshot directory. Default: 06_SRCNN_84/impl_snapshot.
#   -tclargs --no-bitstream    Do not write a .bit file.
#   -tclargs --help            Print this help text.
#
# Notes:
#   - Run this after implementation or bitstream generation is complete.
#   - The script writes reports/checkpoints only to the snapshot directory.
#   - It does not modify RTL, testbench, or project source files.
#============================================================================

#----------------------------------------------------------------------------
# Argument parsing
#----------------------------------------------------------------------------

set project_path ""
set run_name     "impl_1"
set tag_name     "SRCNN_84"
set out_dir      ""
set write_bit    1

set arg_count [llength $argv]
set arg_idx 0

while {$arg_idx < $arg_count} {
    set arg [lindex $argv $arg_idx]

    switch -- $arg {
        "--project" {
            incr arg_idx
            if {$arg_idx >= $arg_count} {
                return -code error "ERROR: --project requires a path."
            }
            set project_path [lindex $argv $arg_idx]
        }
        "--run" {
            incr arg_idx
            if {$arg_idx >= $arg_count} {
                return -code error "ERROR: --run requires a run name."
            }
            set run_name [lindex $argv $arg_idx]
        }
        "--tag" {
            incr arg_idx
            if {$arg_idx >= $arg_count} {
                return -code error "ERROR: --tag requires a filename prefix."
            }
            set tag_name [lindex $argv $arg_idx]
        }
        "--out" {
            incr arg_idx
            if {$arg_idx >= $arg_count} {
                return -code error "ERROR: --out requires a directory path."
            }
            set out_dir [lindex $argv $arg_idx]
        }
        "--no-bitstream" {
            set write_bit 0
        }
        "--help" {
            puts "SRCNN_84 implementation snapshot"
            puts ""
            puts "Usage:"
            puts "  source ./06_SRCNN_84/scripts/save_impl_snapshot.tcl"
            puts ""
            puts "  vivado -nolog -nojournal -notrace -mode batch \\"
            puts "    -source ./06_SRCNN_84/scripts/save_impl_snapshot.tcl \\"
            puts "    -tclargs --project ./00_RTL_Skeleton/dsd_termprj.xpr"
            puts ""
            puts "Options:"
            puts "  --project <path>  Open the given Vivado project before saving."
            puts "  --run <name>      Implementation run to open. Default: impl_1."
            puts "  --tag <name>      Output filename prefix. Default: SRCNN_84."
            puts "  --out <path>      Snapshot directory. Default: 06_SRCNN_84/impl_snapshot."
            puts "  --no-bitstream    Do not write a .bit file."
            puts "  --help            Print this message."
            return
        }
        default {
            puts "Run with --help for usage."
            return -code error "ERROR: Unknown option: $arg"
        }
    }

    incr arg_idx
}

#----------------------------------------------------------------------------
# Directory layout
#----------------------------------------------------------------------------

set script_dir [file dirname [file normalize [info script]]]
set srcnn_dir  [file normalize [file join $script_dir ".."]]

if {$out_dir eq ""} {
    set out_dir [file normalize [file join $srcnn_dir "impl_snapshot"]]
} else {
    set out_dir [file normalize $out_dir]
}

#----------------------------------------------------------------------------
# Helper procedures
#----------------------------------------------------------------------------

proc print_banner {text} {
    puts ""
    puts "============================================================================"
    puts $text
    puts "============================================================================"
}

proc current_project_or_empty {} {
    if {[catch {current_project} project_name]} {
        return ""
    }

    return $project_name
}

proc require_file_exists {path} {
    if {![file exists $path]} {
        puts "ERROR: Required file does not exist:"
        puts "  $path"
        return -code error "Required file does not exist: $path"
    }
}

proc run_report_or_warn {description args} {
    if {[catch {uplevel 1 $args} result]} {
        puts "WARNING: $description failed."
        puts "         $result"
        return 0
    }

    return 1
}

#----------------------------------------------------------------------------
# Project and run checks
#----------------------------------------------------------------------------

print_banner "SRCNN_84 implementation snapshot start"

if {$project_path ne ""} {
    set project_path [file normalize $project_path]
    require_file_exists $project_path
    open_project $project_path
}

set current_project_name [current_project_or_empty]

if {$current_project_name eq ""} {
    puts "ERROR: No Vivado project is open."
    puts "       Open the project first, or pass --project <path> in batch mode."
    return -code error "No Vivado project is open."
}

set runs [get_runs -quiet $run_name]

if {[llength $runs] == 0} {
    return -code error "ERROR: Implementation run does not exist: $run_name"
}

file mkdir $out_dir

puts "Project : $current_project_name"
puts "Run     : $run_name"
puts "Tag     : $tag_name"
puts "Output  : $out_dir"

#----------------------------------------------------------------------------
# Open implemented design and save artifacts
#----------------------------------------------------------------------------

if {[catch {open_run $run_name} result]} {
    puts "ERROR: Could not open implementation run: $run_name"
    puts "       $result"
    puts ""
    puts "Make sure implementation has completed before running this script."
    return -code error "Could not open implementation run: $run_name"
}

set dcp_file    [file join $out_dir "${tag_name}_routed.dcp"]
set bit_file    [file join $out_dir "${tag_name}.bit"]
set util_file   [file join $out_dir "${tag_name}_utilization_impl.rpt"]
set timing_file [file join $out_dir "${tag_name}_timing_summary_impl.rpt"]
set power_file  [file join $out_dir "${tag_name}_power_impl.rpt"]
set notes_file  [file join $out_dir "${tag_name}_notes.txt"]

puts ""
puts "\[RUN\] write_checkpoint"
write_checkpoint -force $dcp_file
puts "\[OK \] $dcp_file"

if {$write_bit} {
    puts ""
    puts "\[RUN\] write_bitstream"
    write_bitstream -force $bit_file
    puts "\[OK \] $bit_file"
}

puts ""
puts "\[RUN\] report_utilization"
report_utilization -file $util_file
puts "\[OK \] $util_file"

puts ""
puts "\[RUN\] report_timing_summary"
report_timing_summary -file $timing_file
puts "\[OK \] $timing_file"

puts ""
puts "\[RUN\] report_power"
run_report_or_warn "report_power" report_power -file $power_file

#----------------------------------------------------------------------------
# Metadata notes
#----------------------------------------------------------------------------

set fp [open $notes_file "w"]
puts $fp "Project     : SRCNN_84"
puts $fp "Tag         : $tag_name"
puts $fp "Vivado      : [version -short]"
puts $fp "Run         : $run_name"
puts $fp "Project file: $current_project_name"
puts $fp "Snapshot dir: $out_dir"
puts $fp "Created at  : [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S %Z}]"
puts $fp ""
puts $fp "Artifacts:"
puts $fp "  ${tag_name}_routed.dcp"
if {$write_bit} {
    puts $fp "  ${tag_name}.bit"
}
puts $fp "  ${tag_name}_utilization_impl.rpt"
puts $fp "  ${tag_name}_timing_summary_impl.rpt"
puts $fp "  ${tag_name}_power_impl.rpt"
close $fp

puts "\[OK \] $notes_file"

print_banner "SRCNN_84 implementation snapshot complete"
puts "Snapshot files were saved in:"
puts "  $out_dir"
