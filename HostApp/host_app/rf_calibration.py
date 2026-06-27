from __future__ import annotations

import json
import math
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from .udp_client import (
    RELAY_ATTENUATOR_MAX_DB,
    RELAY_ATTENUATOR_STEP_DB,
    relay_attenuation_db_from_mask,
    relay_mask_for_attenuation_db,
)


@dataclass(frozen=True)
class RfCalibrationResult:
    enabled: bool
    file: str
    freq_hz: float
    target_vpk: float
    raw_vpk: float
    raw_vpp: float
    relay_atten_mask: int
    relay_atten_db: float
    amp_code: int
    amp_ratio: float
    expected_vpk: float
    expected_vpp: float
    nco_hz: float
    correction_factor: float
    relay_trim_db: float = 0.0

    def to_payload(self) -> dict[str, Any]:
        return {
            "enabled": self.enabled,
            "file": self.file,
            "freq_hz": self.freq_hz,
            "target_vpk": self.target_vpk,
            "raw_vpk": self.raw_vpk,
            "raw_vpp": self.raw_vpp,
            "relay_atten_mask": self.relay_atten_mask,
            "relay_atten_db": self.relay_atten_db,
            "amp_code": self.amp_code,
            "amp_ratio": self.amp_ratio,
            "expected_vpk": self.expected_vpk,
            "expected_vpp": self.expected_vpp,
            "nco_hz": self.nco_hz,
            "correction_factor": self.correction_factor,
            "relay_trim_db": self.relay_trim_db,
        }


def find_latest_ch1_rf_calibration(repo_root: Path, output_mode: str | None = None) -> Path | None:
    calibration_root = repo_root / "HostApp" / "calibration"
    if not calibration_root.exists():
        return None
    if output_mode == "ram_waveform":
        matches = [
            path
            for path in calibration_root.glob("ch1_rf_*/rf_cal_10m_200m_ch1_runtime.json")
            if _looks_like_runtime_rf_calibration(path, output_mode=output_mode)
        ]
        if matches:
            return max(matches, key=lambda path: path.stat().st_mtime)
    if output_mode == "jesd_tone":
        matches = [
            path
            for path in calibration_root.glob("ch1_rf_jesd_tone_*/rf_jesd_tone_ch1_runtime.json")
            if _looks_like_runtime_rf_calibration(path, output_mode=output_mode)
        ]
        if matches:
            return max(matches, key=lambda path: path.stat().st_mtime)
    matches = [
        path
        for path in calibration_root.glob("ch1_rf_*/rf_cal_10m_200m_ch1_runtime.json")
        if _looks_like_runtime_rf_calibration(path, output_mode=output_mode)
    ]
    if not matches:
        return None
    return max(matches, key=lambda path: path.stat().st_mtime)


def _looks_like_runtime_rf_calibration(path: Path, output_mode: str | None = None) -> bool:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return False
    if output_mode is not None and data.get("output_mode") != output_mode:
        return False
    if output_mode is None and data.get("output_mode") == "ram_waveform":
        return False
    if data.get("source") == "rf_unified_attenuator_scope_sweep":
        model = data.get("amplitude_correction_model")
        if not isinstance(model, dict):
            return False
        model_points = model.get("points", [])
        if not isinstance(model_points, list) or len(model_points) < 2:
            return False
    points = data.get("points", [])
    return isinstance(points, list) and len(points) >= 2


def relay_mask_floor_for_attenuation_db(atten_db: float, max_mask: int = 15) -> tuple[int, float]:
    target_db = max(0.0, float(atten_db))
    max_mask = int(max_mask) & 0x0F
    best_mask = 0
    best_db = 0.0
    for mask in range(16):
        mask &= max_mask
        candidate_db = relay_attenuation_db_from_mask(mask)
        if candidate_db <= target_db and candidate_db >= best_db:
            best_mask = mask
            best_db = candidate_db
    return best_mask, best_db


