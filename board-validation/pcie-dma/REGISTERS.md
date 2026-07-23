# PCIe DMA ABI

PCI ID: `1172:e004`, revision `0x01`.

## BAR0: Intel chained-DMA controller

BAR0 is reserved for the descriptor controller instantiated inside the Arria 10
PCIe HIP. The milestone-1 driver uses the register layout supplied by the
Quartus 22.1 Arria 10 chaining-DMA testbench:

| Offset | Direction | Meaning |
| ---: | --- | --- |
| `0x00` | FPGA to host | write-DMA descriptor header DW0 |
| `0x04` | FPGA to host | descriptor-table address high |
| `0x08` | FPGA to host | descriptor-table address low |
| `0x0c` | FPGA to host | last ready descriptor; write starts DMA |
| `0x10` | host to FPGA | read-DMA descriptor header DW0 |
| `0x14` | host to FPGA | descriptor-table address high |
| `0x18` | host to FPGA | descriptor-table address low |
| `0x1c` | host to FPGA | last ready descriptor; write starts DMA |

The names follow Intel terminology: read DMA reads host memory and writes the
FPGA device address; write DMA reads the FPGA device address and writes host
memory.

Each coherent host descriptor table starts with four 32-bit header words,
followed by 16-byte descriptors. A descriptor contains length/control, FPGA
address, host address high, and host address low. Milestone 1 requests EPLAST
writeback and polls header DW3.

## BAR4: application window

The 1 MiB DMA buffer occupies `0x000000` through `0x0fffff`. Diagnostic
registers start at `0x100000` in one custom Avalon-MM slave clocked directly by
the 250 MHz HIP application clock.

| Offset | Access | Meaning |
| ---: | :---: | --- |
| `0x100000` | RO | design ID `0x43444d41` (`CDMA`) |
| `0x100004` | RO | ABI version `0x00010000` |
| `0x100008` | RO | PCIe core-clock heartbeat |
| `0x10000c` | RO | capabilities |
| `0x100010` | RO | observed PERST deassert count |
| `0x100014` | RO | runtime PERST assertion/error count |
| `0x100018` | RW | scratch register |

Capabilities:

- bit 0: host-to-FPGA read DMA
- bit 1: FPGA-to-host write DMA
- bit 2: EPLAST completion polling
- bit 3: BAR4 aperture also exposes the on-chip buffer
- bits 23:16: log2 of on-chip buffer bytes (`20`)
