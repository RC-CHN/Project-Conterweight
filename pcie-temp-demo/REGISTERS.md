# Catapult PCIe debug ABI

The endpoint uses PCI vendor/device ID `1172:e003`. BAR0 is a 64-byte
Avalon-MM control aperture. BAR2 is retained as the original shared test RAM.

## BAR0 registers

| Offset | Access | Name | Description |
|---:|:---:|---|---|
| `0x00` | RO | `ID` | `0x43505433` (`CPT3`) |
| `0x10` | RO | `HEARTBEAT` | Free-running 100 MHz counter |
| `0x20` | RO | `TEMPERATURE` | Bit 10 valid, bits 9:0 Arria 10 ADC code |
| `0x30` | RW | `CONTROL` | Bits 7:0 drive LEDs 7:0 |

Temperature conversion: `T(C) = 693 * code / 1024 - 265`.

## Host tool

```bash
make
sudo ./catapult-bar info
sudo ./catapult-bar temp
sudo ./catapult-bar write 0x30 0x55
sudo ./catapult-bar read 0x30
```

Set `CATAPULT_BDF=dddd:bb:ss.f` when more than one compatible endpoint exists.
