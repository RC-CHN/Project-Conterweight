#!/usr/bin/env bash
set -euo pipefail

quartus_root="${QUARTUS_ROOTDIR:-/workspace/intelFPGA/22.1std/quartus}"

"${quartus_root}/sopc_builder/bin/qsys-generate" \
  Qsys.qsys \
  --synthesis=VERILOG \
  --part=10AXF40AA
