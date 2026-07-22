#!/usr/bin/env bash
set -euo pipefail

QSYS_BIN=/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin

"${QSYS_BIN}/qsys-script" --script=generate_mgmt_system.tcl
"${QSYS_BIN}/qsys-generate" i2c_bridge.qsys \
    --synthesis=VERILOG \
    --part=10AXF40AA
