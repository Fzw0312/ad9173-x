# RF Amplitude Calibration Plan

This document summarizes the RF amplitude calibration strategy for the
AD9173 KU5P HostApp flow. It is written as an implementation reference for
future Codex work.

## Scope

- Frequency range: 10 MHz to 200 MHz.
- RF output path: DAC0 -> HMC788 gain stage -> PE43711 digital attenuator -> RF output.
- Low-frequency output path: DAC1, selected separately by the output switch.
- Output switch pin: B9.
  - `0`: RF path selected.
  - `1`: low-frequency path selected.
- Target RF amplitude range: 0.01 Vpk to 3.0 Vpk.
- Main amplitude control device: PE43711.
- Fine and range-extension control: DAC digital scale.

## Hardware Model

The RF amplitude model is:

```text
DAC0 digital scale
  -> AD9173 DAC0 analog output
  -> HMC788 fixed gain, nominal +14 dB
  -> PE43711 attenuation, 0.25 dB/step, 0..31.75 dB
  -> RF output
```

PE43711 code mapping:

```text
atten_db = code * 0.25
code = round(atten_db / 0.25)
valid code range = 0..127
```

The current FPGA protocol sends this code in the K5DC binary payload:

```text
0x30: rf_atten_code
0x31: output_path_sel
```

## Why DAC Scale Is Still Needed

The requested amplitude range is about 49.54 dB:

```text
20 * log10(3.0 / 0.01) = 49.54 dB
```

PE43711 provides only 31.75 dB. Therefore:

- PE43711 should do the main attenuation.
- DAC scale must cover the remaining range at very low target amplitudes.
- DAC scale should also correct PE43711 step quantization and frequency
  response variation.

Avoid driving DAC scale unnecessarily low because it degrades SNR.

## Calibration Data

Use a frequency calibration table rather than one global gain value.

Recommended initial measurement frequencies:

```text
10, 15, 20, 30, 40, 50, 70, 100, 130, 160, 180, 200 MHz
```

If the response is smooth, this can later be compressed into segments:

```text
10-30 MHz
30-60 MHz
60-100 MHz
100-150 MHz
150-200 MHz
```

Preferred storage format:

```json
{
  "version": 1,
  "path": "rf_dac0_hmc788_pe43711",
  "amplitude_unit": "Vpk",
  "preferred_dac_scale_ratio": 0.8,
  "points": [
    {"freq_hz": 10000000, "raw_vpk": 4.90},
    {"freq_hz": 20000000, "raw_vpk": 4.86},
    {"freq_hz": 50000000, "raw_vpk": 4.70},
    {"freq_hz": 100000000, "raw_vpk": 4.35},
    {"freq_hz": 150000000, "raw_vpk": 4.05},
    {"freq_hz": 200000000, "raw_vpk": 3.82}
  ]
}
```

`raw_vpk` means the measured RF output amplitude at:

```text
output_path_sel = 0
PE43711 code = 0
DAC0 scale = preferred_dac_scale_ratio
```

Store the table in:

```text
HostApp/calibration/rf_cal_10m_200m.json
```

## Measurement Procedure

1. Select RF path.

```text
B9/output_path_sel = 0
```

2. Set PE43711 to minimum attenuation.

```text
pe43711_code = 0
atten_db = 0
```

3. Set DAC0 to a safe high scale.

Recommended start:

```text
dac_scale_ratio = 0.8
```

Do not use full scale until compression has been checked.

4. Generate a single tone at each calibration frequency.

Use the same output mode intended for RF operation. If RF operation will use
JESD single-tone, calibrate with JESD single-tone.

5. Measure output amplitude in Vpk.

Use a consistent setup:

- Same cable.
- Same load.
- Same oscilloscope/power meter settings.
- Same input impedance.
- Same probe/attenuator chain.

6. Check compression.

At several frequencies, sweep DAC scale:

```text
0.4, 0.6, 0.8, 1.0
```

If output is not linear near 1.0, reduce `preferred_dac_scale_ratio`.

7. Save the measured table.

Use dB-domain interpolation at runtime:

