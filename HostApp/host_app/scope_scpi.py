from __future__ import annotations

import csv
import json
import os
import re
import socket
import threading
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Iterable

import numpy as np


DEFAULT_SCOPE_IP = "10.9.122.165"
DEFAULT_SCOPE_PORT = 5025
DEFAULT_SCOPE_TIMEOUT_S = 5.0
DEFAULT_CAPTURE_POINTS = 1000
MAX_SAFE_SIGLENT_POINTS = 100_000
SCPI_LOCK_TIMEOUT_S = 3.0
DEFAULT_MEASUREMENT_NAMES = ("FREQ", "AMP", "PKPK", "MAX", "MIN", "MEAN", "RMS", "PER")

PROFILE_AUTO = "auto"
PROFILE_GENERIC = "generic"
PROFILE_KEYSIGHT = "keysight"
PROFILE_RIGOL = "rigol"
PROFILE_SIGLENT = "siglent"
PROFILE_TEKTRONIX = "tektronix"
SUPPORTED_PROFILES = (
    PROFILE_AUTO,
    PROFILE_GENERIC,
    PROFILE_KEYSIGHT,
    PROFILE_RIGOL,
    PROFILE_SIGLENT,
    PROFILE_TEKTRONIX,
)


class ScpiError(RuntimeError):
    pass


@dataclass(frozen=True)
class ScopeEndpoint:
    host: str = DEFAULT_SCOPE_IP
    port: int = DEFAULT_SCOPE_PORT
    timeout: float = DEFAULT_SCOPE_TIMEOUT_S


@dataclass(frozen=True)
class WaveformCapture:
    idn: str
    profile: str
    channel: str
    time_s: np.ndarray
    voltage_v: np.ndarray
    raw_codes: np.ndarray
    preamble: dict[str, Any]

    @property
    def points(self) -> int:
        return int(self.voltage_v.size)

    @property
    def sample_interval_s(self) -> float:
        if self.time_s.size < 2:
            return 0.0
        return float(self.time_s[1] - self.time_s[0])

    @property
    def sample_rate_hz(self) -> float:
        interval = self.sample_interval_s
        if interval == 0.0:
            return 0.0
        return 1.0 / interval

    @property
    def v_min(self) -> float:
        return float(np.min(self.voltage_v)) if self.voltage_v.size else 0.0

    @property
    def v_max(self) -> float:
        return float(np.max(self.voltage_v)) if self.voltage_v.size else 0.0

    @property
    def v_pp(self) -> float:
        return self.v_max - self.v_min


@dataclass(frozen=True)
class ScopeMeasurement:
    name: str
    value: float | None
    unit: str
    raw: str

    @property
    def valid(self) -> bool:
        return self.value is not None


@dataclass(frozen=True)
class MeasurementCapture:
    idn: str
    profile: str
    channel: str
    measurements: dict[str, ScopeMeasurement]

    def get(self, *names: str) -> ScopeMeasurement | None:
        for name in names:
            measurement = self.measurements.get(name.upper())
            if measurement is not None:
                return measurement
        return None


