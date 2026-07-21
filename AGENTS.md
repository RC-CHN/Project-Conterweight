# AGENTS.md

## Scope

These instructions apply to the entire `Project-Conterweight` repository.

`Project-Conterweight` is the canonical spelling of the repository name. Do not rename it to `Project-Counterweight` unless the user explicitly requests that change.

The repository is intentionally at an early stage. Do not invent a project architecture, select a soft core, import a framework, or create a roadmap without a task from the user. Build only the layer needed for the current request and keep it compatible with the hardware and toolchain documented below.

## Target Board

The target is a Microsoft Catapult v3 SmartNIC in the standard PCIe card form factor, commonly called **Longs Peak** in community documentation.

Important hardware facts:

- FPGA: Altera/Intel Arria 10 with non-standard board marking `10AXF40GAA`.
- Quartus generic device target used by the recovered projects: `10AXF40AA`.
- Expected JTAG ID: `0x02E060DD`.
- Quartus may display the physical device as `10AT115S(1|2)`; this is expected.
- QSPI configuration flash: 1 Gbit / 128 MiB class device. Community documents name `N25Q00AA`; verify the actual flash before creating or writing a JIC.
- DDR4: 5 GB fitted, approximately 4.5 GB usable by the FPGA, organized as two independent 72-bit interfaces (64 data + 8 ECC).
- FPGA connectivity: two independent PCIe Gen3 x8 interfaces.
- NIC: Mellanox ConnectX-4 Lx on the standard PCIe variant, with its own PCIe interface.
- Network cage: one QSFP+ path through a TI `DS250DF810` retimer.
- Onboard programmer: FTDI `FT232H`, connected through the external USB Type-B port.
- Nine LEDs are connected to FPGA pins.
- The PCIe variant has external JTAG, I2C, GPIO, and fan headers.

Do not assume undocumented pins are safe outputs. Keep unknown or unused pins as inputs/tri-stated until their voltage domain and destination are confirmed.

## Host Toolchain

The working toolchain is Intel Quartus Prime Standard Edition 22.1:

```text
Version: 22.1std.0 Build 915
Install: /workspace/intelFPGA/22.1std
Quartus: /workspace/intelFPGA/22.1std/quartus
```

The Arria 10 device support is installed. The required environment is already configured in `/home/pan/.bashrc`:

```bash
export LM_LICENSE_FILE="/workspace/intelFPGA/22.1std/License.dat"
export QUARTUS_ROOTDIR="/workspace/intelFPGA/22.1std/quartus"
export PATH="/workspace/intelFPGA/22.1std/quartus/bin:$PATH"
export QSYS_ROOTDIR="/workspace/intelFPGA/22.1std/quartus/sopc_builder/bin"
```

At the start of an FPGA task, load and verify the environment:

```bash
source /home/pan/.bashrc
quartus_sh --version
command -v quartus_sh quartus_pgm jtagconfig
```

Do not copy, publish, or commit `License.dat` or its contents.

Quartus is fully usable from the CLI. Common commands are:

```bash
# Complete project compilation
quartus_sh --flow compile <revision>

# Scan connected JTAG hardware and the device chain
jtagconfig --enum

# Load a SOF into volatile FPGA SRAM
quartus_pgm -c 1 -m jtag -o 'p;path/to/design.sof'
```

Shell continuation backslashes must be the final character on the line. Do not write `quartus_sh \ --flow ...`; that passes a malformed argument containing a leading space.

Quartus may use fewer workers than `NUM_PARALLEL_PROCESSORS` requests. A previous build requested 52 but Quartus reported a maximum of 16 for its active stages. Treat the tool's log as authoritative.

## Device Selection: Critical Detail

Prefer the recovered project's generic device assignment:

```tcl
set_global_assignment -name FAMILY "Arria 10"
set_global_assignment -name DEVICE 10AXF40AA
```

Quartus 22.1 can synthesize, fit, assemble, and time-analyze `10AXF40AA`, even though some public Quartus Tcl part-list queries report that alias as illegal. The Fitter has been observed to print:

```text
Selected device 10AXF40AA for design "Catapult_v3_LEDs"
```

Do not automatically replace it with `10AX115N4F40E3SG`. That concrete production part compiles, but its SOF expects JTAG ID `0x02E660DD`; the installed board reports `0x02E060DD`, so Quartus Programmer can reject the image before configuration.

The generic Programmer entry accepts the relevant Arria 10 silicon IDs, including `0x02E060DD`. If changing the target device is necessary, explain why and validate the resulting SOF with an SRAM-only load before any persistent programming.

## JTAG and USB

The current board's onboard FT232H is working and has completed long-running stability and full-SOF transfer tests.

Healthy USB enumeration:

```text
0403:6014 Future Technology Devices International, Ltd FT232H
USB speed: 480 Mbps (High-Speed)
```

Healthy JTAG enumeration:

```text
1) JTAG-MPSSE-Blaster [00 Single RS232-HS]
  02E060DD   10AT115S(1|2)
```

Use these read-only checks first:

