from __future__ import annotations

import argparse
import csv
import json
import random
import sys
import time
from dataclasses import asdict, dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from calibrate_rf_unified_attenuator import (  # noqa: E402
    RELAY_ATTENUATOR_STAGES_DB,
    ScpiSocket,
    ScopeEndpoint,
    _normalize_channel,
    disable_bandwidth_limit,
    measure_pkpk_with_autoscale,
    set_tdiv_best_effort,
    vdiv_for_expected_vpp,
)
from host_app.lf_calibration import LfCalibrationTable  # noqa: E402
from host_app.models import ChannelSettings, NetworkSettings, RfSettings, WaveformSettings, build_config_payload  # noqa: E402
from host_app.udp_client import DAC_DDS_SAMPLE_RATE_HZ, UdpWaveformClient  # noqa: E402


JESD_SCALE_MAX = 0x7FFF
LF_JESD_SAFE_DRIVE_VPK = 0.85
LF_JESD_MAX_TARGET_VPK = 1.5
LF_JESD_MAX_TARGET_VPP = 2.0 * LF_JESD_MAX_TARGET_VPK
LF_JESD_SAFE_AMP_CODE = int(round(LF_JESD_SAFE_DRIVE_VPK * JESD_SCALE_MAX))
DEFAULT_FREQ_HZ = [1e3, 10e3, 100e3, 500e3, 1e6, 2e6, 5e6, 8e6, 10e6]
DEFAULT_TARGET_VPP = [0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0]


@dataclass(frozen=True)
class RawPoint:
    freq_hz: float
    amp_code: int
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
    measured_freq_hz: float
    vdiv_v: float
    raw_pava: str
    clipped: bool


@dataclass(frozen=True)
class VerifyPoint:
    index: int
    freq_hz: float
    target_vpp: float
    amp_code: int
    relay_atten_mask: int
    expected_vpp: float
    measured_vpp: float
    measured_freq_hz: float
    error_pct: float
    vdiv_v: float
    raw_pava: str


def relay_db_from_mask(mask: int) -> float:
    return sum(stage_db for bit, stage_db in enumerate(RELAY_ATTENUATOR_STAGES_DB) if mask & (1 << bit))


def tdiv_for_frequency(freq_hz: float) -> float:
    freq_hz = max(float(freq_hz), 1e-3)
    required = 6.0 / freq_hz / 14.0
    for tdiv in (
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
        200e-3,
    ):
        if tdiv >= required:
            return tdiv
    return 200e-3


def write_csv(path: Path, rows: list[object]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(asdict(rows[0]).keys()))
        writer.writeheader()
        for row in rows:
            writer.writerow(asdict(row))


def build_jesd_config(
    *,
    freq_hz: float,
    target_vpk: float,
    amp_code: int,
    relay_mask: int,
    source: str,
) -> dict[str, object]:
    target_vpk = max(0.0, min(float(target_vpk), LF_JESD_SAFE_DRIVE_VPK))
    channel = ChannelSettings(
        enabled=True,
        amplitude=target_vpk,
        amplitude_unit="V",
        frequency=float(freq_hz),
        frequency_unit="Hz",
    )
    rf = RfSettings(
        output_path="lf",
        target_amplitude_vpk=target_vpk,
        relay_atten_db=relay_db_from_mask(relay_mask),
        relay_atten_mask=relay_mask,
    )
    config = build_config_payload(
        WaveformSettings(sample_rate=DAC_DDS_SAMPLE_RATE_HZ / 1e6, sample_rate_unit="MSPS", dac_full_scale_vpk=1.0),
        [channel],
        source,
        "jesd_tone",
        rf,
    )
    config["rf"]["lf_calibration"] = {
        "enabled": True,
        "file": "",
        "freq_hz": float(freq_hz),
        "target_vpk": target_vpk,
        "raw_vpk": LF_JESD_SAFE_DRIVE_VPK,
        "raw_vpp": 2.0 * LF_JESD_SAFE_DRIVE_VPK,
        "relay_atten_mask": int(relay_mask) & 0x0F,
        "relay_atten_db": relay_db_from_mask(relay_mask),
        "amp_code": max(0, min(JESD_SCALE_MAX, int(round(amp_code)))),
        "amp_ratio": max(0.0, min(1.0, float(amp_code) / JESD_SCALE_MAX)),
        "expected_vpk": target_vpk,
        "expected_vpp": 2.0 * target_vpk,
        "nco_hz": DAC_DDS_SAMPLE_RATE_HZ,
        "correction_factor": 1.0,
        "clipped": False,
    }
    config["rf"]["relay_atten_mask"] = int(relay_mask) & 0x0F
    config["rf"]["relay_atten_db"] = relay_db_from_mask(relay_mask)
    config["rf"]["main_nco_hz"] = 0.0
    config["rf"]["target_frequency_hz"] = float(freq_hz)
    config["rf"]["jesd_if_hz"] = float(freq_hz)
    config["rf"]["jesd_main_nco_hz"] = 0.0
    config["rf"]["channel_nco_hz"] = float(freq_hz)
    return config


