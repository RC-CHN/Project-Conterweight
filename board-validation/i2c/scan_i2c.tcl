# Safe first-pass scan for the two Catapult v3 FPGA-controlled I2C buses.
# It emits each 7-bit address in the read direction. If the target ACKs, the
# controller receives one byte, NACKs that byte, and emits STOP. No target byte
# or target register address is written.

set REG_TFR_CMD  0x00
set REG_CTRL     0x08
set REG_ISER     0x0c
set REG_ISR      0x10
set REG_STATUS   0x14
set REG_TX_LEVEL 0x18
set REG_RX_LEVEL 0x1c
set REG_SCL_LOW  0x20
set REG_SCL_HIGH 0x24
set REG_SDA_HOLD 0x28

proc read32 {master address} {
    return [expr {[lindex [master_read_32 $master $address 1] 0]}]
}

proc write32 {master address value} {
    master_write_32 $master $address [list $value]
}

proc find_line_probe {} {
    foreach path [get_service_paths issp] {
        set candidate [claim_service issp $path i2c_line_reader]
        set info [issp_get_instance_info $candidate]
        if {[dict get $info instance_name] eq "I2CS"} {
            return [list $candidate $path]
        }
        close_service issp $candidate
    }
    error "I2CS line-state probe not found"
}

proc sample_lines {stage} {
    lassign [find_line_probe] service path
    set sample [expr {[issp_read_probe_data $service]}]
    after 20
    set sample2 [expr {[issp_read_probe_data $service]}]
    close_service issp $service

    set lines [expr {$sample2 & 0xf}]
    set oe [expr {($sample2 >> 4) & 0xf}]
    set reset_n [expr {($sample2 >> 8) & 1}]
    set heartbeat1 [expr {($sample >> 9) & 0xffffffff}]
    set heartbeat2 [expr {($sample2 >> 9) & 0xffffffff}]
    puts [format "%s: probe=%s lines=0x%x oe=0x%x reset_n=%u heartbeat_delta=%u path=%s" \
        $stage [format 0x%x $sample2] $lines $oe $reset_n \
        [expr {($heartbeat2 - $heartbeat1) & 0xffffffff}] $path]
    return [list $lines $oe $reset_n]
}

proc init_controller {master base} {
    global REG_CTRL REG_ISER REG_ISR REG_SCL_LOW REG_SCL_HIGH REG_SDA_HOLD

    # Intel HAL-equivalent standard-mode timing for 100 MHz / 100 kHz:
    # nominal half-period 500 clocks, adjusted by +/-60 clocks.
    write32 $master [expr {$base + $REG_CTRL}] 0
    write32 $master [expr {$base + $REG_ISER}] 0
    write32 $master [expr {$base + $REG_ISR}] 0x1c
    write32 $master [expr {$base + $REG_SCL_LOW}] 440
    write32 $master [expr {$base + $REG_SCL_HIGH}] 560
    write32 $master [expr {$base + $REG_SDA_HOLD}] 220
}

