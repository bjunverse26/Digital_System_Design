# SRCNN_42 Automation Guide

This folder uses a Vivado non-project batch flow. The scripts run simulation
without opening the Vivado project or modifying `00_RTL_Skeleton/dsd_termprj.xpr`.

## Run Functional Simulation

Run from `C:\DSD26_Termproject_Materials`:

```powershell
vivado -nolog -nojournal -notrace -mode batch -source .\04_SRCNN_42\scripts\run_tb.tcl
```

The script runs:

```text
xvlog -> xelab -> xsim -runall
```

Expected terminal summary:

```text
[RUN] xvlog
[OK ] xvlog
[RUN] xelab
[OK ] xelab
[RUN] xsim
[TB][PASS] SRCNN_42 reference comparison completed.
[OK ] xsim
SRCNN_42 simulation PASSED
```

The simulation ends when `tb_SRCNN_42.v` calls `$finish`.

## Keep Debug Files

By default, each run uses a temporary folder:

```text
04_SRCNN_42/sim_work/run_*
```

and removes that folder after a passing run. To keep the run folder:

```powershell
vivado -nolog -nojournal -notrace -mode batch -source .\04_SRCNN_42\scripts\run_tb.tcl -tclargs --keep
```

## Clean Simulation Byproducts

To remove leftover simulation byproducts:

```powershell
vivado -nolog -nojournal -notrace -mode batch -source .\04_SRCNN_42\scripts\clean_sim.tcl
```

Preview cleanup without deleting:

```powershell
vivado -nolog -nojournal -notrace -mode batch -source .\04_SRCNN_42\scripts\clean_sim.tcl -tclargs --dry-run
```

If `sim_work` cannot be removed, close any open xsim/Vivado GUI windows and run
the cleanup command again.

## Directory Roles

```text
04_SRCNN_42/rtl      RTL source files
04_SRCNN_42/tb       testbench
04_SRCNN_42/init     $readmemh input/weight/bias files
04_SRCNN_42/ref      testbench reference outputs
04_SRCNN_42/scripts  automation Tcl scripts
04_SRCNN_42/docs     usage notes
```

## Option Meaning

```text
-mode batch     Run Vivado without the GUI.
-nolog          Do not create vivado.log.
-nojournal      Do not create vivado.jou.
-notrace        Reduce Tcl command echo noise.
--keep          Keep the current sim_work/run_* folder.
--dry-run       Show cleanup targets without deleting them.
```

