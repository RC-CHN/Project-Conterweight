#!/usr/bin/env bash
set -euo pipefail

quartus_root="${QUARTUS_ROOTDIR:-/workspace/intelFPGA/22.1std/quartus}"
base_qsys="../ddr4-dual/Qsys.qsys"
search_path='../ddr4-dual/ip/**/*,$'

"${quartus_root}/sopc_builder/bin/qsys-script" \
  --system-file="${base_qsys}" \
  --search-path="${search_path}" \
  --package-version=22.1 \
  --script=make_2133.tcl

"${quartus_root}/sopc_builder/bin/qsys-generate" \
  Qsys.qsys \
  --search-path="${search_path}" \
  --synthesis=VERILOG \
  --part=10AXF40AA