class ScpiSocket:
    def __init__(self, endpoint: ScopeEndpoint):
        self.endpoint = endpoint
        self._sock: socket.socket | None = None

    def __enter__(self) -> "ScpiSocket":
        self.open()
        return self

    def __exit__(self, _exc_type, _exc, _tb) -> None:
        self.close()

    def open(self) -> None:
        if self._sock is not None:
            return
        self._sock = socket.create_connection(
            (self.endpoint.host, self.endpoint.port),
            timeout=self.endpoint.timeout,
        )
        self._sock.settimeout(self.endpoint.timeout)

    def close(self) -> None:
        if self._sock is None:
            return
        try:
            try:
                self._sock.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self._sock.close()
        finally:
            self._sock = None

    def write(self, command: str) -> None:
        sock = self._require_socket()
        message = command.rstrip("\r\n").encode("ascii") + b"\n"
        sock.sendall(message)

    def query_text(self, command: str) -> str:
        self.write(command)
        raw = self._read_text_response()
        return raw.decode("ascii", errors="replace").strip()

    def query_data(self, command: str) -> bytes:
        self.write(command)
        first = self._read_response_start()
        if first == b"#":
            return self._read_definite_block()
        return (first + self._read_until_newline()).strip()

    def query_prefixed_block(self, command: str, max_payload_bytes: int | None = None) -> tuple[str, bytes]:
        self.write(command)
        prefix = bytearray()
        while True:
            byte = self._read_response_start()
            if byte == b"#":
                break
            prefix.extend(byte)
            prefix.extend(self._read_until_hash())
            break
        return prefix.decode("ascii", errors="replace").strip(), self._read_definite_block(max_payload_bytes)

    def _require_socket(self) -> socket.socket:
        if self._sock is None:
            raise ScpiError("SCPI socket is not open")
        return self._sock

    def _read_exact(self, byte_count: int) -> bytes:
        sock = self._require_socket()
        chunks: list[bytes] = []
        remaining = byte_count
        while remaining > 0:
            chunk = sock.recv(remaining)
            if not chunk:
                raise ScpiError("SCPI connection closed while reading")
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def _read_response_start(self) -> bytes:
        while True:
            byte = self._read_exact(1)
            if byte not in (b"\r", b"\n"):
                return byte

    def _read_until_newline(self, max_bytes: int = 16 * 1024 * 1024) -> bytes:
        sock = self._require_socket()
        chunks: list[bytes] = []
        total = 0
        while total < max_bytes:
            chunk = sock.recv(min(4096, max_bytes - total))
            if not chunk:
                break
            chunks.append(chunk)
            total += len(chunk)
            if b"\n" in chunk:
                break
        if total >= max_bytes:
            raise ScpiError("SCPI text response exceeded maximum length")
        data = b"".join(chunks)
        newline_index = data.find(b"\n")
        if newline_index >= 0:
            return data[:newline_index]
        return data

    def _read_until_hash(self, max_bytes: int = 4096) -> bytes:
        sock = self._require_socket()
        chunks: list[bytes] = []
        total = 0
        while total < max_bytes:
            chunk = sock.recv(1)
            if not chunk:
                raise ScpiError("SCPI connection closed before binary block header")
            if chunk == b"#":
                return b"".join(chunks)
            chunks.append(chunk)
            total += 1
        raise ScpiError("SCPI response prefix exceeded maximum length")

    def _read_text_response(self) -> bytes:
        first = self._read_response_start()
        return (first + self._read_until_newline()).strip()

    def _read_definite_block(self, max_payload_bytes: int | None = None) -> bytes:
        digit_count_byte = self._read_exact(1)
        if not digit_count_byte.isdigit():
            raise ScpiError(f"Invalid SCPI block header: #{digit_count_byte!r}")
        digit_count = int(digit_count_byte)
        if digit_count == 0:
            return self._read_indefinite_block()

        length_text = self._read_exact(digit_count)
        if not length_text.isdigit():
            raise ScpiError(f"Invalid SCPI block length: {length_text!r}")
        payload_length = int(length_text)
        if max_payload_bytes is not None and payload_length > max_payload_bytes:
            raise ScpiError(
                f"Oscilloscope returned {payload_length} bytes; safety limit is {max_payload_bytes} bytes"
            )
        payload = self._read_exact(payload_length)
        self._consume_available_line_end()
        return payload

    def _read_indefinite_block(self) -> bytes:
        sock = self._require_socket()
        old_timeout = sock.gettimeout()
        chunks: list[bytes] = []
        try:
            sock.settimeout(0.25)
            while True:
                try:
                    chunk = sock.recv(65536)
                except socket.timeout:
                    break
                if not chunk:
                    break
                chunks.append(chunk)
        finally:
            sock.settimeout(old_timeout)
        return b"".join(chunks).rstrip(b"\r\n")

    def _consume_available_line_end(self) -> None:
        sock = self._require_socket()
        old_timeout = sock.gettimeout()
        try:
            sock.settimeout(0.05)
            try:
                tail = sock.recv(2)
            except socket.timeout:
                return
            if tail.strip(b"\r\n"):
                # The next response should never arrive here because commands are serialized.
                # Keep going; returning unexpected bytes would be more confusing to callers.
                return
        finally:
            sock.settimeout(old_timeout)


_scope_process_lock = threading.Lock()


