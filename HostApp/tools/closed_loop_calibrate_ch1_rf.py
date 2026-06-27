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

from host_app.rf_calibration import RfCalibrationTable
from host_app.scope_scpi import ScopeEndpoint, ScpiSocket, ScopeMeasurement, _normalize_channel, _parse_siglent_pava


@dataclass(frozen=True)
class ClosedLoopPoint:
    freq_hz: float
    target_vpp: float
    measured_vpp: float
    measured_vpk: float
    old_correction_factor: float
    new_correction_factor: float
    relay_atten_mask: int
    amp_code: int
    ftw: str
    measured_freq_hz: float
    vdiv_v: float
    raw_pava: str


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


def set_verified_vdiv(
    instrument: ScpiSocket,
    channel: str,
    target_vdiv: float,
    attempts: int = 3,
    settle_s: float = 0.8,
) -> float:
    source = _normalize_channel(channel, "C")
    command_value = format_siglent_vdiv(target_vdiv)
    tolerance = max(0.002, target_vdiv * 0.02)
    last_raw = ""
    for _attempt in range(attempts):
        instrument.write(f"{source}:VDIV {command_value}")
        time.sleep(settle_s)
        last_raw = instrument.query_text(f"{source}:VDIV?")
        measured = parse_vdiv_response(last_raw)
        if measured is not None and abs(measured - target_vdiv) <= tolerance:
            return measured
    raise RuntimeError(
        f"Failed to set {source}:VDIV to {target_vdiv:g} V/div; last response was {last_raw!r}"
    )


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
        freq_raw = ""
        if read_freq:
            freq_raw = instrument.query_text(f"{source}:PAVA? FREQ")
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
    measured_vpp = sum(measured_vpps) / len(measured_vpps)
    measured_freq = sum(measured_freqs) / len(measured_freqs) if measured_freqs else 0.0
    return measured_vpp, measured_freq, " | ".join(raw_values)


def vivado_launcher() -> list[str]:
    candidate = shutil.which("vivado.bat") or r"D:\Xilinx\Vivado\2020.2\bin\vivado.bat"
    if Path(candidate).exists():
        return ["cmd.exe", "/d", "/c", candidate]
    candidate = shutil.which("vivado") or "vivado"
    return [candidate]


class PersistentVio:
    def __init__(self, repo_root: Path, timeout_s: float = 120.0):
        self.repo_root = repo_root
        self.timeout_s = timeout_s
        self.proc: subprocess.Popen[str] | None = None
        self.lines: "queue.Queue[str]" = queue.Queue()
        self.reader: threading.Thread | None = None

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
        self.reader = threading.Thread(target=self._read_lines, daemon=True)
        self.reader.start()
        self._wait_for("K5VIO_READY")
        return self

    def __exit__(self, _exc_type, _exc, _tb) -> None:
        if self.proc is not None and self.proc.poll() is None:
            try:
                self._write("exit")
                self.proc.wait(timeout=20.0)
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

    def apply(self, amp_code: int, ftw: int, relay_mask: int, index: int) -> None:
        marker = f"K5VIO_DONE_{index}"
        self._write(f"ku5p_vio_apply {amp_code:04x} {ftw:012x} 0000 000000000000 {relay_mask:01x} 1")
        self._write(f"puts {marker}")
        self._wait_for(marker)


def ftw_for(freq_hz: float, nco_hz: float) -> int:
    return int(round(freq_hz / nco_hz * (1 << 48))) & 0xFFFFFFFFFFFF


