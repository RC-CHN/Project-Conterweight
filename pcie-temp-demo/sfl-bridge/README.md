# Catapult v3 SFL bridge

This minimal SRAM-only design exposes the Arria 10 dedicated ASMI block to the
Quartus Serial Flash Loader protocol over JTAG.

The important Arria 10 detail is that `twentynm_asmiblock` has a fixed
three-bit `SCE` port. The SFL therefore uses `NCSO_WIDTH=3` even though the
Catapult v3 has one populated configuration flash on CS0. The bridge directly
connects the SFL to the dedicated ASMI primitive and does not enable shared
access or use any user I/O pin.

Build with Quartus Prime Standard 22.1:

```bash
quartus_sh --flow compile sfl_bridge
```

The project targets the recovered generic device alias `10AXF40AA`. The only
active timing domain is the SLD-provided 30 MHz JTAG TCK constraint. JTAG data
and control pins are explicitly false-pathed in `sfl_bridge.sdc`.

The generated SOF is for volatile SRAM loading only. It is not a flash image.
