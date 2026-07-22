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
    -from [get_registers -nowarn {*rst_controller_001*altera_reset_synchronizer_int_chain_out}] \
    -to [get_registers -nowarn {*emif_top_ctrl_amm_0_agent_rdata_fifo*ram_block1a*}]
set_false_path -setup \
    -from [get_registers -nowarn {*rst_controller_003*altera_reset_synchronizer_int_chain_out}] \
    -to [get_registers -nowarn {*emif_bot_ctrl_amm_0_agent_rdata_fifo*ram_block1a*}]

# Quartus inserts these physical JTAG ports for the SLD hub. TCK is constrained
# by the hub's embedded SDC; TMS/TDI/nTRST and TDO are asynchronous test-access
# pins rather than user-mode synchronous I/O.
set_false_path -from [get_ports -nowarn {
    altera_reserved_ntrst altera_reserved_tdi altera_reserved_tms
}]
set_false_path -to [get_ports -nowarn {altera_reserved_tdo}]
