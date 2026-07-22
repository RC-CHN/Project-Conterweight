# Targeted, read-only identification/status reads after scan_i2c.tcl has
# established the ACK address set. Pointer/command bytes select read-only
# registers; this script never writes a target register value.

set REG_TFR_CMD  0x00
set REG_RX_DATA  0x04
set REG_CTRL     0x08
set REG_ISER     0x0c
set REG_ISR      0x10
set REG_STATUS   0x14
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
    for {set attempt 0} {$attempt < 12} {incr attempt} {
        refresh_connections
        foreach path [get_service_paths issp] {
            if {[catch {set candidate [claim_service issp $path i2c_id_line_reader]}]} {
                continue
            }
            set info [issp_get_instance_info $candidate]
            if {[dict get $info instance_name] eq "I2CS"} {
                return $candidate
            }
            close_service issp $candidate
        }
        after 250
    }
    error "I2CS line-state probe not found"
}

proc wait_for_master_path {} {
    for {set attempt 0} {$attempt < 12} {incr attempt} {
        refresh_connections
        set paths [get_service_paths master]
        if {[llength $paths] == 1} {
            return [lindex $paths 0]
        }
        after 250
    }
    error "Expected exactly one JTAG-to-Avalon master, found [llength $paths]: $paths"
}

proc sample_bus {} {
    set service [find_line_probe]
    set value [expr {[issp_read_probe_data $service]}]
    close_service issp $service
    return [list [expr {$value & 0xf}] [expr {($value >> 4) & 0xf}] \
        [expr {($value >> 8) & 1}]]
}

proc init_controller {master base} {
    global REG_CTRL REG_ISER REG_ISR REG_SCL_LOW REG_SCL_HIGH REG_SDA_HOLD
    write32 $master [expr {$base + $REG_CTRL}] 0
    write32 $master [expr {$base + $REG_ISER}] 0
    write32 $master [expr {$base + $REG_ISR}] 0x1c
    write32 $master [expr {$base + $REG_SCL_LOW}] 440
    write32 $master [expr {$base + $REG_SCL_HIGH}] 560
    write32 $master [expr {$base + $REG_SDA_HOLD}] 220
}

proc wait_idle {master base operation} {
    global REG_STATUS
    for {set i 0} {$i < 300} {incr i} {
        if {([read32 $master [expr {$base + $REG_STATUS}]] & 1) == 0} {
            return
        }
        after 1
    }
    error "$operation timed out"
}

proc select_pointer {master base address pointer} {
    global REG_TFR_CMD REG_CTRL REG_ISR
    write32 $master [expr {$base + $REG_CTRL}] 0
    write32 $master [expr {$base + $REG_ISR}] 0x1c
    write32 $master [expr {$base + $REG_CTRL}] 1
    write32 $master [expr {$base + $REG_TFR_CMD}] [expr {($address & 0x7f) << 1}]
    write32 $master [expr {$base + $REG_TFR_CMD}] [expr {($pointer & 0xff) | 0x100}]
    wait_idle $master $base [format "pointer select 0x%02x at 0x%02x" $pointer $address]
    set isr [read32 $master [expr {$base + $REG_ISR}]]
    write32 $master [expr {$base + $REG_CTRL}] 0
    if {$isr & 0x08} {
        error [format "arbitration lost selecting pointer 0x%02x at 0x%02x" $pointer $address]
    }
    if {$isr & 0x04} {
        error [format "NACK selecting pointer 0x%02x at 0x%02x" $pointer $address]
    }
}

