# Catapult v3 dual-I2C validation

This project validates the two documented FPGA-controlled 1.8 V I2C buses with
an Intel Avalon I2C controller on each bus and a JTAG-to-Avalon host bridge.
It is intentionally separate from PCIe, DDR4, QSPI, and transceiver logic.

Safety properties:

- `K20/L20` and `J23/K21` are the only board-management pins used.
- The top-level I2C outputs can pull low or go high-impedance; they cannot drive
  a logic high.
- `scan_i2c.tcl` refuses to transact unless both buses are idle-high and all
  four output enables are inactive.
- Discovery sends each address in the read direction. An ACKed target returns
  exactly one byte, which the controller NACKs before STOP. Discovery writes no
  target byte and does not select a target register.
- A JTAG-controlled open-drain recovery path is disabled by default. The
  guarded `recover_i2c.tcl` script can pulse SCL and generate STOP without any
  path that actively drives a high level.
- `read_i2c_ids.tcl` selects only documented read-only ID/status pointers on
  already discovered targets; it writes no target configuration value.
- QSPI Flash is not present in the design and is not modified.

Regenerate the Platform Designer system and compile with Quartus 22.1:

```bash
/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/qsys-script \
  --script=generate_system.tcl

/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/qsys-generate \
  i2c_bridge.qsys \
  --synthesis=VERILOG \
  --part=10AXF40AA

quartus_sh --flow compile i2c_scan
```

After reviewing the reports, load only the SOF into SRAM and scan:

```bash
quartus_pgm -c 1 -m jtag -o 'p;output_files/i2c_scan.sof'

/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/system-console \
  --project_dir=. \
  --jdi=output_files/i2c_scan.jdi \
  --script=scan_i2c.tcl

/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin/system-console \
  --project_dir=. \
  --jdi=output_files/i2c_scan.jdi \
  --script=read_i2c_ids.tcl
```

The scan runs twice on both buses and requires identical ACK address sets.
See `RESULTS.md` for the local board result and the one-time recovery required
after the original address-only scanner exposed an Intel controller BUS_HOLD
behavior.
