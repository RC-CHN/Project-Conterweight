# Read-only diagnostics for the Catapult v3 dual-I2C validation image.
# This script samples physical line/OE state and controller CSRs. It performs
# no Avalon writes and emits no I2C transactions.

proc read32 {master address} {
    return [expr {[lindex [master_read_32 $master $address 1] 0]}]
}

proc find_line_probe {} {
    set paths [get_service_paths issp]
    puts "issp_paths=$paths"
    foreach path $paths {
        set candidate [claim_service issp $path i2c_line_inspector]
        set info [issp_get_instance_info $candidate]
        puts "issp_candidate=$path info=$info"
        if {[dict get $info instance_name] eq "I2CS"} {
            return [list $candidate $path]
        }
        close_service issp $candidate
    }
    error "I2CS line-state probe not found"
}

refresh_connections
lassign [find_line_probe] probe probe_path
set sample [expr {[issp_read_probe_data $probe]}]
close_service issp $probe

set lines [expr {$sample & 0xf}]
set oe [expr {($sample >> 4) & 0xf}]
set reset_n [expr {($sample >> 8) & 1}]
set heartbeat [expr {($sample >> 9) & 0xffffffff}]
puts [format "probe=%s lines=0x%x oe=0x%x reset_n=%u heartbeat=0x%08x path=%s" \
    [format 0x%x $sample] $lines $oe $reset_n $heartbeat $probe_path]

set paths [get_service_paths master]
if {[llength $paths] != 1} {
    error "Expected exactly one JTAG-to-Avalon master, found [llength $paths]: $paths"
}
set master [claim_service master [lindex $paths 0] i2c_register_inspector]

foreach {label base} {channel1 0x00 channel2 0x40} {
    set ctrl [read32 $master [expr {$base + 0x08}]]
    set iser [read32 $master [expr {$base + 0x0c}]]
    set isr [read32 $master [expr {$base + 0x10}]]
    set status [read32 $master [expr {$base + 0x14}]]
    set tx_level [read32 $master [expr {$base + 0x18}]]
    set rx_level [read32 $master [expr {$base + 0x1c}]]
    puts [format "%s ctrl=0x%08x iser=0x%08x isr=0x%08x status=0x%08x tx_level=%u rx_level=%u" \
        $label $ctrl $iser $isr $status $tx_level $rx_level]
}

close_service master $master
