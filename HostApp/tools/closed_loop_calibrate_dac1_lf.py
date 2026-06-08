from __future__ import annotations

import argparse
import csv
import json
import queue
import shutil
import subprocess
import sys
import threading
import time
from dataclasses import asdict, dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from host_app.lf_calibration import LfCalibrationTable
from host_app.scope_scpi import ScopeEndpoint, ScpiSocket, ScopeMeasurement, _normalize_channel, _parse_siglent_pava


NCO_HZ = 1_474_561_031.9672773
PREFERRED_AMP_CODE = 0x40CC
MAX_AMP_CODE = 0x50FF


@dataclass(frozen=True)
class LfLoopPoint:
    freq_hz: float
    target_vpp: float
    measured_vpp: float
    measured_vpk: float
    old_correction_factor: float
    new_correction_factor: float
    amp_code: int
    ftw: str
    measured_freq_hz: float
    vdiv_v: float
    raw_pava: str
    clipped: bool


def vdiv_for_target_vpp(target_vpp: float) -> float:
    if target_vpp >= 1.0:
        return 0.5
    if target_vpp >= 0.4:
        return 0.15
    if target_vpp >= 0.2:
        return 0.06
    if target_vpp >= 0.1:
        return 0.03
    if target_vpp >= 0.05:
        return 0.015
    if target_vpp >= 0.02:
        return 0.01
    return 0.005


def format_siglent_vdiv(value_v: float) -> str:
    return f"{value_v:.3G}"


def parse_vdiv_response(raw: str) -> float | None:
    text = raw.strip()
    if not text:
        return None
    token = text.split()[-1].strip().rstrip("Vv")
    try:
        return float(token)
    except ValueError:
        return None


def set_verified_vdiv(instrument: ScpiSocket, channel: str, target_vdiv: float, attempts: int = 3) -> float:
    source = _normalize_channel(channel, "C")
    tolerance = max(0.002, target_vdiv * 0.02)
    last_raw = ""
    for _attempt in range(attempts):
        instrument.write(f"{source}:VDIV {format_siglent_vdiv(target_vdiv)}")
        time.sleep(0.8)
        last_raw = instrument.query_text(f"{source}:VDIV?")
        measured = parse_vdiv_response(last_raw)
        if measured is not None and abs(measured - target_vdiv) <= tolerance:
            return measured
    raise RuntimeError(f"Failed to set {source}:VDIV to {target_vdiv:g} V/div; last={last_raw!r}")


def measurement_value(measurements: dict[str, ScopeMeasurement], *names: str) -> float | None:
    for name in names:
        measurement = measurements.get(name.upper())
        if measurement is not None and measurement.value is not None:
            return float(measurement.value)
    return None


def parse_single_pava_value(raw: str, expected_name: str) -> float | None:
    measurements = _parse_siglent_pava(raw)
    value = measurement_value(measurements, expected_name)
    if value is not None:
        return value
    parts = [part.strip().strip('"') for part in raw.split(",")]
    for index, part in enumerate(parts[:-1]):
        if part.upper().endswith(expected_name.upper()):
            try:
                return float(parts[index + 1].rstrip("VvHhzZsS"))
            except ValueError:
                return None
    if len(parts) >= 2 and parts[0].upper() == expected_name.upper():
        try:
            return float(parts[1].rstrip("VvHhzZsS"))
        except ValueError:
            return None
    return None


def query_pava_measurement(
    instrument: ScpiSocket,
    channel: str,
    samples: int,
    interval_s: float,
    read_freq: bool = False,
) -> tuple[float, float, str]:
    source = _normalize_channel(channel, "C")
    measured_vpps: list[float] = []
    measured_freqs: list[float] = []
    raw_values: list[str] = []
    for _index in range(samples):
        pkpk_raw = instrument.query_text(f"{source}:PAVA? PKPK")
        freq_raw = instrument.query_text(f"{source}:PAVA? FREQ") if read_freq else ""
        raw_values.append(f"{pkpk_raw}; {freq_raw}" if freq_raw else pkpk_raw)
        pkpk = parse_single_pava_value(pkpk_raw, "PKPK")
        freq = parse_single_pava_value(freq_raw, "FREQ") if freq_raw else None
        if pkpk is not None and pkpk > 0.0:
            measured_vpps.append(pkpk)
        if freq is not None and freq > 0.0:
            measured_freqs.append(freq)
        time.sleep(interval_s)
    if not measured_vpps:
        raise RuntimeError(f"No valid PKPK measurement in PAVA responses: {raw_values[-3:]}")
    return (
        sum(measured_vpps) / len(measured_vpps),
        sum(measured_freqs) / len(measured_freqs) if measured_freqs else 0.0,
        " | ".join(raw_values),
    )


