from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path


def _restart_inside_local_venv() -> None:
    root = Path(__file__).resolve().parents[1]
    venv_python = root / ".venv" / "Scripts" / "python.exe"
    if not venv_python.exists():
        return

    current_python = Path(sys.executable).resolve()
    if current_python == venv_python.resolve():
        return

    os.execv(str(venv_python), [str(venv_python), *sys.argv])


_restart_inside_local_venv()
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from host_app.scope_scpi import (
    DEFAULT_CAPTURE_POINTS,
    DEFAULT_MEASUREMENT_NAMES,
    DEFAULT_SCOPE_IP,
    DEFAULT_SCOPE_PORT,
    DEFAULT_SCOPE_TIMEOUT_S,
    PROFILE_SIGLENT,
    SUPPORTED_PROFILES,
    ScopeEndpoint,
    capture_scope_waveform,
    query_scope_idn,
    query_scope_measurements,
    save_capture_outputs,
    save_measurements_csv,
)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Capture oscilloscope waveform data over LAN by SCPI.",
    )
    parser.add_argument("--ip", default=DEFAULT_SCOPE_IP, help="Oscilloscope IP address.")
    parser.add_argument("--port", type=int, default=DEFAULT_SCOPE_PORT, help="SCPI TCP port.")
    parser.add_argument("--timeout", type=float, default=DEFAULT_SCOPE_TIMEOUT_S, help="Socket timeout in seconds.")
    parser.add_argument("--channel", default="CHAN1", help="Channel to capture, for example CHAN1 or CH1.")
    parser.add_argument(
        "--profile",
        choices=SUPPORTED_PROFILES,
        default=PROFILE_SIGLENT,
        help="Oscilloscope SCPI dialect.",
    )
    parser.add_argument(
        "--points",
        type=int,
        default=DEFAULT_CAPTURE_POINTS,
        help="Requested point count. Default: 1000.",
    )
    parser.add_argument(
        "--mode",
        default="NORM",
        choices=("NORM", "RAW", "MAX"),
        help="Acquisition readout mode for generic/Rigol/Keysight-style scopes.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parents[1] / "captures",
        help="Directory for captured files.",
    )
    parser.add_argument(
        "--format",
        action="append",
        choices=("csv", "npz", "png"),
        dest="formats",
        help="Output format. Repeat to select more than one. Default: csv.",
    )
    parser.add_argument(
        "--idn-only",
        action="store_true",
        help="Only query *IDN? and exit.",
    )
    parser.add_argument(
        "--measure",
        action="store_true",
        help="Only query automatic measurement values and exit.",
    )
    parser.add_argument(
        "--measurement",
        action="append",
        dest="measurements",
        help="Measurement name to read in --measure mode. Repeat for more. Default: common values.",
    )
    parser.add_argument(
        "--save-measurements",
        action="store_true",
        help="Append measurement values to scope_measurements.csv.",
    )
    parser.add_argument(
        "--stop",
        action="store_true",
        help="Send :STOP before reading waveform data.",
    )
    parser.add_argument(
        "--run-after",
        action="store_true",
        help="Send :RUN after waveform data is read.",
    )
    args = parser.parse_args()

    endpoint = ScopeEndpoint(args.ip, args.port, args.timeout)
    if args.idn_only:
        print(query_scope_idn(endpoint))
        return 0
    if args.measure:
        capture = query_scope_measurements(
            endpoint=endpoint,
            channel=args.channel,
            profile=args.profile,
            names=args.measurements or DEFAULT_MEASUREMENT_NAMES,
        )
        print(f"idn={capture.idn}")
        print(f"profile={capture.profile}")
        print(f"channel={capture.channel}")
        for measurement in capture.measurements.values():
            value = "invalid" if measurement.value is None else f"{measurement.value:.9g}"
            print(f"{measurement.name}={value}{measurement.unit}")
        if args.save_measurements:
            path = args.output_dir / "scope_measurements.csv"
            save_measurements_csv(capture, path)
            print(f"csv={path}")
        return 0

    capture = capture_scope_waveform(
        endpoint=endpoint,
        channel=args.channel,
        profile=args.profile,
        points=args.points,
        mode=args.mode,
        stop_before_capture=args.stop,
        run_after_capture=args.run_after,
    )
    outputs = save_capture_outputs(capture, args.output_dir, args.formats or ("csv",))

    print(f"idn={capture.idn}")
    print(f"profile={capture.profile}")
    print(f"channel={capture.channel}")
    print(f"points={capture.points}")
    print(f"sample_rate_hz={capture.sample_rate_hz:.9g}")
    print(f"v_min={capture.v_min:.9g} v_max={capture.v_max:.9g} v_pp={capture.v_pp:.9g}")
    for output_format, path in outputs.items():
        print(f"{output_format}={path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
