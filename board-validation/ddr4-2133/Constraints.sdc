source ../ddr4-dual/Constraints.sdc

# At 266.7 MHz, the synchronized Platform Designer reset needs more than one
# user-clock period to reach the farthest register in each generated Avalon-MM
# interconnect (measured worst-case route: 4.38 ns; period: 3.752 ns).  Require
# it to reach every interconnect register within two cycles instead of waiving
# recovery.  The BIST remains disabled through its own local synchronizer, so
# neither master can issue a transaction while the interconnect releases from
# reset.  Removal timing is intentionally left at the default one-edge check.
set emif_top_interconnect [get_registers -nowarn {*mm_interconnect_0|*}]
if {[get_collection_size $emif_top_interconnect] > 0} {
    set_multicycle_path -setup 2 -from $emif_top_reset -to $emif_top_interconnect
    set_multicycle_path -hold 1 -from $emif_top_reset -to $emif_top_interconnect
}

set emif_bot_interconnect [get_registers -nowarn {*mm_interconnect_1|*}]
if {[get_collection_size $emif_bot_interconnect] > 0} {
    set_multicycle_path -setup 2 -from $emif_bot_reset -to $emif_bot_interconnect
    set_multicycle_path -hold 1 -from $emif_bot_reset -to $emif_bot_interconnect
}