class ScopeAccessLock:
    def __init__(self, timeout_s: float = SCPI_LOCK_TIMEOUT_S):
        self.timeout_s = timeout_s
        self._handle = None
        self._lock_path = Path(__file__).resolve().parents[1] / "captures" / ".scope_scpi.lock"

    def __enter__(self) -> "ScopeAccessLock":
        deadline = time.monotonic() + self.timeout_s
        self._lock_path.parent.mkdir(parents=True, exist_ok=True)
        _scope_process_lock.acquire()
        try:
            self._handle = self._lock_path.open("a+b")
            while True:
                try:
                    self._try_lock_file()
                    return self
                except OSError as exc:
                    if time.monotonic() >= deadline:
                        raise ScpiError("Another oscilloscope SCPI session is already running") from exc
                    time.sleep(0.1)
        except Exception:
            _scope_process_lock.release()
            if self._handle is not None:
                self._handle.close()
                self._handle = None
            raise

    def __exit__(self, _exc_type, _exc, _tb) -> None:
        try:
            if self._handle is not None:
                self._unlock_file()
                self._handle.close()
                self._handle = None
        finally:
            time.sleep(0.2)
            _scope_process_lock.release()

    def _try_lock_file(self) -> None:
        if self._handle is None:
            raise ScpiError("SCPI lock file is not open")
        if os.name == "nt":
            import msvcrt

            self._handle.seek(0)
            msvcrt.locking(self._handle.fileno(), msvcrt.LK_NBLCK, 1)
            return

        import fcntl

        fcntl.lockf(self._handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

    def _unlock_file(self) -> None:
        if self._handle is None:
            return
        if os.name == "nt":
            import msvcrt

            self._handle.seek(0)
            try:
                msvcrt.locking(self._handle.fileno(), msvcrt.LK_UNLCK, 1)
            except OSError:
                pass
            return

        import fcntl

        fcntl.lockf(self._handle.fileno(), fcntl.LOCK_UN)


def query_scope_idn(endpoint: ScopeEndpoint) -> str:
    with ScopeAccessLock():
        with ScpiSocket(endpoint) as instrument:
            idn = "UNKNOWN"
            try:
                idn = instrument.query_text("*IDN?")
                return idn
            finally:
                _restore_local_best_effort(instrument, detect_profile(idn), False)


def detect_profile(idn: str) -> str:
    upper = idn.upper()
    if "TEKTRONIX" in upper or upper.startswith("TEK,"):
        return PROFILE_TEKTRONIX
    if "SIGLENT" in upper:
        return PROFILE_SIGLENT
    if "RIGOL" in upper:
        return PROFILE_RIGOL
    if "KEYSIGHT" in upper or "AGILENT" in upper or "HEWLETT" in upper:
        return PROFILE_KEYSIGHT
    return PROFILE_GENERIC


def capture_scope_waveform(
    endpoint: ScopeEndpoint,
    channel: str = "CHAN1",
    profile: str = PROFILE_AUTO,
    points: int | None = None,
    mode: str = "NORM",
    stop_before_capture: bool = False,
    run_after_capture: bool = False,
) -> WaveformCapture:
    if profile not in SUPPORTED_PROFILES:
        raise ValueError(f"Unsupported oscilloscope profile: {profile}")

    with ScopeAccessLock():
        with ScpiSocket(endpoint) as instrument:
            idn = "UNKNOWN"
            if profile == PROFILE_AUTO:
                idn = instrument.query_text("*IDN?")
                active_profile = detect_profile(idn)
            else:
                active_profile = profile
            if stop_before_capture:
                instrument.write(":STOP")
                time.sleep(0.1)

            try:
                if active_profile == PROFILE_SIGLENT:
                    return _capture_siglent(instrument, idn, channel, points)
                if active_profile == PROFILE_TEKTRONIX:
                    return _capture_tektronix(instrument, idn, channel, points)
                return _capture_waveform_preamble_style(
                    instrument,
                    idn,
                    active_profile,
                    channel,
                    points,
                    mode,
                )
            finally:
                _restore_local_best_effort(instrument, active_profile, run_after_capture or stop_before_capture)


def query_scope_measurements(
    endpoint: ScopeEndpoint,
    channel: str = "CHAN1",
    profile: str = PROFILE_SIGLENT,
    names: Iterable[str] | None = DEFAULT_MEASUREMENT_NAMES,
) -> MeasurementCapture:
    if profile not in SUPPORTED_PROFILES:
        raise ValueError(f"Unsupported oscilloscope profile: {profile}")

    requested_names = None if names is None else {name.upper() for name in names}
    with ScopeAccessLock():
        with ScpiSocket(endpoint) as instrument:
            idn = "UNKNOWN"
            if profile == PROFILE_AUTO:
                idn = instrument.query_text("*IDN?")
                active_profile = detect_profile(idn)
            else:
                active_profile = profile

            try:
                if active_profile != PROFILE_SIGLENT:
                    raise ScpiError(f"Measurement query is currently implemented for Siglent profile, got {active_profile}")
                return _query_siglent_measurements(instrument, idn, channel, requested_names)
            finally:
                _restore_local_best_effort(instrument, active_profile, False)


def save_waveform_csv(capture: WaveformCapture, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["time_s", "voltage_v", "raw_code"])
        for time_value, voltage_value, raw_code in zip(
            capture.time_s,
            capture.voltage_v,
            capture.raw_codes,
        ):
            writer.writerow([f"{time_value:.15g}", f"{voltage_value:.15g}", int(raw_code)])
    return path


def save_waveform_npz(capture: WaveformCapture, path: Path) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    metadata = {
        "idn": capture.idn,
        "profile": capture.profile,
        "channel": capture.channel,
        "points": capture.points,
        "sample_rate_hz": capture.sample_rate_hz,
        "preamble": capture.preamble,
    }
    np.savez(
        path,
        time_s=capture.time_s,
        voltage_v=capture.voltage_v,
        raw_codes=capture.raw_codes,
        metadata=json.dumps(metadata, ensure_ascii=False, default=str),
    )
    return path


def save_waveform_plot(capture: WaveformCapture, path: Path) -> Path:
    import matplotlib

    matplotlib.use("Agg")
    from matplotlib import pyplot as plt

    path.parent.mkdir(parents=True, exist_ok=True)
    fig, axes = plt.subplots(figsize=(9.0, 4.8), dpi=120)
    axes.plot(capture.time_s, capture.voltage_v, linewidth=1.0)
    axes.set_title(f"{capture.channel} waveform")
    axes.set_xlabel("Time (s)")
    axes.set_ylabel("Voltage (V)")
    axes.grid(True, linewidth=0.5, alpha=0.45)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)
    return path


