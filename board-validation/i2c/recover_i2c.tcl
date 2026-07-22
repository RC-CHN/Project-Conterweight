# Open-drain recovery for a Catapult v3 I2C bus left mid-transaction.
#
# Recovery source bits are {ch2_sda_low, ch2_scl_low, ch1_sda_low,
# ch1_scl_low, manual_enable}. This script only manipulates channel 1, only
# pulls lines low, and restores normal controller ownership before exiting.

proc find_line_probe {} {
    foreach path [get_service_paths issp] {
        set candidate [claim_service issp $path i2c_bus_recovery]
        set info [issp_get_instance_info $candidate]
        if {[dict get $info instance_name] eq "I2CS"} {
            return [list $candidate $path]
        }
        close_service issp $candidate
    }
    error "I2CS line-state/recovery probe not found"
}

proc sample {service stage} {
    after 2
    set value [expr {[issp_read_probe_data $service]}]
    set lines [expr {$value & 0xf}]
    set oe [expr {($value >> 4) & 0xf}]
    set reset_n [expr {($value >> 8) & 1}]
    puts [format "%s lines=0x%x oe=0x%x reset_n=%u" $stage $lines $oe $reset_n]
    return [list $lines $oe $reset_n]
}

proc write_source {service value} {
    issp_write_source_data $service $value
    after 2
}

proc wait_ch1_scl_high {service stage} {
    for {set i 0} {$i < 100} {incr i} {
        set value [expr {[issp_read_probe_data $service]}]
        if {$value & 1} {
            return $value
        }
        after 1
    }
    error "$stage: channel 1 SCL did not return high"
}

refresh_connections
lassign [find_line_probe] service path
puts "recovery_path=$path"
lassign [sample $service preflight] lines oe reset_n

if {$reset_n != 1} {
    close_service issp $service
    error "I2C bridge is still in reset"
}
if {$oe != 0} {
    close_service issp $service
    error [format "FPGA output-enable active before recovery: 0x%x" $oe]
}
if {($lines & 0xc) != 0xc} {
    close_service issp $service
    error [format "Channel 2 is not idle-high; refusing channel-1 recovery: 0x%x" $lines]
}
if {($lines & 1) == 0} {
    close_service issp $service
    error "Channel 1 SCL is externally held low; refusing recovery"
}

if {$lines == 0xf} {
    puts "bus_already_idle=1"
    close_service issp $service
    return
}
if {$lines != 0xd} {
    close_service issp $service
    error [format "Unexpected line state before channel-1 recovery: 0x%x" $lines]
}

# Take manual ownership with every line released.
write_source $service 0x01

set pulses 0
while {$pulses < 9} {
    incr pulses
    # Pull channel-1 SCL low, then release it. No source setting can drive high.
    write_source $service 0x03
    set low_sample [expr {[issp_read_probe_data $service]}]
    if {$low_sample & 1} {
        write_source $service 0x00
        close_service issp $service
        error "Channel 1 SCL did not go low during recovery pulse $pulses"
    }
    write_source $service 0x01
    set high_sample [wait_ch1_scl_high $service "pulse $pulses"]
    puts [format "pulse=%u lines=0x%x" $pulses [expr {$high_sample & 0xf}]]
    if {($high_sample & 2) != 0} {
        break
    }
}

# Generate an explicit STOP: SCL low, SDA low, release SCL, then release SDA.
write_source $service 0x03
write_source $service 0x07
write_source $service 0x05
wait_ch1_scl_high $service stop
write_source $service 0x01
lassign [sample $service post_stop] lines oe reset_n

# Return ownership to the two Intel I2C controllers.
write_source $service 0x00
lassign [sample $service controller_owned] lines oe reset_n
close_service issp $service

if {$lines != 0xf || $oe != 0} {
    error [format "I2C buses did not recover idle-high: lines=0x%x oe=0x%x" $lines $oe]
}
puts [format "recovery=PASS pulses=%u" $pulses]
