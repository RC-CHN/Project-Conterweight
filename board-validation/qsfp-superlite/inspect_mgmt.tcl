# Read-only QSFP management-plane inspection.  Pointer bytes select registers;
# no target configuration value is written.

set REG_TFR_CMD  0x00
set REG_RX_DATA  0x04
set REG_CTRL     0x08
set REG_ISER     0x0c
set REG_ISR      0x10
set REG_STATUS   0x14
set REG_TX_LEVEL 0x18
set REG_RX_LEVEL 0x1c
set REG_SCL_LOW  0x20
set REG_SCL_HIGH 0x24
set REG_SDA_HOLD 0x28

proc field {value lsb width} {
    return [expr {($value >> $lsb) & ((1 << $width) - 1)}]
}

proc gray_to_binary {gray} {
    set binary $gray
    for {set shift 1} {$shift < 32} {set shift [expr {$shift * 2}]} {
        set binary [expr {$binary ^ ($binary >> $shift)}]
    }
    return [expr {$binary & 0xffffffff}]
}

proc find_qsfp_probe {} {
    for {set attempt 0} {$attempt < 12} {incr attempt} {
        refresh_connections
        foreach path [get_service_paths issp] {
            if {[catch {set candidate [claim_service issp $path qsfp_mgmt_reader]}]} {
                continue
            }
            set info [issp_get_instance_info $candidate]
            if {[dict get $info instance_name] eq "QSM1"} {
                return [list $candidate $path]
            }
            close_service issp $candidate
        }
        after 250
    }
    error "QSM1 management probe not found"
}

proc sample_management {} {
    lassign [find_qsfp_probe] service path
    set raw [expr {[issp_read_probe_data $service]}]
    close_service issp $service
    return [list $raw $path]
}

proc read32 {master address} {
    return [expr {[lindex [master_read_32 $master $address 1] 0]}]
}

proc write32 {master address value} {
    master_write_32 $master $address [list $value]
}

proc init_controller {master} {
    global REG_CTRL REG_ISER REG_ISR REG_SCL_LOW REG_SCL_HIGH REG_SDA_HOLD
    write32 $master $REG_CTRL 0
    write32 $master $REG_ISER 0
    write32 $master $REG_ISR 0x1c
    write32 $master $REG_SCL_LOW 440
    write32 $master $REG_SCL_HIGH 560
    write32 $master $REG_SDA_HOLD 220
}

proc wait_idle {master operation} {
    global REG_STATUS
    for {set i 0} {$i < 300} {incr i} {
        if {([read32 $master $REG_STATUS] & 1) == 0} {
            return
        }
        after 1
    }
    error "$operation timed out"
}

proc probe_address {master address} {
    global REG_TFR_CMD REG_CTRL REG_ISR REG_STATUS REG_TX_LEVEL REG_RX_LEVEL REG_RX_DATA

    write32 $master $REG_CTRL 0
    write32 $master $REG_ISR 0x1c
    write32 $master $REG_CTRL 1
    write32 $master $REG_TFR_CMD [expr {(($address & 0x7f) << 1) | 1}]

    set address_done 0
    for {set i 0} {$i < 200} {incr i} {
        set status [read32 $master $REG_STATUS]
        set tx_level [read32 $master $REG_TX_LEVEL]
        if {(($status & 1) == 0) || ($tx_level == 0 && $i >= 10)} {
            set address_done 1
            break
        }
        after 1
    }
    set isr [read32 $master $REG_ISR]
    if {!$address_done || ($isr & 0x08)} {
        write32 $master $REG_CTRL 0
        error [format "address phase failed at 0x%02x" $address]
    }
    if {$isr & 0x04} {
        write32 $master $REG_CTRL 0
        return [list 0 0]
    }

    write32 $master $REG_TFR_CMD 0x100
    wait_idle $master [format "STOP after address 0x%02x" $address]
    set isr [read32 $master $REG_ISR]
    set level [read32 $master $REG_RX_LEVEL]
    if {$isr & 0x0c || $level != 1} {
        write32 $master $REG_CTRL 0
        error [format "read termination failed at 0x%02x, ISR=0x%x RX_LEVEL=%u" \
            $address $isr $level]
    }
    set value [expr {[read32 $master $REG_RX_DATA] & 0xff}]
    write32 $master $REG_CTRL 0
    return [list 1 $value]
}

proc select_pointer {master address pointer} {
    global REG_TFR_CMD REG_CTRL REG_ISR
    write32 $master $REG_CTRL 0
    write32 $master $REG_ISR 0x1c
    write32 $master $REG_CTRL 1
    write32 $master $REG_TFR_CMD [expr {($address & 0x7f) << 1}]
    write32 $master $REG_TFR_CMD [expr {($pointer & 0xff) | 0x100}]
    wait_idle $master [format "pointer 0x%02x at 0x%02x" $pointer $address]
    set isr [read32 $master $REG_ISR]
    write32 $master $REG_CTRL 0
    if {$isr & 0x0c} {
        error [format "pointer 0x%02x at 0x%02x failed, ISR=0x%x" \
            $pointer $address $isr]
    }
}