def save_capture_outputs(
    capture: WaveformCapture,
    output_dir: Path,
    formats: Iterable[str] = ("csv", "npz", "png"),
) -> dict[str, Path]:
    output_dir.mkdir(parents=True, exist_ok=True)
    timestamp = time.strftime("%Y%m%d_%H%M%S")
    channel = _safe_filename(capture.channel)
    base = output_dir / f"scope_{channel}_{timestamp}"
    paths: dict[str, Path] = {}
    for output_format in formats:
        normalized = output_format.lower().strip()
        if normalized == "csv":
            paths["csv"] = save_waveform_csv(capture, base.with_suffix(".csv"))
        elif normalized == "npz":
            paths["npz"] = save_waveform_npz(capture, base.with_suffix(".npz"))
        elif normalized == "png":
            paths["png"] = save_waveform_plot(capture, base.with_suffix(".png"))
        elif normalized:
            raise ValueError(f"Unsupported output format: {output_format}")
    return paths


def save_measurements_csv(capture: MeasurementCapture, path: Path, timestamp_s: float | None = None) -> Path:
    path.parent.mkdir(parents=True, exist_ok=True)
    write_header = not path.exists() or path.stat().st_size == 0
    timestamp = time.time() if timestamp_s is None else timestamp_s
    with path.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        if write_header:
            writer.writerow(["timestamp_s", "channel", "name", "value", "unit", "raw"])
        for measurement in capture.measurements.values():
            value = "" if measurement.value is None else f"{measurement.value:.15g}"
            writer.writerow([f"{timestamp:.6f}", capture.channel, measurement.name, value, measurement.unit, measurement.raw])
    return path


def _query_idn_best_effort(instrument: ScpiSocket) -> str:
    try:
        return instrument.query_text("*IDN?")
    except Exception:
        return "UNKNOWN"


