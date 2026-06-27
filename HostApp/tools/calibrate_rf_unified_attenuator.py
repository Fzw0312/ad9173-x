from __future__ import annotations

import argparse
import csv
import json
import time
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np

from closed_loop_calibrate_ch1_rf import (
    PersistentVio,
    ftw_for,
    query_pava_measurement,
    set_verified_vdiv,
)
from sweep_calibrate_ch1_rf import (
    AD9173_NCO_MAX_AMP,
    DEFAULT_NCO_HZ,
    RELAY_ATTENUATOR_STAGES_DB,
    estimate_frequency,
    robust_vpk,
)

from host_app.rf_calibration import RfCalibrationTable
from host_app.scope_scpi import DEFAULT_SCOPE_IP, ScopeEndpoint, ScpiSocket, _capture_siglent, _normalize_channel
from host_app.scope_scpi import save_waveform_csv


DEFAULT_FREQS_MHZ = [0.1, 0.5, 1, 2, 5, 10, 15, 20, 30, 40, 50, 70, 100, 130, 160, 180, 200]
DEFAULT_TARGET_VPPS = [0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 0.8, 1.0, 1.5, 2.0, 2.5, 3.0]
SIGLENT_VERTICAL_DIVS = 8.0


@dataclass(frozen=True)
class RawPoint:
    freq_hz: float
    amp_code: int
    ftw: str
    relay_atten_mask: int
    measured_freq_hz: float
    raw_vpk: float
    raw_vpp: float
    measured_vrms: float
    waveform_csv: str
    waveform_vpp: float
    waveform_freq_hz: float
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


def relay_db_from_mask(mask: int) -> float:
    return sum(stage_db for bit, stage_db in enumerate(RELAY_ATTENUATOR_STAGES_DB) if mask & (1 << bit))


def vdiv_for_expected_vpp(expected_vpp: float) -> float:
    expected_vpp = max(float(expected_vpp), 0.001)
    required_vdiv = expected_vpp * 1.25 / SIGLENT_VERTICAL_DIVS
    for vdiv in (0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0):
        if vdiv >= required_vdiv:
            return vdiv
    return 2.0


def next_vdiv(vdiv: float) -> float:
    legal_vdivs = (0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 2.0)
    for candidate in legal_vdivs:
        if candidate > vdiv:
            return candidate
    return legal_vdivs[-1]


def tdiv_for_frequency(freq_hz: float, cycles_on_screen: float = 8.0) -> float:
    freq_hz = max(float(freq_hz), 1.0)
    required_tdiv = cycles_on_screen / freq_hz / 14.0
    for tdiv in (
        1e-9,
        2e-9,
        5e-9,
        10e-9,
        20e-9,
        50e-9,
        100e-9,
        200e-9,
        500e-9,
        1e-6,
        2e-6,
        5e-6,
        10e-6,
        20e-6,
        50e-6,
        100e-6,
        200e-6,
        500e-6,
        1e-3,
        2e-3,
        5e-3,
        10e-3,
        20e-3,
        50e-3,
        100e-3,
    ):
        if tdiv >= required_tdiv:
            return tdiv
    return 100e-3


def write_csv(path: Path, rows: list[object]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(asdict(rows[0]).keys()))
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def capture_nonempty_waveform(
    instrument: ScpiSocket,
    idn: str,
    channel: str,
    points: int,
    attempts: int = 3,
    retry_delay_s: float = 0.8,
):
    last_error: Exception | None = None
    for attempt in range(1, attempts + 1):
        try:
            capture = _capture_siglent(instrument, idn, channel, points)
            if capture.voltage_v.size and capture.time_s.size:
                return capture
            last_error = RuntimeError(f"empty waveform on attempt {attempt}")
        except Exception as exc:
            last_error = exc
        time.sleep(retry_delay_s)
    raise RuntimeError(f"Failed to capture a non-empty waveform after {attempts} attempts") from last_error


def reopen_scope(instrument: ScpiSocket) -> None:
    instrument.close()
    time.sleep(0.5)
    instrument.open()
    instrument.write("CHDR SHORT")


