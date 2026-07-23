# Catapult v3 dual DDR4-2133 local validation

## Scope

This record covers the isolated `Catapult_v3_DDR4_2133` revision on the
current Longs Peak `board 2`.  Both independent 72-bit interfaces run at
DDR4-2133: 1066.667 MHz memory clock and approximately 266.7 MHz quarter-rate
user clock.  The test covers the complete 2 GiB controller address aperture
implemented for each channel.  The fitted, connected, ECC and payload capacity
figures are reconciled separately in `../ddr4-dual/GEOMETRY.md`.

Date: 2026-07-23 (Asia/Shanghai)

## Reproducible build

- Quartus Prime Standard 22.1std.0 Build 915.
- Target: `10AXF40AA`.
- `./regenerate.sh` verified that both base EMIFs were 800 MHz, changed both to
  1066.667 MHz, saved a local generated system, and regenerated synthesis HDL.
- Full compilation: 0 errors, 29 warnings.
- Fitter: Standard Fit, 0 errors, 7 warnings.
- The current BIST keeps up to 64 reads outstanding, compares responses in
  address order, and snapshots complete-pass write/read cycle counters.
- Final SOF size: 36,860,417 bytes.
- Final SOF SHA-256:
  `9a6d6ef905ac3dcf4461690bbfeb13266bb110449ca973f2c90d5adf7341339d`.
- Quartus Programmer checksum: `0x30D2BFFC`.

The generated `Qsys.qsys`, Platform Designer output, Quartus databases,
reports, JDI and SOF remain ignored.  The tracked 1600-MT/s base plus
`make_2133.tcl` are the reproducible source of the 2133 variant.

## Timing closure

The final full compilation read the committed two-cycle interconnect reset
recovery constraint during fitting and timing analysis.  The constraint does
not waive reset timing: it requires the synchronized reset to reach every
generated Avalon-MM interconnect register within two 266.7 MHz cycles, with
the matching hold multicycle restoring the original one-edge removal check.
The BIST is locally synchronized and disabled throughout reset release.

The final multicorner summary is fully constrained for setup and hold, has
zero TNS in every category, and reports:

| Check | Worst slack |
| --- | ---: |
| Setup | +0.195 ns |
| Hold | +0.011 ns |
| Recovery | +0.465 ns |
| Removal | +0.151 ns |
| Minimum pulse width | +0.143 ns |

The independent endpoint report found exactly one first-stage register for
each of the six explicit BIST control synchronizers and one for the on-die
temperature EOC synchronizer.  Its 30 worst paths contained no setup, hold,
recovery, removal or pulse-width violations.

## Warning review

- The generic `10AXF40AA` target uses preliminary timing models and does not
  expose a concrete speed-grade string.  The regenerated EMIF therefore warns
  that its E1 speed grade cannot be compared with the blank alias speed grade.
  This is retained to produce an SOF accepted by JTAG ID `0x02E060DD`; timing
  was still checked at every model Quartus provides.
- The two incomplete I/O assignments are the auto-created complementary
  `clk_y3(n)` and `clk_y4(n)` pins.  The external differential reference-clock
  pins and DDR memory pins retain the recovered, previously validated board
  assignments and I/O standards.
- The two ignored generated LVDS assignments target internal EMIF
  `pll_ref_clk` ports, not package pins.
- Forty-eight unused RX and TX channels are expected because this DDR-only
  image instantiates no transceiver channel.
- The MLAB power-up warning applies to generated buffering.  Transaction
  valid/full state is reset and the BIST defaults disabled; the hardware test
  confirmed no transaction before explicit authorization.  Each active
  BIST-to-EMIF interconnect contains 65 command-bookkeeping entries for the
  64-outstanding limit; stale generated files are not referenced by the QIP.
- Platform Designer warns that the retained `master_top.master` port is
  disconnected.  Its only retained role is the existing reset source for the
  100 MHz management domain; both JTAG-to-DDR data connections are removed.
- Remaining connectivity, adapter-width and ROM-inference messages are inside
  generated Intel debug/calibration logic and do not indicate a truncated DDR
  data interface.

## SRAM and hardware result

- Pre-program JTAG: `02E060DD 10AT115S(1|2)`, TCK reported as 15 MHz.
- Final SOF programmed only to volatile SRAM in 52 seconds.
- Programmer: configuration succeeded, 0 errors, 0 warnings.
- Post-program JTAG again returned `0x02E060DD`; no new USB/JTAG disconnect or
  reset message appeared in the kernel log.
