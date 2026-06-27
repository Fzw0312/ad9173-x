from __future__ import annotations

import argparse
import csv
import json
import math
import shutil
import subprocess
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from host_app.scope_scpi import ScopeEndpoint, capture_scope_waveform, save_waveform_csv


DEFAULT_NCO_HZ = 1_474_560_000.0
AD9173_NCO_MAX_AMP = 0x50FF
RELAY_ATTENUATOR_STAGES_DB = (5.0, 10.0, 15.0, 20.0)


@dataclass(frozen=True)
class SweepPoint:
    freq_hz: float
    amp_code: int
    ftw: int
    relay_atten_mask: int
    measured_freq_hz: float
    measured_vpk: float
    measured_vpp: float
    measured_vrms: float
    waveform_csv: str


def ftw_for(freq_hz: float, nco_hz: float) -> int:
    return int(round(freq_hz / nco_hz * (1 << 48))) & 0xFFFFFFFFFFFF


def estimate_frequency(time_s: np.ndarray, voltage_v: np.ndarray) -> float:
    if time_s.size < 8 or voltage_v.size < 8:
        return 0.0
    y = voltage_v.astype(np.float64) - float(np.mean(voltage_v))
    dt = float(np.median(np.diff(time_s)))
    if dt <= 0.0:
        return 0.0
    window = np.hanning(y.size)
    spectrum = np.fft.rfft(y * window)
    freqs = np.fft.rfftfreq(y.size, dt)
    if spectrum.size <= 1:
        return 0.0
    mags = np.abs(spectrum)
    mags[0] = 0.0
    index = int(np.argmax(mags))
    return float(freqs[index])


def robust_vpk(voltage_v: np.ndarray) -> float:
    if voltage_v.size == 0:
        return 0.0
    high = float(np.percentile(voltage_v, 99.5))
    low = float(np.percentile(voltage_v, 0.5))
    return 0.5 * (high - low)


def run_vio_commands(commands: list[str], timeout_s: float) -> str:
    script = Path(__file__).resolve().parents[2] / "Prj" / "scripts" / "hw_runtime_vio_server.tcl"
    payload = "\n".join(commands + ["exit", ""]) 
    vivado_bat = (
        shutil.which("vivado.bat")
        or shutil.which("vivado")
        or r"D:\Xilinx\Vivado\2020.2\bin\vivado.bat"
    )
    if not Path(vivado_bat).exists() and shutil.which(vivado_bat) is None:
        raise FileNotFoundError(f"Cannot find Vivado launcher: {vivado_bat}")
    launcher = ["cmd.exe", "/d", "/c", vivado_bat] if vivado_bat.lower().endswith((".bat", ".cmd")) else [vivado_bat]
    proc = subprocess.run(
        launcher + ["-mode", "tcl", "-source", str(script)],
        input=payload,
        text=True,
        capture_output=True,
        timeout=timeout_s,
        cwd=str(Path(__file__).resolve().parents[2]),
    )
    output = (proc.stdout or "") + (proc.stderr or "")
    if proc.returncode != 0:
        raise RuntimeError(f"Vivado command failed with exit code {proc.returncode}\n{output}")
    if any(line.startswith("ERROR:") for line in output.splitlines()):
        raise RuntimeError(output)
    return output