def fit_linear_amplitude_model(rows: list[ClosedLoopPoint], timestamp: str) -> dict[str, object] | None:
    points = [
        {
            "freq_hz": row.freq_hz,
            "target_vpp": row.target_vpp,
            "correction_factor": row.new_correction_factor,
            "measured_vpp": row.measured_vpp,
            "old_correction_factor": row.old_correction_factor,
        }
        for row in rows
    ]
    if not points:
        return None
    return {
        "type": "correction_factor_linear_v1",
        "source": "closed_loop_scope_sweep",
        "created_at": timestamp,
        "description": "Final correction_factor is interpolated over frequency and target_vpp; points are old_correction_factor*target_vpp/measured_vpp.",
        "min_correction_factor": 0.25,
        "max_correction_factor": 4.0,
        "points": points,
    }


def merge_correction_factor_model(
    existing_model: object,
    new_model: dict[str, object] | None,
    timestamp: str,
) -> dict[str, object] | None:
    if new_model is None:
        return existing_model if isinstance(existing_model, dict) else None

    merged: dict[tuple[float, float], dict[str, object]] = {}
    if isinstance(existing_model, dict) and existing_model.get("type") == "correction_factor_linear_v1":
        for point in existing_model.get("points", []):
            if not isinstance(point, dict):
                continue
            if "freq_hz" not in point or "target_vpp" not in point:
                continue
            key = (float(point["freq_hz"]), float(point["target_vpp"]))
            merged[key] = dict(point)

    for point in new_model.get("points", []):
        if not isinstance(point, dict):
            continue
        key = (float(point["freq_hz"]), float(point["target_vpp"]))
        merged[key] = dict(point)

    model = dict(new_model)
    model["created_at"] = timestamp
    model["merged_from_existing"] = bool(merged)
    model["points"] = [merged[key] for key in sorted(merged)]
    return model


