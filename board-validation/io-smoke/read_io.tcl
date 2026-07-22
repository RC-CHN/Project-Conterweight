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

proc counter_delta {new old} {
    return [expr {($new - $old) & 0xffffffff}]
}

proc decode_counter {snapshot lsb} {
    return [gray_to_binary [field $snapshot $lsb 32]]
}

refresh_connections
set paths [get_service_paths issp]
if {[llength $paths] == 0} {
    error "No ISSP service found"
}

set service ""
set selected_path ""
foreach path $paths {
    set candidate [claim_service issp $path io_smoke_reader]
    set info [issp_get_instance_info $candidate]
    if {[dict get $info instance_name] eq "IOV1"} {
        set service $candidate
        set selected_path $path
        break
    }
    close_service issp $candidate
}
if {$service eq ""} {
    error "IOV1 ISSP instance not found"
}

puts "issp_path=$selected_path"
puts "instance=[issp_get_instance_info $service]"
set raw0 [issp_read_probe_data $service]
after 500
set raw1 [issp_read_probe_data $service]
close_service issp $service

set sample0 [expr $raw0]
set sample1 [expr $raw1]

set names {u59 y3 y4 y5 y6}
set offsets {0 32 64 96 128}
set deltas {}
foreach name $names lsb $offsets {
    set old [decode_counter $sample0 $lsb]
    set new [decode_counter $sample1 $lsb]
    set delta [counter_delta $new $old]
    lappend deltas $delta
    puts [format "counter_%-3s old=0x%08x new=0x%08x delta=%u" $name $old $new $delta]
}

set reference [lindex $deltas 0]
if {$reference == 0} {
    error "U59 reference counter did not advance"
}

puts "relative_frequency_assuming_u59_100mhz:"
foreach name [lrange $names 1 end] delta [lrange $deltas 1 end] {
    puts [format "  %-3s %.6f MHz (ratio %.9f)" $name \
        [expr {100.0 * 32.0 * $delta / $reference}] \
        [expr {32.0 * $delta / $reference}]]
}

puts [format "gpio_j11=0x%x" [field $sample1 160 3]]
puts [format "led_drive=0x%03x" [field $sample1 163 9]]
puts [format "led_index=%u" [field $sample1 172 4]]
puts [format "source_control=0x%04x" [field $sample1 176 16]]

