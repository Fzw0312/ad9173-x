from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class RfCalibrationResult:
    enabled: bool
    file: str
    freq_hz: float
    target_vpk: float
    raw_vpk: float
    raw_vpp: float
    pe43711_code: int
    pe43711_atten_db: float
    amp_code: int
    amp_ratio: float
    expected_vpk: float
    expected_vpp: float
    nco_hz: float
    correction_factor: float
    pe43711_trim_db: float = 0.0

    def to_payload(self) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "file": self.file,
            "freq_hz": self.freq_hz,
            "target_vpk": self.target_vpk,
            "raw_vpk": self.raw_vpk,
            "raw_vpp": self.raw_vpp,
            "pe43711_code": self.pe43711_code,
            "pe43711_atten_db": self.pe43711_atten_db,
            "amp_code": self.amp_code,
            "amp_ratio": self.amp_ratio,
            "expected_vpk": self.expected_vpk,
            "expected_vpp": self.expected_vpp,
            "nco_hz": self.nco_hz,
            "correction_factor": self.correction_factor,
            "pe43711_trim_db": self.pe43711_trim_db,
        }


def find_latest_ch1_rf_calibration(repo_root: Path) -> Path | None:
    calibration_root = repo_root / "HostApp" / "calibration"
    if not calibration_root.exists():
        return None
    matches = list(calibration_root.glob("ch1_rf_*/rf_cal_10m_200m_ch1_runtime.json"))
    if not matches:
        return None
    return max(matches, key=lambda path: path.stat().st_mtime)