def vivado_launcher() -> list[str]:
    candidate = shutil.which("vivado.bat") or r"D:\Xilinx\Vivado\2020.2\bin\vivado.bat"
    if Path(candidate).exists():
        return ["cmd.exe", "/d", "/c", candidate]
    return [shutil.which("vivado") or "vivado"]


class PersistentVio:
    def __init__(self, repo_root: Path, timeout_s: float = 120.0):
        self.repo_root = repo_root
        self.timeout_s = timeout_s
        self.proc: subprocess.Popen[str] | None = None
        self.lines: "queue.Queue[str]" = queue.Queue()

    def __enter__(self) -> "PersistentVio":
        script = self.repo_root / "Prj" / "scripts" / "hw_runtime_vio_server.tcl"
        self.proc = subprocess.Popen(
            vivado_launcher() + ["-mode", "tcl", "-source", str(script)],
            cwd=str(self.repo_root),
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            bufsize=1,
        )
        threading.Thread(target=self._read_lines, daemon=True).start()
        self._wait_for("K5VIO_READY")
        return self

    def __exit__(self, _exc_type, _exc, _tb) -> None:
        if self.proc is not None and self.proc.poll() is None:
            try:
                self._write("exit")
                self.proc.wait(timeout=20)
            except Exception:
                self.proc.kill()

    def _read_lines(self) -> None:
        assert self.proc is not None and self.proc.stdout is not None
        for line in self.proc.stdout:
            line = line.rstrip()
            print(line, flush=True)
            self.lines.put(line)

    def _write(self, command: str) -> None:
        assert self.proc is not None and self.proc.stdin is not None
        self.proc.stdin.write(command + "\n")
        self.proc.stdin.flush()

    def _wait_for(self, marker: str) -> None:
        deadline = time.time() + self.timeout_s
        while time.time() < deadline:
            if self.proc is not None and self.proc.poll() is not None:
                raise RuntimeError(f"Vivado exited before marker {marker}")
            try:
                line = self.lines.get(timeout=0.25)
            except queue.Empty:
                continue
            if line.startswith("ERROR:"):
                raise RuntimeError(line)
            if marker in line:
                return
        raise TimeoutError(f"Timed out waiting for {marker}")

    def apply_lf(self, amp_code: int, ftw: int, index: int) -> None:
        marker = f"K5VIO_DONE_{index}"
        self._write(f"ku5p_vio_apply 0000 000000000000 {amp_code:04x} {ftw:012x} 7f 1")
        self._write(f"puts {marker}")
        self._wait_for(marker)


def ftw_for(freq_hz: float, nco_hz: float = NCO_HZ) -> int:
    return int(round(freq_hz / nco_hz * (1 << 48))) & 0xFFFFFFFFFFFF


def fit_model(rows: list[LfLoopPoint], timestamp: str) -> dict[str, object] | None:
    points = [
        {
            "freq_hz": row.freq_hz,
            "target_vpp": row.target_vpp,
            "correction_factor": row.new_correction_factor,
            "measured_vpp": row.measured_vpp,
            "old_correction_factor": row.old_correction_factor,
        }
        for row in rows
        if not row.clipped
    ]
    if not points:
        return None
    return {
        "type": "correction_factor_linear_v1",
        "source": "dac1_lf_closed_loop_scope_sweep",
        "created_at": timestamp,
        "description": "DAC1 LF direct-output correction. Final amp_code is interpolated over frequency and target_vpp.",
        "min_correction_factor": 0.2,
        "max_correction_factor": 5.0,
        "points": points,
    }