def _capture_waveform_preamble_style(
    instrument: ScpiSocket,
    idn: str,
    profile: str,
    channel: str,
    points: int | None,
    mode: str,
) -> WaveformCapture:
    source = _normalize_channel(channel, style="CHAN")
    normalized_mode = mode.upper()

    instrument.write(f":WAVeform:SOURce {source}")
    if profile == PROFILE_RIGOL:
        instrument.write(f":WAVeform:MODE {normalized_mode}")
    elif profile == PROFILE_KEYSIGHT:
        if normalized_mode == "RAW":
            instrument.write(":WAVeform:POINts:MODE RAW")
        elif normalized_mode == "MAX":
            instrument.write(":WAVeform:POINts:MODE MAXimum")
        else:
            instrument.write(":WAVeform:POINts:MODE NORMal")
    else:
        _write_best_effort(instrument, f":WAVeform:MODE {normalized_mode}")
        if normalized_mode == "RAW":
            _write_best_effort(instrument, ":WAVeform:POINts:MODE RAW")

    instrument.write(":WAVeform:FORMat BYTE")
    _write_best_effort(instrument, ":WAVeform:BYTeorder LSBFirst")
    if points is not None and points > 0:
        _write_best_effort(instrument, ":WAVeform:STARt 1")
        _write_best_effort(instrument, f":WAVeform:STOP {points}")
        _write_best_effort(instrument, f":WAVeform:POINts {points}")

    preamble_text = instrument.query_text(":WAVeform:PREamble?")
    preamble = _parse_standard_preamble(preamble_text)
    payload = instrument.query_data(":WAVeform:DATA?")
    raw = _decode_standard_payload(payload, preamble)
    time_s, voltage_v = _scale_standard_waveform(raw, preamble)
    preamble["raw_preamble"] = preamble_text

    return WaveformCapture(
        idn=idn,
        profile=profile,
        channel=source,
        time_s=time_s,
        voltage_v=voltage_v,
        raw_codes=raw,
        preamble=preamble,
    )


def _capture_tektronix(
    instrument: ScpiSocket,
    idn: str,
    channel: str,
    points: int | None,
) -> WaveformCapture:
    source = _normalize_channel(channel, style="CH")
    instrument.write(f"DATA:SOURCE {source}")
    instrument.write("DATA:START 1")
    if points is not None and points > 0:
        instrument.write(f"DATA:STOP {points}")
    instrument.write("DATA:WIDTH 1")
    instrument.write("DATA:ENCODING RPBINARY")

    preamble = {
        "x_increment": _query_float(instrument, "WFMOUTPRE:XINCR?", 1.0),
        "x_origin": _query_float(instrument, "WFMOUTPRE:XZERO?", 0.0),
        "x_reference": _query_float(instrument, "WFMOUTPRE:PT_OFF?", 0.0),
        "y_increment": _query_float(instrument, "WFMOUTPRE:YMULT?", 1.0),
        "y_origin": _query_float(instrument, "WFMOUTPRE:YZERO?", 0.0),
        "y_reference": _query_float(instrument, "WFMOUTPRE:YOFF?", 0.0),
        "points": _query_float(instrument, "WFMOUTPRE:NR_PT?", 0.0),
    }
    payload = instrument.query_data("CURVE?")
    raw = np.frombuffer(payload, dtype=np.uint8).astype(np.int32)
    index = np.arange(raw.size, dtype=np.float64)
    time_s = preamble["x_origin"] + (index - preamble["x_reference"]) * preamble["x_increment"]
    voltage_v = (raw.astype(np.float64) - preamble["y_reference"]) * preamble["y_increment"] + preamble["y_origin"]

    return WaveformCapture(
        idn=idn,
        profile=PROFILE_TEKTRONIX,
        channel=source,
        time_s=time_s,
        voltage_v=voltage_v,
        raw_codes=raw,
        preamble=preamble,
    )


