# Catapult v3 QSFP single-card validation results

Date: 2026-07-22 (Asia/Shanghai)

Board: Project-Conterweight `board 2`, Catapult v3 PCIe variant

Quartus: Prime Standard 22.1std.0 Build 915

Target: `10AXF40AA`

JTAG ID: `0x02E060DD`

JTAG TCK reported by plugin: `15M`

## Result

The QSFP management plane is locally verified without a module installed.
The image contains no transceiver instance and does not drive the four QSFP
high-speed transmit lanes.

- `MODPRSL=1`, so the active-low module-present input reports no module/cable.
- Y5 measured `644.528097`, `644.528674`, and `644.528682 MHz` in three
  independent 500 ms observations, consistent with nominal 644.53125 MHz.
- I2C address `0x22` ACKed on every run, confirming access to the DS250DF810
  management interface.
- Before configuration, selected reads returned register `0xff=0x21` and
  register `0x2f=0x54`.
- The guarded script wrote the community-documented volatile sequence:
  `0xff=0x03`, then `0x2f=0x04`.  The latter preserves the original low nibble
  and clears only the rate-select high nibble for 10.3125 Gbit/s.
- Immediate and independent subsequent readback returned `0xff=0x03` and
  `0x2f=0x04`; `retimer_rate_103125=PASS`.
- Address `0x50` NACKed, consistent with the independent `MODPRSL` observation
  that no QSFP module/cable is installed.  EEPROM identity/vendor/part/serial
  fields therefore remain untested rather than failed.
- Before and after every transaction, SCL/SDA were both high and all FPGA
  output enables were inactive.
- The accepted read-only runs report `target_configuration_bytes_written=0`.
  The guarded rate run reports exactly two target configuration value bytes.
- QSPI Flash was untouched.  The retimer writes and FPGA image are volatile.

This proves the board reference clock, FPGA-side presence input, management
I2C wiring, retimer ACK/register access and the documented quick-rate sequence.
It does not prove the FPGA transceiver, retimer datapath, cage contacts or any
external module/cable.

## Build and timing audit

The final Quartus 22.1 full compilation completed with 0 errors and 9 warnings.
Fitter selected `10AXF40AA`; Assembler completed with 0 errors and 0 warnings.

TimeQuest reports the design fully constrained for setup and hold at all four
timing corners.  Design-wide TNS is zero for setup, hold, recovery, removal and
minimum pulse width.

| Check | Worst slack |
| --- | ---: |
| Setup | `+0.624 ns` |
| Hold | `+0.016 ns` |
| Recovery | `+7.374 ns` |
| Removal | `+0.164 ns` |
| Minimum pulse width | `+0.001 ns` |

The two custom asynchronous cuts each match exactly one first-stage register:
`y5_toggle_meta` and `modprsl_meta`.  Their second synchronizer stages and all
downstream logic remain timed.  The explicit unconstrained-path report has
zero illegal/unconstrained clocks, ports and input/output paths.

The warnings were reviewed:

- two Fitter critical warnings report all 48 RX and 48 TX transceiver channels
  unused.  This is intentional for the management-only image; Quartus also
  states unused-channel preservation cannot operate without an instantiated
  transceiver;
- three synthesis warnings plus a connectivity summary come from generated
  JTAG stream/channel adapters (unused generated signals and an intentionally
  narrowed channel field), matching the previously validated I2C bridge;
- the generated JTAG FIFOs use 18 MLAB RAMs whose power-up contents are not
  guaranteed.  The controller is reset before use and no initial FIFO contents
  are consumed;
- timing for the generic `10AXF40AA` target is marked preliminary.

The Y5 negative differential pin now has an explicit LVDS assignment; the
final Fitter report contains no incomplete-I/O warning.  The post-fit bidir
table shows SCL/SDA as 1.8 V, 4 mA, slew rate 0, weak pull-up off, with dynamic
OE sources.  RTL ties the output data input to zero, so each pin can only pull
low or release.

## Artifact and SRAM test

- SOF size: `36,732,522` bytes.
- SOF SHA-256:
  `c78b7beb8e9e6f42aa7e779e7a745e4b700461283a3789998e7d628f95d89338`.
- Programmer checksum: `0x30759C45`.
- SRAM programming completed in 51 seconds with 0 errors and 0 warnings.
- Programmer identified device 1 as JTAG ID `0x02E060DD` before configuration.
- A post-test JTAG enumeration again returned `0x02E060DD`.

At the end of this management stage the SRAM image was `qsfp_mgmt`.  It was
later replaced by the internal-loopback image described below.  A power cycle
still restores the `pcie-temp-demo` image from QSPI Flash.

## FPGA-internal four-lane loopback