def send_lf_jesd(
    client: UdpWaveformClient,
    *,
    freq_hz: float,
    target_vpk: float,
    amp_code: int,
    relay_mask: int,
    source: str,
) -> int:
    config = build_jesd_config(
        freq_hz=freq_hz,
        target_vpk=target_vpk,
        amp_code=amp_code,
        relay_mask=relay_mask,
        source=source,
    )
    return client.send_config(config)


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
        "source": "lf_jesd_tone_unified_attenuator_scope_sweep",
        "output_mode": "jesd_tone",
        "path": "lf_dac1_jesd_tone_after_switch_unified_relay_attenuator",
        "description": (
            "LF JESD single-tone calibration after the RF/LF switch. "
            "The relay attenuator is used first; LF JESD digital drive is capped at the 0.85 Vpk setting to avoid clipping."
        ),
        "frequency_range_hz": [min(row.freq_hz for row in raw_rows), max(row.freq_hz for row in raw_rows)],
        "target_amplitude_range_vpp": [min(args.target_vpp), max(args.target_vpp)],
        "max_target_vpk": LF_JESD_MAX_TARGET_VPK,
        "max_safe_drive_vpk": LF_JESD_SAFE_DRIVE_VPK,
        "measurement_channel": args.channel,
        "scope_ip": args.scope_ip,
        "output_path": "lf",
        "output_path_sel": 0,
        "channel": "LF/DAC1 JESD single-tone",
        "amplitude_unit": "Vpk",
        "display_amplitude_unit": "Vpp",
        "nco_hz": DAC_DDS_SAMPLE_RATE_HZ,
        "preferred_amp_code": LF_JESD_SAFE_AMP_CODE,
        "nco_max_amp_code": LF_JESD_SAFE_AMP_CODE,
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
            }
            for row in raw_rows
        ],
        "notes": [
            "LF JESD single-tone uses 0x7FFF as the full-scale digital tone code.",
            "The 0.85 Vpk setting at relay 0x00 is treated as the safe drive ceiling; measured LF output there is the raw post-path gain.",
            "Targets are stored as Vpp because oscilloscope PKPK is used for closed-loop correction.",
        ],
        "completed": False,
    }
    if model_points:
        payload["amplitude_correction_model"] = {
            "type": "correction_factor_linear_v1",
            "source": "lf_jesd_tone_closed_loop_scope_sweep",
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


def parse_point(text: str) -> tuple[float, float]:
    parts = [float(part.strip()) for part in text.split(",")]
    if len(parts) != 2:
        raise argparse.ArgumentTypeError("point must be freq_hz,target_vpp")
    freq_hz, target_vpp = parts
    return freq_hz, min(target_vpp, LF_JESD_MAX_TARGET_VPP)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Calibrate LF JESD single-tone output through the shared relay attenuator.")
    parser.add_argument("--scope-ip", default="10.9.122.146")
    parser.add_argument("--scope-port", type=int, default=5025)
    parser.add_argument("--scope-timeout", type=float, default=8.0)
    parser.add_argument("--channel", default="CHAN2")
    parser.add_argument("--target-ip", default="255.255.255.255")
    parser.add_argument("--target-port", type=int, default=5005)
    parser.add_argument("--local-ip", default="10.9.122.153")
    parser.add_argument("--local-port", type=int, default=0)
    parser.add_argument("--max-datagram-bytes", type=int, default=1200)
    parser.add_argument("--settle", type=float, default=1.2)
    parser.add_argument("--between-captures", type=float, default=0.25)
    parser.add_argument("--vdiv-settle", type=float, default=0.2)
    parser.add_argument("--auto-tdiv", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--tdiv-settle", type=float, default=0.2)
    parser.add_argument("--pava-samples", type=int, default=5)
    parser.add_argument("--raw-pava-samples", type=int, default=4)
    parser.add_argument("--pava-interval", type=float, default=0.2)
    parser.add_argument("--raw-vdiv", type=float, default=0.5)
    parser.add_argument("--min-valid-ratio", type=float, default=0.25)
    parser.add_argument("--bootstrap-relay-mask", type=lambda text: int(text, 0), default=0)
    parser.add_argument("--base-calibration", type=Path, default=None)
    parser.add_argument("--raw-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--freq-hz", type=float, action="append", default=None)
    parser.add_argument("--freq-khz", type=float, action="append", default=None)
    parser.add_argument("--freq-mhz", type=float, action="append", default=None)
    parser.add_argument("--target-vpp", type=float, action="append", default=None)
    parser.add_argument("--target-vpk", type=float, action="append", default=None)
    parser.add_argument("--verify-count", type=int, default=8)
    parser.add_argument("--verify-warmup-count", type=int, default=1)
    parser.add_argument("--verify-point", action="append", type=parse_point, default=None)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "calibration")
    args = parser.parse_args()
    freqs = [float(value) for value in (args.freq_hz or [])]
    freqs += [float(value) * 1e3 for value in (args.freq_khz or [])]
    freqs += [float(value) * 1e6 for value in (args.freq_mhz or [])]
    args.freq_hz_list = sorted(set(freqs or DEFAULT_FREQ_HZ))
    target_vpp = [float(value) for value in (args.target_vpp or [])]
    target_vpp += [2.0 * float(value) for value in (args.target_vpk or [])]
    args.target_vpp = sorted(set(min(value, LF_JESD_MAX_TARGET_VPP) for value in (target_vpp or DEFAULT_TARGET_VPP)))
    args.bootstrap_relay_mask = max(0, min(15, int(args.bootstrap_relay_mask)))
    return args


def measure_point(
    *,
    scope: ScpiSocket,
    client: UdpWaveformClient,
    args: argparse.Namespace,
    source: str,
    freq_hz: float,
    target_vpp: float,
    amp_code: int,
    relay_mask: int,
    index_label: str,
) -> tuple[float, float, str, float]:
    if args.auto_tdiv:
        tdiv = tdiv_for_frequency(freq_hz)
        actual_tdiv = set_tdiv_best_effort(scope, tdiv, args.tdiv_settle)
        print(f"{index_label} set TDIV={tdiv:.3G}s/div for {freq_hz:g} Hz -> {actual_tdiv}", flush=True)
    vdiv = vdiv_for_expected_vpp(target_vpp)
    frames = send_lf_jesd(
        client,
        freq_hz=freq_hz,
        target_vpk=min(target_vpp / 2.0, LF_JESD_SAFE_DRIVE_VPK),
        amp_code=amp_code,
        relay_mask=relay_mask,
        source="lf_jesd_tone_cal",
    )
    print(
        f"{index_label} sent JESD LF {frames} frame(s): freq={freq_hz:g} Hz "
        f"target={target_vpp:g} Vpp amp=0x{amp_code:04X} relay=0x{relay_mask:X}",
        flush=True,
    )
    time.sleep(args.settle)
    return measure_pkpk_with_autoscale(
        scope,
        args.channel,
        vdiv,
        max(1, args.pava_samples),
        max(0.1, args.pava_interval),
        read_freq=True,
        settle_s=args.vdiv_settle,
        source=source,
    )


def main() -> int:
    args = parse_args()
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    out_dir = args.output_dir / f"dac1_lf_jesd_tone_{timestamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    raw_csv = out_dir / "lf_jesd_tone_raw_points.csv"
    closed_csv = out_dir / "lf_jesd_tone_closed_loop_points.csv"
    verify_csv = out_dir / "lf_jesd_tone_verify_points.csv"
    runtime_json = out_dir / "lf_jesd_tone_dac1_runtime.json"
    source = _normalize_channel(args.channel, "C")
    network = NetworkSettings(
        target_ip=args.target_ip,
        target_port=args.target_port,
        local_port=args.local_port,
        max_datagram_bytes=args.max_datagram_bytes,
        local_ip=args.local_ip,
    )

    if args.dry_run:
        print(f"scope_channel={source} udp={args.local_ip or 'OS auto'} -> {args.target_ip}:{args.target_port}")
        print(
            f"max_safe_drive={LF_JESD_SAFE_DRIVE_VPK:g} Vpk, "
            f"calibration_target_range<= {LF_JESD_MAX_TARGET_VPP:g} Vpp"
        )
        for freq_hz in args.freq_hz_list:
            print(f"RAW {freq_hz:12.3f} Hz amp=0x{LF_JESD_SAFE_AMP_CODE:04X} relay=0x{args.bootstrap_relay_mask:X}")
        for target_vpp in args.target_vpp:
            for freq_hz in args.freq_hz_list:
                print(f"CLOSED {freq_hz:12.3f} Hz target={target_vpp:g} Vpp")
        return 0

    raw_rows: list[RawPoint] = []
    closed_rows: list[ClosedLoopPoint] = []
    verify_rows: list[VerifyPoint] = []
    with ScpiSocket(ScopeEndpoint(args.scope_ip, args.scope_port, args.scope_timeout)) as scope:
        print(f"scope={scope.query_text('*IDN?')}", flush=True)
        scope.write("CHDR SHORT")
        bwl_state = disable_bandwidth_limit(scope, args.channel)
        print(f"set {source}:BWL OFF -> {bwl_state}", flush=True)
        client = UdpWaveformClient(network)

        for index, freq_hz in enumerate(args.freq_hz_list, start=1):
            measured_vpp, measured_freq_hz, raw_pava, _actual_vdiv = measure_point(
                scope=scope,
                client=client,
                args=args,
                source=source,
                freq_hz=freq_hz,
                target_vpp=LF_JESD_MAX_TARGET_VPP,
                amp_code=LF_JESD_SAFE_AMP_CODE,
                relay_mask=args.bootstrap_relay_mask,
                index_label=f"[raw {index}/{len(args.freq_hz_list)}]",
            )
            row = RawPoint(
                freq_hz=freq_hz,
                amp_code=LF_JESD_SAFE_AMP_CODE,
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
            total = len(args.target_vpp) * len(args.freq_hz_list)
            closed_index = 0
            for target_vpp in args.target_vpp:
                for freq_hz in args.freq_hz_list:
                    closed_index += 1
                    old_corr = cal.interpolate_correction_factor(freq_hz, target_vpp)
                    result = cal.calculate(freq_hz, target_vpp / 2.0)
                    expected_vpp = max(target_vpp, result.expected_vpp)
                    measured_vpp, measured_freq_hz, raw_pava, actual_vdiv = measure_point(
                        scope=scope,
                        client=client,
                        args=args,
                        source=source,
                        freq_hz=freq_hz,
                        target_vpp=expected_vpp,
                        amp_code=result.amp_code,
                        relay_mask=result.relay_atten_mask,
                        index_label=f"[closed {closed_index}/{total}]",
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
            cal = LfCalibrationTable(runtime_json)

            if args.verify_point:
                verify_plan = args.verify_point
            else:
                rng = random.Random(args.seed)
                candidates = [
                    (freq, target)
                    for freq in args.freq_hz_list
                    for target in args.target_vpp
                    if target <= LF_JESD_MAX_TARGET_VPP
                ]
                rng.shuffle(candidates)
                verify_plan = candidates[: max(0, int(args.verify_count))]
            for verify_index, (freq_hz, target_vpp) in enumerate(verify_plan, start=1):
                result = cal.calculate(freq_hz, target_vpp / 2.0)
                for warmup_index in range(max(0, int(args.verify_warmup_count))):
                    measured_vpp, measured_freq_hz, _raw_pava, _actual_vdiv = measure_point(
                        scope=scope,
                        client=client,
                        args=args,
                        source=source,
                        freq_hz=freq_hz,
                        target_vpp=max(target_vpp, result.expected_vpp),
                        amp_code=result.amp_code,
                        relay_mask=result.relay_atten_mask,
                        index_label=f"[verify warmup {verify_index}.{warmup_index + 1}]",
                    )
                    print(
                        f"  warmup measured={measured_vpp:.6g} Vpp "
                        f"freq={measured_freq_hz:.6g} Hz",
                        flush=True,
                    )
                measured_vpp, measured_freq_hz, raw_pava, actual_vdiv = measure_point(
                    scope=scope,
                    client=client,
                    args=args,
                    source=source,
                    freq_hz=freq_hz,
                    target_vpp=max(target_vpp, result.expected_vpp),
                    amp_code=result.amp_code,
                    relay_mask=result.relay_atten_mask,
                    index_label=f"[verify {verify_index}/{len(verify_plan)}]",
                )
                error = (measured_vpp - target_vpp) / target_vpp * 100.0 if target_vpp else 0.0
                row = VerifyPoint(
                    index=verify_index,
                    freq_hz=freq_hz,
                    target_vpp=target_vpp,
                    amp_code=result.amp_code,
                    relay_atten_mask=result.relay_atten_mask,
                    expected_vpp=result.expected_vpp,
                    measured_vpp=measured_vpp,
                    measured_freq_hz=measured_freq_hz,
                    error_pct=error,
                    vdiv_v=actual_vdiv,
                    raw_pava=raw_pava,
                )
                verify_rows.append(row)
                write_csv(verify_csv, verify_rows)
                print(
                    f"  verify measured={measured_vpp:.6g} Vpp "
                    f"freq={measured_freq_hz:.6g} Hz err={error:+.2f}%",
                    flush=True,
                )
                time.sleep(args.between_captures)
        else:
            payload["completed"] = True
            runtime_json.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    print(f"raw_csv={raw_csv}")
    print(f"closed_loop_csv={closed_csv if closed_rows else ''}")
    print(f"verify_csv={verify_csv if verify_rows else ''}")
    print(f"runtime_json={runtime_json}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
