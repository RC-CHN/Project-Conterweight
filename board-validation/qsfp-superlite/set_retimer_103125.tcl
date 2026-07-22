# Configure the DS250DF810's volatile quick-rate field for 10.3125 Gbit/s.
#
# This script first runs the complete read-only management inspection.  It
# refuses to write unless MODPRSL proves that no QSFP module/cable is present.
# Only the two community-documented configuration values are written:
# register FFh = 03h (channel-register access + broadcast), then the high
# nibble of register 2Fh = 0 while preserving its low nibble.

source inspect_mgmt.tcl

if {$modprsl != 1} {
    error "Refusing retimer rate write while a QSFP module/cable is present"
}
if {!$retimer_ack} {
    error "Refusing retimer rate write because address 0x22 did not ACK"
}

proc write_register_value {master address pointer value} {
    global REG_TFR_CMD REG_CTRL REG_ISR

    write32 $master $REG_CTRL 0
    write32 $master $REG_ISR 0x1c
    write32 $master $REG_CTRL 1
    write32 $master $REG_TFR_CMD [expr {($address & 0x7f) << 1}]
    write32 $master $REG_TFR_CMD [expr {$pointer & 0xff}]
    write32 $master $REG_TFR_CMD [expr {($value & 0xff) | 0x100}]
    wait_idle $master [format "write 0x%02x to register 0x%02x at 0x%02x" \
        $value $pointer $address]
    set isr [read32 $master $REG_ISR]
    write32 $master $REG_CTRL 0
    if {$isr & 0x0c} {
        error [format "register write failed at 0x%02x/0x%02x, ISR=0x%x" \
            $address $pointer $isr]
    }
}

set master_paths [get_service_paths master]
if {[llength $master_paths] != 1} {
    error "Expected one JTAG-to-Avalon master, found [llength $master_paths]: $master_paths"
}
set write_master [claim_service master [lindex $master_paths 0] qsfp_retimer_rate_writer]
init_controller $write_master

set select_before [read_register $write_master 0x22 0xff 1]
set rate_before [read_register $write_master 0x22 0x2f 1]
puts [format "before register_ff=%s register_2f=%s" \
    [hex_bytes $select_before] [hex_bytes $rate_before]]

write_register_value $write_master 0x22 0xff 0x03
set broadcast_select [read_register $write_master 0x22 0xff 1]
if {[lindex $broadcast_select 0] != 0x03} {
    write32 $write_master $REG_CTRL 0
    close_service master $write_master
    error [format "retimer broadcast-select readback mismatch: %s" \
        [hex_bytes $broadcast_select]]
}

set rate_selected [read_register $write_master 0x22 0x2f 1]
set rate_103125 [expr {[lindex $rate_selected 0] & 0x0f}]
write_register_value $write_master 0x22 0x2f $rate_103125
set rate_after [read_register $write_master 0x22 0x2f 1]

write32 $write_master $REG_CTRL 0
close_service master $write_master

puts [format "after register_ff=%s register_2f=%s expected_2f=0x%02x" \
    [hex_bytes $broadcast_select] [hex_bytes $rate_after] $rate_103125]
if {[lindex $rate_after 0] != $rate_103125} {
    error "retimer 10.3125 Gbit/s rate readback mismatch"
}

after 20
lassign [sample_management] final_sample final_path
set final_lines [field $final_sample 0 2]
set final_controller_oe [field $final_sample 2 2]
set final_physical_oe [field $final_sample 4 2]
puts [format "final lines=0x%x controller_oe=0x%x physical_oe=0x%x" \
    $final_lines $final_controller_oe $final_physical_oe]
if {$final_lines != 3 || $final_controller_oe != 0 || $final_physical_oe != 0} {
    error "management bus did not return idle-high after retimer rate write"
}
puts "retimer_rate_103125=PASS"
puts "target_configuration_value_bytes_written=2"
