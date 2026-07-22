# I/O smoke test results

Test date: 2026-07-22

## Build and configuration

- Quartus Prime Standard 22.1std.0 Build 915
- FPGA target: `10AXF40AA`
- Observed JTAG ID before and after programming: `0x02E060DD`
- SRAM artifact: `output_files/io_smoke.sof`
- SOF size: 36,727,414 bytes
- SOF SHA-256: `85f800b9e8518dc0230ed6c06d11c876f366b0cdfacbc97211e593ac2481468d`
- Full compilation: 0 errors, 5 warnings
- SRAM programming: successful, 0 errors, 0 warnings
- Flash was not modified.

The final Timing Analyzer run reports the design fully constrained for setup and
hold. Setup, hold, recovery, removal, and minimum-pulse-width checks all have
non-negative slack. The smallest observed hold slack is `+0.018 ns`, and the
smallest minimum-pulse-width slack is `+0.001 ns`.

The remaining critical warnings are the generic Arria 10 unused-RX and
unused-TX-channel preservation warnings. This smoke test deliberately contains
no transceiver instance, and Quartus states that unused-channel preservation is
effective only when at least one transceiver channel is instantiated. Warning
18291 records that timing characteristics for the generic `10AXF40AA` alias are
preliminary. None of these warnings indicates a failure in the exercised LED,
clock, or input logic.

## Five onboard clocks

The counters were read twice through the in-system source/probe service. The
100 MHz U59 clock is the measurement reference. Each high-speed clock is divided
by 32 before crossing into the U59 domain.

| Input | Measured frequency | Expected class | Result |
| --- | ---: | ---: | --- |
| U59 | 100 MHz reference | 100 MHz | active |
| Y3 | 266.666883 MHz | 266.667 MHz | pass |
| Y4 | 266.667073 MHz | 266.667 MHz | pass |
| Y5 | 644.529394 MHz | 644.53125 MHz | pass |
| Y6 | 644.530155 MHz | 644.53125 MHz | pass |

These are counter-ratio measurements, not oscilloscope measurements of edge
jitter or signal integrity.

## LEDs

`led_walk.tcl` applied and probe-verified all nine one-high patterns
`0x001` through `0x100`, followed by all nine one-low patterns `0x1fe` through
`0x0ff`. Every one of the 18 patterns matched the FPGA-side probe value. The
script then restored the automatic walking pattern and verified source control
returned to zero.

This proves independent digital control of all nine assigned LED outputs. A
person still needs to observe the card while the walk script is running to map
bit number to physical LED position and record active-high/active-low visual
polarity. Software probe readback alone cannot prove that the package-to-LED
board path or the LED itself emits light.

## J11 GPIO

The three documented J11 FPGA GPIO pins (`A24`, `A25`, `A26`) were compiled as
inputs only. Their sampled value during this test was `0b000`. No external
stimulus was attached, so input toggling and header continuity remain untested.
Any future stimulus must respect the 1.8 V I/O domain; these pins must not be
driven from a fixed 3.3 V source.

## Reproduction

Build and program the project as described in `README.md`, then run:

```bash
/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/system-console \
  --project_dir=. \
  --jdi=output_files/io_smoke.jdi \
  --script=read_io.tcl

/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/system-console \
  --project_dir=. \
  --jdi=output_files/io_smoke.jdi \
  --script=led_walk.tcl
```
