# SRCNN_84 Automation Guide

Run from `C:\DSD26_Termproject_Materials`:

```powershell
vivado -nolog -nojournal -notrace -mode batch -source .\06_SRCNN_84\scripts\run_tb.tcl
```

Keep debug files:

```powershell
vivado -nolog -nojournal -notrace -mode batch -source .\06_SRCNN_84\scripts\run_tb.tcl -tclargs --keep
```

Clean simulation byproducts:

```powershell
vivado -nolog -nojournal -notrace -mode batch -source .\06_SRCNN_84\scripts\clean_sim.tcl
```

Directory roles:

```text
06_SRCNN_84/rtl      RTL source files
06_SRCNN_84/tb       testbench
06_SRCNN_84/init     $readmemh input/weight/bias files
06_SRCNN_84/ref      testbench reference outputs
06_SRCNN_84/scripts  automation Tcl scripts
```
