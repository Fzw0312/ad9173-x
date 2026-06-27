import json
import math
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
DAC_DDS_CONFIG_SUFFIX = struct.Struct("<HHHHIBBH")
SAMPLE_FORMAT_INT16_IQ2 = 1
DAC_DDS_SAMPLE_RATE_HZ = 983_040_000
AD9173_NOMINAL_NCO_HZ = 1_474_560_000.0
AD9173_NCO_CALIBRATION_PPM = 0.0
AD9173_NCO_HZ = AD9173_NOMINAL_NCO_HZ * (1.0 + AD9173_NCO_CALIBRATION_PPM * 1e-6)
# Main NCO FTW is referenced to the DAC main datapath rate, not the
# 983.04 MSPS JESD payload rate. This board runs the main datapath at 12x.
AD9173_MAIN_NCO_HZ = DAC_DDS_SAMPLE_RATE_HZ * 12.0
AD9173_MAIN_NCO_SIGN = -1.0
AD9173_NCO_MAX_AMP = 0x50FF
HMC788_GAIN_DB = 14.0
RELAY_ATTENUATOR_STAGES_DB = (5.0, 10.0, 15.0, 20.0)
RELAY_ATTENUATOR_MAX_DB = sum(RELAY_ATTENUATOR_STAGES_DB)
RELAY_ATTENUATOR_STEP_DB = 5.0
CONFIG_FLAG_RESET_PHASE = 0x01
CONFIG_FLAG_NCO_ONLY = 0x02
CONFIG_FLAG_RAM_WAVEFORM = 0x04


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


def relay_attenuation_db_from_mask(mask: int) -> float:
    mask = int(mask) & 0x0F
    return sum(stage_db for bit, stage_db in enumerate(RELAY_ATTENUATOR_STAGES_DB) if mask & (1 << bit))


def relay_mask_for_attenuation_db(atten_db: float) -> tuple[int, float]:
    target_db = max(0.0, min(float(atten_db), RELAY_ATTENUATOR_MAX_DB))
    best_mask = 0
    best_db = 0.0
    best_error = float("inf")
    for mask in range(16):
        candidate_db = relay_attenuation_db_from_mask(mask)
        error = abs(candidate_db - target_db)
        if error < best_error or (math.isclose(error, best_error) and candidate_db <= target_db):
            best_mask = mask
            best_db = candidate_db
            best_error = error
    return best_mask, best_db


def calculate_rf_output_control(target_vpk: float, full_scale_vpk: float) -> tuple[float, int, float]:
    target_vpk = max(0.0005, min(float(target_vpk), 3.0))
    full_scale_vpk = max(float(full_scale_vpk), 0.001)
    gain_linear = 10.0 ** (HMC788_GAIN_DB / 20.0)
    max_dac_for_target = target_vpk * (10.0 ** (RELAY_ATTENUATOR_MAX_DB / 20.0)) / gain_linear
    dac_vpk = max(0.0, min(full_scale_vpk, max_dac_for_target))
    pre_atten_vpk = max(dac_vpk * gain_linear, 1e-12)
    atten_db = max(0.0, min(RELAY_ATTENUATOR_MAX_DB, 20.0 * math.log10(pre_atten_vpk / target_vpk)))
    mask, rounded_atten_db = relay_mask_for_attenuation_db(atten_db)
    return dac_vpk, mask, rounded_atten_db


