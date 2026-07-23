set expected_rate 800.0
set target_rate 1066.667

# The full-aperture BIST and ISSP status/control paths are sufficient for this
# validation image.  Remove both interactive JTAG-to-DDR paths from only the
# 2133 variant so Platform Designer does not build cross-clock arbitration and
# deep response FIFOs on the shorter EMIF user-clock period.  Keep master_top
# itself as the existing 100 MHz reset source; its Avalon interface is unused.
remove_connection master_top.master/emif_top.ctrl_amm_0
remove_instance master_bot
send_message info "removed both JTAG-to-DDR debug paths from DDR4-2133 variant"

foreach instance {emif_bot emif_top} {
    set current [get_instance_parameter_value $instance PHY_DDR4_MEM_CLK_FREQ_MHZ]
    if {$current != $expected_rate} {
        error "$instance base rate is $current MHz, expected $expected_rate MHz"
    }
    set_instance_parameter_value \
        $instance PHY_DDR4_MEM_CLK_FREQ_MHZ $target_rate
}

foreach instance {emif_bot emif_top} {
    set actual [get_instance_parameter_value $instance PHY_DDR4_MEM_CLK_FREQ_MHZ]
    if {$actual != $target_rate} {
        error "$instance target rate is $actual MHz, expected $target_rate MHz"
    }
    send_message info "$instance DDR4 memory clock=$actual MHz"
}

set output_qsys [file join [pwd] Qsys.qsys]
send_message info "saving DDR4-2133 system to $output_qsys"
save_system $output_qsys
