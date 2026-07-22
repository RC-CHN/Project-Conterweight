# Board clocks.  The generated fPLL/Native-PHY SDC files own all derived
# transceiver clocks and hard-IP internal exceptions.
create_clock -name clk_u59 -period 10.000 [get_ports clk_u59]
# TimeQuest 22.1 truncates time values to 1 ps.  Use 1.551 ns rather than
# 1.552 ns so timing is checked slightly faster than the actual 644.53125 MHz
# board oscillator.  The fPLL and Native PHY IP parameters independently set
# the physical line rate to 10.3125 Gbit/s.
create_clock -name clk_y5 -period 1.551 [get_ports clk_y5]
derive_pll_clocks
derive_clock_uncertainty

# External asynchronous presence input: cut only its first synchronizer.
set_false_path -from [get_ports modprsl] \
    -to [get_registers -nowarn {modprsl_meta}]

# Temperature EOC is asynchronous to U59; all downstream state remains timed.
set_false_path -to [get_registers -nowarn {temp_eoc_meta}]

# Status and Gray-coded counters are sampled in U59 through explicit two-flop
# synchronizers.  Cut only the first stage of each crossing.
set_false_path -to [get_registers -nowarn {status_meta[*]}]
set_false_path -to [get_registers -nowarn {tx_gray_meta[*]}]
set_false_path -to [get_registers -nowarn {block_gray_meta[*][*]}]
set_false_path -to [get_registers -nowarn {error_gray_meta[*][*]}]
set_false_path -to [get_registers -nowarn {loss_gray_meta[*][*]}]

# ISSP controls originate in U59 and are explicitly synchronized before use
# in the TX and RX PCS clock domains.
set_false_path -to [get_registers -nowarn {tx_enable_meta[*]}]
set_false_path -to [get_registers -nowarn {tx_ready_meta[*]}]
set_false_path -to [get_registers -nowarn {inject_meta[*]}]
set_false_path -to [get_registers -nowarn {clear_meta_rx[*]}]
set_false_path -to [get_registers -nowarn {blk_lock_meta_rx[*]}]
set_false_path -to [get_registers -nowarn {ready_meta_rx[*]}]
set_false_path -to [get_registers -nowarn {fifo_full_meta_rx[*]}]

# Quartus inserts these physical JTAG ports for the SLD hub.  TCK is owned by
# the hub's embedded SDC; the remaining protocol pins are asynchronous to the
# application clocks.
set_false_path -from [get_ports -nowarn {
    altera_reserved_ntrst altera_reserved_tdi altera_reserved_tms
}]
set_false_path -to [get_ports -nowarn {altera_reserved_tdo}]
