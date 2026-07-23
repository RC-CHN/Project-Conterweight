package require ::quartus::project
package require ::quartus::sta

project_open Catapult_v3_DDR4_2133 -revision Catapult_v3_DDR4_2133
create_timing_netlist
read_sdc
update_timing_netlist

foreach pattern {
    temp_eoc_meta
    Qsys:u0|ddr4_sweep_bist:bist_top|reset_sync[0]
    Qsys:u0|ddr4_sweep_bist:bist_top|enable_sync[0]
    Qsys:u0|ddr4_sweep_bist:bist_top|clear_sync[0]
    Qsys:u0|ddr4_sweep_bist:bist_bot|reset_sync[0]
    Qsys:u0|ddr4_sweep_bist:bist_bot|enable_sync[0]
    Qsys:u0|ddr4_sweep_bist:bist_bot|clear_sync[0]
} {
    set nodes [get_registers -nowarn $pattern]
    puts "cdc_first_stage=$pattern matches=[get_collection_size $nodes]"
}

report_ucp -file output_files/unconstrained_paths.txt
report_timing -setup -npaths 30 -detail full_path \
    -file output_files/setup_paths.txt
report_timing -hold -npaths 30 -detail full_path \
    -file output_files/hold_paths.txt
report_timing -recovery -npaths 30 -detail full_path \
    -file output_files/recovery_paths.txt
report_timing -removal -npaths 30 -detail full_path \
    -file output_files/removal_paths.txt
report_min_pulse_width -nworst 30 -detail full_path \
    -file output_files/min_pulse_width_paths.txt

delete_timing_netlist
project_close