```bash
lsusb -d 0403:6014
lsusb -t
timeout 15 jtagconfig --enum
journalctl -k -b --no-pager | rg -i 'usb|ftdi|jtag|descriptor|disconnect|reset|xhci'
```

Quartus accesses the onboard FT232H through the community `jtag-mpsse-blaster` plugin:

```text
Source:  /home/pan/jtag-mpsse-blaster
Plugin:  /workspace/intelFPGA/22.1std/quartus/linux64/libjtag_hw_mpsse.so
```

The plugin currently hard-codes FT232H TCK to 15 MHz. It implements `GetParam` for `JtagClock` but no writable `SetParam`, so this works:

```bash
jtagconfig --getparam 1 JtagClock
```

and normally returns `15M`, but this is not expected to work:

```bash
jtagconfig --setparam 1 JtagClock 6M
```

Do not claim the clock was changed unless `--getparam` verifies it. To lower TCK, modify and rebuild the plugin with a different MPSSE divisor, keep the original shared object backed up, restart `jtagd`, and re-run the JTAG tests.

Host-side command latency is not TCK electrical jitter. `jtagconfig` can wait on `jtagd` polling/locking in roughly 500 ms increments. Assess practical link stability with repeated IDCODE scans, a full SOF transfer, Programmer status, and USB kernel errors. An oscilloscope or logic analyzer is required for actual TCK edge/jitter measurement.

An SLD virtual JTAG hub exists only when the loaded design contains the relevant SLD nodes. A missing SLD hub does not by itself mean the physical JTAG chain failed; always confirm the physical IDCODE first.

### External JTAG Header

The board also exposes J5, a standard 2x5 Altera-style JTAG header with a **1.8 V target reference**:

| Pin | Signal |
| ---: | --- |
| 1 | TCK |
| 2 | GND |
| 3 | TDO |
| 4 | VCC(TRGT), 1.8 V |
| 5 | TMS |
| 6-8 | NC |
| 9 | TDI |
| 10 | GND; also disables the onboard FT232H path |

Only use an external programmer that follows VCC(TRGT) and explicitly supports 1.8 V signaling. Do not use a fixed-3.3-V clone. Confirm pin 1 orientation before attaching a cable.

## Known-Good SRAM Flow

A known-good Quartus 22.1 build for the current board is available at:

```text
/home/pan/catapult-build/LEDs-f40-q22
```

The matching output is:

```text
/home/pan/catapult-build/LEDs-f40-q22/output_files/Catapult_v3_LEDs.sof
```

Observed artifact properties:

```text
Size:   36,721,134 bytes
SHA256: f68641e9f89ff9e6db94c24d9dfd23a6db5b79ca4024a4aa9b23c7960717023e
Target: 10AXF40AA
```

It completed a full volatile configuration at 15 MHz TCK:

```text
Device 1 contains JTAG ID code 0x02E060DD
Configuration succeeded -- 1 device(s) configured
Quartus Prime Programmer was successful. 0 errors, 0 warnings
```

The transfer took about 54 seconds. Twenty immediate post-load JTAG scans also passed. This design is a useful smoke test, not the required base for every new project.

For any new hardware design:

1. Confirm `jtagconfig --enum` before compiling or programming.
2. Compile with Quartus 22.1 and review every error, critical warning, and timing report.
3. Confirm the generated artifact target is `10AXF40AA` unless the user approved another device.
4. Load the `.sof` into SRAM first.
5. Confirm Programmer success and scan JTAG again.
6. Verify the design's visible behavior and temperature before considering persistence.

## Persistent Flash Safety

Treat `.sof` and `.jic` differently:

- `.sof` configures volatile FPGA SRAM and is lost on power removal.
- `.jic` can modify the QSPI configuration flash and change power-on behavior.

Do not write, erase, or blank-check QSPI merely as a diagnostic step. Persistent flash operations require an explicit user request.

Before the first persistent write to this physical board:

1. Read back the complete current QSPI contents.
2. Record board identity, detected silicon ID, flash part/geometry, tool version, size, timestamp, and SHA-256.
3. Mark the backup read-only and copy it to a second storage location.
4. Test the intended design as a `.sof` in SRAM.
5. Confirm cold-boot recovery and rollback plans.
6. Generate the JIC for the flash actually detected on this board; do not infer the exact part from another card or a community BOM.

Never assume a backup from a different physical card is a valid restore image for this board.

## PCIe Development

The hardware exposes FPGA PCIe x8 connectivity, but an FPGA reconfiguration makes the endpoint disappear and retrain. Linux may retain stale BAR mappings or driver state. Do not assume PCIe FPGA reconfiguration behaves like supported hot-plug.

For PCIe work:

- Prefer a host reboot or a deliberate remove/rescan sequence after changing the endpoint design.
- Unbind any driver before direct BAR access.
- Do not keep an `mmap` of a BAR across FPGA reconfiguration.
- Verify width and speed with `lspci -vv`; board capability does not guarantee the negotiated link generation.
- Record vendor/device IDs and BAR sizes as part of the hardware/software ABI.
- Add stable design ID, ABI version, heartbeat, reset reason, and error counters before adding DMA.

