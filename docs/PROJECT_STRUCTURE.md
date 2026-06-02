# DAC-only + MicroBlaze Project Structure

This project is organized as a DAC-only design. The stable high-speed DAC data
path stays in PL, while MicroBlaze MCS owns slow control and future board
management.

## Architecture

```text
Host PC / MATLAB / Python
        |
        | UDP K5WG/K5DC, DATA, COMMIT
        v
RGMII RX + UDP parser
        |
        +---------------------> waveform RAM / DDS config CDC
                               |
MicroBlaze MCS                 v
        | IO Bus        DDS / waveform source
        v                      |
mb_io_dac_regs                 v
        |              JESD204C TX link0/link1
        |                      |
        |                      v
        |                  AD9173 DAC
        |
        +-- future RF switch select
        +-- future digital attenuator control
        +-- future profile/config/calibration tables
```

## Directory Layout

```text
D:\FPGA\ku5P\ad9173-x
|-- HostApp/                 PC host app and waveform tools
|-- Prj/
|   |-- scripts/             Vivado build/program scripts
|   |-- sim/                 focused protocol/waveform simulations
|   |-- src/
|       |-- rtl/
|       |   |-- top/         KU5P board top
|       |   |-- chip/        AD9173/HMC7044/JESD init tables and engines
|       |   |-- common/      PL data path, Ethernet, MB control island
|       |-- sw/mb_control/   MicroBlaze firmware skeleton
|       |-- xdc/             board constraints
|-- docs/                    protocol, control map, structure notes
|-- archive/                 old/removed ADC and legacy files
```

## Boundary

- PL keeps AD9173 initialization, JESD TX, DDS, waveform RAM, and UDP waveform
  reception.
- MicroBlaze MCS uses the IO Bus at `0xC0000000` for slow control registers.
- UDP remains active for host-driven waveform loading and DDS configuration.
- When UDP and MB both apply DDS updates in the same JESD clock window, the MB
  register update has priority for that update pulse.

## Current Build Output

```text
D:\FPGA\ku5P\ad9173-x\build\vivado\ad9173_dac_only\ku5p_vivado\ku5p_dac_only_top.bit
```

