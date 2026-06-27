from __future__ import annotations

import argparse
import csv
import json
import time
from dataclasses import asdict, dataclass
from pathlib import Path

from calibrate_rf_unified_attenuator import (
    DEFAULT_NCO_HZ,
    AD9173_NCO_MAX_AMP,
    RELAY_ATTENUATOR_STAGES_DB,
    ScpiSocket,
    ScopeEndpoint,
    PersistentVio,
    _normalize_channel,
    disable_bandwidth_limit,
    measure_pkpk_with_autoscale,
    set_tdiv_best_effort,
    set_verified_vdiv_retry,
    vdiv_for_expected_vpp,
)
from host_app.lf_calibration import LfCalibrationTable


PREFERRED_AMP_CODE = AD9173_NCO_MAX_AMP
SIGLENT_VERTICAL_DIVS = 8.0


class LfPersistentVio(PersistentVio):
    def apply_lf(self, amp_code: int, ftw: int, relay_mask: int, index: int) -> None:
        marker = f"K5VIO_DONE_LF_{index}"
        self._write(f"ku5p_vio_apply 0000 000000000000 {amp_code:04x} {ftw:012x} {relay_mask:01x} 0")
        self._write(f"puts {marker}")
        self._wait_for(marker)


@dataclass(frozen=True)
class RawPoint:
    freq_hz: float
    amp_code: int
    ftw: str
    relay_atten_mask: int
    measured_freq_hz: float
    raw_vpk: float
    raw_vpp: float
    raw_pava: str


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
    clipped: bool


def relay_db_from_mask(mask: int) -> float:
    return sum(stage_db for bit, stage_db in enumerate(RELAY_ATTENUATOR_STAGES_DB) if mask & (1 << bit))


def ftw_for(freq_hz: float, nco_hz: float = DEFAULT_NCO_HZ) -> int:
    return int(round(freq_hz / nco_hz * (1 << 48))) & 0xFFFFFFFFFFFF


def tdiv_for_frequency(freq_hz: float) -> float:
    period_s = 1.0 / max(float(freq_hz), 1e-12)
    return max(1e-7, min(0.2, period_s * 3.0))


