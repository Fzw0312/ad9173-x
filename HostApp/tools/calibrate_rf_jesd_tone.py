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
from host_app.models import ChannelSettings, NetworkSettings, RfSettings, WaveformSettings, build_config_payload  # noqa: E402
from host_app.rf_calibration import RfCalibrationTable  # noqa: E402
from host_app.udp_client import DAC_DDS_SAMPLE_RATE_HZ, UdpWaveformClient  # noqa: E402


JESD_SCALE_MAX = 0x7FFF
DEFAULT_FREQ_MHZ = [10, 15, 20, 30, 40, 50, 70, 100, 130, 160, 180, 200]
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


def tdiv_for_frequency(freq_hz: float, cycles_on_screen: float = 8.0) -> float:
    freq_hz = max(float(freq_hz), 1.0)
    required = cycles_on_screen / freq_hz / 14.0
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
    ):
        if tdiv >= required:
            return tdiv
    return 10e-6


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
    target_vpk = max(0.0, min(float(target_vpk), 3.0))
    channel = ChannelSettings(
        enabled=True,
        amplitude=target_vpk,
        amplitude_unit="V",
        frequency=float(freq_hz),
        frequency_unit="Hz",
    )
    rf = RfSettings(
        output_path="rf",
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
    config["rf"]["calibration"] = {
        "enabled": True,
        "file": "",
        "freq_hz": float(freq_hz),
        "target_vpk": target_vpk,
        "raw_vpk": 1.0,
        "raw_vpp": 2.0,
        "relay_atten_mask": int(relay_mask) & 0x0F,
        "relay_atten_db": relay_db_from_mask(relay_mask),
        "amp_code": max(0, min(JESD_SCALE_MAX, int(round(amp_code)))),
        "amp_ratio": max(0.0, min(1.0, float(amp_code) / JESD_SCALE_MAX)),
        "expected_vpk": target_vpk,
        "expected_vpp": 2.0 * target_vpk,
        "nco_hz": DAC_DDS_SAMPLE_RATE_HZ,
        "correction_factor": 1.0,
        "relay_trim_db": 0.0,
    }
    config["rf"]["relay_atten_mask"] = int(relay_mask) & 0x0F
    config["rf"]["relay_atten_db"] = relay_db_from_mask(relay_mask)
    config["rf"]["main_nco_hz"] = 0.0
    config["rf"]["target_frequency_hz"] = float(freq_hz)
    config["rf"]["jesd_if_hz"] = float(freq_hz)
    config["rf"]["jesd_main_nco_hz"] = 0.0
    config["rf"]["channel_nco_hz"] = float(freq_hz)
    return config


def send_rf_jesd(
    client: UdpWaveformClient,
    *,
    freq_hz: float,
    target_vpk: float,
    amp_code: int,
    relay_mask: int,
    source: str,
) -> int:
    return client.send_config(
        build_jesd_config(
            freq_hz=freq_hz,
            target_vpk=target_vpk,
            amp_code=amp_code,
            relay_mask=relay_mask,
            source=source,
        )
    )


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
    ]
    payload: dict[str, object] = {
        "version": 2,
        "created_at": timestamp,
        "updated_at": timestamp,
        "source": "rf_jesd_tone_unified_attenuator_scope_sweep",
        "output_mode": "jesd_tone",
        "path": "rf_dac0_jesd_tone_after_switch_unified_relay_attenuator",
        "description": "RF JESD single-tone calibration after the RF/LF switch, using the shared relay attenuator.",
        "frequency_range_hz": [min(row.freq_hz for row in raw_rows), max(row.freq_hz for row in raw_rows)],
        "target_amplitude_range_vpp": [min(args.target_vpp), max(args.target_vpp)],
        "measurement_channel": args.channel,
        "scope_ip": args.scope_ip,
        "output_path": "rf",
        "output_path_sel": 1,
        "channel": "RF/DAC0 JESD single-tone",
        "amplitude_unit": "Vpk",
        "display_amplitude_unit": "Vpp",
        "nco_hz": DAC_DDS_SAMPLE_RATE_HZ,
        "preferred_amp_code": JESD_SCALE_MAX,
        "nco_max_amp_code": JESD_SCALE_MAX,
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
            "RF JESD single-tone uses 0x7FFF as the full-scale digital tone code.",
            "Targets are stored as Vpp because oscilloscope PKPK is used for closed-loop correction.",
            "Verification points perform a warmup measurement before recording to avoid first-sample relay/scope settling artifacts.",
        ],
        "completed": False,
    }
    if model_points:
        payload["amplitude_correction_model"] = {
            "type": "correction_factor_linear_v1",
            "source": "rf_jesd_tone_closed_loop_scope_sweep",
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
    return parts[0], parts[1]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Calibrate RF JESD single-tone output through the shared relay attenuator.")
    parser.add_argument("--scope-ip", default="10.9.122.146")
    parser.add_argument("--scope-port", type=int, default=5025)
    parser.add_argument("--scope-timeout", type=float, default=8.0)
    parser.add_argument("--channel", default="CHAN2")
    parser.add_argument("--target-ip", default="255.255.255.255")
    parser.add_argument("--target-port", type=int, default=5005)
    parser.add_argument("--local-ip", default="10.9.122.153")
    parser.add_argument("--local-port", type=int, default=0)
    parser.add_argument("--max-datagram-bytes", type=int, default=1200)
    parser.add_argument("--settle", type=float, default=1.5)
    parser.add_argument("--between-captures", type=float, default=0.3)
    parser.add_argument("--vdiv-settle", type=float, default=0.3)
    parser.add_argument("--auto-tdiv", action=argparse.BooleanOptionalAction, default=True)
    parser.add_argument("--tdiv-settle", type=float, default=0.2)
    parser.add_argument("--pava-samples", type=int, default=5)
    parser.add_argument("--raw-pava-samples", type=int, default=4)
    parser.add_argument("--pava-interval", type=float, default=0.2)
    parser.add_argument("--raw-vdiv", type=float, default=1.0)
    parser.add_argument("--min-valid-ratio", type=float, default=0.25)
    parser.add_argument("--bootstrap-relay-mask", type=lambda text: int(text, 0), default=0)
    parser.add_argument("--base-calibration", type=Path, default=None)
    parser.add_argument("--raw-only", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--freq-mhz", type=float, action="append", default=None)
    parser.add_argument("--target-vpp", type=float, action="append", default=None)
    parser.add_argument("--verify-count", type=int, default=8)
    parser.add_argument("--verify-warmup-count", type=int, default=1)
    parser.add_argument("--verify-point", action="append", type=parse_point, default=None)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--output-dir", type=Path, default=Path(__file__).resolve().parents[1] / "calibration")
    args = parser.parse_args()
    args.freq_mhz = args.freq_mhz or DEFAULT_FREQ_MHZ
    args.target_vpp = sorted(set(float(value) for value in (args.target_vpp or DEFAULT_TARGET_VPP)))
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
        print(f"{index_label} set TDIV={tdiv:.3G}s/div for {freq_hz/1e6:g} MHz -> {actual_tdiv}", flush=True)
    vdiv = vdiv_for_expected_vpp(target_vpp)
    frames = send_rf_jesd(
        client,
        freq_hz=freq_hz,
        target_vpk=min(target_vpp / 2.0, 3.0),
        amp_code=amp_code,
        relay_mask=relay_mask,
        source="rf_jesd_tone_cal",
    )
    print(
        f"{index_label} sent JESD RF {frames} frame(s): freq={freq_hz/1e6:g} MHz "
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
    out_dir = args.output_dir / f"ch1_rf_jesd_tone_{timestamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    raw_csv = out_dir / "rf_jesd_tone_raw_points.csv"
    closed_csv = out_dir / "rf_jesd_tone_closed_loop_points.csv"
    verify_csv = out_dir / "rf_jesd_tone_verify_points.csv"
    runtime_json = out_dir / "rf_jesd_tone_ch1_runtime.json"
    source = _normalize_channel(args.channel, "C")
    network = NetworkSettings(
        target_ip=args.target_ip,
        target_port=args.target_port,
        local_port=args.local_port,
        max_datagram_bytes=args.max_datagram_bytes,
        local_ip=args.local_ip,
    )
    freq_hz_list = [float(freq_mhz) * 1e6 for freq_mhz in args.freq_mhz]

    if args.dry_run:
        print(f"scope_channel={source} udp={args.local_ip or 'OS auto'} -> {args.target_ip}:{args.target_port}")
        for freq_hz in freq_hz_list:
            print(f"RAW {freq_hz/1e6:8.3f} MHz amp=0x{JESD_SCALE_MAX:04X} relay=0x{args.bootstrap_relay_mask:X}")
        for target_vpp in args.target_vpp:
            for freq_hz in freq_hz_list:
                print(f"CLOSED {freq_hz/1e6:8.3f} MHz target={target_vpp:g} Vpp")
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

        for index, freq_hz in enumerate(freq_hz_list, start=1):
            measured_vpp, measured_freq_hz, raw_pava, _actual_vdiv = measure_point(
                scope=scope,
                client=client,
                args=args,
                source=source,
                freq_hz=freq_hz,
                target_vpp=3.0,
                amp_code=JESD_SCALE_MAX,
                relay_mask=args.bootstrap_relay_mask,
                index_label=f"[raw {index}/{len(freq_hz_list)}]",
            )
            row = RawPoint(
                freq_hz=freq_hz,
                amp_code=JESD_SCALE_MAX,
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
            cal = RfCalibrationTable(runtime_json)
            total = len(args.target_vpp) * len(freq_hz_list)
            closed_index = 0
            for target_vpp in args.target_vpp:
                for freq_hz in freq_hz_list:
                    closed_index += 1
                    old_corr = cal.interpolate_correction_factor(freq_hz, target_vpp)
                    result = cal.calculate(freq_hz, target_vpp / 2.0, "jesd_tone")
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
            cal = RfCalibrationTable(runtime_json)

            if args.verify_point:
                verify_plan = args.verify_point
            else:
                rng = random.Random(args.seed)
                candidates = [(freq, target) for freq in freq_hz_list for target in args.target_vpp]
                rng.shuffle(candidates)
                verify_plan = candidates[: max(0, int(args.verify_count))]
            for verify_index, (freq_hz, target_vpp) in enumerate(verify_plan, start=1):
                result = cal.calculate(freq_hz, target_vpp / 2.0, "jesd_tone")
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
                    print(f"  warmup measured={measured_vpp:.6g} Vpp freq={measured_freq_hz:.6g} Hz", flush=True)
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
