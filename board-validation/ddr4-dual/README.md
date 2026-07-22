# Catapult v3 dual DDR4 bring-up

This project instantiates two independent Intel Arria 10 External Memory
Interfaces in one image. Each controller owns one board-side 72-bit interface
(64 data + 8 ECC), its own Y3/Y4 reference clock, RZQ input, calibration state,
ECC interrupt, and JTAG-to-Avalon test master. It is not one combined 144-bit
physical controller.

The accepted local bring-up baseline is DDR4-1600: each memory clock is
800 MHz and each quarter-rate user clock is 200 MHz. The fitted devices may
support a higher community-tested rate, and the memory model declares a
DDR4-2133 speed bin, but this project does not claim DDR4-2133 timing or
hardware validation. At DDR4-1600 the raw data-rate ceiling is 12.8 GB/s per
64-bit data channel, or 25.6 GB/s for both channels before protocol overhead.

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

The ISSP BIST controls cross from the 100 MHz U59 clock into the two independent
200 MHz EMIF user domains. `Constraints.sdc` cuts only the asynchronous input
to the first register of each explicit two-flop synchronizer. The second
synchronizer stages and all downstream control and memory paths remain timed.

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

Run one destructive full-aperture pass on both channels concurrently:

```bash
/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/system-console \
  --project_dir=. \
  --jdi=output_files/Catapult_v3_DDR4.jdi \
  --script=run_sweep_bist.tcl
```

Each channel's on-chip BIST visits all 33,554,432 64-byte lines in its 2 GiB
controller address range. It writes and then compares four deterministic data
sequences: two per-lane LFSR seeds, a rotating one-hot bit, and a rotating
one-cold bit. One pass produces 8 GiB of writes and 8 GiB of reads per channel.
Both engines run at the same time and retain pass count, error count, first
error address, and a 64-bit byte-error mask for JTAG inspection. This is a
complete address/data-pattern sweep, not a peak-bandwidth benchmark: reads
deliberately use one outstanding request so failures are easy to localize.

The ISSP source defaults to enabling both BIST engines after configuration, so
the design begins overwriting DDR as soon as calibration/reset release permits.
`run_sweep_bist.tcl` stops, clears, and restarts both engines together to obtain
a controlled measurement. `test_ddr4.tcl` stops the BIST before using the two
JTAG-to-Avalon masters; it remains a useful sampled cross-check at seven
addresses per channel.

The accepted local build and hardware evidence are recorded in `RESULTS.md`.

QSPI Flash and both PCIe interfaces are absent from this design and are not
modified or trained.
