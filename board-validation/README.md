# Catapult v3 board validation

This directory contains small, independent hardware-validation projects for the
current Catapult v3 Longs Peak card. Each project targets `10AXF40AA` and must
be rebuilt with Quartus Prime Standard 22.1.

Validation images are loaded into volatile FPGA SRAM only. They are not flash
images. Unknown and unused board pins remain input/tri-stated.

Current projects:

- `io-smoke`: nine LEDs, five board oscillator inputs, and the three J11 GPIO
  pins as high-impedance inputs.

