# Catapult v3 dual DDR4 bring-up

This project instantiates two independent Intel Arria 10 External Memory
Interfaces in one image. Each controller owns one board-side 72-bit interface
(64 data + 8 ECC), its own Y3/Y4 reference clock, RZQ input, calibration state,
ECC interrupt, and JTAG-to-Avalon test master. It is not one combined 144-bit
physical controller.

The accepted local bring-up baseline is DDR4-1600: each memory clock is
800 MHz and each quarter-rate user clock is 200 MHz. The fitted devices may
support a higher community-tested rate, but this project does not claim
DDR4-2133 timing or hardware validation.

The tracked `Qsys.qsys`, board pin assignments, and memory parameters originate
from the community `DDR4_Dual` project. Platform Designer output, Quartus
databases, reports, logs, and SOF files are regenerated locally and ignored by
Git.

Generate and compile with Quartus 22.1:

```bash
./regenerate.sh

quartus_sh --flow compile Catapult_v3_DDR4
```

The generated `Qsys/` tree remains ignored. `regenerate.sh` reproduces it from
the tracked Platform Designer system without modifying generated Intel IP.

The Intel FIFO template asynchronously clears its packed 512-bit RAM output
register. Those payload bits are explicitly invalid while the FIFO's reset
`out_valid` flag is low, and the FIFO starts empty, so `Constraints.sdc` excludes
only reset-release recovery paths from the two local reset synchronizers to
those two packed payload registers. Although TimeQuest spells this source- and
destination-qualified exception `-setup`, ordinary payload data setup paths
start elsewhere and remain timed. The constraint does not exclude hold,
removal, FIFO-valid, controller, PHY, or board I/O paths.

After report review and a JTAG IDCODE preflight, configure SRAM only:

```bash
quartus_pgm -c 1 -m jtag \
  -o 'p;output_files/Catapult_v3_DDR4.sof'
```

Read both calibration/PLL/ECC states before any memory access:

```bash
/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/system-console \
  --project_dir=. \
  --jdi=output_files/Catapult_v3_DDR4.jdi \
  --script=read_status.tcl
```

`test_ddr4.tcl` is deliberately a sampled bring-up test. It writes a complete
64-byte data line at selected addresses in each independent 2 GiB Avalon
aperture, verifies every word, and rechecks the exported ECC interrupts after
each line. It stops immediately on an ECC indication. It does not claim a full
capacity sweep or simultaneous dual-channel stress; those require full-width
hardware traffic generators so that ECC lines can be initialized and exercised
efficiently without a narrow JTAG bottleneck.

The accepted local build and hardware evidence are recorded in `RESULTS.md`.

QSPI Flash and both PCIe interfaces are absent from this design and are not
modified or trained.
