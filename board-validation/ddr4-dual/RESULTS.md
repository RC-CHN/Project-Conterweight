# Catapult v3 dual-DDR4 local validation result

Date: 2026-07-22 (Asia/Shanghai)

Board: Project-Conterweight `board 2`, Catapult v3 PCIe variant

Quartus: Prime Standard 22.1std.0 Build 915

Target: `10AXF40AA`

JTAG ID: `0x02E060DD`

JTAG TCK reported by plugin: `15M`

## Result

Both physical 72-bit DDR4 interfaces are locally functional with two
independent Arria 10 EMIF controllers. The accepted image runs the memory
clock at 800 MHz (DDR4-1600) and the quarter-rate controller user clocks at
200 MHz. ECC is enabled on both 64-data + 8-ECC interfaces.

Both controllers reported PLL lock and successful local calibration, with no
calibration-failure or ECC-interrupt indication. Independent Gray-coded user
clock counters advanced on both channels.

The final sampled test wrote and read one complete 64-byte line at each of
these byte addresses through each channel's own JTAG-to-Avalon master:

```text
0x00000000  0x00001000  0x00100000  0x01000000
0x10000000  0x40000000  0x7fffffc0
```

All 16 32-bit words matched at all 14 channel/address combinations. Both ECC
interrupts remained zero after every line and at the final check. The accepted
script ended with:

```text
sampled_dual_ddr4=PASS
full_capacity_tested=NO
simultaneous_stress_tested=NO
```

This proves basic operation of both independent controllers and sampled access
across each configured 2 GiB Avalon aperture. It does not prove the complete
fitted 5 GB capacity, the approximately 4.5 GB community-reported usable
capacity, every address/data bit, long-duration retention, or simultaneous
dual-channel bandwidth.

## Build and timing audit

- Final full compilation: 0 errors, 31 warnings.
- Analysis & Synthesis: 0 errors, 7 warnings.
- Fitter: 0 errors, 7 warnings; selected `10AXF40AA`.
- Assembler: 0 errors, 0 warnings.
- Timing Analyzer: 0 errors, 17 warnings.
- Setup and hold requirements are fully constrained.
- Worst setup slack: `+0.657 ns`.
- Worst hold slack: `+0.012 ns`.
- Worst recovery slack: `+0.259 ns`.
- Worst removal slack: `+0.158 ns`.
- Worst minimum pulse-width slack: `+0.300 ns`.
- SOF size: `36,854,318` bytes.
- SOF SHA-256:
  `45db8d72aac1e96ff52833c62091419ec73781527f19f1a6db219ccb73cbb6e7`.
- SRAM programming: success, 0 errors, 0 warnings, 56 seconds.
- Programmer SOF checksum: `0x30A1B5FB`.

The two EMIF read-response FIFOs contain asynchronously cleared 512-bit RAM
payload output registers. Their payload is invalid while the separately reset
valid state is low and the FIFO is empty. `Constraints.sdc` therefore excludes
only setup/recovery checks from each local reset synchronizer to its own
payload RAM outputs. FIFO pointers, valid/full/empty state, CDC controls, EMIF
logic, ordinary data setup, hold, removal, and board I/O remain timed. Before
this narrow exception was applied, the worst recovery report was inspected at
2000-path depth; all 512 negative-slack paths were those top-channel payload
bits, while control recovery paths were non-negative at DDR4-1600.

The remaining critical warnings require care:

- `10AXF40AA` is the generic target needed for this board's `0x02E060DD` JTAG
  ID, so Quartus leaves its speed-grade string blank while the generated EMIF
  reports E1. It also labels the timing model preliminary. Local calibration
  and sampled hardware success are useful evidence, but not production timing
  sign-off for an identified commercial part.
- All 48 RX and 48 TX transceiver channels are unused because this SRAM image
  intentionally contains no PCIe or QSFP transceiver instance.
- The two ignored Fitter assignments are generated LVDS I/O-standard settings
  on EMIF reference-clock ports; the top-level QSF owns their differential
  reference-clock standards and pins.
- Other warnings are generated-IP connectivity/width notices, incomplete I/O
  assignment notices for automatically created differential complements, and
  generated RAM implementation/power-up notices. No timing requirement is
  negative after the accepted build.

## Hardware procedure

Before programming, the FT232H enumerated at USB High-Speed, JTAG returned
`0x02E060DD`, and the plugin reported 15 MHz TCK. The SOF was loaded only into
volatile SRAM. A post-load IDCODE scan succeeded before the final memory test.

System Console exposes one ISSP status service, the two explicit data masters,
and an additional EMIF calibration/debug master. `test_ddr4.tcl` deliberately
selects only `master_bot.master` and `master_top.master`; it does not send data
traffic through the calibration master.

QSPI Flash was untouched. Both PCIe interfaces are absent from this SRAM image
and therefore are not trained while it runs. Flash still contains
`pcie-temp-demo`, which will return after a board power cycle.

The test was short and did not constitute sustained thermal loading. The last
management-I2C reading before DDR bring-up was approximately 35.0 C local and
43.125 C remote, but this DDR image has no temperature telemetry, so a future
long-running traffic generator must add temperature monitoring and require
server-class airflow.

## Remaining work

- Add full-width hardware traffic generators so ECC lines can be exercised at
  useful bandwidth without the narrow JTAG path.
- Run walking-bit, fixed-pattern, pseudorandom, address-line, and broad capacity
  tests independently on both channels.
- Run simultaneous dual-channel stress with error counters and temperature
  logging.
- Revisit DDR4-2133 only after its generated interconnect reset-release paths
  close without waiving control logic; the accepted local baseline is
  DDR4-1600.