def write_csv(path: Path, rows: list[object]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(asdict(rows[0]).keys()))
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def build_payload(
    *,
    timestamp: str,
    args: argparse.Namespace,
    raw_rows: list[RawPoint],
    closed_rows: list[ClosedLoopPoint],
) -> dict[str, object]:
    model_points = [
        {
            "freq_hz": row.freq_hz,
            "target_vpp": row.target_vpp,
            "correction_factor": row.new_correction_factor,
            "measured_vpp": row.measured_vpp,
            "old_correction_factor": row.old_correction_factor,
            "relay_atten_mask": row.relay_atten_mask,
            "amp_code": row.amp_code,
        }
        for row in closed_rows
        if not row.clipped
    ]
    payload: dict[str, object] = {
        "version": 2,
        "created_at": timestamp,
        "updated_at": timestamp,
        "source": "lf_unified_attenuator_scope_sweep",
        "path": "lf_dac1_after_switch_unified_relay_attenuator",
        "description": (
            "LF path calibration after the RF/LF switch, using the shared 4-bit relay attenuator. "
            "Scope waveform/measurements are read from the configured oscilloscope channel."
        ),
        "frequency_range_hz": [min(row.freq_hz for row in raw_rows), max(row.freq_hz for row in raw_rows)],
        "target_amplitude_range_vpp": [min(args.target_vpp), max(args.target_vpp)],
        "measurement_channel": args.channel,
        "scope_ip": args.scope_ip,
        "output_path": "lf",
        "output_path_sel": 0,
        "channel": "DAC1/LF",
        "amplitude_unit": "Vpk",
        "display_amplitude_unit": "Vpp",
        "nco_hz": args.nco_hz,
        "preferred_amp_code": PREFERRED_AMP_CODE,
        "nco_max_amp_code": AD9173_NCO_MAX_AMP,
        "relay_attenuator_step_db": 5.0,
        "relay_attenuator_max_mask": 15,
        "relay_attenuator_stages_db": list(RELAY_ATTENUATOR_STAGES_DB),
        "relay_atten_mask": args.bootstrap_relay_mask,
        "relay_atten_db": relay_db_from_mask(args.bootstrap_relay_mask),
        "points": [
            {
                "freq_hz": row.freq_hz,
                "raw_vpk": row.raw_vpk,
                "raw_vpp": row.raw_vpp,
                "measured_freq_hz": row.measured_freq_hz,
                "amp_code": row.amp_code,
                "relay_atten_mask": row.relay_atten_mask,
                "ftw": row.ftw,
            }
            for row in raw_rows
        ],
    "notes": [
            "LF and RF use separate calibration tables because the switch path gain and relay-loading behavior can differ.",
            "Amplitude targets are Vpp because the closed-loop measurement uses oscilloscope PKPK.",
            "The relay attenuator is shared after the RF/LF switch.",
        ],
        "completed": False,
    }
    if model_points:
        payload["amplitude_correction_model"] = {
            "type": "correction_factor_linear_v1",
            "source": "lf_unified_attenuator_closed_loop_scope_sweep",
            "created_at": timestamp,
            "description": "Final correction_factor is interpolated over frequency, target_vpp, and relay mask.",
            "min_correction_factor": 0.2,
            "max_correction_factor": 5.0,
            "points": model_points,
        }
        payload["amplitude_corrections"] = model_points
    else:
        payload["amplitude_correction_model"] = None
        payload["amplitude_corrections"] = []
    return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Calibrate the LF path through the post-switch shared relay attenuator.")
    parser.add_argument("--scope-ip", default="10.9.122.184")
    parser.add_argument("--scope-port", type=int, default=5025)
    parser.add_argument("--scope-timeout", type=float, default=8.0)
    parser.add_argument("--channel", default="CHAN2")
    parser.add_argument("--settle", type=float, default=2.0)
    parser.add_argument("--between-captures", type=float, default=0.5)
    parser.add_argument("--vdiv-settle", type=float, default=0.2)
    parser.add_argument("--auto-tdiv", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--tdiv-settle", type=float, default=0.2)
    parser.add_argument("--pava-samples", type=int, default=8)
    parser.add_argument("--raw-pava-samples", type=int, default=4)
    parser.add_argument("--pava-interval", type=float, default=0.25)
    parser.add_argument("--raw-vdiv", type=float, default=1.0)
    parser.add_argument("--min-valid-ratio", type=float, default=0.25)
    parser.add_argument("--bootstrap-relay-mask", type=lambda text: int(text, 0), default=0)
    parser.add_argument("--nco-hz", type=float, default=DEFAULT_NCO_HZ)
    parser.add_argument("--base-calibration", type=Path, default=None)
    parser.add_argument("--raw-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--freq-hz", type=float, action="append", default=None)
    parser.add_argument("--freq-khz", type=float, action="append", default=None)
    parser.add_argument("--freq-mhz", type=float, action="append", default=None)
    parser.add_argument("--target-vpp", type=float, action="append", default=None)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "calibration")
    args = parser.parse_args()
    freqs = [float(value) for value in (args.freq_hz or [])]
    freqs += [float(value) * 1e3 for value in (args.freq_khz or [])]
    freqs += [float(value) * 1e6 for value in (args.freq_mhz or [])]
    args.freq_hz_list = sorted(set(freqs or [1e3, 10e3, 100e3, 500e3, 1e6, 2e6, 5e6, 10e6]))
    args.target_vpp = args.target_vpp or [0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]
    args.bootstrap_relay_mask = max(0, min(15, int(args.bootstrap_relay_mask)))
    return args


