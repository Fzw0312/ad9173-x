from dataclasses import asdict, dataclass
from typing import Dict, List


AMPLITUDE_UNITS: Dict[str, float] = {
    "mV": 1e-3,
    "V": 1.0,
}

FREQUENCY_UNITS: Dict[str, float] = {
    "mHz": 1e-3,
    "Hz": 1.0,
    "kHz": 1e3,
    "MHz": 1e6,
    "GHz": 1e9,
}

SAMPLE_RATE_UNITS: Dict[str, float] = {
    "kSPS": 1e3,
    "MSPS": 1e6,
    "GSPS": 1e9,
}


@dataclass
class ChannelSettings:
    enabled: bool = True
    amplitude: float = 500.0
    amplitude_unit: str = "mV"
    frequency: float = 20.0
    frequency_unit: str = "MHz"

    def amplitude_volts(self) -> float:
        return float(self.amplitude) * AMPLITUDE_UNITS[self.amplitude_unit]

    def frequency_hz(self) -> float:
        return float(self.frequency) * FREQUENCY_UNITS[self.frequency_unit]

    def to_payload(self) -> dict:
        payload = asdict(self)
        payload["amplitude_vpk"] = self.amplitude_volts()
        payload["frequency_hz"] = self.frequency_hz()
        return payload


@dataclass
class WaveformSettings:
    sample_rate: float = 983.04
    sample_rate_unit: str = "MSPS"
    sample_count: int = 4096
    dac_full_scale_vpk: float = 1.0

    def sample_rate_hz(self) -> float:
        return float(self.sample_rate) * SAMPLE_RATE_UNITS[self.sample_rate_unit]

    def to_payload(self) -> dict:
        payload = asdict(self)
        payload["sample_rate_hz"] = self.sample_rate_hz()
        return payload


@dataclass
class NetworkSettings:
    target_ip: str = "192.168.1.10"
    target_port: int = 5005
    local_port: int = 0
    max_datagram_bytes: int = 1200
    local_ip: str = ""


def build_config_payload(
    waveform: WaveformSettings,
    channels: List[ChannelSettings],
    source: str,
) -> dict:
    return {
        "app": "ku5p_ad9173_host",
        "protocol": "udp_waveform_v1",
        "source": source,
        "waveform": waveform.to_payload(),
        "channels": [channel.to_payload() for channel in channels],
        "sample_format": "int16_le_interleaved_ch0_ch1",
        "amplitude_convention": "Vpk; code = volts / dac_full_scale_vpk * 32767",
    }