There is an existing reusable PCIe BAR prototype at:

```text
/home/pan/catapult-build/PCIe-debug-q22
```

Its prototype ABI uses PCI ID `1172:e003`, a 64-byte BAR0 register aperture, and an 8 KiB BAR2 test RAM. BAR0 includes:

| Offset | Access | Meaning |
| ---: | :---: | --- |
| `0x00` | RO | `0x43505433` (`CPT3`) design ID |
| `0x10` | RO | 100 MHz heartbeat counter |
| `0x20` | RO | Arria 10 temperature ADC status/code |
| `0x30` | RW | LED control bits |

The host utility and ABI notes are:

```text
/home/pan/catapult-build/PCIe-debug-q22/catapult-bar
/home/pan/catapult-build/PCIe-debug-q22/REGISTERS.md
```

This is reference code, not an instruction to program its existing artifacts unchanged. Check its QSF device target and rebuild it for `10AXF40AA` before loading it on the current board.

Direct sysfs BAR mapping as root is acceptable for focused bring-up, but a maintained design should move to VFIO/UIO or a real kernel driver with explicit ABI and concurrency rules.

## DDR4, QSFP, I2C, and Thermal Work

These subsystems have a much larger electrical and timing blast radius than LEDs or a small BAR. Do not enable them by guessing constraints.

- Reuse verified pin assignments from the available board documentation.
- Keep the two DDR4 interfaces distinct and preserve ECC/data organization.
- Run EMIF calibration and expose calibration/error status to a debug interface.
- Add memory tests before using DDR as DMA storage.
- The `DS250DF810` retimer is reachable on the documented management path at I2C address `0x22` in the community design.
- The retimer's default line rate is not automatically suitable for an Arria 10 40/50 GbE experiment. Configure and verify CDR/line rate before expecting a QSFP link.
- Communication between the FPGA and the Mellanox ASIC is not fully documented. Do not describe that path as working without a local test.

The card contains several high-power components and may rely on server chassis airflow rather than an onboard fan. Ensure airflow before sustained FPGA, DDR4, transceiver, or NIC load. Read temperature during bring-up, but do not treat one idle reading as a full-load thermal qualification.

## Repository and Reference Material

The user will direct the project architecture and which reference material to use. Do not broadly port or copy an upstream project without a task-specific reason.

The current `references/` directory contains two nested Git repositories:

```text
references/catapult-v3-smartnic-re
references/microsoft_fpga
```

Use them as read-only technical references unless the user explicitly asks for changes there. They contain pinouts, example Quartus projects, PCIe/DDR demonstrations, an old OpenCL BSP, and a RISC-V example. Their tool versions and assumptions may differ from the active Quartus 22.1 environment.

Do not delete their nested `.git` directories, flatten their history, update their remotes, or add the entire `references/` tree to the parent repository unless instructed. Avoid generated changes inside reference projects.

Useful external/local documentation:

```text
/home/pan/catapult-build/CATAPULT_V3_BRINGUP.md
/home/pan/catapult-v3-smartnic-re/Documents/FPGA_Pinouts.xlsx
/home/pan/catapult-v3-smartnic-re/Documents/Header_Pinouts.xlsx
```

## Engineering Conventions

- Read the active QPF/QSF/SDC and nearby RTL before changing a design.
- Keep source, generated build databases, and programming artifacts clearly separated.
- Do not commit `db/`, `incremental_db/`, temporary Programmer files, logs, or large bitstreams unless the user explicitly wants release artifacts tracked.
- Keep pin assignments and I/O standards traceable to a board document or a previously validated design.
- Do not silently waive critical timing, I/O, or configuration warnings.
- Treat setup, hold, recovery/removal, pulse-width, and unconstrained-path reports as part of correctness.
- Prefer a small, observable hardware increment over integrating several unverified subsystems at once.
- Add hardware-visible version/ID registers to host-facing designs.
- Record the Quartus version, target part, artifact hash, JTAG ID, and test result for reproducible hardware tests.
- Preserve unrelated user changes and inspect `git status` before and after work.
- Do not change host-wide USB power policy, udev rules, systemd units, kernel drivers, or PCI controller state unless the task requires it and the user understands the impact.
- Never reset a USB controller without first checking which other devices share it.

## Minimum Completion Checklist

For an RTL or FPGA integration task, do not report completion until the applicable items are done:

- Source and constraints reviewed.
- Quartus compilation completed with zero errors.
- Critical warnings reviewed and either fixed or explicitly explained.
- Timing analysis completed for the intended clocks.
- Output artifact target and SHA-256 recorded.
- JTAG chain checked before programming.
- SRAM-only programming completed successfully when hardware validation is requested.
- JTAG and USB checked again after programming.
- User-visible function tested through LEDs, BAR registers, memory test, or the relevant interface.
- Temperature/airflow considered for sustained tests.
- Persistent flash left untouched unless explicitly requested and backed up first.

