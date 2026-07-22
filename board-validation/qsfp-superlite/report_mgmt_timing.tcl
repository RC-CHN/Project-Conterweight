package require ::quartus::project
package require ::quartus::sta

project_open qsfp_mgmt -revision qsfp_mgmt
create_timing_netlist
read_sdc
update_timing_netlist

foreach node_name {y5_toggle_meta modprsl_meta} {
    set nodes [get_registers $node_name]
    puts "cdc_first_stage=$node_name matches=[get_collection_size $nodes]"
}

report_ucp -file output_files/unconstrained_paths.txt
report_timing -setup -npaths 20 -detail full_path \
    -file output_files/setup_paths.txt
report_timing -hold -npaths 20 -detail full_path \
    -file output_files/hold_paths.txt

delete_timing_netlist
project_close
