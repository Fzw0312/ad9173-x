from __future__ import annotations

import argparse
import csv
import time
from dataclasses import asdict, dataclass
from pathlib import Path

from calibrate_lf_unified_attenuator import LfPersistentVio, ftw_for, tdiv_for_frequency
from calibrate_rf_unified_attenuator import (
    ScpiSocket,
    ScopeEndpoint,
    _normalize_channel,
    disable_bandwidth_limit,
    measure_pkpk_with_autoscale,
    set_tdiv_best_effort,
    vdiv_for_expected_vpp,
)
from host_app.lf_calibration import LfCalibrationTable


@dataclass(frozen=True)
class VerifyPoint:
    index: int
    freq_hz: float
    target_vpp: float
    amp_code: int
    ftw: str
    relay_atten_mask: int
    relay_atten_db: float
    expected_vpp: float
    measured_vpp: float
    measured_freq_hz: float
    error_pct: float
    correction_factor: float
    vdiv_v: float
    raw_pava: str


def parse_point(text: str) -> tuple[float, float]:
    parts = [float(part.strip()) for part in text.split(",")]
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("point must be freq_hz,target_vpp")
    return parts[0], parts[1]


def error_pct(measured: float, target: float) -> float:
    if target == 0.0:
        return 0.0
    return (measured - target) / target * 100.0


def write_csv(path: Path, rows: list[VerifyPoint]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(asdict(rows[0]).keys()))
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify LF calibration through the post-switch relay attenuator.")
    parser.add_argument("--scope-ip", default="10.9.122.184")
    parser.add_argument("--scope-port", type=int, default=5025)
    parser.add_argument("--scope-timeout", type=float, default=8.0)
    parser.add_argument("--channel", default="CHAN2")
    parser.add_argument("--calibration", type=Path, default=None)
    parser.add_argument("--settle", type=float, default=2.0)
    parser.add_argument("--vdiv-settle", type=float, default=0.2)
    parser.add_argument("--pava-samples", type=int, default=8)
    parser.add_argument("--pava-interval", type=float, default=0.25)
    parser.add_argument("--auto-tdiv", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--tdiv-settle", type=float, default=0.2)
    parser.add_argument("--point", action="append", type=parse_point, default=None)
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "calibration",
    )
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[2]
    cal = LfCalibrationTable(args.calibration) if args.calibration is not None else LfCalibrationTable.load_latest(repo_root)
    if cal is None:
        raise RuntimeError("No completed LF calibration table found.")

    points = args.point or [
        (100e3, 0.01),
        (500e3, 0.02),
        (1.5e6, 0.05),
        (3e6, 0.1),
        (7e6, 0.2),
        (2.5e6, 0.5),
        (6e6, 1.0),
        (8e6, 1.5),
        (4e6, 2.0),
        (9e6, 2.5),
        (10e6, 3.0),
    ]

    timestamp = time.strftime("%Y%m%d_%H%M%S")
    out_dir = args.output_dir / f"dac1_lf_unified_verify_{timestamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = out_dir / "lf_unified_verify_points.csv"

    prepared = []
    print(f"LF table: {cal.path}")
    for index, (freq_hz, target_vpp) in enumerate(points, start=1):
        result = cal.calculate(freq_hz, target_vpp / 2.0)
        ftw = ftw_for(freq_hz, result.nco_hz)
        prepared.append((index, freq_hz, target_vpp, result, ftw))
        print(
            f"[{index}] {freq_hz:g} Hz {target_vpp:g} Vpp "
            f"amp=0x{result.amp_code:04X} ftw=0x{ftw:012X} relay=0x{result.relay_atten_mask:X} "
            f"expected={result.expected_vpp:.6g} Vpp corr={result.correction_factor:.6g}",
            flush=True,
        )

    if args.dry_run:
        print(f"csv={csv_path}")
        return 0

    rows: list[VerifyPoint] = []
    source = _normalize_channel(args.channel, "C")
    with LfPersistentVio(repo_root) as vio, ScpiSocket(ScopeEndpoint(args.scope_ip, args.scope_port, args.scope_timeout)) as scope:
        print(f"scope={scope.query_text('*IDN?')}", flush=True)
        scope.write("CHDR SHORT")
        bwl_state = disable_bandwidth_limit(scope, args.channel)
        print(f"set {source}:BWL OFF -> {bwl_state}", flush=True)

        for index, freq_hz, target_vpp, result, ftw in prepared:
            if args.auto_tdiv:
                tdiv = tdiv_for_frequency(freq_hz)
                actual_tdiv = set_tdiv_best_effort(scope, tdiv, args.tdiv_settle)
                print(f"[{index}] set TDIV={tdiv:.3G}s/div for {freq_hz:g} Hz -> {actual_tdiv}", flush=True)

            vdiv = max(vdiv_for_expected_vpp(target_vpp), vdiv_for_expected_vpp(result.expected_vpp))
            print(
                f"[{index}] apply LF {freq_hz:g} Hz target={target_vpp:g} Vpp "
                f"amp=0x{result.amp_code:04X} relay=0x{result.relay_atten_mask:X} vdiv={vdiv:g}",
                flush=True,
            )
            vio.apply_lf(result.amp_code, ftw, result.relay_atten_mask, 2000 + index)
            time.sleep(args.settle)
            measured_vpp, measured_freq_hz, raw_pava, actual_vdiv = measure_pkpk_with_autoscale(
                scope,
                args.channel,
                vdiv,
                max(1, args.pava_samples),
                max(0.1, args.pava_interval),
                read_freq=True,
                settle_s=args.vdiv_settle,
                source=source,
            )
            row = VerifyPoint(
                index=index,
                freq_hz=freq_hz,
                target_vpp=target_vpp,
                amp_code=result.amp_code,
                ftw=f"0x{ftw:012X}",
                relay_atten_mask=result.relay_atten_mask,
                relay_atten_db=result.relay_atten_db,
                expected_vpp=result.expected_vpp,
                measured_vpp=measured_vpp,
                measured_freq_hz=measured_freq_hz,
                error_pct=error_pct(measured_vpp, target_vpp),
                correction_factor=result.correction_factor,
                vdiv_v=actual_vdiv,
                raw_pava=raw_pava,
            )
            rows.append(row)
            write_csv(csv_path, rows)
            print(
                f"[{index}] measured={measured_vpp:.6g} Vpp "
                f"freq={measured_freq_hz:.6g} Hz err={row.error_pct:+.2f}%",
                flush=True,
            )

    print(f"csv={csv_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
