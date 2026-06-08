import argparse
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path

import numpy as np

HOST_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HOST_ROOT))

from host_app.models import MAX_WAVEFORM_SAMPLES, ChannelSettings, NetworkSettings, WaveformSettings, build_config_payload
from host_app.udp_client import UdpWaveformClient


DEFAULT_MATLAB = r"D:\Program Files\MATLAB\R2018a\bin\matlab.exe"


def matlab_quote(value: Path | str) -> str:
    return "'" + str(value).replace("'", "''") + "'"


def run_matlab_generator(args: argparse.Namespace, bin_path: Path, mat_path: Path) -> None:
    matlab_exe = args.matlab_exe or shutil.which("matlab") or DEFAULT_MATLAB
    matlab_path = Path(matlab_exe)
    if not matlab_path.exists() and shutil.which(matlab_exe) is None:
        raise FileNotFoundError(f"MATLAB executable not found: {matlab_exe}")

    matlab_dir = HOST_ROOT / "matlab"
    command = (
        "try, "
        f"addpath({matlab_quote(matlab_dir)}); "
        "write_fm_waveform_bin("
        f"{matlab_quote(bin_path)}, "
        f"{matlab_quote(mat_path)}, "
        f"{args.sample_rate_hz:.17g}, "
        f"{args.sample_count:d}, "
        f"{args.full_scale_vpk:.17g}, "
        f"{args.amplitude_vpk:.17g}, "
        f"{args.amplitude_vpk:.17g}, "
        f"{args.carrier_hz:.17g}, "
        f"{args.mod_hz:.17g}, "
        f"{args.deviation_hz:.17g}, "
        f"{args.ch1_phase_deg:.17g}); "
        "catch ME, disp(getReport(ME, 'extended')); exit(1); end; exit(0);"
    )
    completed = subprocess.run(
        [str(matlab_exe), "-nosplash", "-nodesktop", "-wait", "-r", command],
        cwd=str(HOST_ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=args.matlab_timeout_s,
        check=False,
    )
    if completed.stdout:
        print(completed.stdout.strip())
    if completed.returncode != 0:
        raise RuntimeError(f"MATLAB generation failed with exit code {completed.returncode}")


def load_codes(bin_path: Path, sample_count: int) -> np.ndarray:
    raw = np.fromfile(bin_path, dtype="<i2")
    expected = sample_count * 2
    if raw.size != expected:
        raise ValueError(f"Expected {expected} int16 values, found {raw.size} in {bin_path}")
    return raw.reshape((sample_count, 2))


def build_fm_config(args: argparse.Namespace) -> dict:
    waveform = WaveformSettings(
        sample_rate=args.sample_rate_hz / 1e6,
        sample_rate_unit="MSPS",
        sample_count=args.sample_count,
        dac_full_scale_vpk=args.full_scale_vpk,
    )
    channel = ChannelSettings(
        enabled=True,
        amplitude=args.amplitude_vpk * 1e3,
        amplitude_unit="mV",
        frequency=args.carrier_hz / 1e6,
        frequency_unit="MHz",
    )
    config = build_config_payload(waveform, [channel, channel], "MATLAB FM")
    config["fm"] = {
        "carrier_hz": args.carrier_hz,
        "mod_hz": args.mod_hz,
        "deviation_hz": args.deviation_hz,
        "ch1_phase_deg": args.ch1_phase_deg,
        "bin_aligned": True,
    }
    return config


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Generate a MATLAB FM waveform and send it to the AD9173 DAC over UDP.")
    parser.add_argument("--target-ip", default="255.255.255.255", help="FPGA UDP destination IP. Broadcast is the safest default.")
    parser.add_argument("--target-port", type=int, default=5005)
    parser.add_argument("--local-ip", default="", help="Optional source IP used to force a specific NIC.")
    parser.add_argument("--local-port", type=int, default=0)
    parser.add_argument("--max-datagram-bytes", type=int, default=1200)
    parser.add_argument("--sample-rate-hz", type=float, default=983_040_000.0)
    parser.add_argument("--sample-count", type=int, default=MAX_WAVEFORM_SAMPLES)
    parser.add_argument("--full-scale-vpk", type=float, default=1.0)
    parser.add_argument("--amplitude-vpk", type=float, default=0.55)
    parser.add_argument("--carrier-hz", type=float, default=80_160_000.0)
    parser.add_argument("--mod-hz", type=float, default=2_400_000.0)
    parser.add_argument("--deviation-hz", type=float, default=12_000_000.0)
    parser.add_argument("--ch1-phase-deg", type=float, default=90.0)
    parser.add_argument("--matlab-exe", default="", help="Path to matlab.exe; defaults to PATH or MATLAB R2018a.")
    parser.add_argument("--matlab-timeout-s", type=int, default=180)
    parser.add_argument("--output-dir", type=Path, default=HOST_ROOT / "generated")
    parser.add_argument("--no-send", action="store_true", help="Only generate the BIN/MAT files; do not send UDP frames.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.sample_count <= 0 or args.sample_count > MAX_WAVEFORM_SAMPLES:
        raise ValueError(f"sample-count must be in 1..{MAX_WAVEFORM_SAMPLES} for the current FPGA waveform RAM")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    bin_path = args.output_dir / f"fm_{stamp}_ch01_i16.bin"
    mat_path = args.output_dir / f"fm_{stamp}_ch01.mat"

    print("Generating FM waveform with MATLAB...")
    run_matlab_generator(args, bin_path, mat_path)
    codes = load_codes(bin_path, args.sample_count)
    print(f"Loaded {codes.shape[0]} sample pairs from {bin_path}")

    if args.no_send:
        print(f"Generated MAT metadata: {mat_path}")
        return

    network = NetworkSettings(
        target_ip=args.target_ip,
        target_port=args.target_port,
        local_port=args.local_port,
        max_datagram_bytes=args.max_datagram_bytes,
        local_ip=args.local_ip,
    )
    config = build_fm_config(args)
    client = UdpWaveformClient(network)
    frames = client.send_waveform(config, codes)

    print(
        "Sent MATLAB FM waveform: "
        f"frames={frames}, target={args.target_ip}:{args.target_port}, "
        f"fs={args.sample_rate_hz / 1e6:.2f} MSPS, samples={args.sample_count}, "
        f"fc={args.carrier_hz / 1e6:.3f} MHz, fm={args.mod_hz / 1e6:.3f} MHz, "
        f"dev={args.deviation_hz / 1e6:.3f} MHz, amp={args.amplitude_vpk:.3f} Vpk"
    )
    print(f"BIN: {bin_path}")
    print(f"MAT: {mat_path}")


if __name__ == "__main__":
    main()
