# I/O smoke test

This SRAM-only design validates the low-risk, single-card board I/O:

- nine known 1.8 V LED outputs;
- the U59, Y3, Y4, Y5, and Y6 oscillator inputs;
- the three J11 GPIO pins as input-only 1.8 V signals.

It intentionally contains no PCIe HIP, DDR4 EMIF, I2C master, QSPI access, or
high-speed serial transmitter. All unassigned pins are input/tri-stated.

Build:

```bash
source /home/pan/.bashrc
quartus_sh --flow compile io_smoke
```

After reviewing the reports, load the SOF into volatile SRAM:

```bash
jtagconfig --enum
quartus_pgm -c 1 -m jtag -o 'p;output_files/io_smoke.sof'
```

Read the oscillator counters and input state. The fast clock domains use a
six-bit divider; the script converts divided-edge counts back to input clock
frequency relative to U59:

```bash
/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/system-console \
  --project_dir=. --jdi=output_files/io_smoke.jdi --script=read_io.tcl
```

Exercise both LED polarities, one pin at a time:

```bash
/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/system-console \
  --project_dir=. --jdi=output_files/io_smoke.jdi --script=led_walk.tcl
```

Loading this SOF temporarily removes the existing FPGA PCIe endpoint. It does
not modify QSPI flash; a power cycle restores the flash-resident design.
