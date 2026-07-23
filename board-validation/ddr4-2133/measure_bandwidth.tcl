set ::ddr4_user_clock_hz 266666750.0
source [file normalize [file join \
    [file dirname [info script]] ../ddr4-dual/measure_bandwidth.tcl]]