def merge_model(existing_model: object, new_model: dict[str, object] | None, timestamp: str) -> dict[str, object] | None:
    if new_model is None:
        return existing_model if isinstance(existing_model, dict) else None
    merged: dict[tuple[float, float], dict[str, object]] = {}
    if isinstance(existing_model, dict) and existing_model.get("type") == "correction_factor_linear_v1":
        for point in existing_model.get("points", []):
            if isinstance(point, dict) and "freq_hz" in point and "target_vpp" in point:
                merged[(float(point["freq_hz"]), float(point["target_vpp"]))] = dict(point)
    for point in new_model.get("points", []):
        if isinstance(point, dict):
            merged[(float(point["freq_hz"]), float(point["target_vpp"]))] = dict(point)
    model = dict(new_model)
    model["created_at"] = timestamp
    model["merged_from_existing"] = bool(merged)
    model["points"] = [merged[key] for key in sorted(merged)]
    return model


def bootstrap_table(rows: list[LfLoopPoint], timestamp: str, out_dir: Path) -> Path:
    data = {
        "version": 1,
        "created_at": timestamp,
        "path": "dac1_lf_direct_nco",
        "channel": "DAC1/LF",
        "frequency_range_hz": [1e-3, max(row.freq_hz for row in rows)],
        "calibrated_floor_hz": min(row.freq_hz for row in rows),
        "calibrated_floor_behavior": "Frequencies below calibrated_floor_hz reuse the calibrated_floor_hz gain/correction.",
        "amplitude_unit": "Vpk",
        "display_amplitude_unit": "Vpp",
        "nco_hz": NCO_HZ,
        "preferred_amp_code": PREFERRED_AMP_CODE,
        "nco_max_amp_code": MAX_AMP_CODE,
        "points": [
            {
                "freq_hz": row.freq_hz,
                "raw_vpk": row.measured_vpk,
                "raw_vpp": row.measured_vpp,
                "measured_freq_hz": row.measured_freq_hz,
                "amp_code": row.amp_code,
                "ftw": row.ftw,
            }
            for row in rows
        ],
        "amplitude_correction_model": None,
    }
    path = out_dir / "lf_cal_dac1_runtime.json"
    path.write_text(json.dumps(data, indent=2), encoding="utf-8")
    return path


