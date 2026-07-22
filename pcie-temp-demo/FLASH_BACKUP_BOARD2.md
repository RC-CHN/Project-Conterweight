# Board 2 QSPI backup

This backup was created with a read-only Quartus Programmer **Examine**
operation. No QSPI erase, blank-check, program, or verify operation was run.
The SFL bridge was loaded into volatile FPGA SRAM only.

## Board and tool identity

- Board label: board 2
- FPGA JTAG ID: `0x02E060DD`
- Quartus: `22.1std.0 Build 915`
- Cable: `JTAG-MPSSE-Blaster [00 Single RS232-HS]`
- TCK reported by the cable plugin: `15M`
- Programmer flash description: `MT25QU01G`
- Flash silicon ID reported during Examine: `0x21`
- Examine start: `2026-07-21 23:46:30 +08:00`
- Examine end: `2026-07-22 00:04:11 +08:00`

## Artifacts

- Backup: `backup-original-board2-20260721.jic`
- Backup size: `134218006` bytes
- Backup mode after validation: `0444`
- Backup SHA-256: `77537b66db42e28aff0e354b1051f1f08ff20780e214167d4aa101634ec01d14`
- SFL bridge source: `../sfl-bridge/`
- SFL SOF used during Examine SHA-256:
  `0e89bc1a3f12490674e98a59c666030b5c54c96dadda0790263edb30c736a3f8`
- SFL target: `10AXF40AA`

An identical read-only copy is stored on the second physical disk at
`/home/pan/catapult-build/flash-backups/board2/backup-original-board2-20260721.jic`.
The workspace is on `/dev/nvme1n1p1`; the second copy is on `/dev/nvme0n1p2`.

The board 2 backup is not identical to the earlier board 1 backup, whose
SHA-256 is `fa0426fd849df59aa4cc52fb379a48c0db71de9b74a852bcbeed848d92296fd2`.

## Reproduction

Load the custom bridge into volatile SRAM:

```bash
cd sfl-bridge
quartus_pgm -c 1 -m jtag \
  -o 'p;output_files/sfl_bridge.sof'
```

Read the complete flash into a JIC container:

```bash
quartus_pgm -c 1 -m jtag \
  -o 'E;../pcie-temp-demo/backup-original-board2-20260721.jic;MT25QU01G@1'
```

The successful Examine took 17 minutes 54 seconds. Afterward, five consecutive
JTAG scans returned `0x02E060DD`, and the USB kernel log contained no new
disconnect, reset, descriptor, FTDI, or JTAG error.

On 2026-07-22, `pcie_temp_demo-MT25QU01G.jic` was subsequently programmed to
this board and passed Quartus CRC verification with 0 errors and 0 warnings.
Its SHA-256 is
`7dfe7ecfdfd9749d2dfd87dc1d25d62af24cf0b5b5bf1d79dd71c2897c9b0cba`.
After a host reboot, PCIe endpoint `1172:e003` enumerated at `0000:6a:00.0`;
BAR0 reported design ID `0x43505433`, a running heartbeat, and 50.37 C.
