derive_pll_clocks -create_base_clocks

create_clock -name pcie1_refclk -period 10.000 [get_ports pcie1_refclk]

# LEDs are only human-visible status outputs.
set_false_path -to [get_ports {leds[*]}]

# PERST is asynchronous to the HIP application clock and enters an explicit
# two-flop synchronizer before it is used by the diagnostic counters.
set_false_path -from [get_ports pcie1_perstn] \
    -to [get_registers {*|perst_meta}]

