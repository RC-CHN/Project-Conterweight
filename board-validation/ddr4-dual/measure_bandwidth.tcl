source [file join [file dirname [info script]] read_status.tcl]

set user_clock_hz 200000000.0
if {[info exists ::ddr4_user_clock_hz]} {
    set user_clock_hz $::ddr4_user_clock_hz
}
set timeout_seconds 180
if {[llength $argv] >= 1} {
    set timeout_seconds [lindex $argv 0]
}

set phase_bytes 8589934592.0
set theoretical_bytes_per_second [expr {$user_clock_hz * 64.0}]

proc bandwidth_gbs {bytes cycles clock_hz} {
    return [expr {$bytes * $clock_hz / double($cycles) / 1.0e9}]
}

proc bandwidth_gib_s {bytes cycles clock_hz} {
    return [expr {$bytes * $clock_hz / double($cycles) / 1073741824.0}]
}

proc print_bandwidth {label status phase_bytes user_clock_hz theoretical_bps} {
    set write_cycles [dict get $status last_write_cycles]
    set read_cycles [dict get $status last_read_cycles]
    if {$write_cycles <= 0 || $read_cycles <= 0} {
        error "$label did not publish non-zero phase cycle counters"
    }
    set write_gbs [bandwidth_gbs $phase_bytes $write_cycles $user_clock_hz]
    set read_gbs [bandwidth_gbs $phase_bytes $read_cycles $user_clock_hz]
    set combined_gbs [bandwidth_gbs [expr {2.0 * $phase_bytes}] \
        [expr {$write_cycles + $read_cycles}] $user_clock_hz]
    puts [format \
        "%s_bandwidth: write_cycles=%s read_cycles=%s write=%.3f_GB/s(%.3f_GiB/s,%.2f%%) read=%.3f_GB/s(%.3f_GiB/s,%.2f%%) sequential_rw=%.3f_GB/s" \
        $label $write_cycles $read_cycles \
        $write_gbs [bandwidth_gib_s $phase_bytes $write_cycles $user_clock_hz] \
        [expr {100.0 * $write_gbs * 1.0e9 / $theoretical_bps}] \
        $read_gbs [bandwidth_gib_s $phase_bytes $read_cycles $user_clock_hz] \
        [expr {100.0 * $read_gbs * 1.0e9 / $theoretical_bps}] \
        $combined_gbs]
}

read_ddr4_status 1
set_bist_control 0
set_bist_control 4
set_bist_control 0
set_bist_control 3

set start_ms [clock milliseconds]
while {1} {
    after 250
    lassign [read_bist_status] top bottom
    if {[dict get $top errors] != 0 || [dict get $bottom errors] != 0} {
        set_bist_control 0
        error "a data mismatch occurred during the bandwidth pass"
    }
    if {[dict get $top passes] >= 1 && [dict get $bottom passes] >= 1} {
        break
    }
    if {[clock milliseconds] - $start_ms >= $timeout_seconds * 1000} {
        set_bist_control 0
        error "bandwidth pass timed out after $timeout_seconds seconds"
    }
}

set_bist_control 0
lassign [read_bist_status] top bottom
if {[dict get $top running] || [dict get $bottom running]} {
    error "both traffic generators did not stop"
}
if {[dict get $top errors] != 0 || [dict get $bottom errors] != 0} {
    error "a data mismatch appeared while stopping"
}

print_bandwidth top $top $phase_bytes $user_clock_hz \
    $theoretical_bytes_per_second
print_bandwidth bottom $bottom $phase_bytes $user_clock_hz \
    $theoretical_bytes_per_second

set top_total [expr {[dict get $top last_write_cycles] + \
    [dict get $top last_read_cycles]}]
set bottom_total [expr {[dict get $bottom last_write_cycles] + \
    [dict get $bottom last_read_cycles]}]
set slowest_total [expr {max($top_total, $bottom_total)}]
set aggregate_gbs [bandwidth_gbs [expr {4.0 * $phase_bytes}] \
    $slowest_total $user_clock_hz]
puts [format \
    "dual_channel_checked_bandwidth: aggregate_sequential_rw=%.3f_GB/s payload_per_channel=16_GiB errors=0" \
    $aggregate_gbs]
read_ddr4_status 1
puts "ddr4_bandwidth_test=PASS"