def _capture_siglent(
    instrument: ScpiSocket,
    idn: str,
    channel: str,
    points: int | None,
) -> WaveformCapture:
    source = _normalize_channel(channel, style="C")
    safe_points = _safe_siglent_points(points)
    _write_best_effort(instrument, "CHDR SHORT")
    instrument.write(f"WFSU SP,0,NP,{safe_points},F,0")
    time.sleep(0.05)

    v_div = _query_number_with_units(instrument, f"{source}:VDIV?", 1.0)
    v_offset = _query_number_with_units(instrument, f"{source}:OFST?", 0.0)
    t_div = _query_number_with_units(instrument, "TDIV?", 0.0)
    sample_rate = _query_number_with_units(instrument, "SARA?", 0.0)
    trigger_delay = _query_number_with_units(instrument, "TRDL?", 0.0)
    wfsu_text = _query_text_best_effort(instrument, "WFSU?")
    wfsu = _parse_siglent_wfsu(wfsu_text)
    max_payload_bytes = safe_points + 1024
    block_prefix, payload = instrument.query_prefixed_block(f"{source}:WF? DAT2", max_payload_bytes)

    raw = np.frombuffer(payload, dtype=np.int8).astype(np.int32)
    sparsing = int(wfsu.get("SP", 1) or 1)
    first_point = int(wfsu.get("FP", 0) or 0)
    if sample_rate > 0.0:
        time_s = (first_point + np.arange(raw.size, dtype=np.float64) * sparsing) / sample_rate
        sample_interval = sparsing / sample_rate
    elif t_div > 0.0 and raw.size > 1:
        sample_interval = 14.0 * t_div / raw.size
        time_s = np.arange(raw.size, dtype=np.float64) * sample_interval
    else:
        sample_interval = 1.0
        time_s = np.arange(raw.size, dtype=np.float64)

    # SDS2000X Plus DAT2 samples use about 30 ADC codes per vertical division.
    # Using 25 codes/div overestimates Vpp by roughly 20% on this unit.
    siglent_codes_per_div = 30.0
    voltage_v = raw.astype(np.float64) * (v_div / siglent_codes_per_div) - v_offset
    preamble = {
        "format": "DAT2",
        "v_div": v_div,
        "v_offset": v_offset,
        "t_div": t_div,
        "sample_rate": sample_rate,
        "sample_interval": sample_interval,
        "codes_per_div": siglent_codes_per_div,
        "trigger_delay": trigger_delay,
        "wfsu": wfsu,
        "raw_wfsu": wfsu_text,
        "block_prefix": block_prefix,
    }
    return WaveformCapture(
        idn=idn,
        profile=PROFILE_SIGLENT,
        channel=source,
        time_s=time_s,
        voltage_v=voltage_v,
        raw_codes=raw,
        preamble=preamble,
    )


def _query_siglent_measurements(
    instrument: ScpiSocket,
    idn: str,
    channel: str,
    requested_names: set[str] | None,
) -> MeasurementCapture:
    source = _normalize_channel(channel, style="C")
    _write_best_effort(instrument, "CHDR SHORT")
    response = instrument.query_text(f"{source}:PAVA?")
    measurements = _parse_siglent_pava(response)
    if requested_names is not None:
        measurements = {
            name: measurement
            for name, measurement in measurements.items()
            if name in requested_names
        }
    return MeasurementCapture(
        idn=idn,
        profile=PROFILE_SIGLENT,
        channel=source,
        measurements=measurements,
    )


def _parse_standard_preamble(preamble_text: str) -> dict[str, Any]:
    fields = [
        "format",
        "type",
        "points",
        "count",
        "x_increment",
        "x_origin",
        "x_reference",
        "y_increment",
        "y_origin",
        "y_reference",
    ]
    values = _parse_csv_line(preamble_text)
    preamble: dict[str, Any] = {}
    for key, value in zip(fields, values):
        preamble[key] = _number_or_text(value)
    return preamble


def _parse_csv_line(text: str) -> list[str]:
    try:
        return next(csv.reader([text.strip()]))
    except Exception:
        return [part.strip() for part in text.split(",")]


def _number_or_text(value: str) -> Any:
    value = value.strip().strip('"')
    if not value:
        return value
    try:
        if any(char in value.upper() for char in (".", "E")):
            return float(value)
        return int(value, 0)
    except ValueError:
        return value


def _decode_standard_payload(payload: bytes, preamble: dict[str, Any]) -> np.ndarray:
    stripped = payload.strip()
    waveform_format = preamble.get("format", 0)
    if _looks_like_ascii_waveform(stripped) or str(waveform_format).upper().startswith("ASC") or waveform_format == 4:
        values = [float(part) for part in stripped.decode("ascii", errors="ignore").split(",") if part.strip()]
        return np.asarray(values, dtype=np.float64)

    if str(waveform_format).upper().startswith("WORD") or waveform_format == 1:
        even_length = len(payload) - (len(payload) % 2)
        return np.frombuffer(payload[:even_length], dtype="<i2").astype(np.int32)
    return np.frombuffer(payload, dtype=np.uint8).astype(np.int32)


