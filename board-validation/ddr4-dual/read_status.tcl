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

proc temperature_c {raw} {
    return [expr {693.0 * [field $raw 478 10] / 1024.0 - 265.0}]
}

proc bist_channel_status {raw base} {
    set address_words [gray_to_binary [field $raw [expr {$base + 71}] 25]]
    set first_error_words [field $raw [expr {$base + 96}] 25]
    return [dict create \
        running [field $raw $base 1] \
        state [field $raw [expr {$base + 1}] 4] \
        pattern [field $raw [expr {$base + 5}] 2] \
        passes [gray_to_binary [field $raw [expr {$base + 7}] 32]] \
        errors [gray_to_binary [field $raw [expr {$base + 39}] 32]] \
        address_words $address_words \
        address_bytes [expr {$address_words << 6}] \
        first_error_words $first_error_words \
        first_error_bytes [expr {$first_error_words << 6}] \
        error_byte_mask [field $raw [expr {$base + 121}] 64]]
}

proc print_bist_channel {label status} {
    puts [format \
        "%s_bist: running=%u state=%u pattern=%u passes=%u errors=%u address=0x%08x first_error=0x%08x byte_mask=0x%016x" \
        $label \
        [dict get $status running] \
        [dict get $status state] \
        [dict get $status pattern] \
        [dict get $status passes] \
        [dict get $status errors] \
        [dict get $status address_bytes] \
        [dict get $status first_error_bytes] \
        [dict get $status error_byte_mask]]
}

proc claim_ddr4_probe {} {
    for {set attempt 0} {$attempt < 10} {incr attempt} {
        foreach path [get_service_paths issp] {
            if {[catch {set candidate [claim_service issp $path ddr4_status_reader]}]} {
                continue
            }
            set info [issp_get_instance_info $candidate]
            if {[dict get $info instance_name] eq "DDR4"} {
                return [list $candidate $path]
            }
            close_service issp $candidate
        }
        after 1000
        refresh_connections
    }
    error "DDR4 status probe not found after 10 service refresh attempts"
}

proc set_bist_control {value} {
    if {$value < 0 || $value > 7} {
        error "BIST control must fit in three bits"
    }
    lassign [claim_ddr4_probe] service path
    # The RTL maps the known-good raw ISSP power-up value 3 to logical zero,
    # keeping both BIST engines stopped until this script authorizes traffic.
    set raw_value [expr {$value ^ 3}]
    issp_write_source_data $service [format 0x%x $raw_value]
    close_service issp $service
    after 100
    return $path
}

proc read_bist_status {} {
    lassign [claim_ddr4_probe] service path
    set raw [expr {[issp_read_probe_data $service]}]
    close_service issp $service

    set top [bist_channel_status $raw 107]
    set bottom [bist_channel_status $raw 292]
    puts "issp_path=$path"
    puts [format "bist_control=0x%x" [field $raw 104 3]]
    print_bist_channel top $top
    print_bist_channel bottom $bottom
    return [list $top $bottom]
}

proc read_ddr4_status {{require_ready 1}} {
    lassign [claim_ddr4_probe] service path
    set raw0 [expr {[issp_read_probe_data $service]}]
    after 500
    set raw1 [expr {[issp_read_probe_data $service]}]
    close_service issp $service

    set u59_0 [gray_to_binary [field $raw0 0 32]]
    set u59_1 [gray_to_binary [field $raw1 0 32]]
    set bot_0 [gray_to_binary [field $raw0 32 32]]
    set bot_1 [gray_to_binary [field $raw1 32 32]]
    set top_0 [gray_to_binary [field $raw0 64 32]]
    set top_1 [gray_to_binary [field $raw1 64 32]]

    set u59_delta [counter_delta $u59_1 $u59_0]
    set bot_delta [counter_delta $bot_1 $bot_0]
    set top_delta [counter_delta $top_1 $top_0]

    set top_cal_success [field $raw1 96 1]
    set top_cal_fail [field $raw1 97 1]
    set top_pll_locked [field $raw1 98 1]
    set bot_cal_success [field $raw1 99 1]
    set bot_cal_fail [field $raw1 100 1]
    set bot_pll_locked [field $raw1 101 1]
    set top_ecc_interrupt [field $raw1 102 1]
    set bot_ecc_interrupt [field $raw1 103 1]
    set temp_valid [field $raw1 477 1]
    set temp_raw [field $raw1 478 10]
    set temp_c [temperature_c $raw1]

    puts "issp_path=$path"
    puts [format "heartbeat_delta: u59=%u top=%u bottom=%u" \
        $u59_delta $top_delta $bot_delta]
    puts [format "top: pll_locked=%u cal_success=%u cal_fail=%u ecc_interrupt=%u" \
        $top_pll_locked $top_cal_success $top_cal_fail $top_ecc_interrupt]
    puts [format "bottom: pll_locked=%u cal_success=%u cal_fail=%u ecc_interrupt=%u" \
        $bot_pll_locked $bot_cal_success $bot_cal_fail $bot_ecc_interrupt]
    puts [format "temperature: valid=%u raw=%u c=%.2f" \
        $temp_valid $temp_raw $temp_c]

    if {$u59_delta == 0 || $top_delta == 0 || $bot_delta == 0} {
        error "one or more management/EMIF clocks did not advance"
    }
    if {$top_cal_fail || $bot_cal_fail} {
        error "one or more EMIF calibration-failure flags are asserted"
    }
    if {$top_ecc_interrupt || $bot_ecc_interrupt} {
        error "one or more ECC interrupt flags are asserted"
    }
    if {!$temp_valid || $temp_c >= 90.0} {
        error [format "temperature gate failed: valid=%u temp_c=%.2f" \
            $temp_valid $temp_c]
    }
    if {$require_ready && (!$top_pll_locked || !$bot_pll_locked ||
            !$top_cal_success || !$bot_cal_success)} {
        error "both EMIF channels are not ready"
    }
    return [list $top_cal_success $bot_cal_success]
}

refresh_connections
read_ddr4_status 1
read_bist_status
puts "dual_emif_status=PASS"
