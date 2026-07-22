# Read-only safety gate for the currently loaded qsfp_mgmt image.  The
# high-speed loopback SOF must not be loaded unless MODPRSL says that the cage
# is empty and the management I2C pins are released.

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

proc claim_qsfp_mgmt_probe {} {
    for {set attempt 0} {$attempt < 12} {incr attempt} {
        refresh_connections
        foreach path [get_service_paths issp] {
            if {[catch {set candidate [claim_service issp $path qsfp_no_module_preflight]}]} {
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
    error "QSM1 management probe not found; expected the qsfp_mgmt SRAM image"
}

lassign [claim_qsfp_mgmt_probe] service path
set raw0 [expr {[issp_read_probe_data $service]}]
after 500
set raw1 [expr {[issp_read_probe_data $service]}]
close_service issp $service

set lines [field $raw1 0 2]
set controller_oe [field $raw1 2 2]
set physical_oe [field $raw1 4 2]
set reset_n [field $raw1 6 1]
set modprsl [field $raw1 7 1]
set heartbeat0 [gray_to_binary [field $raw0 8 32]]
set heartbeat1 [gray_to_binary [field $raw1 8 32]]
set heartbeat_delta [expr {($heartbeat1 - $heartbeat0) & 0xffffffff}]

puts "issp_path=$path"
puts [format "lines=0x%x controller_oe=0x%x physical_oe=0x%x reset_n=%u" \
    $lines $controller_oe $physical_oe $reset_n]
puts [format "modprsl=%u module_present=%s heartbeat_delta=%u" \
    $modprsl [expr {$modprsl ? "NO" : "YES"}] $heartbeat_delta]

if {$heartbeat_delta == 0} {
    error "management heartbeat did not advance"
}
if {$lines != 3 || $controller_oe != 0 || $physical_oe != 0 || $reset_n != 1} {
    error "QSFP management pins are not released and idle-high"
}
if {$modprsl != 1} {
    error "QSFP module is present; refusing high-speed loopback SRAM load"
}

puts "qsfp_no_module_preflight=PASS"