class RfCalibrationTable:
    def __init__(self, path: Path):
        self.path = path
        self.data = json.loads(path.read_text(encoding="utf-8"))
        self.points = sorted(self.data.get("points", []), key=lambda item: float(item["freq_hz"]))
        if len(self.points) < 2:
            raise ValueError(f"RF calibration file has too few points: {path}")
        self.preferred_amp_code = int(self.data.get("preferred_amp_code", 0x40CC))
        self.max_amp_code = int(self.data.get("nco_max_amp_code", 0x50FF))
        self.relay_step_db = float(self.data.get("relay_attenuator_step_db", RELAY_ATTENUATOR_STEP_DB))
        self.relay_max_mask = int(self.data.get("relay_attenuator_max_mask", 15))
        self.nco_hz = float(self.data.get("nco_hz", 1_474_560_000.0))
        self.amplitude_correction_model = self.data.get("amplitude_correction_model")
        self.ram_waveform_amplitude_model = self.data.get("ram_waveform_amplitude_model")
        self.relay_absolute_model = self.data.get("relay_attenuator_absolute_model")
        self.relay_frequency_trim_model = self.data.get("relay_attenuator_frequency_trim_model")
        self.amplitude_corrections = sorted(
            self.data.get("amplitude_corrections", []),
            key=lambda item: float(item.get("freq_hz", 0.0)),
        )

    @classmethod
    def load_latest(cls, repo_root: Path, output_mode: str | None = None) -> "RfCalibrationTable | None":
        path = find_latest_ch1_rf_calibration(repo_root, output_mode=output_mode)
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

    def interpolate_correction_factor(
        self,
        freq_hz: float,
        target_vpp: float | None = None,
        relay_mask: int | None = None,
    ) -> float:
        model_factor = self._interpolate_model_correction_factor(freq_hz, target_vpp, relay_mask)
        if model_factor is not None:
            return model_factor
        if not self.amplitude_corrections:
            return 1.0
        corrections = self.amplitude_corrections
        if relay_mask is not None:
            relay_mask = int(relay_mask) & 0x0F
            relay_points = [
                point
                for point in corrections
                if int(point.get("relay_atten_mask", -1)) & 0x0F == relay_mask
            ]
            if len(relay_points) >= 2:
                corrections = relay_points
        freq_hz = float(freq_hz)
        groups: dict[float, list[dict[str, Any]]] = {}
        for point in corrections:
            if "target_vpp" not in point:
                continue
            groups.setdefault(float(point["target_vpp"]), []).append(point)
        if target_vpp is None or len(groups) < 2:
            return self._interpolate_correction_over_frequency(corrections, freq_hz)

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
        relay_mask: int | None = None,
    ) -> float | None:
        model = self.amplitude_correction_model
        if not isinstance(model, dict):
            return None
        if model.get("type") == "correction_factor_linear_v1":
            return self._interpolate_correction_factor_model(model, freq_hz, _target_vpp, relay_mask)
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
        relay_mask: int | None = None,
    ) -> float | None:
        points = [
            point
            for point in model.get("points", [])
            if "freq_hz" in point and "target_vpp" in point and "correction_factor" in point
        ]
        if not points:
            return None
        if relay_mask is not None:
            relay_mask = int(relay_mask) & 0x0F
            relay_points = [
                point
                for point in points
                if int(point.get("relay_atten_mask", -1)) & 0x0F == relay_mask
            ]
            if len(relay_points) >= 2:
                points = relay_points

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

    def interpolate_relay_trim_db(self, freq_hz: float, output_mode: str | None = None) -> float:
        if output_mode == "ram_waveform":
            model = self.data.get("ram_relay_attenuator_frequency_trim_model")
            if isinstance(model, dict) and model.get("type") == "relay_atten_delta_db_v1":
                return self._interpolate_relay_trim_model(model, freq_hz)
        model = self.relay_frequency_trim_model
        if not isinstance(model, dict) or model.get("type") != "relay_atten_delta_db_v1":
            return 0.0
        return self._interpolate_relay_trim_model(model, freq_hz)

    @staticmethod
    def _interpolate_relay_trim_model(model: dict[str, Any], freq_hz: float) -> float:
        if not isinstance(model, dict) or model.get("type") != "relay_atten_delta_db_v1":
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

    def interpolate_relay_absolute_db(self, freq_hz: float, output_mode: str | None = None) -> float | None:
        if output_mode == "ram_waveform":
            model = self.data.get("ram_relay_attenuator_absolute_model")
            if isinstance(model, dict) and model.get("type") == "relay_atten_absolute_db_v1":
                return self._interpolate_relay_absolute_model(model, freq_hz)
        model = self.relay_absolute_model
        if not isinstance(model, dict) or model.get("type") != "relay_atten_absolute_db_v1":
            return None
        return self._interpolate_relay_absolute_model(model, freq_hz)

    @staticmethod
    def _interpolate_relay_absolute_model(model: dict[str, Any], freq_hz: float) -> float | None:
        if not isinstance(model, dict) or model.get("type") != "relay_atten_absolute_db_v1":
            return None
        points = [
            point
            for point in model.get("points", [])
            if "freq_hz" in point and "atten_db" in point
        ]
        if not points:
            return None
        points = sorted(points, key=lambda item: float(item.get("freq_hz", 0.0)))
        freq_hz = float(freq_hz)
        freqs = [float(point["freq_hz"]) for point in points]
        atten_values = [float(point["atten_db"]) for point in points]
        interpolation = str(model.get("interpolation", "linear")).lower()

        if interpolation in {"previous", "step", "step_previous"}:
            if freq_hz <= freqs[0]:
                return atten_values[0]
            atten_db = atten_values[-1]
            for index in range(len(freqs) - 1):
                if freqs[index] <= freq_hz < freqs[index + 1]:
                    atten_db = atten_values[index]
                    break
            return atten_db

        if freq_hz <= freqs[0]:
            return atten_values[0]
        if freq_hz >= freqs[-1]:
            return atten_values[-1]
        for index in range(len(freqs) - 1):
            left_f = freqs[index]
            right_f = freqs[index + 1]
            if left_f <= freq_hz <= right_f:
                ratio = (freq_hz - left_f) / (right_f - left_f)
                return atten_values[index] + ratio * (atten_values[index + 1] - atten_values[index])
        return atten_values[-1]

    def interpolate_ram_sample_vpk(
        self,
        freq_hz: float,
        target_vpk: float,
        full_scale_vpk: float,
    ) -> float | None:
        model = self.ram_waveform_amplitude_model
        if not isinstance(model, dict) or model.get("type") != "ram_sample_vpk_v1":
            return None
        points = [
            point
            for point in model.get("points", [])
            if "freq_hz" in point
            and ("sample_vpk_at_reference" in point or point.get("sample_full_scale_at_reference"))
        ]
        if not points:
            return None
        points = sorted(points, key=lambda item: float(item.get("freq_hz", 0.0)))
        reference_vpp = max(float(model.get("reference_target_vpp", 2.0 * target_vpk)), 1e-12)
        scale = max(float(target_vpk) * 2.0, 0.0) / reference_vpp
        full_scale_vpk = max(float(full_scale_vpk), 0.0)

        def point_vpk(point: dict[str, Any]) -> float:
            if point.get("sample_full_scale_at_reference"):
                return full_scale_vpk
            return max(0.0, float(point.get("sample_vpk_at_reference", 0.0)) * scale)

        freq_hz = float(freq_hz)
        freqs = [float(point["freq_hz"]) for point in points]
        values = [point_vpk(point) for point in points]
        if freq_hz <= freqs[0]:
            return min(full_scale_vpk, values[0])
        if freq_hz >= freqs[-1]:
            return min(full_scale_vpk, values[-1])
        for index in range(len(freqs) - 1):
            left_f = freqs[index]
            right_f = freqs[index + 1]
            if left_f <= freq_hz <= right_f:
                ratio = (freq_hz - left_f) / (right_f - left_f)
                value = values[index] + ratio * (values[index + 1] - values[index])
                return min(full_scale_vpk, max(0.0, value))
        return min(full_scale_vpk, values[-1])

    def interpolate_ram_relay_atten_db(self, freq_hz: float) -> float | None:
        points = [
            point
            for point in self.points
            if "freq_hz" in point and ("relay_atten_db" in point or "relay_atten_mask" in point)
        ]
        if not points:
            return None
        points = sorted(points, key=lambda item: float(item.get("freq_hz", 0.0)))
        freq_hz = float(freq_hz)

        def point_db(point: dict[str, Any]) -> float:
            if "relay_atten_db" in point:
                return float(point["relay_atten_db"])
            return relay_attenuation_db_from_mask(int(point.get("relay_atten_mask", 0)))

        freqs = [float(point["freq_hz"]) for point in points]
        if freq_hz <= freqs[0]:
            return point_db(points[0])
        if freq_hz >= freqs[-1]:
            return point_db(points[-1])
        for index in range(len(freqs) - 1):
            left_f = freqs[index]
            right_f = freqs[index + 1]
            if left_f <= freq_hz < right_f:
                return point_db(points[index])
        return point_db(points[-1])

    def calculate(
        self,
        freq_hz: float,
        target_vpk: float,
        output_mode: str | None = None,
        relay_mask_override: int | None = None,
    ) -> RfCalibrationResult:
        max_amp_code = self.max_amp_code if output_mode == "nco_only" else 0x7FFF
        target_vpk = max(0.0005, min(float(target_vpk), 3.0))
        raw_vpk = self.interpolate_raw_vpk(freq_hz)
        need_atten_db = 20.0 * math.log10(max(raw_vpk, 1e-12) / target_vpk)
        if relay_mask_override is None:
            absolute_relay_db = self.interpolate_relay_absolute_db(freq_hz, output_mode)
            ram_relay_db = self.interpolate_ram_relay_atten_db(freq_hz) if output_mode == "ram_waveform" else None
            if output_mode == "ram_waveform" and ram_relay_db is not None:
                relay_mask, relay_db = relay_mask_for_attenuation_db(
                    max(0.0, min(RELAY_ATTENUATOR_MAX_DB, ram_relay_db))
                )
                relay_mask &= self.relay_max_mask
                relay_db = relay_attenuation_db_from_mask(relay_mask)
                relay_db_for_amp = relay_db
                relay_trim_db = 0.0
                correction_factor = self.interpolate_correction_factor(
                    freq_hz,
                    2.0 * target_vpk,
                    relay_mask,
                )
            elif absolute_relay_db is None:
                relay_mask_for_amp, relay_db_for_amp = relay_mask_floor_for_attenuation_db(
                    need_atten_db,
                    self.relay_max_mask,
                )
                correction_factor = self.interpolate_correction_factor(
                    freq_hz,
                    2.0 * target_vpk,
                    relay_mask_for_amp,
                )
                requested_amp_code = self.preferred_amp_code * target_vpk * correction_factor
                requested_amp_code *= 10.0 ** (relay_db_for_amp / 20.0)
                requested_amp_code /= max(raw_vpk, 1e-12)
                while requested_amp_code > max_amp_code and relay_db_for_amp > 0.0:
                    relay_mask_for_amp, relay_db_for_amp = relay_mask_floor_for_attenuation_db(
                        max(0.0, relay_db_for_amp - self.relay_step_db),
                        self.relay_max_mask,
                    )
                    correction_factor = self.interpolate_correction_factor(
                        freq_hz,
                        2.0 * target_vpk,
                        relay_mask_for_amp,
                    )
                    requested_amp_code = self.preferred_amp_code * target_vpk * correction_factor
                    requested_amp_code *= 10.0 ** (relay_db_for_amp / 20.0)
                    requested_amp_code /= max(raw_vpk, 1e-12)
                relay_trim_db = self.interpolate_relay_trim_db(freq_hz, output_mode)
                relay_mask, relay_db = relay_mask_floor_for_attenuation_db(
                    max(0.0, min(RELAY_ATTENUATOR_MAX_DB, relay_db_for_amp + relay_trim_db)),
                    self.relay_max_mask,
                )
                correction_factor = self.interpolate_correction_factor(
                    freq_hz,
                    2.0 * target_vpk,
                    relay_mask,
                )
            else:
                relay_trim_db = 0.0
                relay_mask, relay_db = relay_mask_for_attenuation_db(
                    max(0.0, min(RELAY_ATTENUATOR_MAX_DB, absolute_relay_db))
                )
                relay_mask &= self.relay_max_mask
                relay_db = relay_attenuation_db_from_mask(relay_mask)
                relay_db_for_amp = relay_db
                correction_factor = self.interpolate_correction_factor(
                    freq_hz,
                    2.0 * target_vpk,
                    relay_mask,
                )
        else:
            relay_mask = max(0, min(self.relay_max_mask, int(relay_mask_override))) & 0x0F
            relay_db = relay_attenuation_db_from_mask(relay_mask)
            relay_db_for_amp = relay_db
            relay_trim_db = 0.0
            correction_factor = self.interpolate_correction_factor(
                freq_hz,
                2.0 * target_vpk,
                relay_mask,
            )
        amp_code = int(round(self.preferred_amp_code * target_vpk * (10.0 ** (relay_db_for_amp / 20.0)) / raw_vpk))
        amp_code = int(round(amp_code * correction_factor))
        amp_code = max(0, min(max_amp_code, amp_code))
        amp_ratio = amp_code / max_amp_code if max_amp_code > 0 else 0.0
        expected_vpk = raw_vpk * (amp_code / self.preferred_amp_code) / (10.0 ** (relay_db / 20.0))
        expected_vpk /= max(correction_factor, 1e-12)
        return RfCalibrationResult(
            enabled=True,
            file=str(self.path),
            freq_hz=float(freq_hz),
            target_vpk=target_vpk,
            raw_vpk=raw_vpk,
            raw_vpp=2.0 * raw_vpk,
            relay_atten_mask=relay_mask,
            relay_atten_db=relay_db,
            amp_code=amp_code,
            amp_ratio=amp_ratio,
            expected_vpk=expected_vpk,
            expected_vpp=2.0 * expected_vpk,
            nco_hz=self.nco_hz,
            correction_factor=correction_factor,
            relay_trim_db=relay_trim_db,
        )
