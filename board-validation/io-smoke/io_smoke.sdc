derive_pll_clocks -create_base_clocks

create_clock -name clk_u59 -period 10.000 [get_ports clk_u59]
create_clock -name clk_y3  -period 3.750  [get_ports clk_y3]
create_clock -name clk_y4  -period 3.750  [get_ports clk_y4]
create_clock -name clk_y5  -period 1.551  [get_ports clk_y5]
create_clock -name clk_y6  -period 1.551  [get_ports clk_y6]

# The counters are independent oscillators sampled as Gray codes over JTAG.
# There are deliberately no synchronous transfers between these domains.
set_clock_groups -asynchronous \
    -group {clk_u59} \
    -group {clk_y3} \
    -group {clk_y4} \
    -group {clk_y5} \
    -group {clk_y6}

set_false_path -from [get_ports {gpio_j11[*]}]
set_false_path -to [get_ports {leds[*]}]

# The SLD hub supplies the altera_reserved_tck constraint. Its protocol pins
# are asynchronous JTAG control/data, not board-level synchronous interfaces.
set_false_path -from [get_ports {altera_reserved_ntrst altera_reserved_tdi altera_reserved_tms}]
set_false_path -to [get_ports {altera_reserved_tdo}]
