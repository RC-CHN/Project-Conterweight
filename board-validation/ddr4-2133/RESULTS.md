# Catapult v3 dual DDR4-2133 local validation

## Scope

This record covers the isolated `Catapult_v3_DDR4_2133` revision on the
current Longs Peak `board 2`.  Both independent 72-bit interfaces run at
DDR4-2133: 1066.667 MHz memory clock and approximately 266.7 MHz quarter-rate
user clock.  The test covers the complete 2 GiB controller address aperture
implemented for each channel; it does not claim the additional fitted memory
capacity described by community documentation.

Date: 2026-07-23 (Asia/Shanghai)

## Reproducible build

- Quartus Prime Standard 22.1std.0 Build 915.
- Target: `10AXF40AA`.
- `./regenerate.sh` verified that both base EMIFs were 800 MHz, changed both to
  1066.667 MHz, saved a local generated system, and regenerated synthesis HDL.
- Full compilation: 0 errors, 29 warnings.
- Fitter: Standard Fit, 0 errors, 7 warnings.
- Final SOF size: 36,857,644 bytes.
- Final SOF SHA-256:
  `08206bc38b482294a7aed5dacfa2577d16cf9f04ae7ebcb9c6c41c6ce2a1c79c`.
- Quartus Programmer checksum: `0x30D09CA7`.

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
| Setup | +0.269 ns |
| Hold | +0.013 ns |
| Recovery | +0.574 ns |
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
  confirmed no transaction before explicit authorization.
- Platform Designer warns that the retained `master_top.master` port is
  disconnected.  Its only retained role is the existing reset source for the
  100 MHz management domain; both JTAG-to-DDR data connections are removed.
- Remaining connectivity, adapter-width and ROM-inference messages are inside
  generated Intel debug/calibration logic and do not indicate a truncated DDR
  data interface.

## SRAM and hardware result

- Pre-program JTAG: `02E060DD 10AT115S(1|2)`, TCK reported as 15 MHz.
- Final SOF programmed only to volatile SRAM in 53 seconds.
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

The final concurrent full-aperture run stopped after both channels had reached
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

## Limits

This validates calibration, timing and repeated full-address data integrity at
DDR4-2133 on this card.  The single-outstanding read BIST is deliberately easy
to diagnose and is not a peak-bandwidth benchmark.  A multi-outstanding traffic
generator, multi-hour thermal/endurance run, retention testing, and audit of
the community 5 GB fitted / approximately 4.5 GB usable geometry remain open.
QSPI Flash and both PCIe interfaces were untouched.
