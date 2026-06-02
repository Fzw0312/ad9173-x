import json
import socket
import struct
import time
import zlib
from enum import IntEnum
from typing import Callable, Iterable, Optional

import numpy as np

from .models import NetworkSettings


MAGIC = b"K5WG"
VERSION = 1
HEADER = struct.Struct("<4sBBHIIIII")
DATA_CHUNK = struct.Struct("<HHIIII")
DAC_DDS_CONFIG_PREFIX = struct.Struct("<4sBBHI")
DAC_DDS_CONFIG_SUFFIX = struct.Struct("<HHHHI")
SAMPLE_FORMAT_INT16_IQ2 = 1
DAC_DDS_SAMPLE_RATE_HZ = 983_040_000


class FrameType(IntEnum):
    HELLO = 1
    CONFIG = 2
    DATA = 3
    COMMIT = 4


def build_frame(frame_type: FrameType, sequence: int, payload: bytes, flags: int = 0) -> bytes:
    crc = zlib.crc32(payload) & 0xFFFFFFFF
    header = HEADER.pack(
        MAGIC,
        VERSION,
        int(frame_type),
        HEADER.size,
        int(sequence) & 0xFFFFFFFF,
        int(flags) & 0xFFFFFFFF,
        len(payload),
        crc,
        0,
    )
    return header + payload


def json_payload(payload: dict) -> bytes:
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")


def build_dac_dds_config_payload(config: dict, reset_phase: bool = True) -> bytes:
    waveform = config.get("waveform", {})
    channels = list(config.get("channels", []))
    sample_rate_hz = float(waveform.get("sample_rate_hz", DAC_DDS_SAMPLE_RATE_HZ))
    if sample_rate_hz <= 0.0:
        sample_rate_hz = float(DAC_DDS_SAMPLE_RATE_HZ)
    full_scale_vpk = float(waveform.get("dac_full_scale_vpk", 1.0))
    if full_scale_vpk <= 0.0:
        full_scale_vpk = 1.0

    phase_inc = []
    scales = []
    channel_mask = 0
    mirror_source_count = len(channels) if len(channels) > 0 else 1
    for index in range(4):
        source_index = index if index < len(channels) else index % mirror_source_count
        channel = channels[source_index] if channels else {}
        enabled = bool(channel.get("enabled", True))
        if enabled:
            channel_mask |= (1 << index)
        frequency_hz = float(channel.get("frequency_hz", 0.0)) if enabled else 0.0
        amplitude_vpk = abs(float(channel.get("amplitude_vpk", 0.0))) if enabled else 0.0
        ftw = int(round((frequency_hz / sample_rate_hz) * (1 << 48))) & 0xFFFFFFFFFFFF
        scale = int(round(min(amplitude_vpk / full_scale_vpk, 1.0) * 0x7FFF))
        phase_inc.append(ftw)
        scales.append(max(0, min(scale, 0x7FFF)))

    flags = 0x01 if reset_phase else 0x00
    payload = DAC_DDS_CONFIG_PREFIX.pack(
        b"K5DC",
        1,
        flags,
        channel_mask & 0xFFFF,
        int(round(sample_rate_hz)) & 0xFFFFFFFF,
    )
    payload += b"".join(value.to_bytes(6, "little", signed=False) for value in phase_inc)
    payload += DAC_DDS_CONFIG_SUFFIX.pack(
        scales[0],
        scales[1],
        scales[2],
        scales[3],
        0,
    )
    return payload


def iter_data_payloads(codes: np.ndarray, max_datagram_bytes: int) -> Iterable[bytes]:
    if codes.ndim != 2 or codes.shape[1] != 2:
        raise ValueError("codes must be shaped as [samples, 2]")

    bytes_per_sample_pair = 4
    usable = max_datagram_bytes - HEADER.size - DATA_CHUNK.size
    sample_pairs_per_packet = max(1, usable // bytes_per_sample_pair)
    total_samples = int(codes.shape[0])

    for offset in range(0, total_samples, sample_pairs_per_packet):
        chunk = codes[offset : offset + sample_pairs_per_packet]
        payload_header = DATA_CHUNK.pack(
            0x0003,
            SAMPLE_FORMAT_INT16_IQ2,
            offset,
            int(chunk.shape[0]),
            total_samples,
            0,
        )
        yield payload_header + chunk.astype("<i2", copy=False).tobytes(order="C")


class UdpWaveformClient:
    def __init__(self, network: NetworkSettings):
        self.network = network
        self.sequence = 1

    def send_hello(self) -> int:
        payload = json_payload({"app": "ku5p_ad9173_host", "time": time.time()})
        return self._send_frames([build_frame(FrameType.HELLO, self._next_sequence(), payload)])

    def send_config(self, config: dict) -> int:
        frames = [
            build_frame(FrameType.CONFIG, self._next_sequence(), json_payload(config)),
            build_frame(FrameType.CONFIG, self._next_sequence(), build_dac_dds_config_payload(config)),
        ]
        return self._send_frames(frames, broadcast_last=True)

    def send_waveform(
        self,
        config: dict,
        codes: np.ndarray,
        progress: Optional[Callable[[int, int], None]] = None,
    ) -> int:
        frames = [
            build_frame(FrameType.CONFIG, self._next_sequence(), json_payload(config)),
            build_frame(FrameType.CONFIG, self._next_sequence(), build_dac_dds_config_payload(config)),
        ]

        data_payloads = list(iter_data_payloads(codes, self.network.max_datagram_bytes))
        total_data_frames = len(data_payloads)
        for index, payload in enumerate(data_payloads, start=1):
            frames.append(build_frame(FrameType.DATA, self._next_sequence(), payload))
            if progress:
                progress(index, total_data_frames)

        commit = {
            "total_samples": int(codes.shape[0]),
            "data_frames": total_data_frames,
            "sample_format": "int16_le_interleaved_ch0_ch1",
        }
        frames.append(build_frame(FrameType.COMMIT, self._next_sequence(), json_payload(commit)))
        return self._send_frames(frames, broadcast_config=True)

    def _send_frames(
        self,
        frames: Iterable[bytes],
        broadcast_last: bool = False,
        broadcast_config: bool = False,
    ) -> int:
        sent = 0
        target = (self.network.target_ip, int(self.network.target_port))
        broadcast_target = ("255.255.255.255", int(self.network.target_port))
        target_ip = self.network.target_ip.strip().lower()
        target_is_broadcast = target_ip in ("255.255.255.255", "<broadcast>")
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            bind_ip = getattr(self.network, "local_ip", "").strip()
            if self.network.local_port or bind_ip:
                sock.bind((bind_ip, int(self.network.local_port)))
            if target_is_broadcast or broadcast_last or broadcast_config:
                sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            frame_list = list(frames)
            for index, frame in enumerate(frame_list):
                sock.sendto(frame, target)
                sent += 1
                if broadcast_last and index == len(frame_list) - 1:
                    sock.sendto(frame, broadcast_target)
                    sent += 1
                elif broadcast_config and frame[0:4] == MAGIC and frame[5] == int(FrameType.CONFIG):
                    sock.sendto(frame, broadcast_target)
                    sent += 1
        return sent

    def _next_sequence(self) -> int:
        current = self.sequence
        self.sequence = (self.sequence + 1) & 0xFFFFFFFF
        if self.sequence == 0:
            self.sequence = 1
        return current
