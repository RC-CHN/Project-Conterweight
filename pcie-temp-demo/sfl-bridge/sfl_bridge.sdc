# The SLD hub supplies the 30 MHz altera_reserved_tck clock constraint.
# JTAG protocol control/data pins are asynchronous to the internal TCK-clocked
# SFL datapath and have no board-level source/sink timing requirement.
set_false_path -from [get_ports {altera_reserved_ntrst altera_reserved_tdi altera_reserved_tms}]
set_false_path -to [get_ports {altera_reserved_tdo}]
