# Four-lane 10.3125 Gbit/s Native PHY internal serial-loopback validation.
# The script verifies lock/calibration, exercises each lane's checker error
# path, then runs a clean 60-second soak.  It always disables the high-speed
# path before returning, including after an error.

set SOAK_INTERVAL_MS 5000
set SOAK_SAMPLES 12

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

proc claim_loopback_probe {} {
    for {set attempt 0} {$attempt < 20} {incr attempt} {
        refresh_connections
        foreach path [get_service_paths issp] {
            if {[catch {set candidate [claim_service issp $path qsfp_loopback_test]}]} {
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

proc set_source {service value} {
    issp_write_source_data $service [format 0x%02x $value]
    after 50
}

proc read_snapshot {service} {
    return [expr {[issp_read_probe_data $service]}]
}

proc lane_block_count {raw lane} {
    set offsets {141 221 301 381}
    return [gray_to_binary [field $raw [lindex $offsets $lane] 32]]
}

proc lane_error_count {raw lane} {
    set offsets {173 253 333 413}
    return [gray_to_binary [field $raw [lindex $offsets $lane] 32]]
}

proc lane_lock_loss_count {raw lane} {
    set offsets {205 285 365 445}
    return [gray_to_binary [field $raw [lindex $offsets $lane] 16]]
}

proc temperature_c {raw} {
    return [expr {693.0 * [field $raw 59 10] / 1024.0 - 265.0}]
}

proc print_snapshot {raw label} {
    puts [format \
        "%s modprsl=%u enable=%u fpll=%u/%u txpll=%u/%u tx_ready=0x%x rx_ready=0x%x lock_data=0x%x lock_ref=0x%x block_lock=0x%x tx_cal=0x%x rx_cal=0x%x checker=0x%x fifo_full=0x%x fifo_pfull=0x%x overflow=0x%x temp_valid=%u temp_raw=%u temp_c=%.2f source=0x%02x powerdown=%u reset=%u tx_arst=0x%x tx_drst=0x%x rx_arst=0x%x rx_drst=0x%x" \
        $label \
        [field $raw 0 1] [field $raw 1 1] \
        [field $raw 2 1] [field $raw 3 1] \
        [field $raw 4 1] [field $raw 5 1] \
        [field $raw 6 4] [field $raw 10 4] \
        [field $raw 14 4] [field $raw 18 4] [field $raw 22 4] \
        [field $raw 42 4] [field $raw 46 4] [field $raw 50 4] \
        [field $raw 26 4] [field $raw 30 4] [field $raw 54 4] \
        [field $raw 58 1] [field $raw 59 10] [temperature_c $raw] \
        [field $raw 69 8] \
        [field $raw 461 1] [field $raw 462 1] \
        [field $raw 463 4] [field $raw 467 4] \
        [field $raw 471 4] [field $raw 475 4]]
    for {set lane 0} {$lane < 4} {incr lane} {
        puts [format "  lane%u blocks=%u errors=%u lock_losses=%u" \
            $lane [lane_block_count $raw $lane] \
            [lane_error_count $raw $lane] \
            [lane_lock_loss_count $raw $lane]]
    }
}

proc require_healthy {raw label} {
    if {[field $raw 0 1] != 1 || [field $raw 1 1] != 1} {
        error "$label: module-present safety gate is not enabled"
    }
    if {[field $raw 2 1] != 1 || [field $raw 3 1] != 0 ||
            [field $raw 4 1] != 1 || [field $raw 5 1] != 0} {
        error "$label: transceiver fPLL is not locked and idle"
    }
    foreach {name lsb expected} {
        tx_ready 6 15
        rx_ready 10 15
        rx_lockedtodata 14 15
        rx_lockedtoref 18 15
        rx_block_lock 22 15
        tx_cal_busy 42 0
        rx_cal_busy 46 0
        checker_acquired 50 15
        fifo_full 26 0
        fifo_pfull 30 0
        fifo_overflow_sticky 54 0
    } {
        set value [field $raw $lsb 4]
        if {$value != $expected} {
            error [format "%s: %s=0x%x expected=0x%x" \
                $label $name $value $expected]
        }
    }
    if {[field $raw 58 1] != 1} {
        error "$label: on-die temperature sample is not valid"
    }
    if {[temperature_c $raw] >= 90.0} {
        error [format "%s: on-die temperature %.2f C exceeds 90 C gate" \
            $label [temperature_c $raw]]
    }
}

proc clear_counters {service} {
    set_source $service 0x03
    after 100
    set_source $service 0x01
    after 200
}

proc wait_for_ready {service} {
    for {set attempt 0} {$attempt < 150} {incr attempt} {
        set raw [read_snapshot $service]
        if {[field $raw 0 1] == 1 && [field $raw 1 1] == 1 &&
                [field $raw 2 1] == 1 && [field $raw 3 1] == 0 &&
                [field $raw 4 1] == 1 && [field $raw 5 1] == 0 &&
                [field $raw 6 4] == 15 && [field $raw 10 4] == 15 &&
                [field $raw 14 4] == 15 && [field $raw 18 4] == 15 &&
                [field $raw 22 4] == 15 && [field $raw 42 4] == 0 &&
                [field $raw 46 4] == 0 && [field $raw 50 4] == 15 &&
                [field $raw 58 1] == 1} {
            return $raw
        }
        after 100
    }
    print_snapshot $raw "ready_timeout"
    error "four-lane loopback did not become ready within 15 seconds"
}

set service ""
set test_result [catch {
    lassign [claim_loopback_probe] service path
    puts "issp_path=$path"
    puts "instance=[issp_get_instance_info $service]"

    set_source $service 0x01
    # Give the dedicated Y5 reference time to settle, then force one explicit
    # clean restart of the fPLL/PHY reset sequence before testing.
    after 2000
    set_source $service 0x05
    after 100
    set_source $service 0x01
    set ready [wait_for_ready $service]
    print_snapshot $ready "ready"
    require_healthy $ready "ready"

    # Prove that every lane has an independent, observable checker error path.
    for {set target 0} {$target < 4} {incr target} {
        clear_counters $service
        set_source $service [expr {1 | (1 << (3 + $target))}]
        after 100
        set_source $service 0x01
        after 200
        set injected [read_snapshot $service]
        require_healthy $injected "lane${target}_injection"
        for {set lane 0} {$lane < 4} {incr lane} {
            set errors [lane_error_count $injected $lane]
            if {$lane == $target && $errors == 0} {
                error "lane $target injection did not increment its error counter"
            }
            if {$lane != $target && $errors != 0} {
                error "lane $target injection changed lane $lane error counter"
            }
        }
        puts [format "lane%u_error_injection=PASS target_errors=%u" \
            $target [lane_error_count $injected $target]]
    }

    clear_counters $service
    set previous [read_snapshot $service]
    require_healthy $previous "soak_start"
    set heartbeat_previous [gray_to_binary [field $previous 77 32]]
    set total_blocks {0 0 0 0}

    for {set sample 1} {$sample <= $SOAK_SAMPLES} {incr sample} {
        after $SOAK_INTERVAL_MS
        set current [read_snapshot $service]
        require_healthy $current "soak_sample_$sample"

        set heartbeat_current [gray_to_binary [field $current 77 32]]
        set heartbeat_delta [counter_delta $heartbeat_current $heartbeat_previous]
        if {$heartbeat_delta == 0} {
            error "soak sample $sample: 100 MHz heartbeat stopped"
        }
        set heartbeat_previous $heartbeat_current

        set interval_blocks {}
        for {set lane 0} {$lane < 4} {incr lane} {
            set delta [counter_delta \
                [lane_block_count $current $lane] \
                [lane_block_count $previous $lane]]
            if {$delta == 0} {
                error "soak sample $sample: lane $lane block counter stopped"
            }
            if {[lane_error_count $current $lane] != 0 ||
                    [lane_lock_loss_count $current $lane] != 0} {
                error "soak sample $sample: lane $lane reported an error or lock loss"
            }
            lappend interval_blocks $delta
            lset total_blocks $lane [expr {[lindex $total_blocks $lane] + $delta}]
        }
        puts [format \
            "soak_sample=%u/%u heartbeat_delta=%u interval_blocks=%s temp_c=%.2f" \
            $sample $SOAK_SAMPLES $heartbeat_delta $interval_blocks \
            [temperature_c $current]]
        set previous $current
    }

    print_snapshot $previous "soak_end"
    puts "soak_total_blocks=$total_blocks"
    puts [format "soak_seconds=%.3f" \
        [expr {$SOAK_INTERVAL_MS * $SOAK_SAMPLES / 1000.0}]]
    puts "qsfp_internal_loopback=PASS"
} test_error]

if {$service ne ""} {
    catch {set_source $service 0x00}
    catch {
        set disabled [read_snapshot $service]
        puts [format "postflight source=0x%02x safe_enable=%u" \
            [field $disabled 69 8] [field $disabled 1 1]]
    }
    catch {close_service issp $service}
}

if {$test_result} {
    error $test_error
}
