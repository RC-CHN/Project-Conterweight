# PCIe DMA validation results

Status: Gen3 build, post-fit timing, and SRAM configuration passed, but the
endpoint did not enumerate after a host reboot. DMA hardware tests are blocked
until a link-capable image is loaded and the host is rebooted again.

## Build evidence

Date: 2026-07-23 (Asia/Shanghai)

- Quartus Prime Standard 22.1std.0 Build 915
- target: Arria 10 `10AXF40AA`
- Fitter: successful, 0 errors
- Assembler: successful, 0 errors
- final standalone TimeQuest: successful, 0 errors, 5 warnings
- host driver: builds against Linux `7.0.0-28-generic`
- driver PCI alias: `1172:e004`

Post-fit resource use:

| Resource | Used | Available |
| --- | ---: | ---: |
| ALMs | 14,646 | 427,200 |
| registers | 27,661 | — |
| block-memory bits | 8,876,544 | 55,562,240 |
| RAM blocks | 555 | 2,713 |
| HSSI RX channels | 8 | 48 |
| HSSI TX channels | 8 | 48 |

Final multicorner worst-case slack:

| Check | Slack |
| --- | ---: |
| setup | +0.274 ns |
| hold | +0.013 ns |
| recovery | +0.704 ns |
| removal | +0.183 ns |
| minimum pulse width | +0.124 ns |

TimeQuest reports zero illegal clocks, unconstrained clocks, unconstrained
input/output ports, and unconstrained input/output paths.

The Platform Designer reset controller releases one high-fanout Avalon fabric
reset from a core-clocked synchronizer. Its physical propagation is longer than
one 4 ns core-clock period. A paired setup/hold multicycle of 2/1 is applied
only from that synchronizer output. This is the minimum passing value and
follows the same generated-reset pattern used by the recovered Microsoft
Catapult v3 BSP, which used 4/3 for its kernel reset.

Artifact:

```text
output_files/pcie_dma.sof
size:   36,746,638 bytes
SHA256: 6194a8d7dabbec9365699500d1e6e0e33e18ebd3b744b816ba3cabdd76d561a3
```

## SRAM configuration

Date: 2026-07-23 12:38–12:39 (Asia/Shanghai)

- pre-load JTAG: `02E060DD 10AT115S(1|2)`
- cable: `JTAG-MPSSE-Blaster [00 Single RS232-HS]`
- programming target: `10AXF40AA@1`
- Quartus programming-file checksum: `0x30DD430B`
- transfer time: 54 seconds
- Programmer result: successful, 0 errors, 0 warnings
- post-load JTAG: `02E060DD 10AT115S(1|2)`
- FT232H remained enumerated as `0403:6014` at USB high speed
- no post-load USB, JTAG, PCIe AER, disconnect, or reset error was logged

As expected on this host, Linux did not hot-enumerate `1172:e004` after FPGA
reconfiguration. A host reboot was required before the BAR and DMA tests.

## First cold-enumeration result

Date: 2026-07-23 12:51 onward (Asia/Shanghai)

- the host rebooted while the SRAM image remained loaded
- JTAG still enumerated as `02E060DD 10AT115S(1|2)`
- the FT232H programmer still enumerated at USB high speed
- neither `1172:e004` nor another `1172:*` endpoint appeared in the complete
  PCIe topology
- the previous `0000:6a:00.0` BDF was reassigned to an ASMedia USB controller;
  BDFs are therefore not stable identifiers across this missing endpoint
- no relevant PCIe AER or link error was logged

The reset wiring, lane pins, reference-clock pin, PERST pin, and generated
terminations for the optional HIP control/PIPE conduits match the locally
working BAR prototype. The material link-layer difference is that this image is
the first local Gen3 x8 / 256-bit build, while the working prototype resolves
to Gen2 x8 / 128-bit. Warning 18708 also exists only because Gen3 requires the
ATX PLL. The next isolation image will keep the DMA subsystem and PCI identity
but use the previously proven Gen2 x8 PHY mode.

## Warning review

- Critical Warnings 17951 and 18655 report 40 unused RX and TX transceiver
  channels. This milestone intentionally uses only the first PCIe x8 interface.
  No undocumented channels are enabled or assigned as outputs.
- Warning 15714 reports that transceiver rail voltage was not explicitly
  assigned. The Fitter selected 950 mV for both VCCR_GXB and VCCT_GXB, matching
  the behavior of the locally validated PCIe BAR prototype. An explicit board
  rail assignment is not added without an authoritative schematic value.
- Warning 18708 reports that the Gen3 ATX PLL was placed in bank 1D while the
  100 MHz PCIe reference clock is in bank 1C. Placement is legal and timing
  passes, but this design is the first local Gen3 endpoint; negotiated Gen3 x8
  link status and DMA integrity must be checked on hardware before marking it
  validated.
- Remaining synthesis and TimeQuest warnings originate in generated Intel HIP,
  transceiver, and interconnect variants for disabled or optimized-away
  features. No ignored filter belongs to the project SDC.

## Required evidence

- [x] Quartus Prime Standard 22.1 full compile with zero errors
- [x] review of every critical warning
- [x] setup, hold, recovery/removal, pulse-width, and unconstrained-path reports
- [x] generated SOF target, size, and SHA-256
- [x] JTAG ID before and after SRAM programming
- [ ] cold host enumeration as `1172:e004` (failed for first Gen3 image)
- negotiated PCIe speed and width from `lspci -vv`
- BAR0/BAR4 sizes and design ABI register readback
- host-to-device, device-to-host, and closed-loop comparison results
- transfer size, loop count, elapsed time, throughput, and error count
- temperature before and after the test

QSPI Flash is out of scope.