def main() -> int:
    args = parse_args()
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    repo_root = Path(__file__).resolve().parents[2]
    out_dir = args.output_dir / f"dac1_lf_unified_attenuator_{timestamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    raw_csv = out_dir / "lf_unified_raw_points.csv"
    closed_csv = out_dir / "lf_unified_closed_loop_points.csv"
    runtime_json = out_dir / "lf_cal_dac1_runtime.json"
    source = _normalize_channel(args.channel, "C")
    plan = [(freq_hz, ftw_for(freq_hz, args.nco_hz)) for freq_hz in args.freq_hz_list]
    if args.dry_run:
        print(f"scope_channel={source} output_path_sel=0 relay_bootstrap=0x{args.bootstrap_relay_mask:X}")
        for freq_hz, ftw in plan:
            print(f"RAW {freq_hz:12.3f} Hz amp=0x{PREFERRED_AMP_CODE:04X} ftw=0x{ftw:012X}")
        for target_vpp in args.target_vpp:
            for freq_hz, _ftw in plan:
                print(f"CLOSED {freq_hz:12.3f} Hz target={target_vpp:g} Vpp")
        return 0

    raw_rows: list[RawPoint] = []
    closed_rows: list[ClosedLoopPoint] = []
    with LfPersistentVio(repo_root) as vio, ScpiSocket(ScopeEndpoint(args.scope_ip, args.scope_port, args.scope_timeout)) as scope:
        print(f"scope={scope.query_text('*IDN?')}", flush=True)
        scope.write("CHDR SHORT")
        bwl_state = disable_bandwidth_limit(scope, args.channel)
        print(f"set {source}:BWL OFF -> {bwl_state}", flush=True)
        set_verified_vdiv_retry(scope, args.channel, args.raw_vdiv, settle_s=args.vdiv_settle)
        for index, (freq_hz, ftw) in enumerate(plan, start=1):
            if args.auto_tdiv:
                tdiv = tdiv_for_frequency(freq_hz)
                actual_tdiv = set_tdiv_best_effort(scope, tdiv, args.tdiv_settle)
                print(f"set TDIV={tdiv:.3G}s/div for {freq_hz:g} Hz -> {actual_tdiv}", flush=True)
            print(f"[raw {index}/{len(plan)}] {freq_hz:g} Hz amp=0x{PREFERRED_AMP_CODE:04X} relay=0x{args.bootstrap_relay_mask:X}", flush=True)
            vio.apply_lf(PREFERRED_AMP_CODE, ftw, args.bootstrap_relay_mask, index)
            time.sleep(args.settle)
            measured_vpp, measured_freq_hz, raw_pava, _actual_vdiv = measure_pkpk_with_autoscale(
                scope,
                args.channel,
                args.raw_vdiv,
                max(1, args.raw_pava_samples),
                max(0.1, args.pava_interval),
                read_freq=True,
                settle_s=args.vdiv_settle,
                source=source,
            )
            row = RawPoint(
                freq_hz=freq_hz,
                amp_code=PREFERRED_AMP_CODE,
                ftw=f"0x{ftw:012X}",
                relay_atten_mask=args.bootstrap_relay_mask,
                measured_freq_hz=measured_freq_hz,
                raw_vpk=measured_vpp / 2.0,
                raw_vpp=measured_vpp,
                raw_pava=raw_pava,
            )
            raw_rows.append(row)
            write_csv(raw_csv, raw_rows)
            print(f"  raw_vpp={measured_vpp:.6g} Vpp raw_vpk={measured_vpp/2.0:.6g} Vpk", flush=True)
            time.sleep(args.between_captures)

        payload = build_payload(timestamp=timestamp, args=args, raw_rows=raw_rows, closed_rows=[])
        if args.base_calibration is not None:
            base_data = json.loads(args.base_calibration.read_text(encoding="utf-8"))
            if "amplitude_correction_model" in base_data:
                payload["amplitude_correction_model"] = base_data["amplitude_correction_model"]
            if "amplitude_corrections" in base_data:
                payload["amplitude_corrections"] = base_data["amplitude_corrections"]
        runtime_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")

        if not args.raw_only:
            cal = LfCalibrationTable(runtime_json)
            total = len(args.target_vpp) * len(plan)
            closed_index = 0
            for target_vpp in args.target_vpp:
                for freq_hz, _raw_ftw in plan:
                    closed_index += 1
                    old_corr = cal.interpolate_correction_factor(freq_hz, target_vpp)
                    result = cal.calculate(freq_hz, target_vpp / 2.0)
                    expected_vpp = max(target_vpp, result.expected_vpp)
                    vdiv = max(vdiv_for_expected_vpp(target_vpp), vdiv_for_expected_vpp(expected_vpp))
                    ftw = ftw_for(freq_hz, result.nco_hz)
                    print(
                        f"[closed {closed_index}/{total}] {freq_hz:g} Hz target={target_vpp:g} Vpp "
                        f"amp=0x{result.amp_code:04X} relay=0x{result.relay_atten_mask:X}",
                        flush=True,
                    )
                    vio.apply_lf(result.amp_code, ftw, result.relay_atten_mask, 1000 + closed_index)
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
                    if measured_vpp < target_vpp * args.min_valid_ratio:
                        raise RuntimeError(
                            f"Rejecting implausible scope measurement: target={target_vpp:g} Vpp, measured={measured_vpp:g} Vpp"
                        )
                    new_corr = old_corr * target_vpp / measured_vpp
                    row = ClosedLoopPoint(
                        freq_hz=freq_hz,
                        target_vpp=target_vpp,
                        measured_vpp=measured_vpp,
                        measured_vpk=measured_vpp / 2.0,
                        old_correction_factor=old_corr,
                        new_correction_factor=new_corr,
                        relay_atten_mask=result.relay_atten_mask,
                        amp_code=result.amp_code,
                        ftw=f"0x{ftw:012X}",
                        measured_freq_hz=measured_freq_hz,
                        vdiv_v=actual_vdiv,
                        raw_pava=raw_pava,
                        clipped=result.clipped,
                    )
                    closed_rows.append(row)
                    write_csv(closed_csv, closed_rows)
                    payload = build_payload(timestamp=timestamp, args=args, raw_rows=raw_rows, closed_rows=closed_rows)
                    runtime_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")
                    print(
                        f"  measured={measured_vpp:.6g} Vpp "
                        f"error={(measured_vpp - target_vpp) / target_vpp * 100.0:+.2f}% "
                        f"new_corr={new_corr:.6g}",
                        flush=True,
                    )
                    time.sleep(args.between_captures)

        payload = build_payload(timestamp=timestamp, args=args, raw_rows=raw_rows, closed_rows=closed_rows)
        payload["completed"] = True
        runtime_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(f"raw_csv={raw_csv}")
    print(f"closed_loop_csv={closed_csv if closed_rows else ''}")
    print(f"runtime_json={runtime_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