class RfCalibrationTable:
    def __init__(self, path: Path):
        self.path = path
        self.data = json.loads(path.read_text(encoding="utf-8"))
        self.points = sorted(self.data.get("points", []), key=lambda item: float(item["freq_hz"]))
        if len(self.points) < 2:
            raise ValueError(f"RF calibration file has too few points: {path}")
        self.preferred_amp_code = int(self.data.get("preferred_amp_code", 0x40CC))
        self.max_amp_code = int(self.data.get("nco_max_amp_code", 0x50FF))
        self.pe_step_db = float(self.data.get("pe43711_step_db", 0.25))
        self.pe_max_code = int(self.data.get("pe43711_max_code", 127))
        self.nco_hz = float(self.data.get("nco_hz", 1_474_561_031.9672773))
        self.amplitude_correction_model = self.data.get("amplitude_correction_model")
        self.pe43711_frequency_trim_model = self.data.get("pe43711_frequency_trim_model")
        self.amplitude_corrections = sorted(
            self.data.get("amplitude_corrections", []),
            key=lambda item: float(item.get("freq_hz", 0.0)),
        )

    @classmethod
    def load_latest(cls, repo_root: Path) -> "RfCalibrationTable | None":
        path = find_latest_ch1_rf_calibration(repo_root)
        if path is None:
            return None
        return cls(path)

    def interpolate_raw_vpk(self, freq_hz: float) -> float:
        freq_hz = float(freq_hz)
        freqs = [float(point["freq_hz"]) for point in self.points]
        db_values = [20.0 * math.log10(max(float(point["raw_vpk"]), 1e-12)) for point in self.points]
        if freq_hz <= freqs[0]:
            return 10.0 ** (db_values[0] / 20.0)
        if freq_hz >= freqs[-1]:
            return 10.0 ** (db_values[-1] / 20.0)
        for index in range(len(freqs) - 1):
            left_f = freqs[index]
            right_f = freqs[index + 1]
            if left_f <= freq_hz <= right_f:
                ratio = (freq_hz - left_f) / (right_f - left_f)
                dbv = db_values[index] + ratio * (db_values[index + 1] - db_values[index])
                return 10.0 ** (dbv / 20.0)
        return 10.0 ** (db_values[-1] / 20.0)

    def _interpolate_correction_over_frequency(self, points: list[dict[str, Any]], freq_hz: float) -> float:
        points = sorted(points, key=lambda item: float(item.get("freq_hz", 0.0)))
        freqs = [float(point.get("freq_hz", 0.0)) for point in points]
        factors = [float(point.get("correction_factor", 1.0)) for point in points]
        if freq_hz <= freqs[0]:
            return factors[0]
        if freq_hz >= freqs[-1]:
            return factors[-1]
        for index in range(len(freqs) - 1):
            left_f = freqs[index]
            right_f = freqs[index + 1]
            if left_f <= freq_hz <= right_f:
                ratio = (freq_hz - left_f) / (right_f - left_f)
                return factors[index] + ratio * (factors[index + 1] - factors[index])
        return factors[-1]

    def interpolate_correction_factor(self, freq_hz: float, target_vpp: float | None = None) -> float:
        model_factor = self._interpolate_model_correction_factor(freq_hz, target_vpp)
        if model_factor is not None:
            return model_factor
        if not self.amplitude_corrections:
            return 1.0
        freq_hz = float(freq_hz)
        groups: dict[float, list[dict[str, Any]]] = {}
        for point in self.amplitude_corrections:
            if "target_vpp" not in point:
                continue
            groups.setdefault(float(point["target_vpp"]), []).append(point)
        if target_vpp is None or len(groups) < 2:
            return self._interpolate_correction_over_frequency(self.amplitude_corrections, freq_hz)

        target_vpp = max(float(target_vpp), 1e-12)
        targets = sorted(groups)
        per_target = [self._interpolate_correction_over_frequency(groups[target], freq_hz) for target in targets]
        if target_vpp <= targets[0]:
            return per_target[0]
        if target_vpp >= targets[-1]:
            return per_target[-1]

        log_target = math.log10(target_vpp)
        log_targets = [math.log10(max(target, 1e-12)) for target in targets]
        for index in range(len(targets) - 1):
            if targets[index] <= target_vpp <= targets[index + 1]:
                ratio = (log_target - log_targets[index]) / (log_targets[index + 1] - log_targets[index])
                return per_target[index] + ratio * (per_target[index + 1] - per_target[index])
        return per_target[-1]

    def _interpolate_model_correction_factor(
        self,
        freq_hz: float,
        _target_vpp: float | None = None,
    ) -> float | None:
        model = self.amplitude_correction_model
        if not isinstance(model, dict):
            return None
        if model.get("type") == "correction_factor_linear_v1":
            return self._interpolate_correction_factor_model(model, freq_hz, _target_vpp)
        if model.get("type") == "linear_amplitude_v1":
            return self._interpolate_linear_amplitude_model(model, freq_hz, _target_vpp)
        if model.get("type") != "frequency_gain_v1":
            return None
        points = [
            point
            for point in model.get("points", [])
            if "freq_hz" in point and "correction_factor" in point
        ]
        if not points:
            return None
        return self._interpolate_correction_over_frequency(points, freq_hz)

    def _interpolate_linear_amplitude_model(
        self,
        model: dict[str, Any],
        freq_hz: float,
        target_vpp: float | None,
    ) -> float | None:
        points = [
            point
            for point in model.get("points", [])
            if "freq_hz" in point and "slope" in point and "offset_vpp" in point
        ]
        if not points:
            return None
        freq_hz = float(freq_hz)
        target_vpp = max(float(target_vpp or model.get("reference_target_vpp", 1.0)), 1e-12)
        points = sorted(points, key=lambda item: float(item.get("freq_hz", 0.0)))
        freqs = [float(point["freq_hz"]) for point in points]
        slopes = [float(point["slope"]) for point in points]
        offsets = [float(point["offset_vpp"]) for point in points]

        if freq_hz <= freqs[0]:
            slope = slopes[0]
            offset = offsets[0]
        elif freq_hz >= freqs[-1]:
            slope = slopes[-1]
            offset = offsets[-1]
        else:
            slope = slopes[-1]
            offset = offsets[-1]
            for index in range(len(freqs) - 1):
                left_f = freqs[index]
                right_f = freqs[index + 1]
                if left_f <= freq_hz <= right_f:
                    ratio = (freq_hz - left_f) / (right_f - left_f)
                    slope = slopes[index] + ratio * (slopes[index + 1] - slopes[index])
                    offset = offsets[index] + ratio * (offsets[index + 1] - offsets[index])
                    break

        predicted_vpp = slope * target_vpp + offset
        if predicted_vpp <= 1e-12:
            return None
        factor = target_vpp / predicted_vpp
        min_factor = float(model.get("min_correction_factor", 0.25))
        max_factor = float(model.get("max_correction_factor", 4.0))
        return max(min_factor, min(max_factor, factor))

    def _interpolate_correction_factor_model(
        self,
        model: dict[str, Any],
        freq_hz: float,
        target_vpp: float | None,
    ) -> float | None:
        points = [
            point
            for point in model.get("points", [])
            if "freq_hz" in point and "target_vpp" in point and "correction_factor" in point
        ]
        if not points:
            return None

        target_vpp = max(float(target_vpp or model.get("reference_target_vpp", 1.0)), 1e-12)
        groups: dict[float, list[dict[str, Any]]] = {}
        for point in points:
            groups.setdefault(float(point["target_vpp"]), []).append(point)

        targets = sorted(groups)
        if not targets:
            return None
        per_target = [self._interpolate_correction_over_frequency(groups[target], freq_hz) for target in targets]
        if target_vpp <= targets[0]:
            factor = per_target[0]
        elif target_vpp >= targets[-1]:
            factor = per_target[-1]
        else:
            log_target = math.log10(target_vpp)
            log_targets = [math.log10(max(target, 1e-12)) for target in targets]
            factor = per_target[-1]
            for index in range(len(targets) - 1):
                if targets[index] <= target_vpp <= targets[index + 1]:
                    ratio = (log_target - log_targets[index]) / (log_targets[index + 1] - log_targets[index])
                    factor = per_target[index] + ratio * (per_target[index + 1] - per_target[index])
                    break

        min_factor = float(model.get("min_correction_factor", 0.25))
        max_factor = float(model.get("max_correction_factor", 4.0))
        return max(min_factor, min(max_factor, factor))

    def interpolate_pe43711_trim_db(self, freq_hz: float, output_mode: str | None = None) -> float:
        if output_mode == "ram_waveform":
            model = self.data.get("ram_pe43711_frequency_trim_model")
            if isinstance(model, dict) and model.get("type") == "pe43711_atten_delta_db_v1":
                return self._interpolate_pe43711_trim_model(model, freq_hz)
        model = self.pe43711_frequency_trim_model
        if not isinstance(model, dict) or model.get("type") != "pe43711_atten_delta_db_v1":
            return 0.0
        return self._interpolate_pe43711_trim_model(model, freq_hz)

    @staticmethod
    def _interpolate_pe43711_trim_model(model: dict[str, Any], freq_hz: float) -> float:
        if not isinstance(model, dict) or model.get("type") != "pe43711_atten_delta_db_v1":
            return 0.0
        if float(freq_hz) <= float(model.get("min_freq_hz", 0.0)):
            return 0.0
        points = [
            point
            for point in model.get("points", [])
            if "freq_hz" in point and "atten_delta_db" in point
        ]
        if not points:
            return 0.0
        points = sorted(points, key=lambda item: float(item.get("freq_hz", 0.0)))
        freqs = [float(point["freq_hz"]) for point in points]
        deltas = [float(point["atten_delta_db"]) for point in points]
        if freq_hz <= freqs[0]:
            return deltas[0]
        if freq_hz >= freqs[-1]:
            return deltas[-1]
        for index in range(len(freqs) - 1):
            left_f = freqs[index]
            right_f = freqs[index + 1]
            if left_f <= freq_hz <= right_f:
                ratio = (freq_hz - left_f) / (right_f - left_f)
                return deltas[index] + ratio * (deltas[index + 1] - deltas[index])
        return deltas[-1]

    def calculate(self, freq_hz: float, target_vpk: float, output_mode: str | None = None) -> RfCalibrationResult:
        target_vpk = max(0.005, min(float(target_vpk), 3.0))
        raw_vpk = self.interpolate_raw_vpk(freq_hz)
        correction_factor = self.interpolate_correction_factor(freq_hz, 2.0 * target_vpk)
        need_atten_db = 20.0 * math.log10(max(raw_vpk, 1e-12) / target_vpk)
        pe_code_for_amp = max(0, min(self.pe_max_code, int(round(need_atten_db / self.pe_step_db))))
        requested_amp_code = self.preferred_amp_code * target_vpk * correction_factor
        requested_amp_code *= 10.0 ** ((pe_code_for_amp * self.pe_step_db) / 20.0)
        requested_amp_code /= max(raw_vpk, 1e-12)
        if requested_amp_code > self.max_amp_code and pe_code_for_amp > 0:
            excess_db = 20.0 * math.log10(requested_amp_code / self.max_amp_code)
            reduce_steps = int(math.ceil(excess_db / self.pe_step_db))
            pe_code_for_amp = max(0, pe_code_for_amp - reduce_steps)
        pe_code = pe_code_for_amp
        pe_trim_db = self.interpolate_pe43711_trim_db(freq_hz, output_mode)
        pe_code = max(0, min(self.pe_max_code, pe_code + int(round(pe_trim_db / self.pe_step_db))))
        pe_db = pe_code * self.pe_step_db
        amp_db = pe_code_for_amp * self.pe_step_db
        amp_code = int(round(self.preferred_amp_code * target_vpk * (10.0 ** (amp_db / 20.0)) / raw_vpk))
        amp_code = int(round(amp_code * correction_factor))
        amp_code = max(0, min(self.max_amp_code, amp_code))
        amp_ratio = amp_code / self.max_amp_code if self.max_amp_code > 0 else 0.0
        expected_vpk = raw_vpk * (amp_code / self.preferred_amp_code) / (10.0 ** (pe_db / 20.0))
        expected_vpk /= max(correction_factor, 1e-12)
        return RfCalibrationResult(
            enabled=True,
            file=str(self.path),
            freq_hz=float(freq_hz),
            target_vpk=target_vpk,
            raw_vpk=raw_vpk,
            raw_vpp=2.0 * raw_vpk,
            pe43711_code=pe_code,
            pe43711_atten_db=pe_db,
            amp_code=amp_code,
            amp_ratio=amp_ratio,
            expected_vpk=expected_vpk,
            expected_vpp=2.0 * expected_vpk,
            nco_hz=self.nco_hz,
            correction_factor=correction_factor,
            pe43711_trim_db=pe_trim_db,
        )