proc receive_bytes {master address count} {
    global REG_TFR_CMD REG_RX_DATA REG_CTRL REG_ISR REG_RX_LEVEL
    write32 $master $REG_CTRL 0
    write32 $master $REG_ISR 0x1c
    write32 $master $REG_CTRL 1
    write32 $master $REG_TFR_CMD [expr {(($address & 0x7f) << 1) | 1}]
    for {set i 0} {$i < $count} {incr i} {
        write32 $master $REG_TFR_CMD [expr {$i == ($count - 1) ? 0x100 : 0}]
    }
    wait_idle $master [format "read %u byte(s) from 0x%02x" $count $address]
    set isr [read32 $master $REG_ISR]
    set level [read32 $master $REG_RX_LEVEL]
    set data {}
    while {$level > 0} {
        lappend data [expr {[read32 $master $REG_RX_DATA] & 0xff}]
        incr level -1
    }
    write32 $master $REG_CTRL 0
    if {$isr & 0x0c || [llength $data] != $count} {
        error [format "read 0x%02x failed, ISR=0x%x bytes=%u expected=%u" \
            $address $isr [llength $data] $count]
    }
    return $data
}

proc read_register {master address pointer count} {
    select_pointer $master $address $pointer
    return [receive_bytes $master $address $count]
}

proc hex_bytes {data} {
    set printable {}
    foreach value $data {
        lappend printable [format "0x%02x" $value]
    }
    return [join $printable { }]
}

proc ascii_bytes {data} {
    set text ""
    foreach value $data {
        if {$value >= 0x20 && $value <= 0x7e} {
            append text [format %c $value]
        } else {
            append text "."
        }
    }
    return $text
}

refresh_connections
lassign [sample_management] sample0 probe_path
after 500
lassign [sample_management] sample1 ignored_path

set lines [field $sample1 0 2]
set controller_oe [field $sample1 2 2]
set physical_oe [field $sample1 4 2]
set reset_n [field $sample1 6 1]
set modprsl [field $sample1 7 1]
set heartbeat0 [gray_to_binary [field $sample0 8 32]]
set heartbeat1 [gray_to_binary [field $sample1 8 32]]
set y5_0 [gray_to_binary [field $sample0 40 32]]
set y5_1 [gray_to_binary [field $sample1 40 32]]
set heartbeat_delta [expr {($heartbeat1 - $heartbeat0) & 0xffffffff}]
set y5_delta [expr {($y5_1 - $y5_0) & 0xffffffff}]

puts "issp_path=$probe_path"
puts [format "preflight lines=0x%x controller_oe=0x%x physical_oe=0x%x reset_n=%u" \
    $lines $controller_oe $physical_oe $reset_n]
puts [format "modprsl=%u module_present=%s" $modprsl [expr {$modprsl ? "NO" : "YES"}]]
puts [format "heartbeat_delta=%u y5_event_delta=%u" $heartbeat_delta $y5_delta]
if {$heartbeat_delta == 0} {
    error "100 MHz management heartbeat did not advance"
}
puts [format "y5_frequency_assuming_u59_100mhz=%.6f_MHz" \
    [expr {100.0 * 32.0 * $y5_delta / $heartbeat_delta}]]
if {$lines != 3 || $controller_oe != 0 || $physical_oe != 0 || $reset_n != 1} {
    error "management bus is not released and idle-high before inspection"
}

set master_paths [get_service_paths master]
if {[llength $master_paths] != 1} {
    error "Expected one JTAG-to-Avalon master, found [llength $master_paths]: $master_paths"
}
set master_path [lindex $master_paths 0]
set master [claim_service master $master_path qsfp_mgmt_i2c_reader]
puts "master_path=$master_path"
init_controller $master

lassign [probe_address $master 0x22] retimer_ack retimer_current
puts [format "retimer address=0x22 ack=%s current_byte=0x%02x" \
    [expr {$retimer_ack ? "YES" : "NO"}] $retimer_current]
if {!$retimer_ack} {
    close_service master $master
    error "DS250DF810 did not ACK at 0x22"
}

foreach pointer {0xff 0x2f} {
    set value [read_register $master 0x22 $pointer 1]
    puts [format "retimer register=0x%02x data=%s" $pointer [hex_bytes $value]]
}

lassign [probe_address $master 0x50] module_ack module_current
puts [format "module-eeprom address=0x50 ack=%s current_byte=0x%02x" \
    [expr {$module_ack ? "YES" : "NO"}] $module_current]
if {$module_ack} {
    foreach {label pointer count} {
        identifier   0   1
        vendor     148  16
        part       168  16
        serial     196  16
    } {
        set data [read_register $master 0x50 $pointer $count]
        puts [format "module-%s offset=%u data=%s ascii=\"%s\"" \
            $label $pointer [hex_bytes $data] [ascii_bytes $data]]
    }
}

write32 $master $REG_CTRL 0
close_service master $master
after 20
lassign [sample_management] post_sample post_path
set post_lines [field $post_sample 0 2]
set post_controller_oe [field $post_sample 2 2]
set post_physical_oe [field $post_sample 4 2]
puts [format "postflight lines=0x%x controller_oe=0x%x physical_oe=0x%x" \
    $post_lines $post_controller_oe $post_physical_oe]
if {$post_lines != 3 || $post_controller_oe != 0 || $post_physical_oe != 0} {
    error "management bus did not return idle-high"
}
puts "target_configuration_bytes_written=0"