def build_dac_dds_config_payload(config: dict, reset_phase: bool = True) -> bytes:
    waveform = config.get("waveform", {})
    channels = list(config.get("channels", []))
    output_mode = str(config.get("output_mode", "jesd_tone"))
    nco_only = output_mode == "nco_only"
    sample_rate_hz = float(waveform.get("sample_rate_hz", DAC_DDS_SAMPLE_RATE_HZ))
    if sample_rate_hz <= 0.0:
        sample_rate_hz = float(DAC_DDS_SAMPLE_RATE_HZ)
    rf = dict(config.get("rf", {}))
    rf_cal = dict(rf.get("calibration", {}))
    lf_cal = dict(rf.get("lf_calibration", {}))
    active_nco_cal = lf_cal if lf_cal.get("enabled") else rf_cal
    ftw_rate_hz = float(active_nco_cal.get("nco_hz", AD9173_NCO_HZ)) if nco_only else sample_rate_hz
    full_scale_vpk = float(waveform.get("dac_full_scale_vpk", 1.0))
    if full_scale_vpk <= 0.0:
        full_scale_vpk = 1.0
    output_path = str(rf.get("output_path", "rf"))
    output_path_sel = 0 if output_path == "lf" else 1
    target_rf_vpk = float(rf.get("target_amplitude_vpk", 1.0))
    jesd_main_nco_hz = 0.0 if nco_only else float(rf.get("jesd_main_nco_hz", 0.0))
    jesd_main_nco_ftw = int(round((AD9173_MAIN_NCO_SIGN * jesd_main_nco_hz / AD9173_MAIN_NCO_HZ) * (1 << 48))) & 0xFFFFFFFFFFFF
    rf_dac_vpk, auto_rf_atten_mask, _rf_atten_db = calculate_rf_output_control(target_rf_vpk, full_scale_vpk)
    jesd_scale_max = 0x7FFF
    if rf_cal.get("enabled"):
        rf_atten_mask = max(0, min(15, int(rf_cal.get("relay_atten_mask", auto_rf_atten_mask))))
        rf_cal_amp_code_max = AD9173_NCO_MAX_AMP if nco_only else jesd_scale_max
        rf_cal_amp_code = max(0, min(rf_cal_amp_code_max, int(rf_cal.get("amp_code", 0))))
    else:
        rf_atten_mask = max(0, min(15, int(rf.get("relay_atten_mask", auto_rf_atten_mask))))
        rf_cal_amp_code = 0
    lf_cal_amp_code_max = AD9173_NCO_MAX_AMP if nco_only else jesd_scale_max
    lf_cal_amp_code = max(0, min(lf_cal_amp_code_max, int(lf_cal.get("amp_code", 0)))) if lf_cal.get("enabled") else 0

    if output_path == "lf":
        gui_to_dac_map = [None, 0, None, None] if output_mode == "ram_waveform" else [None, None, 0, None]
    else:
        gui_to_dac_map = [0, None, 1, None]

    phase_inc = []
    scales = []
    channel_mask = 0
    for index in range(4):
        source_index = gui_to_dac_map[index]
        channel = channels[source_index] if source_index is not None and source_index < len(channels) else {}
        enabled = source_index is not None and bool(channel.get("enabled", True))
        if enabled:
            channel_mask |= (1 << index)
        frequency_hz = float(channel.get("frequency_hz", 0.0)) if enabled else 0.0
        amplitude_vpk = abs(float(channel.get("amplitude_vpk", 0.0))) if enabled else 0.0
        if output_path == "rf" and index == 0 and enabled and not rf_cal.get("enabled"):
            amplitude_vpk = rf_dac_vpk
        ftw = int(round((frequency_hz / ftw_rate_hz) * (1 << 48))) & 0xFFFFFFFFFFFF
        max_scale = AD9173_NCO_MAX_AMP if nco_only else 0x7FFF
        if output_path == "rf" and index == 0 and enabled and rf_cal.get("enabled"):
            scale = rf_cal_amp_code
        elif output_path == "lf" and index in (1, 2) and enabled and lf_cal.get("enabled"):
            scale = lf_cal_amp_code
        else:
            scale = int(round(min(amplitude_vpk / full_scale_vpk, 1.0) * max_scale))
        phase_inc.append(ftw)
        scales.append(max(0, min(scale, max_scale)))

    flags = CONFIG_FLAG_NCO_ONLY if nco_only else 0x00
    if output_mode == "ram_waveform":
        flags |= CONFIG_FLAG_RAM_WAVEFORM
    if reset_phase:
        flags |= CONFIG_FLAG_RESET_PHASE
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
        jesd_main_nco_ftw & 0xFFFFFFFF,
        rf_atten_mask,
        output_path_sel,
        (jesd_main_nco_ftw >> 32) & 0xFFFF,
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


class UdpRuntimeConfigStreamer:
    """Keep one UDP socket open for fast runtime NCO CONFIG updates."""

    def __init__(self, network: NetworkSettings):
        self.network = network
        self.sequence = 1
        self.target = (self.network.target_ip, int(self.network.target_port))
        target_ip = self.network.target_ip.strip().lower()
        self.target_is_broadcast = target_ip in ("255.255.255.255", "<broadcast>")
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        bind_ip = getattr(self.network, "local_ip", "").strip()
        if self.network.local_port or bind_ip:
            self.sock.bind((bind_ip, int(self.network.local_port)))
        if self.target_is_broadcast:
            self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)

    def send_dac_config(self, config: dict) -> int:
        return self.send_dac_config_payload(build_dac_dds_config_payload(config))

    def send_dac_config_payload(self, payload: bytes) -> int:
        frame = build_frame(FrameType.CONFIG, self._next_sequence(), payload)
        self.sock.sendto(frame, self.target)
        return 1

    def close(self) -> None:
        self.sock.close()

    def _next_sequence(self) -> int:
        current = self.sequence
        self.sequence = (self.sequence + 1) & 0xFFFFFFFF
        if self.sequence == 0:
            self.sequence = 1
        return current
