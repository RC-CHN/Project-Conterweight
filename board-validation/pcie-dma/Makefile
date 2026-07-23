QUARTUS_SH ?= quartus_sh
QSYS_SCRIPT ?= /workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/qsys-script
QSYS_GENERATE ?= /workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/qsys-generate

.PHONY: all generate compile driver

all: compile

generate:
	$(QSYS_SCRIPT) --script=generate_system.tcl
	$(QSYS_GENERATE) dma_system.qsys --synthesis=VERILOG --part=10AXF40AA

compile: generate
	$(QUARTUS_SH) --flow compile pcie_dma

driver:
	$(MAKE) -C driver
