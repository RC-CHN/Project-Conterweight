package require -exact qsys 22.1

create_system dma_system
set_project_property DEVICE_FAMILY "Arria 10"

# The IP catalog needs a concrete production part trait to expose the Gen3 x8,
# 256-bit HIP mode. The enclosing Quartus project remains targeted to the
# board-compatible generic 10AXF40AA alias.
set_project_property DEVICE 10AX115N4F40E3SG

add_instance hip altera_pcie_a10_hip 22.1
set_instance_parameter_value hip interface_type_hwtcl "Avalon-MM with DMA"

# Hard-IP mode 0 is Gen3 x8 with a 256-bit, 250 MHz application interface.
# Setting the derived width/rate fields directly is ineffective in Quartus
# 22.1 because wrala_hwtcl rewrites them during validation.
set_instance_parameter_value hip wrala_hwtcl 0
set_instance_parameter_value hip port_type_hwtcl "Native endpoint"
set_instance_parameter_value hip pcie_spec_version_hwtcl 3.0
set_instance_parameter_value hip internal_controller_hwtcl 1
set_instance_parameter_value hip completion_timeout_disable_hwtcl 1
set_instance_parameter_value hip completion_timeout_hwtcl NONE
set_instance_parameter_value hip rx_buffer_credit_alloc_hwtcl Low
set_instance_parameter_value hip maximum_payload_size_hwtcl 256
set_instance_parameter_value hip extended_tag_support_hwtcl 0

set_instance_parameter_value hip vendor_id_hwtcl 4466
set_instance_parameter_value hip device_id_hwtcl 57348
set_instance_parameter_value hip revision_id_hwtcl 1
set_instance_parameter_value hip class_code_hwtcl 0
set_instance_parameter_value hip subsystem_vendor_id_hwtcl 4466
set_instance_parameter_value hip subsystem_device_id_hwtcl 257

# BAR0 is exclusively owned by the internal descriptor controller.
set_instance_parameter_value hip bar0_type_hwtcl "64-bit prefetchable memory"
set_instance_parameter_value hip bar0_address_width_hwtcl 28
set_instance_parameter_value hip bar1_type_hwtcl Disabled
set_instance_parameter_value hip bar2_type_hwtcl Disabled
set_instance_parameter_value hip bar3_type_hwtcl Disabled

# BAR4 contains 1 MiB RAM plus diagnostic registers in a 2 MiB aperture.
set_instance_parameter_value hip bar4_type_hwtcl "64-bit prefetchable memory"
set_instance_parameter_value hip bar4_address_width_hwtcl 21
set_instance_parameter_value hip bar5_type_hwtcl Disabled
set_instance_parameter_value hip cg_impl_cra_av_slave_port_hwtcl 0
set_instance_parameter_value hip enable_devkit_conduit_hwtcl 0
set_instance_parameter_value hip select_design_example_hwtcl DMA

# Re-assert the HIP mode last because several parameter callbacks validate and
# may otherwise restore the default Gen2 x8 / 128-bit mode.
set_instance_parameter_value hip wrala_hwtcl 0

set resolved_lane_rate [get_instance_parameter_value hip lane_rate_hwtcl]
set resolved_link_width [get_instance_parameter_value hip link_width_hwtcl]
set resolved_interface_width [get_instance_parameter_value hip app_interface_width_hwtcl]
if {![string equal $resolved_lane_rate "Gen3 (8.0 Gbps)"]} {
    error "HIP lane rate did not resolve to Gen3"
}
if {![string equal $resolved_link_width "x8"]} {
    error "HIP link width did not resolve to x8"
}
if {![string equal $resolved_interface_width "256-bit"]} {
    error "HIP application interface did not resolve to 256 bits"
}

add_instance dma_buffer altera_avalon_onchip_memory2 22.1
set_instance_parameter_value dma_buffer dataWidth 256
set_instance_parameter_value dma_buffer dataWidth2 256
set_instance_parameter_value dma_buffer deviceFamily "Arria 10"
set_instance_parameter_value dma_buffer dualPort true
set_instance_parameter_value dma_buffer ecc_enabled false
set_instance_parameter_value dma_buffer initMemContent false
set_instance_parameter_value dma_buffer memorySize 1048576
set_instance_parameter_value dma_buffer readDuringWriteMode DONT_CARE
set_instance_parameter_value dma_buffer resetrequest_enabled false
set_instance_parameter_value dma_buffer singleClockOperation false
set_instance_parameter_value dma_buffer slave1Latency 2
set_instance_parameter_value dma_buffer slave2Latency 2
set_instance_parameter_value dma_buffer useNonDefaultInitFile false
set_instance_parameter_value dma_buffer useShallowMemBlocks false
set_instance_parameter_value dma_buffer writable true

add_instance status dma_status_regs 1.0

add_connection hip.coreclkout_hip dma_buffer.clk1
add_connection hip.coreclkout_hip dma_buffer.clk2
add_connection hip.app_nreset_status dma_buffer.reset1
add_connection hip.app_nreset_status dma_buffer.reset2
add_connection hip.coreclkout_hip status.clock
add_connection hip.app_nreset_status status.reset

# Payload engines and their internal descriptor FIFOs.
add_connection hip.dma_rd_master dma_buffer.s1
add_connection hip.dma_wr_master dma_buffer.s2
add_connection hip.dma_rd_master hip.rd_dts_slave
add_connection hip.dma_rd_master hip.wr_dts_slave

# Descriptor fetches, status writeback, and payload host-memory accesses.
add_connection hip.rd_dcm_master hip.txs
add_connection hip.wr_dcm_master hip.txs

# BAR4 provides a PIO debug path to the same RAM and the stable ABI registers.
add_connection hip.rxm_bar4 dma_buffer.s1
add_connection hip.rxm_bar4 status.s0

set_connection_parameter_value hip.dma_rd_master/dma_buffer.s1 baseAddress 0x00000000
set_connection_parameter_value hip.dma_wr_master/dma_buffer.s2 baseAddress 0x00000000
set_connection_parameter_value hip.dma_rd_master/hip.rd_dts_slave baseAddress 0x01000000
set_connection_parameter_value hip.dma_rd_master/hip.wr_dts_slave baseAddress 0x01002000

set_connection_parameter_value hip.rxm_bar4/dma_buffer.s1 baseAddress 0x00000000
set_connection_parameter_value hip.rxm_bar4/status.s0 baseAddress 0x00100000

add_interface hip_refclk clock sink
set_interface_property hip_refclk EXPORT_OF hip.refclk
add_interface hip_npor conduit end
set_interface_property hip_npor EXPORT_OF hip.npor
add_interface hip_hip_serial conduit end
set_interface_property hip_hip_serial EXPORT_OF hip.hip_serial
add_interface status_perst conduit end
set_interface_property status_perst EXPORT_OF status.perst
add_interface status_leds conduit end
set_interface_property status_leds EXPORT_OF status.leds

set_interconnect_requirement {$system} qsys_mm.clockCrossingAdapter HANDSHAKE
set_interconnect_requirement {$system} qsys_mm.maxAdditionalLatency 4

save_system dma_system.qsys
