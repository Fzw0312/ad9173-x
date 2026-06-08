from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True)
class LfCalibrationResult:
    enabled: bool
    file: str
    freq_hz: float
    target_vpk: float
    raw_vpk: float
    raw_vpp: float
    amp_code: int
    amp_ratio: float
    expected_vpk: float
    expected_vpp: float
    nco_hz: float
    correction_factor: float
    clipped: bool

    def to_payload(self) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "file": self.file,
            "freq_hz": self.freq_hz,
            "target_vpk": self.target_vpk,
            "raw_vpk": self.raw_vpk,
            "raw_vpp": self.raw_vpp,
            "amp_code": self.amp_code,
            "amp_ratio": self.amp_ratio,
            "expected_vpk": self.expected_vpk,
            "expected_vpp": self.expected_vpp,
            "nco_hz": self.nco_hz,
            "correction_factor": self.correction_factor,
            "clipped": self.clipped,
        }


def find_latest_lf_calibration(repo_root: Path) -> Path | None:
    calibration_root = repo_root / "HostApp" / "calibration"
    if not calibration_root.exists():
        return None
    matches = [
        path
        for path in calibration_root.glob("dac1_lf_*/lf_cal_dac1_runtime.json")
        if not path.parent.name.startswith("dac1_lf_manual_")
    ]
    if not matches:
        return None
    return max(matches, key=lambda path: path.stat().st_mtime)


class LfCalibrationTable:
    def __init__(self, path: Path):
        self.path = path
        self.data = json.loads(path.read_text(encoding="utf-8"))
        self.points = sorted(self.data.get("points", []), key=lambda item: float(item["freq_hz"]))
        if len(self.points) < 2:
            raise ValueError(f"LF calibration file has too few points: {path}")
        self.preferred_amp_code = int(self.data.get("preferred_amp_code", 0x40CC))
        self.max_amp_code = int(self.data.get("nco_max_amp_code", 0x50FF))
        self.nco_hz = float(self.data.get("nco_hz", 1_474_561_031.9672773))
        self.amplitude_correction_model = self.data.get("amplitude_correction_model")

    @classmethod
    def load_latest(cls, repo_root: Path) -> "LfCalibrationTable | None":
        path = find_latest_lf_calibration(repo_root)
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

    def interpolate_correction_factor(self, freq_hz: float, target_vpp: float | None = None) -> float:
        model = self.amplitude_correction_model
        if not isinstance(model, dict) or model.get("type") != "correction_factor_linear_v1":
            return 1.0
        points = [
            point
            for point in model.get("points", [])
            if "freq_hz" in point and "target_vpp" in point and "correction_factor" in point
        ]
        if not points:
            return 1.0

        freq_hz = float(freq_hz)
        target_vpp = max(float(target_vpp or model.get("reference_target_vpp", 1.0)), 1e-12)
        groups: dict[float, list[dict[str, Any]]] = {}
        for point in points:
            groups.setdefault(float(point["target_vpp"]), []).append(point)
        targets = sorted(groups)
        per_target = [self._interpolate_over_frequency(groups[target], freq_hz) for target in targets]
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
        return max(float(model.get("min_correction_factor", 0.2)), min(float(model.get("max_correction_factor", 5.0)), factor))

    @staticmethod
    def _interpolate_over_frequency(points: list[dict[str, Any]], freq_hz: float) -> float:
        points = sorted(points, key=lambda item: float(item.get("freq_hz", 0.0)))
        freqs = [float(point.get("freq_hz", 0.0)) for point in points]
        factors = [float(point.get("correction_factor", 1.0)) for point in points]
        if freq_hz <= freqs[0]:
            return factors[0]
        if freq_hz >= freqs[-1]:
            return factors[-1]
        for index in range(len(freqs) - 1):
            if freqs[index] <= freq_hz <= freqs[index + 1]:
                ratio = (freq_hz - freqs[index]) / (freqs[index + 1] - freqs[index])
                return factors[index] + ratio * (factors[index + 1] - factors[index])
        return factors[-1]

    def calculate(self, freq_hz: float, target_vpk: float) -> LfCalibrationResult:
        target_vpk = max(0.0, float(target_vpk))
        raw_vpk = self.interpolate_raw_vpk(freq_hz)
        correction_factor = self.interpolate_correction_factor(freq_hz, 2.0 * target_vpk)
        requested = self.preferred_amp_code * target_vpk * correction_factor / max(raw_vpk, 1e-12)
        clipped = requested > self.max_amp_code
        amp_code = max(0, min(self.max_amp_code, int(round(requested))))
        amp_ratio = amp_code / self.max_amp_code if self.max_amp_code > 0 else 0.0
        expected_vpk = raw_vpk * (amp_code / self.preferred_amp_code) / max(correction_factor, 1e-12)
        return LfCalibrationResult(
            enabled=True,
            file=str(self.path),
            freq_hz=float(freq_hz),
            target_vpk=target_vpk,
            raw_vpk=raw_vpk,
            raw_vpp=2.0 * raw_vpk,
            amp_code=amp_code,
            amp_ratio=amp_ratio,
            expected_vpk=expected_vpk,
            expected_vpp=2.0 * expected_vpk,
            nco_hz=self.nco_hz,
            correction_factor=correction_factor,
            clipped=clipped,
        )
