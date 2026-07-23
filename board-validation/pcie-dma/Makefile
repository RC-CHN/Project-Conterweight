QUARTUS_SH ?= quartus_sh
QSYS_SCRIPT ?= /workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/qsys-script

.PHONY: all generate compile driver

all: compile

generate: dma_system.qsys

dma_system.qsys: generate_system.tcl
	$(QSYS_SCRIPT) --script=$<

compile: generate
	$(QUARTUS_SH) --flow compile pcie_dma

driver:
	$(MAKE) -C driver

