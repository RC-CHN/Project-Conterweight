# LEDs are only human-visible status outputs.
set_false_path -to [get_ports {leds[*]}]

# PERST is asynchronous to the HIP application clock and enters an explicit
# two-flop synchronizer before it is used by the diagnostic counters.
# PCIe PERST# is an asynchronous sideband reset. The recovered Microsoft
# Catapult v3 BSP constrains its equivalent input as asynchronous as well;
# reset release is synchronized inside the HIP and dma_status_regs.
set_false_path -from [get_ports pcie1_perstn]
