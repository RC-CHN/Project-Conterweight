# PCIe DMA validation results

Status: source implementation in progress; no hardware result recorded yet.

## Required evidence

- Quartus Prime Standard 22.1 full compile with zero errors
- review of every critical warning
- setup, hold, recovery/removal, pulse-width, and unconstrained-path reports
- generated SOF target, size, and SHA-256
- JTAG ID before and after SRAM programming
- cold host enumeration as `1172:e004`
- negotiated PCIe speed and width from `lspci -vv`
- BAR0/BAR4 sizes and design ABI register readback
- host-to-device, device-to-host, and closed-loop comparison results
- transfer size, loop count, elapsed time, throughput, and error count
- temperature before and after the test

QSPI Flash is out of scope.