proc probe_address {master base address} {
    global REG_TFR_CMD REG_CTRL REG_ISR REG_STATUS REG_TX_LEVEL REG_RX_LEVEL

    write32 $master [expr {$base + $REG_CTRL}] 0
    write32 $master [expr {$base + $REG_ISR}] 0x1c
    write32 $master [expr {$base + $REG_CTRL}] 1

    # Address byte in the read direction. Intel's controller enters BUS_HOLD
    # after an address ACK, even if the address command carries STOP, so STOP
    # must be attached to a separate receive command after ACK is established.
    write32 $master [expr {$base + $REG_TFR_CMD}] \
        [expr {(($address & 0x7f) << 1) | 1}]

    # A NACKed address automatically generates STOP and becomes idle. An ACKed
    # address consumes the FIFO word and remains busy in BUS_HOLD. Waiting for
    # both conditions avoids leaving a second FIFO command behind after NACK.
    set address_done 0
    for {set i 0} {$i < 200} {incr i} {
        set status [read32 $master [expr {$base + $REG_STATUS}]]
        set tx_level [read32 $master [expr {$base + $REG_TX_LEVEL}]]
        if {(($status & 1) == 0) || ($tx_level == 0 && $i >= 10)} {
            set address_done 1
            break
        }
        after 1
    }

    set isr [read32 $master [expr {$base + $REG_ISR}]]
    if {!$address_done} {
        write32 $master [expr {$base + $REG_CTRL}] 0
        error [format "I2C address phase at base 0x%x timed out probing 0x%02x" $base $address]
    }
    if {$isr & 0x08} {
        write32 $master [expr {$base + $REG_CTRL}] 0
        error [format "I2C arbitration lost at base 0x%x probing 0x%02x" $base $address]
    }
    if {$isr & 0x04} {
        write32 $master [expr {$base + $REG_CTRL}] 0
        return 0
    }

    # ACK: receive exactly one byte, NACK it, and emit STOP. The command data
    # field is ignored in receive mode; only its STOP modifier is relevant.
    write32 $master [expr {$base + $REG_TFR_CMD}] 0x100
    set stopped 0
    for {set i 0} {$i < 200} {incr i} {
        if {([read32 $master [expr {$base + $REG_STATUS}]] & 1) == 0} {
            set stopped 1
            break
        }
        after 1
    }
    set isr [read32 $master [expr {$base + $REG_ISR}]]
    set rx_level [read32 $master [expr {$base + $REG_RX_LEVEL}]]
    if {$rx_level != 1} {
        write32 $master [expr {$base + $REG_CTRL}] 0
        error [format "Expected one received byte at base 0x%x address 0x%02x, FIFO level=%u" \
            $base $address $rx_level]
    }
    set value [read32 $master [expr {$base + 0x04}]]
    write32 $master [expr {$base + $REG_CTRL}] 0
    if {!$stopped} {
        error [format "I2C STOP at base 0x%x timed out after address 0x%02x" $base $address]
    }
    if {$isr & 0x08} {
        error [format "I2C arbitration lost at base 0x%x probing 0x%02x" $base $address]
    }
    return [list 1 [expr {$value & 0xff}]]
}

proc scan_bus {master label base pass} {
    set found {}
    set values {}
    for {set address 0x03} {$address <= 0x77} {incr address} {
        set result [probe_address $master $base $address]
        if {[lindex $result 0]} {
            lappend found $address
            lappend values [lindex $result 1]
        }
    }
    set printable {}
    foreach address $found value $values {
        lappend printable [format "0x%02x=0x%02x" $address $value]
    }
    puts [format "%s pass %u ACK/read-byte: %s" $label $pass [join $printable { }]]
    return [list $found $values]
}

refresh_connections
lassign [sample_lines preflight] lines oe reset_n
if {$reset_n != 1} {
    error "I2C bridge is still in reset"
}
if {$oe != 0} {
    error [format "I2C output-enable is unexpectedly active before scan: 0x%x" $oe]
}
if {$lines != 0xf} {
    error [format "I2C buses are not idle-high before scan: line bitmap 0x%x" $lines]
}

set paths [get_service_paths master]
if {[llength $paths] != 1} {
    error "Expected exactly one JTAG-to-Avalon master, found [llength $paths]: $paths"
}
set master_path [lindex $paths 0]
set master [claim_service master $master_path i2c_scanner]
puts "master_path=$master_path"

init_controller $master 0x00
init_controller $master 0x40

set ch1_first [scan_bus $master channel1 0x00 1]
set ch2_first [scan_bus $master channel2 0x40 1]
set ch1_second [scan_bus $master channel1 0x00 2]
set ch2_second [scan_bus $master channel2 0x40 2]

write32 $master [expr {0x00 + $REG_CTRL}] 0
write32 $master [expr {0x40 + $REG_CTRL}] 0
close_service master $master

if {[lindex $ch1_first 0] ne [lindex $ch1_second 0]} {
    error "Channel 1 scan was not repeatable: $ch1_first vs $ch1_second"
}
if {[lindex $ch2_first 0] ne [lindex $ch2_second 0]} {
    error "Channel 2 scan was not repeatable: $ch2_first vs $ch2_second"
}

lassign [sample_lines postflight] lines oe reset_n
if {$oe != 0 || $lines != 0xf} {
    error [format "I2C buses did not return idle-high: lines=0x%x oe=0x%x" $lines $oe]
}

puts "repeatability=PASS"
puts "target_data_bytes_written=0"