def main() -> int:
    parser = argparse.ArgumentParser(description="Closed-loop DAC1 LF direct-output amplitude calibration.")
    parser.add_argument("--bootstrap", action="store_true", help="Build raw DAC1 LF calibration table with preferred amp code.")
    parser.add_argument("--target-vpp", type=float, action="append", default=None)
    parser.add_argument("--freq-hz", type=float, action="append", default=None)
    parser.add_argument("--freq-khz", type=float, action="append", default=None)
    parser.add_argument("--freq-mhz", type=float, action="append", default=None)
    parser.add_argument("--scope-ip", default="10.9.122.103")
    parser.add_argument("--scope-port", type=int, default=5025)
    parser.add_argument("--scope-timeout", type=float, default=5.0)
    parser.add_argument("--channel", default="CHAN2")
    parser.add_argument("--settle", type=float, default=2.5)
    parser.add_argument("--between-captures", type=float, default=0.7)
    parser.add_argument("--pava-samples", type=int, default=20)
    parser.add_argument("--pava-interval", type=float, default=0.2)
    parser.add_argument("--read-freq", action="store_true")
    parser.add_argument("--min-valid-ratio", type=float, default=0.2)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "calibration")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    freqs = [float(value) for value in (args.freq_hz or [])]
    freqs += [float(value) * 1e3 for value in (args.freq_khz or [])]
    freqs += [float(value) * 1e6 for value in (args.freq_mhz or [])]
    if not freqs:
        freqs = [1e3, 10e3, 100e3, 1e6, 5e6, 10e6, 20e6, 30e6]
    targets = args.target_vpp or ([1.0] if args.bootstrap else [0.01, 0.03, 0.1, 0.3, 1.0, 2.0])
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    out_dir = args.output_dir / f"dac1_lf_{timestamp}"
    out_dir.mkdir(parents=True, exist_ok=True)

    cal = None if args.bootstrap else LfCalibrationTable.load_latest(repo_root)
    if cal is None and not args.bootstrap:
        raise RuntimeError("No DAC1 LF calibration table found; run with --bootstrap first.")

    rows: list[LfLoopPoint] = []
    csv_path = out_dir / "lf_loop_points.csv"
    source = _normalize_channel(args.channel, "C")
    with PersistentVio(repo_root) as vio, ScpiSocket(ScopeEndpoint(args.scope_ip, args.scope_port, args.scope_timeout)) as scope:
        print(f"scope={scope.query_text('*IDN?')}", flush=True)
        scope.write("CHDR SHORT")
        index = 0
        for target_vpp in targets:
            actual_vdiv = set_verified_vdiv(scope, args.channel, vdiv_for_target_vpp(target_vpp))
            print(f"set {source}:VDIV={actual_vdiv:g} V/div for target {target_vpp:g} Vpp", flush=True)
            time.sleep(0.8)
            for freq_hz in freqs:
                index += 1
                if args.bootstrap:
                    amp_code = PREFERRED_AMP_CODE
                    old_corr = 1.0
                    clipped = False
                    nco_hz = NCO_HZ
                else:
                    assert cal is not None
                    old_corr = cal.interpolate_correction_factor(freq_hz, target_vpp)
                    result = cal.calculate(freq_hz, target_vpp / 2.0)
                    amp_code = result.amp_code
                    clipped = result.clipped
                    nco_hz = result.nco_hz
                ftw = ftw_for(freq_hz, nco_hz)
                print(
                    f"[{index}/{len(targets) * len(freqs)}] {freq_hz:g} Hz target={target_vpp:g} Vpp "
                    f"amp=0x{amp_code:04X}{' clipped' if clipped else ''}",
                    flush=True,
                )
                vio.apply_lf(amp_code, ftw, index)
                time.sleep(args.settle)
                measured_vpp, measured_freq_hz, raw_pava = query_pava_measurement(
                    scope,
                    args.channel,
                    samples=max(1, args.pava_samples),
                    interval_s=max(0.1, args.pava_interval),
                    read_freq=args.read_freq,
                )
                if measured_vpp < target_vpp * args.min_valid_ratio:
                    raise RuntimeError(
                        f"Rejecting implausible measurement: target={target_vpp:g} Vpp, measured={measured_vpp:g} Vpp"
                    )
                ratio = target_vpp / measured_vpp if measured_vpp > 0.0 else 1.0
                row = LfLoopPoint(
                    freq_hz=freq_hz,
                    target_vpp=target_vpp,
                    measured_vpp=measured_vpp,
                    measured_vpk=measured_vpp / 2.0,
                    old_correction_factor=old_corr,
                    new_correction_factor=old_corr * ratio,
                    amp_code=amp_code,
                    ftw=f"0x{ftw:012X}",
                    measured_freq_hz=measured_freq_hz,
                    vdiv_v=actual_vdiv,
                    raw_pava=raw_pava,
                    clipped=clipped,
                )
                rows.append(row)
                with csv_path.open("w", newline="", encoding="utf-8") as handle:
                    writer = csv.DictWriter(handle, fieldnames=list(asdict(rows[0]).keys()))
                    writer.writeheader()
                    for saved in rows:
                        writer.writerow(asdict(saved))
                print(f"  measured={measured_vpp:.6g} Vpp, ratio={ratio:.6g}, new_corr={row.new_correction_factor:.6g}", flush=True)
                time.sleep(args.between_captures)

    if args.bootstrap:
        runtime_path = bootstrap_table(rows, timestamp, out_dir)
    else:
        assert cal is not None
        updated = dict(cal.data)
        updated["updated_at"] = timestamp
        updated["amplitude_correction_model"] = merge_model(
            cal.data.get("amplitude_correction_model"),
            fit_model(rows, timestamp),
            timestamp,
        )
        runtime_path = out_dir / "lf_cal_dac1_runtime.json"
        runtime_path.write_text(json.dumps(updated, indent=2), encoding="utf-8")
        cal.path.write_text(json.dumps(updated, indent=2), encoding="utf-8")

    print(f"csv={csv_path}")
    print(f"runtime={runtime_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
