# Catapult v3 QSFP and transceiver validation

This directory owns the local, single-card QSFP validation work.  It is based
on board facts recovered by the community, but every result claimed here must
come from a Quartus 22.1 rebuild and an SRAM-only test on the current Longs
Peak card.

## Proven board connections

The local pinout workbook and the community `SuperliteII_V4_QSFP` project agree
on the following FPGA connections:

| Function | FPGA pin(s) | Direction at FPGA | Local test scope |
| --- | --- | --- | --- |
| QSFP reference clock Y5 | `U29/U28` | input, LVDS | measure and use as the transceiver reference |
| QSFP RX lanes 0..3 | `W33/W32`, `V35/V34`, `V31/V30`, `U33/U32` | input | CDR/PCS and external-path tests |
| QSFP TX lanes 0..3 | `V39/V38`, `U37/U36`, `T39/T38`, `R37/R36` | output | internal loopback first; external path only with a suitable endpoint |
| QSFP module present, active low | `AG15` | input, 1.8 V | sample before enabling the high-speed test |
| management I2C channel 1 | `K20/L20` | open-drain | retimer `0x22` and module EEPROM `0x50` |

The workbook shows the cage `ModSelL`, `LPMode/Reset` and `IntL` pins, but does
not map them to additional FPGA GPIO pins.  They are therefore not driven or
claimed as FPGA-controllable here.  Unknown and unused pins remain inputs or
tri-stated.

The QSFP lanes pass through the eight-channel DS250DF810 retimer; four retimer
channels cover each direction.  The recovered management path places the
retimer at 7-bit I2C address `0x22`.  The module EEPROM, when a module or DAC is
present and selected by the board wiring, is expected at `0x50`.

## What one card can prove

The validation is split so that an internal result cannot be mistaken for a
complete cage result.

1. **Management plane**
   - sample `modprsl` without driving it;
   - confirm the Y5 reference clock;
   - scan channel 1 and read the retimer's current channel/rate registers;
   - read the QSFP identifier/vendor/part/serial fields only if `0x50` ACKs;
   - with no module installed, optionally write the documented volatile
     10.3125 Gbit/s quick-rate setting and verify its readback.
2. **FPGA internal high-speed path**
   - instantiate four Arria 10 Native PHY lanes at 10.3125 Gbit/s;
   - enable each Native PHY serial loopback input;
   - verify reference/fPLL lock, TX/RX reset completion, CDR lock and sustained
     per-lane pattern checking with zero errors;
   - keep the result labelled *internal PMA/PCS loopback*.  It does not pass
     through the retimer, cage, cable or module.
3. **External path**
   - configure the retimer for 10.3125 Gbit/s per lane;
   - require a QSFP loopback assembly or a second compatible endpoint;
   - then verify all four physical TX paths, retimer directions, cage contacts
     and RX paths using a long-duration error-counting run.

The reference Native PHY exposes `rx_seriallpbken[3:0]`; the reference software
maps those controls to one bit per lane.  This makes the second stage genuinely
single-card testable.  The community SuperLite protocol itself still requires
a remote peer when serial loopback is disabled.

## Safety boundary

- Use Quartus Prime Standard 22.1 and target `10AXF40AA`.
- Confirm JTAG ID `0x02E060DD`, USB health and airflow before configuration.
- Read `modprsl` first.  The initial internal-loopback load is permitted only
  with no QSFP module/cable installed, so an unintended external transmitter
  cannot disturb another device.
- Start at 10.3125 Gbit/s per lane.  Treat 12.5 Gbit/s as a later speed-grade
  experiment, because the generic FPGA target does not identify a concrete
  transceiver speed grade.
- Do not copy the community output products or program an old SOF.  Regenerate
  all Intel IP locally under Quartus 22.1.
- Do not write undocumented retimer registers.  The only initially permitted
  writes are the community-documented volatile sequence: select/broadcast via
  register `0xff`, then masked rate selection in register `0x2f`.
- Program SRAM only.  This validation does not touch QSPI Flash.

## Current evidence and remaining work

The existing local I2C project has already found stable ACKs from retimer
address `0x22`.  It did not find `0x50`, so module EEPROM access and all
external-path claims remain unverified.  The previous clock smoke test measured
Y5 at approximately 644.530 MHz, consistent with the nominal 644.53125 MHz
source used by the recovered fPLL configuration.

Next, add a management image that exposes `modprsl` and safe retimer readback,
then build a small four-lane internal-loopback image.  Build reports, artifact
hashes, exact status/error counters and hardware observations will be recorded
in `RESULTS.md` after each stage runs.
