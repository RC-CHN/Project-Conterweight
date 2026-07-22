proc field {value lsb width} {
    return [expr {($value >> $lsb) & ((1 << $width) - 1)}]
}

proc drive_and_check {service value expected} {
    issp_write_source_data $service [format 0x%04x $value]
    after 100
    set snapshot [expr [issp_read_probe_data $service]]
    set actual [field $snapshot 163 9]
    if {$actual != $expected} {
        error [format "LED readback mismatch: source=0x%04x expected=0x%03x actual=0x%03x" \
            $value $expected $actual]
    }
    puts [format "source=0x%04x led_drive=0x%03x verified" $value $actual]
}

refresh_connections
set paths [get_service_paths issp]
if {[llength $paths] == 0} {
    error "No ISSP service found"
}

set service ""
foreach path $paths {
    set candidate [claim_service issp $path io_smoke_led_walk]
    set info [issp_get_instance_info $candidate]
    if {[dict get $info instance_name] eq "IOV1"} {
        set service $candidate
        break
    }
    close_service issp $candidate
}
if {$service eq ""} {
    error "IOV1 ISSP instance not found"
}

# Manual-enable is bit 9. Drive exactly one FPGA LED pin high at a time, then
# exactly one low at a time. Both passes make the physical LED polarity clear.
puts "one-high pass"
for {set index 0} {$index < 9} {incr index} {
    set pins [expr {1 << $index}]
    set source [expr {0x200 | $pins}]
    drive_and_check $service $source $pins
    after 400
}

puts "one-low pass"
for {set index 0} {$index < 9} {incr index} {
    set pins [expr {0x1ff ^ (1 << $index)}]
    set source [expr {0x200 | $pins}]
    drive_and_check $service $source $pins
    after 400
}

# Return to the autonomous walk.
issp_write_source_data $service 0x0000
after 100
set snapshot [expr [issp_read_probe_data $service]]
if {[field $snapshot 176 16] != 0} {
    error "Failed to return source control to automatic mode"
}
close_service issp $service
puts "returned to automatic one-hot walk"

