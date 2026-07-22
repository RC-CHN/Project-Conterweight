derive_pll_clocks -create_base_clocks

create_clock -name clk_u59 -period 10.000 [get_ports clk_u59]

# I2C is asynchronous to the 100 MHz fabric clock and is intentionally much
# slower. The controller synchronizes input samples internally; the open-drain
# pins have no board-level synchronous timing contract in this smoke test.
set_false_path -from [get_ports {scl_ch1 sda_ch1 scl_ch2 sda_ch2}]
set_false_path -to   [get_ports {scl_ch1 sda_ch1 scl_ch2 sda_ch2}]

# The JTAG IP supplies its own TCK constraints. These SLD protocol pins are
# asynchronous control/data paths, not board-level synchronous interfaces.
set_false_path -from [get_ports {altera_reserved_ntrst altera_reserved_tdi altera_reserved_tms}]
set_false_path -to [get_ports {altera_reserved_tdo}]
