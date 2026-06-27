# RF Amplitude Calibration Plan

This document describes the current RF amplitude calibration flow for the
AD9173 KU5P HostApp after the hardware change to a shared post-switch relay
attenuator.

## Scope

- First calibration range: 10 MHz to 200 MHz RF path.
- First target amplitude range: 1 Vpp to 3 Vpp.
- Oscilloscope measurement channel: CH2.
- RF output path: DAC0 RF chain selected by the RF/LF output switch.
- LF and RF now use the same relay attenuation after path switching.
- The old RF-only PE43711 assumption is obsolete for new tables.

## Hardware Model

The active RF model for this calibration is:

```text
DAC0 digital scale
  -> AD9173 RF tone path
  -> RF gain/output conditioning
  -> RF/LF output switch
  -> shared 4-bit relay attenuator
  -> output connector
```

The relay attenuation mask is sent in the runtime payload:

```text
0x30: relay_atten_mask
0x31: output_path_sel
```

Current mapping:

```text
bit0/D9  =  5 dB
bit1/C11 = 10 dB
bit2/E11 = 15 dB
bit3/D11 = 20 dB
```

`relay_atten_mask` supports 0 dB to 50 dB in 5 dB-combinable steps. RF path
selection uses `output_path_sel = 1`; LF path selection uses
`output_path_sel = 0`.

## Calibration Table

Use a fresh RF table under:

```text
HostApp/calibration/ch1_rf_unified_attenuator_<timestamp>/rf_cal_10m_200m_ch1_runtime.json
```

The `ch1_rf` part of the directory/file name is retained for HostApp loader
compatibility. The table metadata records the actual measurement channel:

```json
{
  "source": "rf_unified_attenuator_scope_sweep",
  "path": "rf_dac0_after_switch_unified_relay_attenuator",
  "measurement_channel": "CHAN2",
  "output_path": "rf",
  "output_path_sel": 1
}
```

The runtime table stores:

- `points`: raw RF frequency response at a preferred DAC/NCO amplitude and
  bootstrap relay mask.
- `amplitude_correction_model`: closed-loop correction factors over frequency
  and target Vpp.
- `relay_attenuator_*`: the shared relay attenuator description.

## Recommended Sweep

Default raw frequency points:

```text
10, 15, 20, 30, 40, 50, 70, 100, 130, 160, 180, 200 MHz
```

Default closed-loop target amplitudes:

```text
1.0, 1.5, 2.0, 2.5, 3.0 Vpp
```

The 1 Vpp to 3 Vpp range is intentionally narrower than the old table. It
matches the immediate request and avoids spending time on low-level SNR
behavior before the new shared attenuator path is characterized.

## Tool

Use:

```powershell
python .\HostApp\tools\calibrate_rf_unified_attenuator.py --scope-ip <scope-ip>
```

Useful dry run:

```powershell
python .\HostApp\tools\calibrate_rf_unified_attenuator.py --dry-run
```

Important defaults:

```text
--channel CHAN2
--freq-mhz 10 ... 200
--target-vpp 1.0 ... 3.0
--bootstrap-amp-ratio 1.0
--bootstrap-relay-mask 0
```

To capture only the raw response before closed-loop correction:

```powershell
python .\HostApp\tools\calibrate_rf_unified_attenuator.py --raw-only
```

## Measurement Procedure

1. Connect the RF output to oscilloscope CH2 with the final intended cable,
   load, and any external protection/attenuation in place.
2. Select RF path with `output_path_sel = 1`.
3. Start with max AD9173/NCO amplitude and relay mask `0x0` unless the raw
   output would over-range the oscilloscope or compress the analog chain.
4. Run the raw sweep. The tool captures waveform CSV files and computes raw
   Vpk/Vpp per frequency.
5. Run closed-loop correction over 1 Vpp to 3 Vpp. The tool measures CH2
   `PKPK` repeatedly and writes correction factors into the runtime JSON.
6. The newest matching runtime JSON is loaded by `RfCalibrationTable.load_latest`.

## Runtime Algorithm

For each RF target:

1. Interpolate raw RF Vpk over frequency in dB domain.
2. Interpolate the amplitude correction factor over frequency and target Vpp.
3. Choose the largest shared relay attenuation that does not exceed the
   required attenuation.
4. Compute the AD9173 NCO amplitude code from raw Vpk, target Vpk, relay dB,
   and correction factor. This keeps the source amplitude as high as possible
   and uses source-amplitude reduction only for the residual below the selected
   relay step.
5. Clamp to `nco_max_amp_code`.
6. Send RF path select and relay mask in the runtime payload.

## Validation

After the calibration table is created, validate at points not identical to
the calibration grid:

```text
12, 25, 60, 90, 120, 175, 200 MHz
1.0, 1.8, 2.4, 3.0 Vpp
```

Initial acceptance target:

```text
<= +/-0.5 dB across 10-200 MHz and 1-3 Vpp
```

Refined target after another closed-loop pass:

```text
<= +/-0.2 dB where the analog chain is not compressed
```

## Notes

- RF and LF should have separate amplitude correction tables because the RF
  and LF paths before the shared attenuator have different gain and frequency
  response.
- Keep the old PE43711 calibration files for historical comparison, but do not
  use them as the source of truth for the new switched shared-attenuator board.
- Keep amplitude units explicit: the calibration request and oscilloscope
  measurement use Vpp, while HostApp runtime calculations internally use Vpk.
