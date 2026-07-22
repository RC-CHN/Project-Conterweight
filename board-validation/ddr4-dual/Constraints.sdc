#100 MHz from U59
create_clock -period 10 [get_ports clk_u59]

# The two EMIF-generated SDC files own the Y3/Y4 DDR reference clocks and
# all derived PHY/user clocks. Do not create duplicate clocks here.

set_false_path -to [get_ports {leds[*]}]

# Platform Designer implements each EMIF read-response FIFO as a 512-bit
# altsyncram with asynchronously-cleared output registers.  The output payload
# is explicitly invalid while the separately reset out_valid state is low and
# the FIFO is empty.  Exclude only reset-release recovery checks from each
# local reset synchronizer to those payload RAM output registers.  FIFO
# pointers, valid/full/empty state, CDC controls, EMIF logic, hold/removal, and
# all ordinary data paths remain timed.
set_false_path -setup \
    -from [get_registers -nowarn {Qsys:u0|altera_reset_controller:rst_controller_001|altera_reset_synchronizer:alt_rst_sync_uq1|altera_reset_synchronizer_int_chain_out}] \
    -to [get_registers -nowarn {*emif_top_ctrl_amm_0_agent_rdata_fifo*ram_block1a*}]
set_false_path -setup \
    -from [get_registers -nowarn {Qsys:u0|altera_reset_controller:rst_controller|altera_reset_synchronizer:alt_rst_sync_uq1|altera_reset_synchronizer_int_chain_out}] \
    -to [get_registers -nowarn {*emif_bot_ctrl_amm_0_agent_rdata_fifo*ram_block1a*}]

# The ISSP source is clocked by clk_u59 while each BIST control is consumed in
# its own EMIF user-clock domain.  Exclude only the asynchronous input paths to
# the first register of each explicit two-flop synchronizer.  The second stages
# and all downstream BIST/control paths remain timed.
set_false_path -to [get_registers -nowarn {Qsys:u0|ddr4_sweep_bist:bist_top|enable_sync[0]}]
set_false_path -to [get_registers -nowarn {Qsys:u0|ddr4_sweep_bist:bist_top|clear_sync[0]}]
set_false_path -to [get_registers -nowarn {Qsys:u0|ddr4_sweep_bist:bist_bot|enable_sync[0]}]
set_false_path -to [get_registers -nowarn {Qsys:u0|ddr4_sweep_bist:bist_bot|clear_sync[0]}]

# Quartus inserts these physical JTAG ports for the SLD hub. TCK is constrained
# by the hub's embedded SDC; TMS/TDI/nTRST and TDO are asynchronous test-access
# pins rather than user-mode synchronous I/O.
set_false_path -from [get_ports -nowarn {
    altera_reserved_ntrst altera_reserved_tdi altera_reserved_tms
}]
set_false_path -to [get_ports -nowarn {altera_reserved_tdo}]
