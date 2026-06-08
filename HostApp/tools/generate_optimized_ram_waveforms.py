from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

import numpy as np


SAMPLE_RATE_HZ = 983_040_000.0
SAMPLE_COUNT = 32768
DEFAULT_FULL_SCALE_LSB = 32767


def coherent_cycles(freq_hz: float, sample_rate_hz: float, sample_count: int) -> int:
    cycles = int(round(float(freq_hz) * int(sample_count) / float(sample_rate_hz)))
    return max(1, min(cycles, sample_count // 2 - 1))


def analyze(ch0: np.ndarray) -> dict:
    x = ch0.astype(np.float64)
    n = int(x.size)
    half = n // 2
    anti = x[:half] + x[half:] if n % 2 == 0 else np.asarray([np.nan])
    spec = np.fft.rfft(x - np.mean(x))
    mag = np.abs(spec)
    fund_bin = int(np.argmax(mag[1:]) + 1) if mag.size > 1 else 0
    fund = float(mag[fund_bin]) if fund_bin > 0 else 1.0

    def dbc(k: int) -> float | None:
        if k <= 0 or k >= mag.size:
            return None
        return 20.0 * math.log10(max(float(mag[k]), 1e-12) / max(fund, 1e-12))

    dc_mag = abs(float(np.mean(x))) * n
    return {
        "mean_lsb": float(np.mean(x)),
        "min_lsb": int(np.min(x)),
        "max_lsb": int(np.max(x)),
        "peak_lsb": int(np.max(np.abs(x))),
        "halfwave_antisymmetry_rms_lsb": float(np.sqrt(np.mean(anti * anti))),
        "halfwave_antisymmetry_peak_lsb": int(np.max(np.abs(anti))),
        "fundamental_bin": fund_bin,
        "dc_dbc": 20.0 * math.log10(max(dc_mag, 1e-12) / max(fund, 1e-12)),
        "h2_dbc": dbc(2 * fund_bin),
        "h3_dbc": dbc(3 * fund_bin),
    }


def quantize_interleaved(y: np.ndarray, peak_lsb: int) -> np.ndarray:
    y = np.asarray(y, dtype=np.float64)
    y = y - float(np.mean(y))
    peak = max(float(np.max(np.abs(y))), 1e-12)
    ch0 = np.rint(y / peak * int(peak_lsb)).astype(np.int32)
    ch0 = np.clip(ch0, -DEFAULT_FULL_SCALE_LSB, DEFAULT_FULL_SCALE_LSB)
    ch0 = ch0 - int(round(float(np.mean(ch0))))
    ch0 = np.clip(ch0, -DEFAULT_FULL_SCALE_LSB, DEFAULT_FULL_SCALE_LSB).astype("<i2")
    ch1 = np.zeros_like(ch0)
    return np.column_stack((ch0, ch1)).astype("<i2", copy=False)


def make_wave(sample_count: int, cycles: int, h2_ratio: float, h2_phase_deg: float) -> np.ndarray:
    n = np.arange(sample_count, dtype=np.float64)
    theta = 2.0 * np.pi * int(cycles) * n / int(sample_count)
    return np.sin(theta) + float(h2_ratio) * np.sin(2.0 * theta + math.radians(float(h2_phase_deg)))


def write_wave(
    out_dir: Path,
    name: str,
    freq_hz: float,
    cycles: int,
    peak_lsb: int,
    h2_ratio: float,
    h2_phase_deg: float,
) -> dict:
    y = make_wave(SAMPLE_COUNT, cycles, h2_ratio, h2_phase_deg)
    codes = quantize_interleaved(y, peak_lsb)
    bin_path = out_dir / f"{name}.bin"
    json_path = out_dir / f"{name}.json"
    codes.tofile(bin_path)
    metrics = {
        "file": str(bin_path),
        "sample_rate_hz": SAMPLE_RATE_HZ,
        "sample_count": SAMPLE_COUNT,
        "cycles_per_loop": int(cycles),
        "actual_frequency_hz": float(freq_hz),
        "peak_lsb_requested": int(peak_lsb),
        "h2_predistortion_ratio": float(h2_ratio),
        "h2_predistortion_phase_deg": float(h2_phase_deg),
        "format": "int16 little-endian interleaved CH0/CH1, signed two-complement",
        "notes": [
            "No endpoint duplicate: theta = 2*pi*k*n/N for n=0..N-1.",
            "DC is removed before and after round-to-nearest quantization.",
            "CH1 is zero.",
            "Predistortion candidates intentionally add a tiny H2 tone to cancel analog H2.",
        ],
        **analyze(codes[:, 0]),
    }
    json_path.write_text(json.dumps(metrics, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return metrics


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate RAM sine and H2 predistortion candidates.")
    parser.add_argument("--freq-hz", type=float, default=100_020_000.0)
    parser.add_argument("--out-dir", type=Path, default=Path(__file__).resolve().parents[1] / "generated_waveforms" / "optimized_h2_sweep")
    parser.add_argument("--peak-lsb", type=int, default=16000)
    parser.add_argument("--single-ratio", type=float, default=None, help="Generate only one H2 predistortion ratio, for example 0.015.")
    parser.add_argument("--single-phase", type=float, default=None, help="Generate only one H2 predistortion phase in degrees, for example 270.")
    parser.add_argument("--single-label", type=str, default="", help="Optional output name prefix for a single predistortion waveform.")
    args = parser.parse_args()

    out_dir = args.out_dir
    out_dir.mkdir(parents=True, exist_ok=True)
    cycles = coherent_cycles(args.freq_hz, SAMPLE_RATE_HZ, SAMPLE_COUNT)
    actual_freq_hz = SAMPLE_RATE_HZ * cycles / SAMPLE_COUNT

    rows: list[dict] = []
    single_mode = args.single_ratio is not None or args.single_phase is not None
    if single_mode:
        if args.single_ratio is None or args.single_phase is None:
            parser.error("--single-ratio and --single-phase must be used together")
        label = args.single_label.strip() or "ram_best_h2pd"
        name = f"{label}_{actual_freq_hz/1e6:.3f}m_pk{args.peak_lsb}_r{args.single_ratio:.4f}_p{int(round(args.single_phase)):03d}"
        rows.append(write_wave(out_dir, name, actual_freq_hz, cycles, args.peak_lsb, args.single_ratio, args.single_phase))
    else:
        rows.append(write_wave(out_dir, f"ram_clean_sine_{actual_freq_hz/1e6:.3f}m_pk{args.peak_lsb}", actual_freq_hz, cycles, args.peak_lsb, 0.0, 0.0))

        for ratio in (0.0025, 0.005, 0.01, 0.015, 0.02):
            for phase in (0.0, 90.0, 180.0, 270.0):
                name = f"ram_h2pd_{actual_freq_hz/1e6:.3f}m_pk{args.peak_lsb}_r{ratio:.4f}_p{int(phase):03d}"
                rows.append(write_wave(out_dir, name, actual_freq_hz, cycles, args.peak_lsb, ratio, phase))

    summary_path = out_dir / "summary.csv"
    with summary_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)

    print(f"out_dir={out_dir}")
    print(f"summary={summary_path}")
    print(f"requested_freq_hz={args.freq_hz:.9g}")
    print(f"actual_freq_hz={actual_freq_hz:.9g}")
    print(f"cycles={cycles}")
    print(f"files={len(rows)}")


if __name__ == "__main__":
    main()