def main() -> int:
    parser = argparse.ArgumentParser(description="Sweep-calibrate CH1 RF output with VIO and oscilloscope capture.")
    parser.add_argument("--channel", default="CHAN1")
    parser.add_argument("--scope-ip", default="10.9.122.165")
    parser.add_argument("--scope-port", type=int, default=5025)
    parser.add_argument("--scope-timeout", type=float, default=5.0)
    parser.add_argument("--points", type=int, default=20000)
    parser.add_argument("--settle", type=float, default=1.0)
    parser.add_argument("--amp-ratio", type=float, default=0.8)
    parser.add_argument("--relay-mask", type=lambda x: int(x, 0), default=0)
    parser.add_argument("--nco-hz", type=float, default=DEFAULT_NCO_HZ)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "calibration")
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    freqs_mhz = [10, 15, 20, 30, 40, 50, 70, 100, 130, 160, 180, 200]
    amp_code = max(0, min(AD9173_NCO_MAX_AMP, int(round(args.amp_ratio * AD9173_NCO_MAX_AMP))))
    relay_mask = max(0, min(15, int(args.relay_mask)))
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    out_dir = args.output_dir / f"ch1_rf_10m_200m_{timestamp}"
    wave_dir = out_dir / "waveforms"
    out_dir.mkdir(parents=True, exist_ok=True)
    wave_dir.mkdir(parents=True, exist_ok=True)

    points: list[SweepPoint] = []
    endpoint = ScopeEndpoint(args.scope_ip, args.scope_port, args.scope_timeout)

    plan = []
    for freq_mhz in freqs_mhz:
        freq_hz = freq_mhz * 1e6
        plan.append((freq_hz, ftw_for(freq_hz, args.nco_hz)))

    if args.dry_run:
        for freq_hz, ftw in plan:
            print(f"{freq_hz/1e6:8.3f} MHz amp=0x{amp_code:04X} ftw=0x{ftw:012X} relay=0x{relay_mask:02X}")
        return 0

    for index, (freq_hz, ftw) in enumerate(plan, 1):
        command = f"ku5p_vio_apply {amp_code:04x} {ftw:012x} 0000 000000000000 {relay_mask:01x} 1"
        print(f"[{index}/{len(plan)}] apply {freq_hz/1e6:.3f} MHz: {command}", flush=True)
        run_vio_commands([command], timeout_s=90.0)
        time.sleep(args.settle)
        capture = capture_scope_waveform(
            endpoint=endpoint,
            channel=args.channel,
            profile="siglent",
            points=args.points,
            mode="NORM",
        )
        measured_vpk = robust_vpk(capture.voltage_v)
        measured_vpp = float(np.max(capture.voltage_v) - np.min(capture.voltage_v))
        measured_vrms = float(np.sqrt(np.mean((capture.voltage_v - np.mean(capture.voltage_v)) ** 2)))
        measured_freq = estimate_frequency(capture.time_s, capture.voltage_v)
        waveform_csv = wave_dir / f"ch1_{int(round(freq_hz))}.csv"
        save_waveform_csv(capture, waveform_csv)
        point = SweepPoint(
            freq_hz=freq_hz,
            amp_code=amp_code,
            ftw=ftw,
            relay_atten_mask=relay_mask,
            measured_freq_hz=measured_freq,
            measured_vpk=measured_vpk,
            measured_vpp=measured_vpp,
            measured_vrms=measured_vrms,
            waveform_csv=str(waveform_csv),
        )
        points.append(point)
        print(
            f"  measured freq={measured_freq/1e6:.6f} MHz, "
            f"vpk={measured_vpk:.6g} V, vpp={measured_vpp:.6g} V",
            flush=True,
        )

    raw_points = [
        {
            "freq_hz": point.freq_hz,
            "raw_vpk": point.measured_vpk,
            "measured_freq_hz": point.measured_freq_hz,
            "amp_code": point.amp_code,
            "relay_atten_mask": point.relay_atten_mask,
            "ftw": f"0x{point.ftw:012X}",
        }
        for point in points
    ]
    cal = {
        "version": 1,
        "created_at": timestamp,
        "path": "ch1_rf_dac0_hmc788_relay_attenuator",
        "amplitude_unit": "Vpk",
        "nco_hz": args.nco_hz,
        "preferred_amp_code": amp_code,
        "preferred_dac_scale_ratio": amp_code / AD9173_NCO_MAX_AMP,
        "relay_atten_mask": relay_mask,
        "relay_atten_db": sum(
            stage_db for bit, stage_db in enumerate(RELAY_ATTENUATOR_STAGES_DB)
            if relay_mask & (1 << bit)
        ),
        "points": raw_points,
    }
    json_path = out_dir / "rf_cal_10m_200m_ch1_raw.json"
    csv_path = out_dir / "rf_cal_10m_200m_ch1_raw.csv"
    json_path.write_text(json.dumps(cal, indent=2), encoding="utf-8")
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(asdict(points[0]).keys()))
        writer.writeheader()
        for point in points:
            writer.writerow(asdict(point))
    print(f"json={json_path}")
    print(f"csv={csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
