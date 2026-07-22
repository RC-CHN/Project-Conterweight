source [file join [file dirname [info script]] read_status.tcl]

set timeout_seconds 1800
if {[llength $argv] >= 1} {
    set timeout_seconds [lindex $argv 0]
}
if {$timeout_seconds < 60} {
    error "BIST timeout must be at least 60 seconds"
}

# Stop both masters, pulse the shared clear input while stopped, then start
# both together. Control bits are {clear, bottom enable, top enable}.
set_bist_control 0
set_bist_control 4
set_bist_control 0
set_bist_control 3

set start_ms [clock milliseconds]
set completed 0
while {!$completed} {
    after 5000
    lassign [read_bist_status] top bottom

    foreach label {top bottom} status [list $top $bottom] {
        if {[dict get $status errors] != 0} {
            set_bist_control 0
            error [format \
                "%s BIST failed: errors=%u first_error=0x%08x byte_mask=0x%016x" \
                $label \
                [dict get $status errors] \
                [dict get $status first_error_bytes] \
                [dict get $status error_byte_mask]]
        }
    }

    set completed [expr {
        [dict get $top passes] >= 1 && [dict get $bottom passes] >= 1
    }]
    set elapsed_ms [expr {[clock milliseconds] - $start_ms}]
    if {!$completed && $elapsed_ms >= $timeout_seconds * 1000} {
        set_bist_control 0
        error [format "Dual full-aperture BIST timed out after %.1f seconds" \
            [expr {$elapsed_ms / 1000.0}]]
    }
}

set_bist_control 0
lassign [read_bist_status] top bottom
if {[dict get $top running] || [dict get $bottom running]} {
    error "Both BIST engines did not stop"
}
if {[dict get $top errors] != 0 || [dict get $bottom errors] != 0} {
    error "A BIST error appeared while stopping"
}

read_ddr4_status 1
set elapsed_ms [expr {[clock milliseconds] - $start_ms}]
puts [format "dual_full_aperture_bist=PASS elapsed_seconds=%.3f" \
    [expr {$elapsed_ms / 1000.0}]]
puts "bytes_per_channel_per_pass=17179869184"
puts "usable_bytes_covered_per_channel=2147483648"
puts "simultaneous_channels=YES"
