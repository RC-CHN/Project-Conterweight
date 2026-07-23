# Catapult v3 DDR4 capacity and geometry audit

This note reconciles the three capacities commonly quoted for the board:

- 5 GiB physically fitted;
- 4.5 GiB electrically connected to the FPGA;
- 4 GiB of user payload exposed by the two EMIF Avalon interfaces.

The community documentation uses `GB`.  The devices are binary-density DRAMs,
so the calculations below use GiB/MiB.

## Evidence

The local board reference identifies the fitted device as SK hynix
`H5AN4G6NAFR-UHC`, describes two independent 72-bit interfaces (64 data + 8
ECC), and records that one device on each channel has only 8 of its 16 data
bits connected.  See:

- `references/catapult-v3-smartnic-re/README.md`, hardware list and DDR4 note;
- `references/catapult-v3-smartnic-re/Documents/Datasheets/DDR4 -
  H5AN4G6NAFR-UHC/HYSC-S-A0002810570-1.pdf`.

The SK hynix datasheet identifies `H5AN4G6NAFR` as a 4 Gbit, 256M x16 device.
One complete device therefore stores 512 MiB.

Both active EMIF instances in `Qsys.qsys` independently specify:

| Parameter | Value |
| --- | ---: |
| `MEM_DDR4_DQ_WIDTH` | 72 |
| `MEM_DDR4_DQ_PER_DQS` | 8 |
| `MEM_DDR4_ROW_ADDR_WIDTH` | 15 |
| `MEM_DDR4_COL_ADDR_WIDTH` | 10 |
| `MEM_DDR4_BANK_ADDR_WIDTH` | 2 |
| `MEM_DDR4_BANK_GROUP_WIDTH` | 1 |
| `CTRL_DDR4_ECC_EN` | true |
| `CTRL_DDR4_ECC_AUTO_CORRECTION_EN` | true |

The BIST master and generated EMIF user interface use 25 word-address bits and
a 512-bit (64-byte) payload beat.

## Capacity calculation

There are five x16 devices per channel.  Four contribute all 16 data bits and
the fifth contributes only 8 bits:

```text
physical per channel       = 5 x 512 MiB          = 2.5 GiB
connected per channel      = 4.5 x 512 MiB        = 2.25 GiB
payload per channel        = 64 / 72 x 2.25 GiB   = 2.0 GiB
ECC per channel            =  8 / 72 x 2.25 GiB   = 0.25 GiB
unconnected per channel    = 0.5 x 512 MiB        = 0.25 GiB
```

Across both independent channels:

| Capacity class | Total |
| --- | ---: |
| Physically fitted | 5.0 GiB |
| Electrically connected | 4.5 GiB |
| User payload | 4.0 GiB |
| ECC storage | 0.5 GiB |
| Physically present but not connected | 0.5 GiB |

The EMIF address geometry gives the same result.  A 15-row + 10-column +
2-bank + 1-bank-group x16 device contains `2^28 x 16 bits = 4 Gbit`.  At the
72-bit channel width the connected capacity is `2^28 x 72 bits = 2.25 GiB`.
After the ECC controller consumes 8 of every 72 bits, its user side exposes
`2^28 x 64 bits = 2 GiB`.

The Avalon aperture is also exactly `2^25 words x 64 bytes = 2 GiB` per
channel.  The completed sweep from word address `0x0000000` through
`0x1ffffff` therefore covered the entire user-payload aperture.  There is no
additional 0.25 GiB/channel of payload hidden beyond that address: it is the
ECC storage managed internally by EMIF.

## Conclusion

The local 4 GiB full-address BIST result and the community 5/4.5 GiB figures
describe different capacity classes and are consistent.  The board has 5 GiB
of DRAM packages, 4.5 GiB wired to the FPGA, and 4 GiB available as protected
user data.  No unexplained payload-capacity gap remains.
