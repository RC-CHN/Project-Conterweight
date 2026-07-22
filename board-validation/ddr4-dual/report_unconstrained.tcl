package require ::quartus::project
package require ::quartus::sta

project_open Catapult_v3_DDR4 -revision Catapult_v3_DDR4
create_timing_netlist
read_sdc
update_timing_netlist
report_ucp -file output_files/unconstrained_paths.txt
delete_timing_netlist
project_close
