from __future__ import annotations

import argparse
import csv
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from closed_loop_calibrate_ch1_rf import (  # noqa: E402
    PersistentVio,
    ftw_for,
    query_pava_measurement,
    set_verified_vdiv,
    vdiv_for_target_vpp,
)
from host_app.lf_calibration import LfCalibrationTable  # noqa: E402
from host_app.rf_calibration import RfCalibrationTable  # noqa: E402
from host_app.scope_scpi import ScopeEndpoint, ScpiSocket  # noqa: E402


@dataclass(frozen=True)
class VerifyPoint:
    index: int
    rf_freq_hz: float
    rf_target_vpp: float
    rf_amp_code: int
    rf_ftw: str
    rf_pe43711_code: int
    rf_measured_vpp: float
    rf_error_pct: float
    lf_freq_hz: float
    lf_target_vpp: float
    lf_amp_code: int
    lf_ftw: str
    lf_measured_vpp: float
    lf_error_pct: float
    raw_rf: str
    raw_lf: str


def parse_point(text: str) -> tuple[float, float, float, float]:
    parts = [float(part.strip()) for part in text.split(",")]
    if len(parts) != 4:
        raise argparse.ArgumentTypeError("point must be rf_mhz,rf_vpp,lf_mhz,lf_vpp")
    return parts[0] * 1e6, parts[1], parts[2] * 1e6, parts[3]


def error_pct(measured: float, target: float) -> float:
    if target == 0.0:
        return 0.0
    return (measured - target) / target * 100.0


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify RF CH1 and LF CH2 calibration together.")
    parser.add_argument("--scope-ip", default="10.9.122.103")
    parser.add_argument("--scope-port", type=int, default=5025)
    parser.add_argument("--scope-timeout", type=float, default=5.0)
    parser.add_argument("--rf-channel", default="CHAN1")
    parser.add_argument("--lf-channel", default="CHAN2")
    parser.add_argument("--pava-samples", type=int, default=8)
    parser.add_argument("--pava-interval", type=float, default=0.35)
    parser.add_argument("--settle", type=float, default=2.0)
    parser.add_argument("--path-sel", type=int, default=0)
    parser.add_argument("--dry-run", action="store_true", help="Only print the calculated VIO settings.")
    parser.add_argument(
        "--point",
        action="append",
        type=parse_point,
        default=None,
        help="Verification point as rf_mhz,rf_vpp,lf_mhz,lf_vpp. Repeat for multiple points.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "calibration",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    rf = RfCalibrationTable.load_latest(repo_root)
    lf = LfCalibrationTable.load_latest(repo_root)
    if rf is None:
        raise RuntimeError("No RF calibration table found.")
    if lf is None:
        raise RuntimeError("No LF calibration table found.")

    points = args.point or [
        (20e6, 1.0, 1e6, 1.0),
        (150e6, 1.5, 5e6, 1.0),
        (180e6, 2.5, 10e6, 0.3),
        (75e6, 0.3, 0.5e6, 0.3),
    ]
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    out_dir = args.output_dir / f"dual_rf_lf_verify_{timestamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "dual_verify_points.csv"

    print(f"RF table: {rf.path}")
    print(f"LF table: {lf.path}")

    prepared = []
    for index, (rf_freq, rf_vpp, lf_freq, lf_vpp) in enumerate(points, start=1):
        rf_result = rf.calculate(rf_freq, rf_vpp / 2.0)
        lf_result = lf.calculate(lf_freq, lf_vpp / 2.0)
        rf_ftw = ftw_for(rf_freq, rf_result.nco_hz)
        lf_ftw = ftw_for(lf_freq, lf_result.nco_hz)
        prepared.append((index, rf_freq, rf_vpp, rf_result, rf_ftw, lf_freq, lf_vpp, lf_result, lf_ftw))
        print(
            f"[{index}] RF {rf_freq/1e6:g}MHz {rf_vpp:g}Vpp "
            f"amp=0x{rf_result.amp_code:04X} ftw=0x{rf_ftw:012X} pe=0x{rf_result.pe43711_code:02X}; "
            f"LF {lf_freq/1e6:g}MHz {lf_vpp:g}Vpp amp=0x{lf_result.amp_code:04X} ftw=0x{lf_ftw:012X}"
        )

    if args.dry_run:
        return 0

    rows: list[VerifyPoint] = []
    endpoint = ScopeEndpoint(args.scope_ip, args.scope_port, args.scope_timeout)
    with PersistentVio(repo_root) as vio, ScpiSocket(endpoint) as scope:
        print(f"scope={scope.query_text('*IDN?')}")
        scope.write("CHDR SHORT")
        for index, rf_freq, rf_vpp, rf_result, rf_ftw, lf_freq, lf_vpp, lf_result, lf_ftw in prepared:
            rf_vdiv = set_verified_vdiv(scope, args.rf_channel, vdiv_for_target_vpp(rf_vpp))
            lf_vdiv = set_verified_vdiv(scope, args.lf_channel, vdiv_for_target_vpp(lf_vpp))
            print(f"[{index}] VDIV rf={rf_vdiv:g} lf={lf_vdiv:g}")
            marker = f"K5VIO_DONE_DUAL_{index}"
            vio._write(
                f"ku5p_vio_apply {rf_result.amp_code:04x} {rf_ftw:012x} "
                f"{lf_result.amp_code:04x} {lf_ftw:012x} {rf_result.pe43711_code:02x} {args.path_sel}"
            )
            vio._write(f"puts {marker}")
            vio._wait_for(marker)
            time.sleep(args.settle)
            rf_measured, _rf_freq_measured, raw_rf = query_pava_measurement(
                scope, args.rf_channel, args.pava_samples, args.pava_interval
            )
            lf_measured, _lf_freq_measured, raw_lf = query_pava_measurement(
                scope, args.lf_channel, args.pava_samples, args.pava_interval
            )
            row = VerifyPoint(
                index=index,
                rf_freq_hz=rf_freq,
                rf_target_vpp=rf_vpp,
                rf_amp_code=rf_result.amp_code,
                rf_ftw=f"0x{rf_ftw:012X}",
                rf_pe43711_code=rf_result.pe43711_code,
                rf_measured_vpp=rf_measured,
                rf_error_pct=error_pct(rf_measured, rf_vpp),
                lf_freq_hz=lf_freq,
                lf_target_vpp=lf_vpp,
                lf_amp_code=lf_result.amp_code,
                lf_ftw=f"0x{lf_ftw:012X}",
                lf_measured_vpp=lf_measured,
                lf_error_pct=error_pct(lf_measured, lf_vpp),
                raw_rf=raw_rf,
                raw_lf=raw_lf,
            )
            rows.append(row)
            print(
                f"[{index}] RF measured={rf_measured:.6g}Vpp err={row.rf_error_pct:+.2f}% | "
                f"LF measured={lf_measured:.6g}Vpp err={row.lf_error_pct:+.2f}%"
            )
            with csv_path.open("w", newline="", encoding="utf-8") as handle:
                writer = csv.DictWriter(handle, fieldnames=list(asdict(rows[0]).keys()))
                writer.writeheader()
                for saved in rows:
                    writer.writerow(asdict(saved))

    print(f"csv={csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