def query_idn_retry(instrument: ScpiSocket, retries: int = 3) -> str:
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            return instrument.query_text("*IDN?")
        except Exception as exc:
            last_error = exc
            print(f"  *IDN? retry {attempt}/{retries}: {exc}", flush=True)
            reopen_scope(instrument)
    raise RuntimeError(f"Failed to query scope *IDN? after {retries} retries") from last_error


def disable_bandwidth_limit(instrument: ScpiSocket, channel: str) -> str:
    source = _normalize_channel(channel, "C")
    instrument.write(f"{source}:BWL OFF")
    time.sleep(0.2)
    try:
        return instrument.query_text(f"{source}:BWL?")
    except Exception as exc:
        return f"query failed: {exc}"


def set_verified_vdiv_retry(
    instrument: ScpiSocket,
    channel: str,
    target_vdiv: float,
    settle_s: float,
    retries: int = 3,
) -> float:
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            return set_verified_vdiv(instrument, channel, target_vdiv, settle_s=settle_s)
        except Exception as exc:
            last_error = exc
            print(f"  VDIV retry {attempt}/{retries}: {exc}", flush=True)
            reopen_scope(instrument)
    raise RuntimeError(f"Failed to set verified VDIV after {retries} retries") from last_error


def set_tdiv_best_effort(instrument: ScpiSocket, tdiv_s: float, settle_s: float) -> str:
    instrument.write(f"TDIV {tdiv_s:.3G}")
    time.sleep(settle_s)
    try:
        return instrument.query_text("TDIV?")
    except Exception as exc:
        return f"query failed: {exc}"


def query_pava_measurement_retry(
    instrument: ScpiSocket,
    channel: str,
    samples: int,
    interval_s: float,
    read_freq: bool,
    retries: int = 3,
) -> tuple[float, float, str]:
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            return query_pava_measurement(instrument, channel, samples, interval_s, read_freq=read_freq)
        except Exception as exc:
            last_error = exc
            print(f"  PAVA retry {attempt}/{retries}: {exc}", flush=True)
            reopen_scope(instrument)
    raise RuntimeError(f"Failed to query PAVA after {retries} retries") from last_error


def measure_pkpk_with_autoscale(
    instrument: ScpiSocket,
    channel: str,
    initial_vdiv: float,
    samples: int,
    interval_s: float,
    read_freq: bool,
    settle_s: float,
    source: str,
) -> tuple[float, float, str, float]:
    vdiv = initial_vdiv
    for attempt in range(4):
        actual_vdiv = set_verified_vdiv_retry(instrument, channel, vdiv, settle_s=settle_s)
        print(f"set {source}:VDIV={actual_vdiv:g} V/div", flush=True)
        measured_vpp, measured_freq_hz, raw_pava = query_pava_measurement_retry(
            instrument,
            channel,
            samples,
            interval_s,
            read_freq=read_freq,
        )
        vertical_span_vpp = actual_vdiv * SIGLENT_VERTICAL_DIVS
        if measured_vpp <= vertical_span_vpp * 0.78 or actual_vdiv >= 2.0:
            return measured_vpp, measured_freq_hz, raw_pava, actual_vdiv
        vdiv = next_vdiv(actual_vdiv)
        print(
            f"  measured {measured_vpp:.6g} Vpp is close to {vertical_span_vpp:.6g} Vpp span; "
            f"retrying at {vdiv:g} V/div",
            flush=True,
        )
    return measured_vpp, measured_freq_hz, raw_pava, actual_vdiv


