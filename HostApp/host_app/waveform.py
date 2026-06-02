from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

import numpy as np

from .models import ChannelSettings, WaveformSettings


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
    ) -> WaveformResult:
        if self.matlab_enabled:
            try:
                return self._generate_with_matlab(settings, channels)
            except Exception as exc:
                result = self._generate_with_numpy(settings, channels)
                result.warnings.append(f"MATLAB 生成失败，已使用 NumPy 回退: {exc}")
                return result
        return self._generate_with_numpy(settings, channels)

    def _generate_with_numpy(
        self,
        settings: WaveformSettings,
        channels: List[ChannelSettings],
    ) -> WaveformResult:
        sample_rate_hz = settings.sample_rate_hz()
        sample_count = int(settings.sample_count)
        time_s = np.arange(sample_count, dtype=np.float64) / sample_rate_hz
        volts = np.zeros((sample_count, 2), dtype=np.float64)
        warnings = self._validate(settings, channels)

        for index, channel in enumerate(channels[:2]):
            if not channel.enabled:
                continue
            amplitude_v = channel.amplitude_volts()
            frequency_hz = channel.frequency_hz()
            volts[:, index] = amplitude_v * np.sin(2.0 * np.pi * frequency_hz * time_s)

        codes = self._volts_to_codes(volts, settings.dac_full_scale_vpk)
        return WaveformResult(time_s=time_s, volts=volts, codes=codes, source="NumPy", warnings=warnings)

    def _generate_with_matlab(
        self,
        settings: WaveformSettings,
        channels: List[ChannelSettings],
    ) -> WaveformResult:
        import matlab.engine  # type: ignore

        matlab_dir = self.matlab_dir or Path(__file__).resolve().parents[1] / "matlab"
        eng = matlab.engine.start_matlab()
        eng.addpath(str(matlab_dir), nargout=0)

        ch0, ch1 = channels[0], channels[1]
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
        warnings = self._validate(settings, channels)
        return WaveformResult(time_s=time_s, volts=volts, codes=codes, source="MATLAB", warnings=warnings)

    @staticmethod
    def _volts_to_codes(volts: np.ndarray, full_scale_vpk: float) -> np.ndarray:
        scale = max(float(full_scale_vpk), 1e-12)
        codes = np.rint(np.clip(volts / scale, -1.0, 1.0) * 32767.0)
        return codes.astype("<i2", copy=False)

    @staticmethod
    def _validate(settings: WaveformSettings, channels: List[ChannelSettings]) -> List[str]:
        warnings: List[str] = []
        sample_rate_hz = settings.sample_rate_hz()
        nyquist_hz = sample_rate_hz / 2.0
        for index, channel in enumerate(channels[:2], start=1):
            if not channel.enabled:
                continue
            if channel.frequency_hz() > nyquist_hz:
                warnings.append(f"CH{index} 频率超过奈奎斯特频率，预览和输出会混叠")
            if channel.amplitude_volts() > settings.dac_full_scale_vpk:
                warnings.append(f"CH{index} 幅度超过 DAC 满幅，已在量化时限幅")
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
