# LEDs are only human-visible status outputs.
set_false_path -to [get_ports {leds[*]}]

# PERST is asynchronous to the HIP application clock and enters an explicit
# two-flop synchronizer before it is used by the diagnostic counters.
# PCIe PERST# is an asynchronous sideband reset. The recovered Microsoft
# Catapult v3 BSP constrains its equivalent input as asynchronous as well;
# reset release is synchronized inside the HIP and dma_status_regs.
set_false_path -from [get_ports pcie1_perstn]

# Platform Designer fans its synchronously deasserted reset across the Avalon
# fabric. Permit the reset release to propagate for two core-clock cycles. The
# recovered Microsoft Catapult v3 BSP uses the same paired setup/hold pattern
# (with four cycles) for its generated reset controller; two is sufficient for
# this fitted design and keeps the exception as tight as possible.
set system_reset_sync [get_registers \
    {*|rst_controller|alt_rst_sync_uq1|altera_reset_synchronizer_int_chain_out}]
set_multicycle_path -setup 2 -from $system_reset_sync
set_multicycle_path -hold 1 -from $system_reset_sync
