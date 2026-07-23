# Catapult v3 dual DDR4-2133 validation

This directory is an isolated speed experiment derived from the accepted
`../ddr4-dual` DDR4-1600 source.  `make_2133.tcl` requires both base EMIFs to
be exactly 800 MHz, changes only their memory-clock parameter to 1066.667 MHz,
and saves a local generated `Qsys.qsys`.  The memory model already declares
the DDR4-2133 speed bin and the board reference clocks remain 266.667 MHz.

The generated Qsys file and all Platform Designer/Quartus output are ignored;
the committed base plus the Tcl transformation are the reproducible source.
The ISSP source retains its Quartus-validated raw power-up value of 3; RTL
maps that to logical BIST control zero, so both engines remain stopped.
Traffic starts only after System Console verifies both calibrations, both
PLLs, both user clocks, ECC status and an on-die temperature below 90 C.

Build with Quartus Prime Standard 22.1:

```bash
./regenerate.sh
quartus_sh --flow compile Catapult_v3_DDR4_2133
quartus_sta -t report_timing.tcl
```

After report review and the normal JTAG/USB/temperature preflight, program only
the SOF into volatile SRAM.  Reuse the base project's status and full-aperture
BIST scripts against this revision's JDI:

```bash
quartus_pgm -c 1 -m jtag \
  -o 'p;output_files/Catapult_v3_DDR4_2133.sof'

/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/system-console \
  --project_dir=. \
  --jdi=output_files/Catapult_v3_DDR4_2133.jdi \
  --script=read_status.tcl

/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/system-console \
  --project_dir=. \
  --jdi=output_files/Catapult_v3_DDR4_2133.jdi \
  --script=run_sweep_bist.tcl
```

This experiment never creates a JIC and must not touch QSPI Flash.

The accepted local build, timing review and two-pass concurrent full-aperture
hardware result are recorded in `RESULTS.md`.
