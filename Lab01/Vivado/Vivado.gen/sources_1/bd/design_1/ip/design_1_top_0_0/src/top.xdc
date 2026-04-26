# 100 MHz clock -> period = 10.000 ns
create_clock -period 10.000 -name clk [get_ports clk]

# Treat reset as async control path (optional but commonly used)
set_false_path -from [get_ports rst_n]