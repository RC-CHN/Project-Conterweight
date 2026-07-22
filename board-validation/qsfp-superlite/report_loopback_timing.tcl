package require ::quartus::project
package require ::quartus::sta

project_open qsfp_internal_loopback -revision qsfp_internal_loopback
create_timing_netlist
read_sdc
update_timing_netlist

foreach pattern {
    modprsl_meta
    temp_eoc_meta
    status_meta[*]
    tx_gray_meta[*]
    block_gray_meta[*][*]
    error_gray_meta[*][*]
    loss_gray_meta[*][*]
    tx_enable_meta[*]
    tx_ready_meta[*]
    inject_meta[*]
    clear_meta_rx[*]
    blk_lock_meta_rx[*]
    ready_meta_rx[*]
    fifo_full_meta_rx[*]
} {
    set nodes [get_registers -nowarn $pattern]
    puts "cdc_first_stage=$pattern matches=[get_collection_size $nodes]"
}

report_ucp -file output_files_loopback/unconstrained_paths.txt
report_timing -setup -npaths 30 -detail full_path \
    -file output_files_loopback/setup_paths.txt
report_timing -hold -npaths 30 -detail full_path \
    -file output_files_loopback/hold_paths.txt

delete_timing_netlist
project_close