```text
raw_dbv = interp(freq_hz, 20 * log10(raw_vpk))
raw_vpk = 10 ** (raw_dbv / 20)
```

## Runtime Algorithm

Inputs:

```text
freq_hz
target_vpk
calibration table
```

Constants:

```text
PE_MAX_ATTEN_DB = 31.75
PE_STEP_DB = 0.25
TARGET_MIN_VPK = 0.01
TARGET_MAX_VPK = 3.0
```

Steps:

1. Clamp target amplitude.

```text
target_vpk = clamp(target_vpk, 0.01, 3.0)
```

2. Interpolate calibrated raw amplitude.

```text
raw_vpk = interpolate_raw_vpk(freq_hz)
```

3. Calculate required attenuation.

```text
need_atten_db = 20 * log10(raw_vpk / target_vpk)
```

4. Assign most attenuation to PE43711.

```text
pe_atten_db = clamp(round(need_atten_db / 0.25) * 0.25, 0, 31.75)
pe_code = round(pe_atten_db / 0.25)
```

5. Use DAC scale for the remaining correction.

```text
dac_scale_ratio = target_vpk * 10 ** (pe_atten_db / 20) / raw_vpk
```

6. Clamp DAC scale.

```text
dac_scale_ratio = clamp(dac_scale_ratio, DAC_MIN_SCALE, DAC_MAX_SCALE)
```

Recommended:

```text
DAC_MAX_SCALE = preferred_dac_scale_ratio
DAC_MIN_SCALE = value corresponding to acceptable SNR
```

If `dac_scale_ratio` is below the minimum, allow it only with a GUI warning
that low-amplitude SNR may be degraded.

7. Convert to FPGA scale field.

For JESD single-tone mode:

```text
scale_code = round(dac_scale_ratio * 0x7FFF)
```

For AD9173 NCO-only mode:

```text
scale_code = round(dac_scale_ratio * AD9173_NCO_MAX_AMP)
```

8. Send K5DC.

```text
cfg_scale0 = scale_code
rf_atten_code = pe_code
output_path_sel = 0
```

## HostApp Implementation Notes

Add RF calibration support around the existing `calculate_rf_output_control()`
logic.

Recommended behavior:

- If calibration file exists and RF path is selected:
  - Use frequency table interpolation.
  - Calculate PE43711 code and DAC scale from calibrated `raw_vpk`.
- If no calibration file exists:
  - Fall back to the current nominal HMC788 +14 dB model.
- Show these values in the GUI:
  - Target amplitude.
  - Frequency.
  - Interpolated raw amplitude.
  - PE43711 attenuation dB/code.
  - DAC scale ratio/code.
  - Expected output amplitude.
  - Warning if DAC scale is very low or target amplitude exceeds safe range.

Recommended GUI fields:

```text
RF calibration enabled
Calibration file path
Interpolated raw Vpk
PE43711 code/dB
DAC scale ratio/code
Expected RF output Vpk
```

## Error Targets

Initial target:

```text
<= +/-0.5 dB over 10-200 MHz
```

Refined target after iterative calibration:

```text
<= +/-0.2 dB over 10-200 MHz
```

Validation amplitudes per segment:

```text
0.03, 0.1, 0.5, 1.0, 2.0, 3.0 Vpk
```

Validation frequencies:

```text
10, 20, 50, 100, 150, 200 MHz
```

Add intermediate points if error is not monotonic.

## Important Risks

- 0.01 Vpk cannot be achieved by PE43711 alone because PE43711 has only
  31.75 dB attenuation.
- HMC788 and downstream RF components may compress near high output levels.
- AD9173 frequency response and board routing may roll off with frequency.
- Cable, load, and measurement instrument setup must be kept identical.
- dBm, Vpp, Vrms, and Vpk must not be mixed. Store calibration in Vpk.

## Suggested Next Implementation Task

Implement:

```text
HostApp/calibration/rf_cal_10m_200m.json
HostApp/host_app/rf_calibration.py
```

Then modify:

```text
HostApp/host_app/udp_client.py
```

so RF mode uses calibrated frequency-dependent `raw_vpk` instead of the fixed
nominal +14 dB model when a calibration table is available.