def build_calibration_payload(
    *,
    timestamp: str,
    args: argparse.Namespace,
    raw_rows: list[RawPoint],
    closed_rows: list[ClosedLoopPoint],
) -> dict[str, object]:
    raw_points = [
        {
            "freq_hz": row.freq_hz,
            "raw_vpk": row.raw_vpk,
            "measured_freq_hz": row.measured_freq_hz,
            "amp_code": row.amp_code,
            "relay_atten_mask": row.relay_atten_mask,
            "ftw": row.ftw,
        }
        for row in raw_rows
    ]
    payload: dict[str, object] = {
        "version": 2,
        "created_at": timestamp,
        "updated_at": timestamp,
        "source": "rf_unified_attenuator_scope_sweep",
        "path": "rf_dac0_after_switch_unified_relay_attenuator",
        "description": (
            "RF path calibration after the RF/LF switch, using the shared 4-bit relay attenuator. "
            "Scope waveform/measurements are read from the configured oscilloscope channel."
        ),
        "frequency_range_hz": [min(point.freq_hz for point in raw_rows), max(point.freq_hz for point in raw_rows)],
        "target_amplitude_range_vpp": [min(args.target_vpp), max(args.target_vpp)],
        "measurement_channel": args.channel,
        "scope_ip": args.scope_ip,
        "output_path": "rf",
        "output_path_sel": 1,
        "amplitude_unit": "Vpk",
        "nco_hz": args.nco_hz,
        "preferred_amp_code": int(round(args.bootstrap_amp_ratio * AD9173_NCO_MAX_AMP)),
        "nco_max_amp_code": AD9173_NCO_MAX_AMP,
        "preferred_dac_scale_ratio": args.bootstrap_amp_ratio,
        "relay_attenuator_step_db": 5.0,
        "relay_attenuator_max_mask": 15,
        "relay_attenuator_stages_db": list(RELAY_ATTENUATOR_STAGES_DB),
        "relay_atten_mask": args.bootstrap_relay_mask,
        "relay_atten_db": relay_db_from_mask(args.bootstrap_relay_mask),
        "points": raw_points,
        "notes": [
            "This table replaces the older RF PE43711-only calibration assumption.",
            "The relay attenuator is shared after the RF/LF switch; RF and LF should each have separate amplitude correction tables.",
            "Amplitude targets are Vpp because the closed-loop measurement uses oscilloscope PKPK.",
        ],
    }
    if closed_rows:
        payload["amplitude_correction_model"] = {
            "type": "correction_factor_linear_v1",
            "source": "rf_unified_attenuator_closed_loop_scope_sweep",
            "created_at": timestamp,
            "description": (
                "Final correction_factor is interpolated over frequency and target_vpp; "
                "points are old_correction_factor*target_vpp/measured_vpp."
            ),
            "min_correction_factor": 0.25,
            "max_correction_factor": 4.0,
            "points": [
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
            ],
        }
        payload["amplitude_corrections"] = [
            {
                "freq_hz": row.freq_hz,
                "target_vpp": row.target_vpp,
                "measured_vpp": row.measured_vpp,
                "measured_freq_hz": row.measured_freq_hz,
                "vdiv_v": row.vdiv_v,
                "correction_factor": row.new_correction_factor,
                "old_correction_factor": row.old_correction_factor,
                "source": "rf_unified_attenuator_closed_loop_scope_sweep",
                "created_at": timestamp,
            }
            for row in closed_rows
        ]
    return payload


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Start a fresh RF calibration for the post-switch shared relay attenuator. "
            "Defaults measure oscilloscope CH2 and close the loop over 10 mVpp to 3 Vpp."
        )
    )
    parser.add_argument("--scope-ip", default="10.9.122.184")
    parser.add_argument("--scope-port", type=int, default=5025)
    parser.add_argument("--scope-timeout", type=float, default=5.0)
    parser.add_argument("--channel", default="CHAN2", help="Oscilloscope channel carrying the RF output waveform.")
    parser.add_argument("--points", type=int, default=20000, help="Waveform points for raw response capture.")
    parser.add_argument("--raw-vdiv", type=float, default=1.0, help="Oscilloscope V/div used for the raw RF sweep.")
    parser.add_argument("--settle", type=float, default=2.0)
    parser.add_argument("--between-captures", type=float, default=1.0)
    parser.add_argument("--vdiv-settle", type=float, default=1.0)
    parser.add_argument("--auto-tdiv", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--tdiv-settle", type=float, default=0.4)
    parser.add_argument("--pava-samples", type=int, default=6)
    parser.add_argument("--pava-interval", type=float, default=0.35)
    parser.add_argument("--raw-pava-samples", type=int, default=4)
    parser.add_argument("--min-valid-ratio", type=float, default=0.25)
    parser.add_argument("--bootstrap-amp-ratio", type=float, default=1.0)
    parser.add_argument("--bootstrap-relay-mask", type=lambda text: int(text, 0), default=0)
    parser.add_argument("--nco-hz", type=float, default=DEFAULT_NCO_HZ)
    parser.add_argument(
        "--base-calibration",
        type=Path,
        default=None,
        help="Existing runtime JSON whose correction model is used for this refinement pass.",
    )
    parser.add_argument("--raw-only", action="store_true", help="Only build the raw frequency-response table.")
    parser.add_argument("--dry-run", action="store_true", help="Print the VIO plan without touching hardware.")
    parser.add_argument(
        "--freq-mhz",
        type=float,
        action="append",
        default=None,
        help="Frequency point in MHz. Repeat to override the default 10-200 MHz list.",
    )
    parser.add_argument(
        "--target-vpp",
        type=float,
        action="append",
        default=None,
        help="Closed-loop target amplitude in Vpp. Repeat to override defaults.",
    )
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "calibration")
    args = parser.parse_args()
    args.freq_mhz = args.freq_mhz or DEFAULT_FREQS_MHZ
    args.target_vpp = args.target_vpp or DEFAULT_TARGET_VPPS
    args.bootstrap_amp_ratio = max(0.01, min(1.0, float(args.bootstrap_amp_ratio)))
    args.bootstrap_relay_mask = max(0, min(15, int(args.bootstrap_relay_mask)))
    return args


