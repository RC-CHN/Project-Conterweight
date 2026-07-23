source [file join [file dirname [info script]] read_status.tcl]

set duration_seconds 7200
set poll_seconds 30
if {[llength $argv] >= 1} {
    set duration_seconds [lindex $argv 0]
}
if {[llength $argv] >= 2} {
    set poll_seconds [lindex $argv 1]
}
if {$duration_seconds < 60} {
    error "endurance duration must be at least 60 seconds"
}
if {$poll_seconds < 5 || $poll_seconds > 60} {
    error "poll interval must be between 5 and 60 seconds"
}

set pre [read_ddr4_status 1]
set min_temp [dict get $pre temperature_c]
set max_temp $min_temp
set_bist_control 0
set_bist_control 4
set_bist_control 0
set_bist_control 3

set start_ms [clock milliseconds]
set deadline_ms [expr {$start_ms + $duration_seconds * 1000}]
set run_rc [catch {
    while {[clock milliseconds] < $deadline_ms} {
        set remaining_ms [expr {$deadline_ms - [clock milliseconds]}]
        set wait_ms [expr {min($poll_seconds * 1000, $remaining_ms)}]
        after $wait_ms

        lassign [read_bist_status] top bottom
        if {[dict get $top errors] != 0 || [dict get $bottom errors] != 0} {
            error "a data mismatch occurred during endurance testing"
        }
        set health [read_ddr4_status 1]
        set temp [dict get $health temperature_c]
        set min_temp [expr {min($min_temp, $temp)}]
        set max_temp [expr {max($max_temp, $temp)}]
        puts [format "endurance_elapsed_seconds=%.1f temperature_c=%.2f" \
            [expr {([clock milliseconds] - $start_ms) / 1000.0}] $temp]
    }
} run_error run_options]

# Stop traffic even if a status claim, temperature gate, calibration check or
# data check throws.  Preserve the original failure after the cleanup attempt.
set stop_rc [catch {set_bist_control 0} stop_error]
if {$run_rc} {
    if {$stop_rc} {
        append run_error "; cleanup also failed: $stop_error"
    }
    return -options $run_options $run_error
}
if {$stop_rc} {
    error "endurance cleanup failed: $stop_error"
}

lassign [read_bist_status] top bottom
set final_health [read_ddr4_status 1]
if {[dict get $top running] || [dict get $bottom running]} {
    error "both traffic generators did not stop"
}
if {[dict get $top passes] < 1 || [dict get $bottom passes] < 1} {
    error "each channel must complete at least one checked pass"
}
if {[dict get $top errors] != 0 || [dict get $bottom errors] != 0} {
    error "a data mismatch appeared while stopping"
}

set top_checked_bytes [expr {[dict get $top passes] * 17179869184}]
set bottom_checked_bytes [expr {[dict get $bottom passes] * 17179869184}]
puts [format \
    "endurance_summary: requested_seconds=%u elapsed_seconds=%.1f top_passes=%u bottom_passes=%u top_checked_bytes=%s bottom_checked_bytes=%s min_temp_c=%.2f max_temp_c=%.2f final_temp_c=%.2f errors=0" \
    $duration_seconds [expr {([clock milliseconds] - $start_ms) / 1000.0}] \
    [dict get $top passes] [dict get $bottom passes] \
    $top_checked_bytes $bottom_checked_bytes $min_temp $max_temp \
    [dict get $final_health temperature_c]]
puts "ddr4_endurance_test=PASS"
