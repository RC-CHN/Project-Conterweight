# Catapult v3 QSFP management-plane result

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

The current SRAM image is `qsfp_mgmt`.  A power cycle still restores the
`pcie-temp-demo` image from QSPI Flash.

## Remaining work

- Add the four-lane 10.3125 Gbit/s Native PHY internal serial-loopback image
  and validate PLL/reset/CDR status plus long-running per-lane error counters.
- Install a compatible QSFP module or DAC before testing EEPROM fields.
- Use a QSFP loopback assembly or a second compatible endpoint for the full
  FPGA TX -> retimer -> cage -> external path -> cage -> retimer -> FPGA RX
  test.  Internal loopback must not be presented as evidence for that path.