def main() -> int:
    parser = argparse.ArgumentParser(description="Closed-loop CH1 RF amplitude calibration.")
    parser.add_argument(
        "--target-vpp",
        type=float,
        action="append",
        default=None,
        help="Target output amplitude in Vpp. Repeat for multiple values.",
    )
    parser.add_argument("--settle", type=float, default=5.0)
    parser.add_argument("--between-captures", type=float, default=3.0)
    parser.add_argument("--vdiv-settle", type=float, default=2.0)
    parser.add_argument("--pava-samples", type=int, default=5)
    parser.add_argument("--pava-interval", type=float, default=0.6)
    parser.add_argument("--read-freq", action="store_true", help="Also log C1:PAVA? FREQ. Frequency is never corrected.")
    parser.add_argument("--min-valid-ratio", type=float, default=0.2)
    parser.add_argument("--scope-ip", default="10.9.122.88")
    parser.add_argument("--scope-port", type=int, default=5025)
    parser.add_argument("--scope-timeout", type=float, default=5.0)
    parser.add_argument("--channel", default="CHAN1")
    parser.add_argument(
        "--freq-mhz",
        type=float,
        action="append",
        default=None,
        help="Frequency point in MHz. Repeat to override the default sweep list.",
    )
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "calibration")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    cal = RfCalibrationTable.load_latest(repo_root)
    if cal is None:
        raise RuntimeError("No CH1 RF calibration table found.")

    freqs_mhz = args.freq_mhz or [10, 15, 20, 30, 50, 70, 100, 150, 200]
    target_vpps = args.target_vpp or [0.01, 0.03, 0.1, 0.3, 1.0, 2.0, 3.0]
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    out_dir = args.output_dir / f"ch1_rf_closed_loop_{timestamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    endpoint = ScopeEndpoint(args.scope_ip, args.scope_port, args.scope_timeout)
    rows: list[ClosedLoopPoint] = []
    csv_path = out_dir / "closed_loop_points.csv"

    source = _normalize_channel(args.channel, "C")
    with PersistentVio(repo_root) as vio, ScpiSocket(endpoint) as scope:
        idn = scope.query_text("*IDN?")
        print(f"scope={idn}", flush=True)
        scope.write("CHDR SHORT")
        total = len(freqs_mhz) * len(target_vpps)
        index = 0
        for target_vpp in target_vpps:
            vdiv = vdiv_for_target_vpp(target_vpp)
            actual_vdiv = set_verified_vdiv(scope, args.channel, vdiv)
            print(
                f"set {source}:VDIV={actual_vdiv:g} V/div for target {target_vpp:g} Vpp",
                flush=True,
            )
            time.sleep(args.vdiv_settle)
            for freq_mhz in freqs_mhz:
                index += 1
                freq_hz = freq_mhz * 1e6
                old_corr = cal.interpolate_correction_factor(freq_hz, target_vpp)
                result = cal.calculate(freq_hz, target_vpp / 2.0)
                ftw = ftw_for(freq_hz, result.nco_hz)
                print(
                    f"[{index}/{total}] {freq_mhz:.3f} MHz target={target_vpp:.4g} Vpp "
                    f"amp=0x{result.amp_code:04X} relay=0x{result.relay_atten_mask:02X}",
                    flush=True,
                )
                vio.apply(result.amp_code, ftw, result.relay_atten_mask, index)
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
                        f"Rejecting implausible scope measurement: target={target_vpp:g} Vpp, "
                        f"measured={measured_vpp:g} Vpp, raw={raw_pava}"
                    )
                measured_vpk = measured_vpp / 2.0
                ratio = target_vpp / measured_vpp if measured_vpp > 0.0 else 1.0
                new_corr = old_corr * ratio
                row = ClosedLoopPoint(
                    freq_hz=freq_hz,
                    target_vpp=target_vpp,
                    measured_vpp=measured_vpp,
                    measured_vpk=measured_vpk,
                    old_correction_factor=old_corr,
                    new_correction_factor=new_corr,
                    relay_atten_mask=result.relay_atten_mask,
                    amp_code=result.amp_code,
                    ftw=f"0x{ftw:012X}",
                    measured_freq_hz=measured_freq_hz,
                    vdiv_v=vdiv,
                    raw_pava=raw_pava,
                )
                rows.append(row)
                with csv_path.open("w", newline="", encoding="utf-8") as handle:
                    writer = csv.DictWriter(handle, fieldnames=list(asdict(rows[0]).keys()))
                    writer.writeheader()
                    for saved_row in rows:
                        writer.writerow(asdict(saved_row))
                print(f"  measured={measured_vpp:.6g} Vpp, ratio={ratio:.6g}, new_corr={new_corr:.6g}", flush=True)
                time.sleep(args.between_captures)

    if not rows:
        raise RuntimeError("No closed-loop calibration points were captured.")

    updated = dict(cal.data)
    updated["updated_at"] = timestamp
    model = merge_correction_factor_model(
        cal.data.get("amplitude_correction_model"),
        fit_linear_amplitude_model(rows, timestamp),
        timestamp,
    )
    if model is not None:
        updated["amplitude_correction_model"] = model
    existing_corrections = [
        point
        for point in cal.data.get("amplitude_corrections", [])
        if point.get("source") != "closed_loop_scope_sweep"
    ]
    updated["amplitude_corrections"] = existing_corrections + [
        {
            "freq_hz": row.freq_hz,
            "target_vpp": row.target_vpp,
            "measured_vpp": row.measured_vpp,
            "measured_freq_hz": row.measured_freq_hz,
            "vdiv_v": row.vdiv_v,
            "correction_factor": row.new_correction_factor,
            "old_correction_factor": row.old_correction_factor,
            "source": "closed_loop_scope_sweep",
            "created_at": timestamp,
        }
        for row in rows
    ]
    updated_path = out_dir / "rf_cal_10m_200m_ch1_runtime_closed_loop.json"
    updated_path.write_text(json.dumps(updated, indent=2), encoding="utf-8")
    latest_path = cal.path
    latest_path.write_text(json.dumps(updated, indent=2), encoding="utf-8")

    print(f"csv={csv_path}")
    print(f"updated_runtime={updated_path}")
    print(f"active_runtime={latest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
