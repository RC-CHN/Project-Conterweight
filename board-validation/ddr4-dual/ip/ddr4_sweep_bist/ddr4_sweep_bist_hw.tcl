package require -exact qsys 16.0

set_module_property NAME ddr4_sweep_bist
set_module_property VERSION 1.0
set_module_property DISPLAY_NAME "DDR4 full-aperture sweep BIST"
set_module_property DESCRIPTION "Deterministic 512-bit full-address sweep and compare engine"
set_module_property GROUP "Project-Conterweight"
set_module_property AUTHOR "Project-Conterweight"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
set_module_property OPAQUE_ADDRESS_MAP true

add_parameter CHANNEL_ID INTEGER 0
set_parameter_property CHANNEL_ID HDL_PARAMETER true
add_parameter ADDRESS_WIDTH INTEGER 25
set_parameter_property ADDRESS_WIDTH HDL_PARAMETER true
add_parameter DATA_WIDTH INTEGER 512
set_parameter_property DATA_WIDTH HDL_PARAMETER true
add_parameter BYTE_ENABLE_WIDTH INTEGER 64
set_parameter_property BYTE_ENABLE_WIDTH HDL_PARAMETER true
add_parameter PATTERN_COUNT INTEGER 4
set_parameter_property PATTERN_COUNT HDL_PARAMETER true

add_fileset quartus_synth QUARTUS_SYNTH synth_callback
set_fileset_property quartus_synth TOP_LEVEL ddr4_sweep_bist

proc synth_callback {name} {
    add_fileset_file ddr4_sweep_bist.sv SYSTEM_VERILOG PATH ddr4_sweep_bist.sv TOP_LEVEL_FILE
}

add_interface clock clock end
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset_n reset_n Input 1

add_interface control conduit end
add_interface_port control enable_async enable Input 1
add_interface_port control clear_async clear Input 1

add_interface avm avalon start
set_interface_property avm associatedClock clock
set_interface_property avm associatedReset reset
set_interface_property avm addressUnits WORDS
set_interface_property avm bitsPerSymbol 8
set_interface_property avm burstOnBurstBoundariesOnly false
set_interface_property avm doStreamReads false
set_interface_property avm doStreamWrites false
set_interface_property avm linewrapBursts false
set_interface_property avm readLatency 0
add_interface_port avm avm_address address Output ADDRESS_WIDTH
add_interface_port avm avm_read read Output 1
add_interface_port avm avm_write write Output 1
add_interface_port avm avm_writedata writedata Output DATA_WIDTH
add_interface_port avm avm_readdata readdata Input DATA_WIDTH
add_interface_port avm avm_waitrequest waitrequest Input 1
add_interface_port avm avm_readdatavalid readdatavalid Input 1
add_interface_port avm avm_byteenable byteenable Output BYTE_ENABLE_WIDTH
add_interface_port avm avm_burstcount burstcount Output 7

add_interface status conduit end
add_interface_port status running running Output 1
add_interface_port status state_status state Output 4
add_interface_port status pattern_status pattern Output 2
add_interface_port status heartbeat_gray heartbeat_gray Output 32
add_interface_port status pass_count_gray pass_count_gray Output 32
add_interface_port status error_count_gray error_count_gray Output 32
add_interface_port status address_gray address_gray Output ADDRESS_WIDTH
add_interface_port status first_error_address first_error_address Output ADDRESS_WIDTH
add_interface_port status error_byte_mask error_byte_mask Output BYTE_ENABLE_WIDTH