The locally generated `qsfp_internal_loopback` image passed on the same card at
10.3125 Gbit/s per lane.  Y5 drives one Arria 10 fPLL in transceiver mode; its
5.15625 GHz MCGB output clocks four non-bonded Native PHY TX lanes.  Each RX CDR
uses Y5 directly.  All four lanes use the Native PHY serial-loopback input, so
the test covers FPGA TX PCS/PMA, internal serial loopback, RX PMA/CDR and RX PCS,
but does not traverse the DS250DF810, cage, module or cable.

Before SRAM replacement, the already loaded `QSL1` image reported
`MODPRSL=1`, `source=0x00`, `safe_enable=0`, an advancing heartbeat and
`51.72 C`.  The cage was therefore empty and the old high-speed path disabled.
Immediately after programming the accepted image, and before any control
write, a second read-only preflight again returned `source=0x00`,
`safe_enable=0`, an advancing heartbeat and `50.37 C`.  This verifies on
hardware that the image's power-up state leaves the high-speed path off.

After the new image's explicit reset sequence, the accepted status was:

```text
fpll=1/0  tx_ready=0xf  rx_ready=0xf
lock_data=0xf  lock_ref=0xf  block_lock=0xf  checker=0xf
tx_cal=0x0  rx_cal=0x0  fifo_full=0x0  fifo_pfull=0x0  overflow=0x0
```

The test then injected data errors into lanes 0, 1, 2 and 3 independently.  In
each case only the selected lane's counter advanced, and all four injection
checks passed.  After clearing the counters, twelve five-second samples ran
with no checker error, FIFO overflow or CDR/block-lock loss.  The per-lane
66-bit block totals over the 60-second soak were:

```text
lane0=9385810667  lane1=9385810664
lane2=9385810667  lane3=9385810667
```

The final temperature was `52.40 C`.  The script ended with
`qsfp_internal_loopback=PASS` and then confirmed
`postflight source=0x00 safe_enable=0`.

### Internal-loopback build and timing audit

- Full compilation: 0 errors, 9 warnings.
- Analysis & Synthesis: 0 errors, 1 warning.
- Fitter: 0 errors, 7 warnings; selected `10AXF40AA`.
- Assembler: 0 errors, 0 warnings.
- TimeQuest full flow: 0 errors, 1 warning; the final custom timing audit
  completed with 0 errors and 0 warnings.
- Setup and hold are fully constrained, with zero unconstrained clocks, ports,
  input paths and output paths.
- Worst setup slack: `+1.166 ns`.
- Worst hold slack: `+0.017 ns` across all four corners (`+0.055 ns` in the
  slow 100 C corner used by the detailed path audit).
- Worst recovery slack: `+3.675 ns`.
- Worst removal slack: `+0.218 ns`.
- Worst minimum pulse-width slack: `+0.090 ns`.

The custom audit confirmed the exact first-stage CDC match counts: one each for
`modprsl_meta` and `temp_eoc_meta`, 50 status bits, 32 TX counter bits, 128
block-counter bits, 128 error-counter bits, 64 lock-loss bits, and four bits
for each per-lane TX-enable, TX-ready, injection, clear, block-lock, RX-ready
and FIFO-full crossing.  Only these first stages are cut; their second stages
and downstream logic remain timed.

The warnings were reviewed:

- generated Native PHY/JTAG hierarchy connectivity warnings are unused debug
  inputs/outputs and zero-filled disabled reconfiguration buses;
- unused HSSI channels on the left strip inherit a 1.03 V preservation setting,
  while all eight active QSFP RX/TX pins are explicitly assigned 1.0 V;
- timing for the generic `10AXF40AA` target is marked preliminary.

No critical warning was waived.  The 1 ps TimeQuest representation constrains
Y5 as `1.551 ns`, slightly faster than the measured 644.53125 MHz oscillator;
the generated fPLL and Native PHY parameters independently set the physical
line rate to 10.3125 Gbit/s.

### Internal-loopback artifact and SRAM test

- SOF size: `36,767,524` bytes.
- SOF SHA-256:
  `5e2e58ded09831fc50b92d9e9822e1652cb0bdefabdd498e7aaec554729b966e`.
- Programmer checksum: `0x307CAED4`.
- SRAM programming completed in 52 seconds with 0 errors and 0 warnings.
- Programmer and post-test scans both returned JTAG ID `0x02E060DD`; the plugin
  still reported 15 MHz TCK and the FT232H remained at USB High-Speed.
- The post-test kernel log contained no USB disconnect, descriptor, reset or
  xHCI fault; only local AppArmor denials caused by `lsusb` sysfs enrichment.
- QSPI Flash was untouched.

The current SRAM image is the disabled `qsfp_internal_loopback` image.  Power
cycling still restores `pcie-temp-demo` from QSPI Flash.

## Remaining work

- Install a compatible QSFP module or DAC before testing EEPROM fields.
- Use a QSFP loopback assembly or a second compatible endpoint for the full
  FPGA TX -> retimer -> cage -> external path -> cage -> retimer -> FPGA RX
  test.  Internal loopback must not be presented as evidence for that path.
