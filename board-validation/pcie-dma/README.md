# PCIe DMA validation

This project validates the first FPGA PCIe x8 interface by moving data through
the following closed loop:

```text
coherent host buffer -> PCIe Read DMA -> FPGA on-chip RAM
FPGA on-chip RAM -> PCIe Write DMA -> coherent host buffer
```

The first milestone deliberately uses 1 MiB of on-chip RAM instead of DDR4.
This isolates PCIe bus mastering, descriptor fetches, payload movement, status
writeback, BAR access, and host-side data comparison from EMIF integration.
After this path is proven, the same DMA masters can be connected to the already
validated DDR4 controllers.

## Fixed interface

- FPGA PCIe interface: first x8 interface only
- Link capability: PCIe Gen3 x8
- PCI ID: `1172:e004`
- BAR0: Intel internal chained-DMA descriptor controller
- BAR4: 2 MiB application window
- DMA device buffer: 1 MiB on-chip RAM at device address `0x00000000`
- Completion method in milestone 1: EPLAST status writeback polling
- FPGA target used by the Quartus project: `10AXF40AA`

Platform Designer cannot configure the Gen3 x8 / 256-bit HIP variant when its
catalog context uses the non-production `10AXF40AA` alias. The generation
script therefore uses `10AX115N4F40E3SG` only as the IP catalog's part-trait
context, matching the already working PCIe prototype. The Quartus QSF remains
authoritative and compiles the complete design for `10AXF40AA`; the generated
SOF target must be checked before any SRAM load.

## Build

Quartus Prime Standard 22.1 is required:

```bash
source /home/pan/.bashrc
make generate
make compile
make driver
```

Generated HDL, Quartus databases, logs, reports, and programming artifacts are
ignored by Git. The generated `dma_system.qsys` remains tracked together with
`generate_system.tcl` so that the exact IP configuration is reviewable and
reproducible.

## Host test

After the SRAM image is loaded and the host has rebooted, the endpoint should
enumerate as `1172:e004`. Load the validation driver and run a closed-loop
transfer from its PCI sysfs directory:

```bash
sudo insmod driver/catapult_dma.ko
device=/sys/bus/pci/devices/0000:6a:00.0
cat "$device/catapult_dma/info"
echo "131072 10" | sudo tee "$device/catapult_dma/run"
cat "$device/catapult_dma/result"
sudo rmmod catapult_dma
```

Replace the BDF if enumeration assigns a different address. The `run` input is
`<bytes> <loops>`; the byte count must be four-byte aligned and no greater than
262140 in milestone 1. A passing result reports separately measured
host-to-FPGA and FPGA-to-host MB/s and `total_errors=0`.

## Hardware-test boundary

The new SOF must first be loaded into volatile SRAM. Reconfiguring the FPGA
removes the active PCIe endpoint, and this host has not reliably recovered it
with a PCIe rescan, so a host reboot is expected before running the driver.
This project does not write QSPI Flash.

Hardware results, artifact hashes, warning review, timing closure, negotiated
link width/speed, temperature, and DMA measurements belong in `RESULTS.md`.
