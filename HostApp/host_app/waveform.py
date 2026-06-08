from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from typing import List, Optional, Tuple

import numpy as np

from .models import DIGITAL_SYMBOL_COUNT, ChannelSettings, ModulationSettings, WaveformSettings


SINE_H2_PREDISTORTION_RATIO = 0.015
SINE_H2_PREDISTORTION_PHASE_DEG = 270.0


@dataclass
class WaveformResult:
    time_s: np.ndarray
    volts: np.ndarray
    codes: np.ndarray
    source: str
    warnings: List[str]


class WaveformGenerator:
    def __init__(self, matlab_enabled: bool = False, matlab_dir: Optional[Path] = None):
        self.matlab_enabled = matlab_enabled
        self.matlab_dir = matlab_dir

    def generate(
        self,
        settings: WaveformSettings,
        channels: List[ChannelSettings],
        modulation: Optional[ModulationSettings] = None,
    ) -> WaveformResult:
        modulation = modulation or ModulationSettings()
        if self.matlab_enabled and modulation.modulation_type == "sine":
            result = self._generate_with_numpy(settings, channels, modulation)
            result.warnings.append(
                "RAM sine uses clean NumPy sine; MATLAB sine generation skipped"
            )
            return result

        result = self._generate_with_numpy(settings, channels, modulation)
        if self.matlab_enabled and modulation.modulation_type != "sine":
            result.warnings.append("Modulated RAM waveforms are generated with NumPy")
        return result

    def _generate_with_numpy(
        self,
        settings: WaveformSettings,
        channels: List[ChannelSettings],
        modulation: ModulationSettings,
    ) -> WaveformResult:
        sample_rate_hz = settings.sample_rate_hz()
        sample_count = int(settings.sample_count)
        time_s = np.arange(sample_count, dtype=np.float64) / sample_rate_hz
        volts = np.zeros((sample_count, 2), dtype=np.float64)
        warnings = self._validate(settings, channels)

        modulation_type = modulation.modulation_type
        valid_types = {"sine", "sawtooth", "square", "harmonic", "am", "fm", "pm", "ask", "fsk", "psk"}
        if modulation_type not in valid_types:
            warnings.append(f"Unknown modulation '{modulation_type}', generated sine")
            modulation_type = "sine"

        use_loop_coherent = bool(modulation.loop_coherent) or modulation_type != "sine"
        if use_loop_coherent:
            coherent_channels, coherent_warnings = self._loop_coherent_channels(settings, channels)
            warnings += coherent_warnings
            mod_frequency_hz, mod_warning = self._coherent_frequency(
                settings,
                modulation.mod_frequency_hz(),
                "modulation frequency",
                minimum_cycles=1,
            )
            if mod_warning and modulation_type in {"am", "fm", "pm"}:
                warnings.append(mod_warning)

            if modulation_type in {"ask", "fsk", "psk"}:
                symbol_rate_hz = sample_rate_hz * DIGITAL_SYMBOL_COUNT / max(sample_count, 1)
                requested_symbol_rate_hz = modulation.symbol_rate_hz()
                if abs(symbol_rate_hz - requested_symbol_rate_hz) > max(symbol_rate_hz * 1e-9, 1e-6):
                    warnings.append(
                        f"Digital modulation uses {DIGITAL_SYMBOL_COUNT} symbols/RAM loop; "
                        f"effective symbol rate is {symbol_rate_hz:.6g} Sym/s"
                    )
            else:
                symbol_rate_hz = modulation.symbol_rate_hz()
        else:
            coherent_channels = channels
            mod_frequency_hz = modulation.mod_frequency_hz()
            if modulation_type in {"ask", "fsk", "psk"}:
                symbol_rate_hz = sample_rate_hz * DIGITAL_SYMBOL_COUNT / max(sample_count, 1)
            else:
                symbol_rate_hz = modulation.symbol_rate_hz()

        for index, channel in enumerate(coherent_channels[:2]):
            if not channel.enabled:
                continue
            volts[:, index] = self._generate_channel_volts(
                time_s=time_s,
                sample_rate_hz=sample_rate_hz,
                amplitude_v=channel.amplitude_volts(),
                carrier_hz=channel.frequency_hz(),
                modulation=modulation,
                modulation_type=modulation_type,
                mod_frequency_hz=mod_frequency_hz,
                symbol_rate_hz=symbol_rate_hz,
                warnings=warnings if index == 0 else None,
            )

        peak_v = float(np.max(np.abs(volts))) if volts.size else 0.0
        if peak_v > float(settings.dac_full_scale_vpk) + 1e-12:
            warnings.append(
                f"Generated waveform peak {peak_v:.6g} V exceeds DAC full scale "
                f"{settings.dac_full_scale_vpk:.6g} V and will be clipped"
            )

        codes = self._volts_to_codes(volts, settings.dac_full_scale_vpk)
        source = "NumPy" if modulation_type == "sine" else f"NumPy {modulation_type.upper()}"
        return WaveformResult(time_s=time_s, volts=volts, codes=codes, source=source, warnings=warnings)

    @classmethod
    def _generate_channel_volts(
        cls,
        time_s: np.ndarray,
        sample_rate_hz: float,
        amplitude_v: float,
        carrier_hz: float,
        modulation: ModulationSettings,
        modulation_type: str,
        mod_frequency_hz: float,
        symbol_rate_hz: float,
        warnings: List[str] | None,
    ) -> np.ndarray:
        carrier_phase = 2.0 * np.pi * carrier_hz * time_s

        if modulation_type == "sine":
            return amplitude_v * np.sin(carrier_phase)

        if modulation_type == "sawtooth":
            cycles = carrier_hz * time_s
            frac = cycles - np.floor(cycles)
            rise = np.clip(float(modulation.sawtooth_rise_percent) / 100.0, 0.01, 0.99)
            rising = -1.0 + (2.0 * frac / rise)
            falling = 1.0 - (2.0 * (frac - rise) / (1.0 - rise))
            return amplitude_v * np.where(frac < rise, rising, falling)

        if modulation_type == "square":
            duty = np.clip(float(modulation.square_duty_percent) / 100.0, 0.001, 0.999)
            phase_frac = (carrier_hz * time_s) - np.floor(carrier_hz * time_s)
            return amplitude_v * np.where(phase_frac < duty, 1.0, -1.0)

        if modulation_type == "harmonic":
            return cls._generate_harmonic_waveform(
                time_s=time_s,
                amplitude_v=amplitude_v,
                fundamental_hz=carrier_hz,
                harmonic_spec=modulation.harmonic_spec,
                warnings=warnings,
            )

        if modulation_type == "am":
            depth = np.clip(float(modulation.am_depth_percent) / 100.0, 0.0, 1.0)
            envelope = 1.0 + depth * np.sin(2.0 * np.pi * mod_frequency_hz * time_s)
            return amplitude_v * envelope * np.sin(carrier_phase)

        if modulation_type == "fm":
            if mod_frequency_hz <= 0.0:
                if warnings is not None:
                    warnings.append("FM modulation frequency is zero; generated carrier only")
                return amplitude_v * np.sin(carrier_phase)
            deviation_hz = max(0.0, float(modulation.fm_deviation_hz()))
            beta = deviation_hz / mod_frequency_hz
            phase = carrier_phase + beta * (1.0 - np.cos(2.0 * np.pi * mod_frequency_hz * time_s))
            return amplitude_v * np.sin(phase)

        if modulation_type == "pm":
            phase_dev = np.deg2rad(max(0.0, float(modulation.pm_deviation_deg)))
            phase = carrier_phase + phase_dev * np.sin(2.0 * np.pi * mod_frequency_hz * time_s)
            return amplitude_v * np.sin(phase)

        bits = cls._pattern_bits(modulation.data_pattern, DIGITAL_SYMBOL_COUNT)
        symbols = cls._fixed_symbol_values(bits, time_s.size)

        if modulation_type == "ask":
            low = np.clip(float(modulation.ask_low_percent) / 100.0, 0.0, 1.0)
            envelope = np.where(symbols > 0, 1.0, low)
            return amplitude_v * envelope * np.sin(carrier_phase)

        if modulation_type == "fsk":
            deviation_hz = max(0.0, float(modulation.fsk_deviation_hz()))
            levels = np.where(symbols > 0, 1.0, -1.0)
            inst_freq_hz = carrier_hz + deviation_hz * levels
            total_cycles = float(np.sum(inst_freq_hz) / sample_rate_hz)
            cycle_error = round(total_cycles) - total_cycles
            if abs(cycle_error) > 1e-9:
                correction_hz = cycle_error * sample_rate_hz / max(time_s.size, 1)
                inst_freq_hz = inst_freq_hz + correction_hz
                if warnings is not None:
                    warnings.append(
                        f"FSK carrier shifted by {correction_hz:.6g} Hz "
                        "for RAM loop phase continuity"
                    )
            phase = 2.0 * np.pi * np.cumsum(np.concatenate(([0.0], inst_freq_hz[:-1]))) / sample_rate_hz
            return amplitude_v * np.sin(phase)

        if modulation_type == "psk":
            order = 4 if int(modulation.psk_order) == 4 else 2
            if order == 2:
                phase_offset = np.where(symbols > 0, 0.0, np.pi)
            else:
                dibits = cls._fixed_dibit_symbol_values(bits, time_s.size)
                phase_lookup = np.array([0.0, 0.5 * np.pi, 1.5 * np.pi, np.pi], dtype=np.float64)
                phase_offset = phase_lookup[dibits]
            return amplitude_v * np.sin(carrier_phase + phase_offset)

        return amplitude_v * np.sin(carrier_phase)

    @staticmethod
    def _generate_predistorted_sine(carrier_phase: np.ndarray, amplitude_v: float) -> np.ndarray:
        phase_rad = np.deg2rad(SINE_H2_PREDISTORTION_PHASE_DEG)
        wave = np.sin(carrier_phase)
        wave += SINE_H2_PREDISTORTION_RATIO * np.sin((2.0 * carrier_phase) + phase_rad)
        wave = wave - float(np.mean(wave))
        peak = float(np.max(np.abs(wave))) if wave.size else 0.0
        if peak <= 1e-12:
            return np.zeros_like(carrier_phase, dtype=np.float64)
        return float(amplitude_v) * wave / peak

    @classmethod
    def _generate_harmonic_waveform(
        cls,
        time_s: np.ndarray,
        amplitude_v: float,
        fundamental_hz: float,
        harmonic_spec: str,
        warnings: List[str] | None,
    ) -> np.ndarray:
        harmonics = cls._parse_harmonic_spec(harmonic_spec, warnings)
        wave = np.zeros_like(time_s, dtype=np.float64)
        for order, gain, phase_deg in harmonics:
            phase = np.deg2rad(phase_deg)
            wave += gain * np.sin((2.0 * np.pi * fundamental_hz * order * time_s) + phase)
        peak = float(np.max(np.abs(wave))) if wave.size else 0.0
        if peak <= 1e-12:
            return np.zeros_like(time_s, dtype=np.float64)
        return amplitude_v * wave / peak

    @staticmethod
    def _parse_number(text: str) -> float:
        text = str(text).strip()
        if "/" in text:
            return float(Fraction(text))
        return float(text)

    @classmethod
    def _parse_harmonic_spec(cls, harmonic_spec: str, warnings: List[str] | None) -> List[tuple[int, float, float]]:
        harmonics: List[tuple[int, float, float]] = []
        for item in str(harmonic_spec).replace(";", ",").split(","):
            item = item.strip()
            if not item:
                continue
            parts = [part.strip() for part in item.split(":")]
            try:
                order = int(cls._parse_number(parts[0]))
                gain = cls._parse_number(parts[1]) if len(parts) > 1 and parts[1] else 1.0
                phase_deg = cls._parse_number(parts[2]) if len(parts) > 2 and parts[2] else 0.0
            except (ValueError, ZeroDivisionError):
                if warnings is not None:
                    warnings.append(f"Ignored invalid harmonic entry '{item}'")
                continue
            if order <= 0:
                if warnings is not None:
                    warnings.append(f"Ignored non-positive harmonic order '{item}'")
                continue
            harmonics.append((order, gain, phase_deg))
        if not harmonics:
            harmonics = [(1, 1.0, 0.0)]
            if warnings is not None:
                warnings.append("No valid harmonics specified; generated fundamental sine")
        return harmonics

    def _generate_with_matlab(
        self,
        settings: WaveformSettings,
        channels: List[ChannelSettings],
        modulation: ModulationSettings,
    ) -> WaveformResult:
        import matlab.engine  # type: ignore

        if modulation.loop_coherent:
            coherent_channels, coherent_warnings = self._loop_coherent_channels(settings, channels)
        else:
            coherent_channels, coherent_warnings = channels, []
        matlab_dir = self.matlab_dir or Path(__file__).resolve().parents[1] / "matlab"
        eng = matlab.engine.start_matlab()
        eng.addpath(str(matlab_dir), nargout=0)

        ch0, ch1 = coherent_channels[0], coherent_channels[1]
        t, y0, y1 = eng.generate_two_channel_waveform(
            float(settings.sample_rate_hz()),
            int(settings.sample_count),
            float(ch0.amplitude_volts()),
            float(ch0.frequency_hz()),
            bool(ch0.enabled),
            float(ch1.amplitude_volts()),
            float(ch1.frequency_hz()),
            bool(ch1.enabled),
            nargout=3,
        )
        eng.quit()

        time_s = np.asarray(t, dtype=np.float64).reshape(-1)
        volts = np.column_stack(
            (
                np.asarray(y0, dtype=np.float64).reshape(-1),
                np.asarray(y1, dtype=np.float64).reshape(-1),
            )
        )
        codes = self._volts_to_codes(volts, settings.dac_full_scale_vpk)
        warnings = self._validate(settings, channels) + coherent_warnings
        return WaveformResult(time_s=time_s, volts=volts, codes=codes, source="MATLAB", warnings=warnings)

    @staticmethod
    def _volts_to_codes(volts: np.ndarray, full_scale_vpk: float) -> np.ndarray:
        scale = max(float(full_scale_vpk), 1e-12)
        codes = np.rint(np.clip(volts / scale, -1.0, 1.0) * 32767.0)
        return codes.astype("<i2", copy=False)

    @staticmethod
    def _coherent_frequency(
        settings: WaveformSettings,
        frequency_hz: float,
        label: str,
        minimum_cycles: int = 0,
        maximum_cycles: int | None = None,
    ) -> Tuple[float, str | None]:
        sample_rate_hz = settings.sample_rate_hz()
        sample_count = max(int(settings.sample_count), 1)
        bin_hz = sample_rate_hz / sample_count
        max_cycles = sample_count // 2 if maximum_cycles is None else int(maximum_cycles)
        requested_hz = max(0.0, float(frequency_hz))
        cycles = int(round(requested_hz / bin_hz))
        cycles = max(int(minimum_cycles), min(cycles, max_cycles))
        adjusted_hz = cycles * bin_hz
        warning = None
        if abs(adjusted_hz - requested_hz) > max(bin_hz * 1e-9, 1e-6):
            warning = (
                f"RAM loop {label} adjusted from {requested_hz:.6g} Hz "
                f"to {adjusted_hz:.6g} Hz ({cycles} cycles/{sample_count} samples)"
            )
        return adjusted_hz, warning

    @staticmethod
    def _pattern_bits(pattern: str, fixed_count: int | None = None) -> np.ndarray:
        bits = [1 if char == "1" else 0 for char in str(pattern) if char in {"0", "1"}]
        if not bits:
            bits = [1, 0, 1, 1, 0, 0, 1, 0]
        if fixed_count is not None:
            fixed_count = max(1, int(fixed_count))
            bits = (bits + [0] * fixed_count)[:fixed_count]
        return np.asarray(bits, dtype=np.int8)

    @staticmethod
    def _fixed_symbol_indices(symbol_count: int, sample_count: int) -> np.ndarray:
        symbol_count = max(1, int(symbol_count))
        sample_count = max(1, int(sample_count))
        return np.minimum((np.arange(sample_count, dtype=np.int64) * symbol_count) // sample_count, symbol_count - 1)

    @classmethod
    def _fixed_symbol_values(cls, bits: np.ndarray, sample_count: int) -> np.ndarray:
        symbol_indices = cls._fixed_symbol_indices(bits.size, sample_count)
        return bits[symbol_indices]

    @classmethod
    def _fixed_dibit_symbol_values(cls, bits: np.ndarray, sample_count: int) -> np.ndarray:
        if bits.size % 2:
            bits = np.concatenate((bits, np.asarray([0], dtype=np.int8)))
        pairs = bits.reshape(max(1, bits.size // 2), 2)
        values = ((pairs[:, 0] << 1) | pairs[:, 1]).astype(np.int8)
        symbol_indices = cls._fixed_symbol_indices(values.size, sample_count)
        return values[symbol_indices]

    @classmethod
    def _symbol_indices(cls, symbol_rate_hz: float, sample_rate_hz: float, sample_count: int) -> np.ndarray:
        symbol_count = max(1, int(round(float(symbol_rate_hz) * sample_count / sample_rate_hz)))
        return np.minimum((np.arange(sample_count, dtype=np.int64) * symbol_count) // sample_count, symbol_count - 1)

    @classmethod
    def _symbol_values(
        cls,
        bits: np.ndarray,
        symbol_rate_hz: float,
        sample_rate_hz: float,
        sample_count: int,
    ) -> np.ndarray:
        symbol_indices = cls._symbol_indices(symbol_rate_hz, sample_rate_hz, sample_count)
        return bits[symbol_indices % bits.size]

    @classmethod
    def _dibit_symbol_values(
        cls,
        bits: np.ndarray,
        symbol_rate_hz: float,
        sample_rate_hz: float,
        sample_count: int,
    ) -> np.ndarray:
        if bits.size % 2:
            bits = np.concatenate((bits, np.asarray([0], dtype=np.int8)))
        pairs = bits.reshape(max(1, bits.size // 2), 2)
        values = ((pairs[:, 0] << 1) | pairs[:, 1]).astype(np.int8)
        symbol_indices = cls._symbol_indices(symbol_rate_hz, sample_rate_hz, sample_count)
        return values[symbol_indices % values.size]

    @staticmethod
    def _loop_coherent_channels(
        settings: WaveformSettings,
        channels: List[ChannelSettings],
    ) -> Tuple[List[ChannelSettings], List[str]]:
        sample_rate_hz = settings.sample_rate_hz()
        sample_count = max(int(settings.sample_count), 1)
        bin_hz = sample_rate_hz / sample_count
        max_cycles = sample_count // 2
        coherent_channels: List[ChannelSettings] = []
        warnings: List[str] = []

        for index, channel in enumerate(channels):
            adjusted = ChannelSettings(
                enabled=channel.enabled,
                amplitude=channel.amplitude,
                amplitude_unit=channel.amplitude_unit,
                frequency=channel.frequency,
                frequency_unit=channel.frequency_unit,
            )
            if channel.enabled:
                requested_hz = channel.frequency_hz()
                cycles = int(round(requested_hz / bin_hz))
                cycles = max(0, min(cycles, max_cycles))
                adjusted_hz = cycles * bin_hz
                if abs(adjusted_hz - requested_hz) > max(bin_hz * 1e-9, 1e-6):
                    warnings.append(
                        f"CH{index + 1} RAM loop frequency adjusted "
                        f"from {requested_hz / 1e6:.6g} MHz to {adjusted_hz / 1e6:.6g} MHz "
                        f"({cycles} cycles/{sample_count} samples)"
                    )
                adjusted.frequency = adjusted_hz
                adjusted.frequency_unit = "Hz"
            coherent_channels.append(adjusted)

        return coherent_channels, warnings

    @staticmethod
    def _validate(settings: WaveformSettings, channels: List[ChannelSettings]) -> List[str]:
        warnings: List[str] = []
        sample_rate_hz = settings.sample_rate_hz()
        nyquist_hz = sample_rate_hz / 2.0
        for index, channel in enumerate(channels[:2], start=1):
            if not channel.enabled:
                continue
            if channel.frequency_hz() > nyquist_hz:
                warnings.append(f"CH{index} frequency exceeds Nyquist; preview and output will alias")
            if channel.amplitude_volts() > settings.dac_full_scale_vpk:
                warnings.append(f"CH{index} amplitude exceeds DAC full scale and will be clipped")
        return warnings


def estimate_time_axis_unit(time_s: np.ndarray) -> Tuple[np.ndarray, str]:
    if time_s.size == 0:
        return time_s, "s"
    span = float(time_s[-1] - time_s[0])
    if span < 1e-6:
        return time_s * 1e9, "ns"
    if span < 1e-3:
        return time_s * 1e6, "us"
    if span < 1.0:
        return time_s * 1e3, "ms"
    return time_s, "s"
