source [file join [file dirname [info script]] read_status.tcl]

# The full-aperture BIST is the other master on each controller and starts by
# default after configuration. Stop it and allow any accepted read to drain
# before issuing focused JTAG-to-Avalon transactions.
set_bist_control 0
lassign [read_bist_status] top_bist bottom_bist
if {[dict get $top_bist running] || [dict get $bottom_bist running]} {
    error "Failed to stop both full-aperture BIST engines"
}

proc words_to_hex {words} {
    set result {}
    foreach word $words {
        lappend result [format "0x%08x" [expr {$word & 0xffffffff}]]
    }
    return [join $result { }]
}

proc test_location {master label address seed} {
    set values {}
    for {set i 0} {$i < 16} {incr i} {
        lappend values [expr {($seed ^ $address ^ ($i * 0x10204081)) & 0xffffffff}]
    }

    # Sixteen 32-bit words cover one 64-byte ECC data line. The JTAG master is
    # narrow, so the generated width adapter may implement these as partial
    # read-modify-writes. Check the exported ECC interrupt immediately after
    # every line and stop on the first indication rather than continuing over
    # a large address range.
    master_write_32 $master $address $values
    set actual [master_read_32 $master $address 16]
    for {set i 0} {$i < 16} {incr i} {
        set expected_word [expr {[lindex $values $i] & 0xffffffff}]
        set actual_word [expr {[lindex $actual $i] & 0xffffffff}]
        if {$actual_word != $expected_word} {
            error [format "%s mismatch at 0x%08x word %u: expected %s actual %s" \
                $label $address $i [words_to_hex $values] [words_to_hex $actual]]
        }
    }
    read_ddr4_status 1
    puts [format "%s address=0x%08x words=16 PASS" $label $address]
}

# read_status.tcl performs the mandatory calibration/clock/ECC preflight when
# sourced. EMIF also exposes an internal calibration/debug master; select only
# the two explicit JTAG-to-Avalon data masters created by this design.
set paths {}
foreach path [get_service_paths master] {
    if {[string match -nocase *master_top.master $path] ||
            [string match -nocase *master_bot.master $path]} {
        lappend paths $path
    }
}
if {[llength $paths] != 2} {
    error "Expected explicit top/bottom data masters, found [llength $paths]: $paths"
}

puts "master_paths=$paths"
set claimed {}
set labels {}
foreach path $paths {
    if {[string match -nocase *top* $path]} {
        set label top
    } elseif {[string match -nocase *bot* $path]} {
        set label bottom
    } else {
        set label channel[llength $claimed]
    }
    lappend claimed [claim_service master $path ddr4_memory_test]
    lappend labels $label
}

# Sample low, row/bank-boundary-like powers of two, and the final 64-byte line
# in each controller's 2 GiB Avalon aperture. This is a bring-up test, not the
# later full-capacity or simultaneous traffic-generator stress test.
set addresses {
    0x00000000 0x00001000 0x00100000 0x01000000
    0x10000000 0x40000000 0x7fffffc0
}

set seed 0x6d5a1234
foreach master $claimed label $labels {
    foreach address $addresses {
        test_location $master $label $address $seed
        set seed [expr {(($seed << 1) ^ (($seed >> 31) ? 0x04c11db7 : 0)) & 0xffffffff}]
    }
}

foreach master $claimed {
    close_service master $master
}

read_ddr4_status 1
puts "sampled_dual_ddr4=PASS"
puts "sampled_script_full_capacity_tested=NO"
puts "sampled_script_simultaneous_stress_tested=NO"
