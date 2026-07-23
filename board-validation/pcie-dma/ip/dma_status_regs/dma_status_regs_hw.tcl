package require -exact qsys 16.0

set_module_property NAME dma_status_regs
set_module_property VERSION 1.0
set_module_property DISPLAY_NAME "Catapult PCIe DMA status registers"
set_module_property DESCRIPTION "Stable BAR ABI, heartbeat, reset/error counters, and scratch register"
set_module_property GROUP "Project-Conterweight"
set_module_property AUTHOR "Project-Conterweight"
set_module_property INSTANTIATE_IN_SYSTEM_MODULE true
set_module_property EDITABLE true
set_module_property OPAQUE_ADDRESS_MAP true

add_fileset quartus_synth QUARTUS_SYNTH synth_callback
set_fileset_property quartus_synth TOP_LEVEL dma_status_regs

proc synth_callback {name} {
    add_fileset_file dma_status_regs.sv SYSTEM_VERILOG PATH dma_status_regs.sv TOP_LEVEL_FILE
}

add_interface clock clock end
add_interface_port clock clk clk Input 1

add_interface reset reset end
set_interface_property reset associatedClock clock
set_interface_property reset synchronousEdges DEASSERT
add_interface_port reset reset_n reset_n Input 1

add_interface s0 avalon end
set_interface_property s0 associatedClock clock
set_interface_property s0 associatedReset reset
set_interface_property s0 addressUnits WORDS
set_interface_property s0 bitsPerSymbol 8
set_interface_property s0 readLatency 0
set_interface_property s0 maximumPendingReadTransactions 0
set_interface_property s0 maximumPendingWriteTransactions 0
add_interface_port s0 avs_address address Input 3
add_interface_port s0 avs_read read Input 1
add_interface_port s0 avs_write write Input 1
add_interface_port s0 avs_writedata writedata Input 32
add_interface_port s0 avs_readdata readdata Output 32
add_interface_port s0 avs_byteenable byteenable Input 4

add_interface perst conduit end
add_interface_port perst perst_n_async perst_n Input 1

add_interface leds conduit end
add_interface_port leds leds_export leds Output 9