def _scale_standard_waveform(raw: np.ndarray, preamble: dict[str, Any]) -> tuple[np.ndarray, np.ndarray]:
    x_increment = float(preamble.get("x_increment", 1.0))
    x_origin = float(preamble.get("x_origin", 0.0))
    x_reference = float(preamble.get("x_reference", 0.0))
    y_increment = float(preamble.get("y_increment", 1.0))
    y_origin = float(preamble.get("y_origin", 0.0))
    y_reference = float(preamble.get("y_reference", 0.0))

    index = np.arange(raw.size, dtype=np.float64)
    time_s = x_origin + (index - x_reference) * x_increment
    voltage_v = (raw.astype(np.float64) - y_reference) * y_increment + y_origin
    return time_s, voltage_v


def _looks_like_ascii_waveform(payload: bytes) -> bool:
    if not payload:
        return False
    sample = payload[:256]
    allowed = b"0123456789+-.,Ee \t\r\n"
    return all(byte in allowed for byte in sample) and b"," in sample


def _query_float(instrument: ScpiSocket, command: str, default: float) -> float:
    try:
        return float(instrument.query_text(command))
    except Exception:
        return default


def _query_text_best_effort(instrument: ScpiSocket, command: str) -> str:
    try:
        return instrument.query_text(command)
    except Exception:
        return ""


def _query_number_with_units(instrument: ScpiSocket, command: str, default: float) -> float:
    return _parse_first_float(_query_text_best_effort(instrument, command), default)


def _parse_first_float(text: str, default: float) -> float:
    matches = re.findall(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][-+]?\d+)?", text)
    for candidate in reversed(matches):
        try:
            return float(candidate)
        except ValueError:
            continue
    return default


def _parse_siglent_wfsu(text: str) -> dict[str, int]:
    normalized = text.replace(",", " ").split()
    values: dict[str, int] = {}
    for index, token in enumerate(normalized[:-1]):
        key = token.upper()
        if key in ("SP", "NP", "FP"):
            try:
                values[key] = int(float(normalized[index + 1]))
            except ValueError:
                pass
    return values


def _parse_siglent_pava(text: str) -> dict[str, ScopeMeasurement]:
    parts = _parse_csv_line(_strip_siglent_pava_prefix(text))
    if parts and re.fullmatch(r"C\d+:PAVA", parts[0].strip(), re.IGNORECASE):
        parts = parts[1:]

    measurements: dict[str, ScopeMeasurement] = {}
    index = 0
    while index + 1 < len(parts):
        name = parts[index].strip().upper()
        raw_value = parts[index + 1].strip().strip('"')
        if name:
            value, unit = _parse_measurement_value(raw_value)
            measurements[name] = ScopeMeasurement(name=name, value=value, unit=unit, raw=raw_value)
        index += 2
    return measurements


def _strip_siglent_pava_prefix(text: str) -> str:
    stripped = text.strip()
    match = re.match(r"^(?:C\d+:)?PAVA\s+", stripped, re.IGNORECASE)
    if match:
        return stripped[match.end() :]
    return stripped


def _parse_measurement_value(raw_value: str) -> tuple[float | None, str]:
    text = raw_value.strip()
    match = re.match(r"^\s*([-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[Ee][-+]?\d+)?)\s*([^\d\s+-].*)?\s*$", text)
    if match is None:
        return None, ""
    try:
        value = float(match.group(1))
    except ValueError:
        return None, ""
    unit = (match.group(2) or "").strip()
    return value, unit


def _safe_siglent_points(points: int | None) -> int:
    if points is None or points <= 0:
        return DEFAULT_CAPTURE_POINTS
    return max(1, min(int(points), MAX_SAFE_SIGLENT_POINTS))


def _restore_local_best_effort(instrument: ScpiSocket, profile: str, run_after_capture: bool) -> None:
    if run_after_capture:
        _write_best_effort(instrument, ":RUN")
        _write_best_effort(instrument, "RUN")
    if profile == PROFILE_SIGLENT:
        _write_best_effort(instrument, "SYST:LOC")
        _write_best_effort(instrument, "SYSTEM:LOCAL")
    time.sleep(0.05)


def _write_best_effort(instrument: ScpiSocket, command: str) -> None:
    try:
        instrument.write(command)
    except Exception:
        pass


def _normalize_channel(channel: str, style: str) -> str:
    text = str(channel).strip().upper()
    digits = "".join(char for char in text if char.isdigit())
    if not digits:
        digits = "1"
    if style == "C":
        return f"C{digits}"
    if style == "CH":
        return f"CH{digits}"
    return f"CHAN{digits}"


def _safe_filename(value: str) -> str:
    return "".join(char if char.isalnum() or char in ("-", "_") else "_" for char in value)
