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

The controlled hardware BIST ran both channels simultaneously and completed
one pass in `27.345` seconds. Per channel, the pass addressed every 64-byte line
from byte address `0x00000000` through `0x7fffffc0`, covering the complete
configured 2 GiB user-data range. Four write/read/compare patterns produced
16 GiB of traffic per channel: two independent per-lane LFSR sequences, a
rotating one-hot bit, and a rotating one-cold bit. Both error counters and both
64-bit byte-error masks remained zero. The script ended with:

```text
dual_full_aperture_bist=PASS elapsed_seconds=27.345
bytes_per_channel_per_pass=17179869184
usable_bytes_covered_per_channel=2147483648
simultaneous_channels=YES
```

The engines had also been enabled by the ISSP power-up value before the
controlled restart; the first status capture observed four completed passes on
each channel with zero errors. Only the explicitly cleared/restarted pass is
used for the recorded elapsed time.

After stopping both BIST engines, the sampled JTAG cross-check wrote and read
one complete 64-byte line at each of these byte addresses through each
channel's own JTAG-to-Avalon master:

```text
0x00000000  0x00001000  0x00100000  0x01000000
0x10000000  0x40000000  0x7fffffc0
```

All 16 32-bit words matched at all 14 channel/address combinations. Both ECC
interrupts remained zero after every line and at the final check. This also
verifies that both explicit JTAG masters still work through Platform Designer
arbitration after the on-chip masters stop. The sampled script ended with:

```text
sampled_dual_ddr4=PASS
```

Together, the BIST and JTAG results verify both independent controllers, every
address in each controller's configured 2 GiB range, multiple data patterns,
and concurrent dual-channel operation. The result is 4 GiB of locally verified
user data in total. It does not establish the community-reported 5 GB fitted /
approximately 4.5 GB usable organization, because this controller geometry
exposes exactly 2 GiB of user data per channel; any claimed additional user
capacity needs a separate geometry and board-population audit. It also does not
prove long-duration retention, maximum sustainable bandwidth, or full-load
thermal behavior.

## Build and timing audit

- Final full compilation: 0 errors, 31 warnings.
- Analysis & Synthesis: 0 errors, 7 warnings.
- Fitter: 0 errors, 7 warnings; selected `10AXF40AA`.
- Assembler: 0 errors, 0 warnings.
- Timing Analyzer: 0 errors, 17 warnings.
- Setup and hold requirements are fully constrained.
- Worst setup slack: `+0.423 ns`.
- Worst hold slack: `+0.013 ns`.
- Worst recovery slack: `+0.266 ns`.
- Worst removal slack: `+0.174 ns`.
- Worst minimum pulse-width slack: `+0.300 ns`.
- SOF size: `36,858,933` bytes.
- SOF SHA-256:
  `9725aef1202a5e6fc51d66ba13d1fea73e870550153e35e3b7ebdfac48853a38`.
- SRAM programming: success, 0 errors, 0 warnings, 53 seconds.
- Programmer SOF checksum: `0x30DDFC66`.

The two EMIF read-response FIFOs contain asynchronously cleared 512-bit RAM
payload output registers. Their payload is invalid while the separately reset
valid state is low and the FIFO is empty. `Constraints.sdc` therefore excludes
only setup/recovery checks from each local reset synchronizer to its own
payload RAM outputs. FIFO pointers, valid/full/empty state, CDC controls, EMIF
logic, ordinary data setup, hold, removal, and board I/O remain timed. Before
this narrow exception was applied, the worst recovery report was inspected at
2000-path depth; all 512 negative-slack paths were those top-channel payload
bits, while control recovery paths were non-negative at DDR4-1600.

The four ISSP-to-BIST control crossings terminate at the first registers of
explicit two-flop synchronizers. The final SDC cuts only those four asynchronous
input paths. Netlist queries confirmed that every exception matches exactly one
first-stage register; the second-stage and all downstream paths remain timed.
An intermediate audit exposed the uncut CDC paths as approximately `-5.3 ns`
setup violations, which were not accepted as a finished build. After applying
the precise CDC constraints and refitting, setup TNS is zero at every corner.

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

System Console exposes one ISSP status/control service, the two explicit data
masters, and an additional EMIF calibration/debug master. `run_sweep_bist.tcl`
controls the two on-chip engines through ISSP. `test_ddr4.tcl` first stops the
BIST and then deliberately selects only `master_bot.master` and
`master_top.master`; it does not send data traffic through the calibration
master.

QSPI Flash was untouched. Both PCIe interfaces are absent from this SRAM image
and therefore are not trained while it runs. Flash still contains
`pcie-temp-demo`, which will return after a board power cycle.

The controlled pass was short and did not constitute sustained thermal loading
or a maximum-bandwidth test. The last management-I2C reading before DDR
bring-up was approximately 35.0 C local and
43.125 C remote, but this DDR image has no temperature telemetry. A future
long-duration run must add temperature monitoring and require server-class
airflow.

## Remaining work

- Add pipelined/multiple-outstanding traffic modes and throughput counters for
  a maximum-sustainable-bandwidth test; the current BIST prioritizes exhaustive
  coverage and error localization.
- Add temperature telemetry and run hours-long simultaneous dual-channel
  endurance/retention testing under confirmed server-class airflow.
- Audit the physical memory population and geometry before claiming the
  community-reported capacity beyond the verified 4 GiB of user data.
- Evaluate DDR4-1866/2133 as separate regenerated EMIF configurations. The
  memory model declares a DDR4-2133 speed bin, but the accepted local baseline
  remains DDR4-1600 and the generic FPGA target lacks a concrete speed grade.