def main() -> int:
    args = parse_args()
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    repo_root = Path(__file__).resolve().parents[2]
    out_dir = args.output_dir / f"ch1_rf_unified_attenuator_{timestamp}"
    wave_dir = out_dir / "waveforms"
    out_dir.mkdir(parents=True, exist_ok=True)
    wave_dir.mkdir(parents=True, exist_ok=True)
    raw_csv = out_dir / "rf_unified_raw_points.csv"
    closed_csv = out_dir / "rf_unified_closed_loop_points.csv"
    runtime_json = out_dir / "rf_cal_10m_200m_ch1_runtime.json"
    endpoint = ScopeEndpoint(args.scope_ip, args.scope_port, args.scope_timeout)
    source = _normalize_channel(args.channel, "C")
    amp_code = int(round(args.bootstrap_amp_ratio * AD9173_NCO_MAX_AMP))

    plan = [(freq_mhz * 1e6, ftw_for(freq_mhz * 1e6, args.nco_hz)) for freq_mhz in args.freq_mhz]
    if args.dry_run:
        print(f"scope_channel={source} output_path_sel=1 relay_bootstrap=0x{args.bootstrap_relay_mask:X}")
        for freq_hz, ftw in plan:
            print(f"RAW {freq_hz/1e6:8.3f} MHz amp=0x{amp_code:04X} ftw=0x{ftw:012X}")
        if not args.raw_only:
            for target_vpp in args.target_vpp:
                for freq_hz, _ftw in plan:
                    print(f"CLOSED {freq_hz/1e6:8.3f} MHz target={target_vpp:g} Vpp")
        return 0

    raw_rows: list[RawPoint] = []
    closed_rows: list[ClosedLoopPoint] = []
    with PersistentVio(repo_root) as vio, ScpiSocket(endpoint) as scope:
        idn = query_idn_retry(scope)
        print(f"scope={idn}", flush=True)
        scope.write("CHDR SHORT")
        bwl_state = disable_bandwidth_limit(scope, args.channel)
        print(f"set {source}:BWL OFF -> {bwl_state}", flush=True)
        actual_raw_vdiv = set_verified_vdiv_retry(scope, args.channel, args.raw_vdiv, settle_s=args.vdiv_settle)
        print(f"set {source}:VDIV={actual_raw_vdiv:g} V/div for raw sweep", flush=True)

        for index, (freq_hz, ftw) in enumerate(plan, start=1):
            if args.auto_tdiv:
                tdiv = tdiv_for_frequency(freq_hz)
                actual_tdiv = set_tdiv_best_effort(scope, tdiv, args.tdiv_settle)
                print(f"set TDIV={tdiv:.3G}s/div for {freq_hz/1e6:.6g} MHz -> {actual_tdiv}", flush=True)
            print(
                f"[raw {index}/{len(plan)}] {freq_hz/1e6:.3f} MHz "
                f"amp=0x{amp_code:04X} relay=0x{args.bootstrap_relay_mask:X} channel={source}",
                flush=True,
            )
            vio.apply(amp_code, ftw, args.bootstrap_relay_mask, index)
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
            capture = capture_nonempty_waveform(scope, idn, args.channel, args.points)
            waveform_vpk = robust_vpk(capture.voltage_v)
            waveform_vpp = float(np.max(capture.voltage_v) - np.min(capture.voltage_v))
            measured_vrms = float(np.sqrt(np.mean((capture.voltage_v - np.mean(capture.voltage_v)) ** 2)))
            waveform_freq = estimate_frequency(capture.time_s, capture.voltage_v)
            waveform_csv = wave_dir / f"rf_{source.lower()}_raw_{int(round(freq_hz))}.csv"
            save_waveform_csv(capture, waveform_csv)
            row = RawPoint(
                freq_hz=freq_hz,
                amp_code=amp_code,
                ftw=f"0x{ftw:012X}",
                relay_atten_mask=args.bootstrap_relay_mask,
                measured_freq_hz=measured_freq_hz,
                raw_vpk=measured_vpp / 2.0,
                raw_vpp=measured_vpp,
                measured_vrms=measured_vrms,
                waveform_csv=str(waveform_csv),
                waveform_vpp=waveform_vpp,
                waveform_freq_hz=waveform_freq,
                raw_pava=raw_pava,
            )
            raw_rows.append(row)
            write_csv(raw_csv, raw_rows)
            print(
                f"  raw_vpp={measured_vpp:.6g} Vpp raw_vpk={measured_vpp/2.0:.6g} Vpk "
                f"waveform_vpp={waveform_vpp:.6g} Vpp",
                flush=True,
            )
            time.sleep(args.between_captures)

        payload = build_calibration_payload(timestamp=timestamp, args=args, raw_rows=raw_rows, closed_rows=[])
        if args.base_calibration is not None:
            base_data = json.loads(args.base_calibration.read_text(encoding="utf-8"))
            if "amplitude_correction_model" in base_data:
                payload["amplitude_correction_model"] = base_data["amplitude_correction_model"]
            if "amplitude_corrections" in base_data:
                payload["amplitude_corrections"] = base_data["amplitude_corrections"]
        runtime_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")

        if not args.raw_only:
            cal = RfCalibrationTable(runtime_json)
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
                        f"[closed {closed_index}/{total}] {freq_hz/1e6:.3f} MHz "
                        f"target={target_vpp:g} Vpp amp=0x{result.amp_code:04X} "
                        f"relay=0x{result.relay_atten_mask:X}",
                        flush=True,
                    )
                    vio.apply(result.amp_code, ftw, result.relay_atten_mask, 1000 + closed_index)
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
                            f"Rejecting implausible scope measurement: target={target_vpp:g} Vpp, "
                            f"measured={measured_vpp:g} Vpp, raw={raw_pava}"
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
                    )
                    closed_rows.append(row)
                    write_csv(closed_csv, closed_rows)
                    payload = build_calibration_payload(
                        timestamp=timestamp,
                        args=args,
                        raw_rows=raw_rows,
                        closed_rows=closed_rows,
                    )
                    runtime_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")
                    print(
                        f"  measured={measured_vpp:.6g} Vpp "
                        f"error={(measured_vpp - target_vpp) / target_vpp * 100.0:+.2f}% "
                        f"new_corr={new_corr:.6g}",
                        flush=True,
                    )
                    time.sleep(args.between_captures)

    print(f"raw_csv={raw_csv}")
    print(f"closed_loop_csv={closed_csv if closed_rows else ''}")
    print(f"runtime_json={runtime_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
