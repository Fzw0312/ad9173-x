# MicroBlaze Control Map

The DAC-only bitstream keeps the JESD/DAC sample path in PL and adds a
MicroBlaze MCS control island for slow control. The MCS IO bus base address is
`0xC0000000`.

The MCS is generated with debug enabled and without external BSCAN pins. That
keeps the RTL top free of extra JTAG ports while leaving a path for later
XSDB/Vitis software download/debug without rerunning place and route.

All registers are 32-bit little-endian words.

| Offset | Name | R/W | Description |
| ---: | --- | --- | --- |
| `0x000` | `IDENT` | R | `0x44414358` (`DACX`) |
| `0x004` | `VERSION` | R | `0x00010000` |
| `0x008` | `STATUS0` | R | boot/link status flags from the PL top |
| `0x00c` | `STATUS1` | R | JESD retry/QPLL/GT heartbeat flags |
| `0x010` | `CONTROL` | R/W | bit0 enables MB DDS apply; bit1 resets DDS phase on apply |
| `0x014` | `COMMAND` | W | bit0 apply DDS registers; bit1 reset phase for this apply; bit8 clear update counter |
| `0x018` | `SCALE01` | R/W | `{DAC1 scale, DAC0 scale}` unsigned Q1.15 |
| `0x01c` | `SCALE23` | R/W | `{DAC3 scale, DAC2 scale}` unsigned Q1.15 |
| `0x020` | `FTW0_LO` | R/W | DAC0 FTW bits `[31:0]` |
| `0x024` | `FTW0_HI` | R/W | DAC0 FTW bits `[47:32]` in bits `[15:0]` |
| `0x028` | `FTW1_LO` | R/W | DAC1 FTW bits `[31:0]` |
| `0x02c` | `FTW1_HI` | R/W | DAC1 FTW bits `[47:32]` in bits `[15:0]` |
| `0x030` | `FTW2_LO` | R/W | DAC2 FTW bits `[31:0]` |
| `0x034` | `FTW2_HI` | R/W | DAC2 FTW bits `[47:32]` in bits `[15:0]` |
| `0x038` | `FTW3_LO` | R/W | DAC3 FTW bits `[31:0]` |
| `0x03c` | `FTW3_HI` | R/W | DAC3 FTW bits `[47:32]` in bits `[15:0]` |
| `0x040` | `RF_SWITCH` | R/W | future RF switch select in bits `[3:0]` |
| `0x044` | `ATTEN01` | R/W | `{atten1, atten0}` future attenuator words |
| `0x048` | `ATTEN23` | R/W | `{atten3, atten2}` future attenuator words |
| `0x04c` | `RF_FLAGS` | R/W | future RF control flags |
| `0x050` | `DAC_PROFILE` | R/W | `{DAC1 profile, DAC0 profile}` in bits `[15:0]`; defaults `DAC0=1`, `DAC1=2` |
| `0x054` | `UPDATE_CNT` | R | number of accepted MB DDS apply commands |

Current source priority:

- UDP `K5WG/K5DC` control and DATA/COMMIT waveform download remain active.
- MB writes only change DDS output after software sets `CONTROL[0]` and writes
  `COMMAND[0]`.
- If UDP and MB apply in the same JESD clock window, the MB apply wins for that
  update pulse.

Future board-control intent:

- DAC0 RF path: 10 MHz to 1 GHz. Use AD9173 NCO/mixer and RF switch/attenuator
  settings from MB software.
- DAC1 LF path: DC to 10 MHz. Use direct/baseband sample output and separate
  switch/attenuator settings from MB software.
- PL should keep the JESD sample mover stable; MB software should own slow
  register sequences, calibration tables, RF switch selection, and attenuation.