- Before traffic, both channels reported `pll_locked=1`, `cal_success=1`,
  `cal_fail=0`, `ecc_interrupt=0`.
- The management heartbeat and both user-clock heartbeats advanced.  Over the
  same 0.5-second sample, each user counter advanced about 2.667 times as far
  as the 100 MHz management counter, matching the expected 266.7 MHz domains.
- The raw ISSP power-up source mapped to logical `bist_control=0`; both engines
  were idle before any host write.
- Pre-test temperature was 59.84 C; the status gate is 90 C.

### Initial single-outstanding integrity baseline

Before the pipelined revision, SOF
`08206bc38b482294a7aed5dacfa2577d16cf9f04ae7ebcb9c6c41c6ce2a1c79c`
used one outstanding read for easier bring-up diagnosis.  Its final concurrent
full-aperture run stopped after both channels had reached
two complete passes:

| Result | Top channel | Bottom channel |
| --- | ---: | ---: |
| Completed passes | 2 | 2 |
| Error count | 0 | 0 |
| First-error address | 0 | 0 |
| Byte-error mask | 0 | 0 |
| ECC interrupt | 0 | 0 |

Each pass visits all 33,554,432 64-byte lines from `0x00000000` through
`0x7fffffc0`, using two LFSR patterns, rotating one-hot and rotating one-cold.
One pass performs 8 GiB of writes plus 8 GiB of reads per channel.  The final
run therefore exercised 32 GiB per channel, 64 GiB total, in 36.284 seconds.
Both engines ran simultaneously, were stopped by the cleanup path, and read
back `bist_control=0`, `running=0`, `errors=0` afterward.  Both calibrations
and ECC status remained healthy; final temperature was 61.20 C.

### Checked pipelined bandwidth

The latest SOF exposes the original 488-bit health/BIST ISSP node plus a
separate 256-bit read-only cycle-counter node, staying within Quartus's 511-bit
per-node limit.  Before traffic, both PLLs were locked, both calibrations had
succeeded, both ECC interrupts were zero, logical control was zero, both
engines were stopped, all counters were zero, and temperature was 60.52 C.

`measure_bandwidth.tcl` then ran both channels concurrently.  Each completed
pass performs four 2 GiB writes and four 2 GiB checked reads.  The reported
phase counters therefore measure complete 8 GiB phases and cannot be inflated
by short command buffering.

| Result | Top channel | Bottom channel |
| --- | ---: | ---: |
| Last write cycles | 200,088,232 | 200,970,320 |
| Last read cycles | 140,779,680 | 140,779,824 |
| Sustained write | 11.448 GB/s (10.662 GiB/s) | 11.398 GB/s (10.615 GiB/s) |
| Write efficiency vs 17.067 GB/s user port | 67.08% | 66.78% |
| Sustained checked read | 16.271 GB/s (15.154 GiB/s) | 16.271 GB/s (15.154 GiB/s) |
| Read efficiency vs 17.067 GB/s user port | 95.34% | 95.34% |
| Sequential write+read average | 13.440 GB/s | 13.405 GB/s |
| Complete passes before stop | 9 | 8 |
| Error count / ECC interrupt | 0 / 0 | 0 / 0 |

The conservative dual-channel aggregate, using the slower channel's complete
write+read cycle count, was 26.811 GB/s.  JTAG polling and control latency let
the engines continue for several passes before the stop command; that does not
affect the latched per-pass cycle measurements.  Cleanup returned logical
control and both `running` flags to zero.  Final temperature was 63.90 C, both
calibrations remained healthy, and QSPI Flash was untouched.

### Short endurance smoke test

`run_endurance.tcl 60 5` requested a 60-second concurrent run and completed in
66.1 seconds including polling and cleanup.  Both channels completed 49 full
passes and checked 841,813,590,016 bytes (approximately 784 GiB) per channel,
approximately 1.53 TiB total.  Both error counters and both ECC interrupts
remained zero; PLL and calibration status remained healthy.  Temperature was
63.90 C initially, peaked at 65.93 C, and finished at 65.26 C.  The cleanup
path read back `bist_control=0` and `running=0` for both channels.

## Limits

This validates calibration, timing, repeated full-address data integrity and
checked sequential bandwidth at DDR4-2133 on this card, including a short
endurance smoke test.  The user elected to close this validation round without
the proposed two-hour run.  A multi-hour thermal/endurance qualification and a
dedicated static-retention interval therefore remain unclaimed optional work,
not failed tests.  The capacity geometry audit is complete.  QSPI Flash and
both PCIe interfaces were untouched.