proc receive_bytes {master base address count} {
    global REG_TFR_CMD REG_RX_DATA REG_CTRL REG_ISR REG_RX_LEVEL
    write32 $master [expr {$base + $REG_CTRL}] 0
    write32 $master [expr {$base + $REG_ISR}] 0x1c
    write32 $master [expr {$base + $REG_CTRL}] 1
    write32 $master [expr {$base + $REG_TFR_CMD}] [expr {(($address & 0x7f) << 1) | 1}]
    for {set i 0} {$i < $count} {incr i} {
        set command 0
        if {$i == ($count - 1)} {
            set command 0x100
        }
        write32 $master [expr {$base + $REG_TFR_CMD}] $command
    }
    wait_idle $master $base [format "read %u byte(s) from 0x%02x" $count $address]
    set isr [read32 $master [expr {$base + $REG_ISR}]]
    set level [read32 $master [expr {$base + $REG_RX_LEVEL}]]
    set data {}
    while {$level > 0} {
        lappend data [expr {[read32 $master [expr {$base + $REG_RX_DATA}]] & 0xff}]
        incr level -1
    }
    write32 $master [expr {$base + $REG_CTRL}] 0
    if {$isr & 0x08} {
        error [format "arbitration lost reading 0x%02x" $address]
    }
    if {$isr & 0x04} {
        error [format "NACK reading 0x%02x" $address]
    }
    if {[llength $data] != $count} {
        error [format "read 0x%02x returned %u byte(s), expected %u" \
            $address [llength $data] $count]
    }
    return $data
}

proc read_register {master label base address pointer count} {
    if {[catch {
        select_pointer $master $base $address $pointer
        set data [receive_bytes $master $base $address $count]
    } message]} {
        puts [format "%s address=0x%02x pointer=0x%02x result=UNSUPPORTED detail=%s" \
            $label $address $pointer $message]
        return {}
    }
    set printable {}
    foreach value $data {
        lappend printable [format "0x%02x" $value]
    }
    puts [format "%s address=0x%02x pointer=0x%02x data=%s" \
        $label $address $pointer [join $printable { }]]
    return $data
}

refresh_connections
lassign [sample_bus] lines oe reset_n
puts [format "preflight lines=0x%x oe=0x%x reset_n=%u" $lines $oe $reset_n]
if {$lines != 0xf || $oe != 0 || $reset_n != 1} {
    error "I2C buses are not idle and released before ID reads"
}

set master_path [wait_for_master_path]
puts "master_path=$master_path"
set master [claim_service master $master_path i2c_id_reader]
init_controller $master 0x00
init_controller $master 0x40

# DS250DF810 programming register map is not public. The scan's current-byte
# read is retained as proof of a responding target; no undocumented pointer is
# selected here.
set retimer [receive_bytes $master 0x00 0x22 1]
puts [format "retimer-current address=0x22 data=0x%02x" [lindex $retimer 0]]

# TMP411 identification registers are read-only (FEh/FFh); 00h and 01h are
# local and remote temperature high-byte pointers.
set tmp_mfr [read_register $master tmp411-mfr 0x40 0x4c 0xfe 1]
set tmp_dev [read_register $master tmp411-device 0x40 0x4c 0xff 1]
set tmp_local [read_register $master tmp411-local-temp 0x40 0x4c 0x00 2]
set tmp_remote [read_register $master tmp411-remote-temp 0x40 0x4c 0x01 2]

# PMBus command 99h is MFR_ID. Reading four bytes captures the block count and
# up to three vendor characters without altering operation or fault state.
read_register $master pmbus-mfr-id-40 0x40 0x40 0x99 4
read_register $master pmbus-mfr-id-42 0x40 0x42 0x99 4

# Additional low-risk discrimination for address 0x40. These LM25066 commands
# are all read-only: CAPABILITY, STATUS_BYTE, and READ_VIN. A NACK or an
# incompatible response leaves the target unidentified and does not trigger a
# fallback write.
set raw40 [receive_bytes $master 0x40 0x40 4]
set raw40_printable {}
foreach value $raw40 {
    lappend raw40_printable [format "0x%02x" $value]
}
puts "address-40-current-four data=[join $raw40_printable { }]"
read_register $master address-40-capability 0x40 0x40 0x19 1
read_register $master address-40-status-byte 0x40 0x40 0x78 1
read_register $master address-40-read-vin 0x40 0x40 0x88 2

# PCA9535 commands 06h/07h are configuration registers. They are read-only in
# this transaction; all ones is the expected power-up input configuration.
read_register $master pca9535-config-candidate 0x40 0x27 0x06 2

close_service master $master
lassign [sample_bus] lines oe reset_n
puts [format "postflight lines=0x%x oe=0x%x reset_n=%u" $lines $oe $reset_n]
if {$lines != 0xf || $oe != 0} {
    error "I2C buses did not return idle-high after ID reads"
}
puts "target_configuration_bytes_written=0"
