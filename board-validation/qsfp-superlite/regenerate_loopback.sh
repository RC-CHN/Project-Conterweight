#!/usr/bin/env bash
set -euo pipefail

QSYS_BIN=/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin

for system in fpll xcvr_superlite_ii xcvr_reset_controller; do
    "${QSYS_BIN}/qsys-generate" "${system}.qsys" \
        --synthesis=VERILOG \
        --part=10AXF40AA
done
