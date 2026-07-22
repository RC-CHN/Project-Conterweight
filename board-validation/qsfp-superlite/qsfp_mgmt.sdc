derive_pll_clocks -create_base_clocks
derive_clock_uncertainty

create_clock -name clk_u59 -period 10.000 [get_ports clk_u59]
create_clock -name clk_y5 -period 1.551 [get_ports clk_y5]

# Each asynchronous input is cut only to its first synchronizer stage.
set_false_path -from [get_clocks clk_y5] -to [get_registers {y5_toggle_meta}]
set_false_path -from [get_ports modprsl] -to [get_registers {modprsl_meta}]

# I2C has no synchronous board-level timing contract.  The Intel controller
# synchronizes the sampled open-drain inputs internally.
set_false_path -from [get_ports {scl_ch1 sda_ch1}]
set_false_path -to   [get_ports {scl_ch1 sda_ch1}]

# The JTAG IP owns its TCK constraints; these reserved pins are asynchronous
# SLD protocol signals rather than application-clock I/O.
set_false_path -from [get_ports {altera_reserved_ntrst altera_reserved_tdi altera_reserved_tms}]
set_false_path -to [get_ports {altera_reserved_tdo}]
