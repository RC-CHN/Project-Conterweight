# Catapult v3 dual-I2C local validation result

Date: 2026-07-22 (Asia/Shanghai)

Board: Project-Conterweight `board 2`, Catapult v3 PCIe variant

Quartus: Prime Standard 22.1std.0 Build 915

Target: `10AXF40AA`

JTAG ID: `0x02E060DD`

JTAG TCK reported by plugin: `15M`

## Result

Both documented FPGA-controlled I2C buses are locally verified at 100 kHz.
Both were idle-high before and after the accepted test, both produced
repeatable ACK address sets, and documented read-only ID/status registers were
read without changing a target configuration value. QSPI Flash was untouched.

| Bus | FPGA SCL/SDA | Repeated ACK addresses |
| --- | --- | --- |
| channel 1 | `K20` / `L20` | `0x22` |
| channel 2 | `J23` / `K21` | `0x0c 0x1f 0x27 0x40 0x42 0x4c 0x51 0x6d` |

The accepted scan ran two complete passes on each bus. Address sets matched.
Every ACKed target returned one byte in the read direction and was terminated
with controller NACK plus STOP. `target_data_bytes_written=0`; the final probe
was `lines=0xf`, `oe=0x0`, `reset_n=1`.

## Build and report audit

The final source includes explicit Arria 10 I/O atoms whose data input is tied
to zero. Dynamic OE selects either pull-low or high impedance, never an active
high output. The post-fit Bidir Pins table reports all four pins as 1.8 V and
shows an OE source for each pin.

- Full compilation: 0 errors, 9 warnings.
- Fitter selected `10AXF40AA`.
- Setup and hold requirements are fully constrained.
- Worst setup slack: `+5.456 ns`.
- Worst hold slack: `+0.016 ns`.
- Worst recovery slack: `+7.469 ns`.
- Worst removal slack: `+0.166 ns`.
- Worst minimum pulse-width slack: `+4.511 ns`.
- SOF size: `36,732,692` bytes.
- SOF SHA-256: `c0f35d8d3f8f204b4dcd7a6b4cfee05de64cfb6f9cbdd772d4f2e21a9849e52a`.
- SRAM programming: success, 0 errors, 0 warnings, 53 seconds.

The two Fitter critical warnings say that all 48 RX and 48 TX transceiver
channels are unused. That is expected for this I2C-only image; it contains no
transceiver instance and does not drive QSFP. Other warnings are generated-IP
connectivity/width notices, MLAB power-up behavior, and preliminary timing for
the generic `10AXF40AA` target. No I2C open-drain/OE warning remains.

## Address evidence

| Bus/address | Evidence | Status |
| --- | --- | --- |
| ch1 `0x22` | Local ACK/current-byte reads; community design and local DS250DF810 material assign the retimer to `0x22` | DS250DF810 retimer confirmed at management-plane level; undocumented rate/channel registers were not written |
| ch2 `0x4c` | TMP411 MFR ID `0x55`, device ID `0x12` | TMP411A/E confirmed |
| ch2 `0x27` | Pointer `0x06` returned configuration bytes `ff ff`, matching PCA9535 ports configured as inputs | PCA9535 strongly supported |
| ch2 `0x51` | ACK/current-byte reads; address is in the M24128 memory-array range and the board BOM contains U16 M24128WP | M24128 EEPROM likely; contents were not interpreted or written |
| ch2 `0x6d` | ACK/current-byte reads; both local 9DBV0241/0441 datasheets specify `0x6d` for the fitted address option | 9DBV PCIe clock buffer strongly supported |
| ch2 `0x40` | ACK/current reads return `ff`; PMBus `MFR_ID(0x99)` and `CAPABILITY(0x19)` command bytes NACK, while `STATUS_BYTE(0x78)` returns `ff` and `READ_VIN(0x88)` returns `ff ff` | Responding device confirmed, but a normally operating LM25066 is not supported by the command behavior; identity unresolved |
| ch2 `0x42` | ACK/current-byte reads; pointer `0x99` returned `ff ff ff ff`, not a valid LM25066 block MFR_ID | Identity unresolved |
| ch2 `0x0c`, `0x1f` | Repeatable ACK/current-byte reads only | Identity unresolved |

The local address set is close to the community scan image but not identical:
the community image also showed `0x48`, while this board did not. No QSFP
EEPROM at the usual `0x50` address responded, so QSFP module/cable management
cannot be marked locally verified from this run.

## Read-only status

TMP411 documented read-only registers returned:

- manufacturer ID (`0xfe`): `0x55`;
- device ID (`0xff`): `0x12`;
- local temperature (`0x00`, two-byte read): `0x23 0x00`, approximately
  `35.000 C`;
- remote temperature (`0x01`, two-byte read): `0x2b 0x20`, approximately
  `43.125 C`.

The identification script writes pointer/PMBus command bytes only to select
read-only registers and reports `target_configuration_bytes_written=0`. It
does not clear faults, change thresholds, configure GPIO outputs, change clock
settings, or program the retimer.

Address `0x40` received an additional candidate-specific read-only probe. A
LM25066 must support `CAPABILITY(0x19)` (datasheet default `0xb0`) and
`MFR_ID(0x99)`, but this target NACKed both command bytes. It ACKed
`STATUS_BYTE(0x78)` and `READ_VIN(0x88)` but returned only `ff`/`ff ff`.
Consequently `0x40` is electrically reachable but is not identified as a
normally operating LM25066. Determining whether it is another PMBus regulator,
an unready power device, or an address alias needs schematic tracing or a
device-specific command map.

## BUS_HOLD discovery and recovery

The first scanner attempted an address byte in the write direction with STOP
set on that same FIFO command. Addresses `0x03` through `0x21` NACKed normally,
but `0x22` ACKed and the controller remained busy. Intel's 22.1
`altera_avalon_i2c_mstfsm.v` shows why: after an address ACK with an empty FIFO,
the controller enters `BUS_HOLD`; the address command's STOP bit is not acted
on in the address state.

The scanner stopped instead of forcing more traffic. A read-only diagnostic
showed channel 1 `STATUS=1`, line bitmap `0xd`, and FPGA OE bitmap `0x0`: the
target held SDA low after the incomplete transaction while the FPGA released
all lines. Reprogramming the same SOF reset the FPGA controller but did not
release target SDA.

The final image therefore adds a default-off JTAG recovery mux ahead of the
same constant-low I/O atoms. `recover_i2c.tcl` accepted only the expected
`0xd` precondition, pulsed channel-1 SCL once, then generated an explicit STOP.
It ended with `lines=0xf`, `oe=0x0`, and returned ownership to the Intel
controllers. The accepted scanner uses read-direction discovery and a separate
receive command carrying STOP, so every ACKed address terminates correctly.

## Remaining limits

- The unresolved channel-2 addresses need schematic tracing or known-safe,
  device-specific ID commands before assigning names.
- QSFP EEPROM/presence was not observed; an installed compatible module or
  cable is needed for that part of management-plane validation.
- Retimer line-rate, channel selection, CDR state, and high-speed datapath were
  deliberately not changed by this I2C step.
- This SOF is loaded only in SRAM. Flash still contains `pcie-temp-demo`.
