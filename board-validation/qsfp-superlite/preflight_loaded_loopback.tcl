# Read-only safety gate for replacing an already loaded QSL1 loopback image.
# The new SOF must not be loaded unless the cage is empty and the old image's
# high-speed source is disabled.

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

proc claim_loopback_probe {} {
    for {set attempt 0} {$attempt < 20} {incr attempt} {
        refresh_connections
        foreach path [get_service_paths issp] {
            if {[catch {set candidate [claim_service issp $path qsfp_replace_preflight]}]} {
                continue
            }
            set info [issp_get_instance_info $candidate]
            if {[dict get $info instance_name] eq "QSL1"} {
                return [list $candidate $path]
            }
            close_service issp $candidate
        }
        after 250
    }
    error "QSL1 loopback probe not found"
}

lassign [claim_loopback_probe] service path
set raw0 [expr {[issp_read_probe_data $service]}]
after 500
set raw1 [expr {[issp_read_probe_data $service]}]
close_service issp $service

set modprsl [field $raw1 0 1]
set safe_enable [field $raw1 1 1]
set temp_valid [field $raw1 58 1]
set temp_raw [field $raw1 59 10]
set temp_c [expr {693.0 * $temp_raw / 1024.0 - 265.0}]
set source [field $raw1 69 8]
set heartbeat0 [gray_to_binary [field $raw0 77 32]]
set heartbeat1 [gray_to_binary [field $raw1 77 32]]
set heartbeat_delta [expr {($heartbeat1 - $heartbeat0) & 0xffffffff}]

puts "issp_path=$path"
puts [format "modprsl=%u module_present=%s safe_enable=%u source=0x%02x" \
    $modprsl [expr {$modprsl ? "NO" : "YES"}] $safe_enable $source]
puts [format "heartbeat_delta=%u temp_valid=%u temp_raw=%u temp_c=%.2f" \
    $heartbeat_delta $temp_valid $temp_raw $temp_c]

if {$modprsl != 1} {
    error "QSFP module is present; refusing loopback SRAM replacement"
}
if {$source != 0 || $safe_enable != 0} {
    error "loaded loopback image is not disabled"
}
if {$heartbeat_delta == 0} {
    error "loaded loopback heartbeat did not advance"
}
if {$temp_valid != 1 || $temp_c >= 90.0} {
    error [format "temperature gate failed: valid=%u temp_c=%.2f" \
        $temp_valid $temp_c]
}

puts "qsfp_loaded_loopback_preflight=PASS"
