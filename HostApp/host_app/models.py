from dataclasses import asdict, dataclass
from typing import Dict, List


AMPLITUDE_UNITS: Dict[str, float] = {
    "mV": 1e-3,
    "V": 1.0,
}

FREQUENCY_UNITS: Dict[str, float] = {
    "uHz": 1e-6,
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

MAX_WAVEFORM_SAMPLES = 32768
DIGITAL_SYMBOL_COUNT = 4

OUTPUT_MODES: Dict[str, str] = {
    "nco_only": "SPI调试",
    "jesd_tone": "DDS单音输出",
    "ram_waveform": "任意波形输出",
}

MODULATION_TYPES: Dict[str, str] = {
    "sine": "Sine",
    "sawtooth": "Sawtooth",
    "square": "Square",
    "harmonic": "Custom harmonics",
    "am": "AM",
    "fm": "FM",
    "pm": "PM",
    "ask": "4ASK",
    "fsk": "4FSK",
    "psk": "4PSK",
}

OUTPUT_PATHS: Dict[str, str] = {
    "rf": "RF DAC0 10MHz-2GHz",
    "lf": "LF DAC1 3.49uHz-10MHz",
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
    sample_count: int = MAX_WAVEFORM_SAMPLES
    dac_full_scale_vpk: float = 1.0

    def sample_rate_hz(self) -> float:
        return float(self.sample_rate) * SAMPLE_RATE_UNITS[self.sample_rate_unit]

    def to_payload(self) -> dict:
        payload = asdict(self)
        payload["sample_rate_hz"] = self.sample_rate_hz()
        return payload


@dataclass
class ModulationSettings:
    modulation_type: str = "sine"
    loop_coherent: bool = False
    mod_frequency: float = 120.0
    mod_frequency_unit: str = "kHz"
    am_depth_percent: float = 50.0
    fm_deviation: float = 5.0
    fm_deviation_unit: str = "MHz"
    pm_deviation_deg: float = 90.0
    symbol_rate: float = 120.0
    symbol_rate_unit: str = "kHz"
    ask_low_percent: float = 10.0
    fsk_deviation: float = 5.0
    fsk_deviation_unit: str = "MHz"
    psk_order: int = 2
    data_pattern: str = "1011"
    harmonic_spec: str = "1:1,2:0.30,3:0.15"
    sawtooth_rise_percent: float = 50.0
    square_duty_percent: float = 50.0

    def mod_frequency_hz(self) -> float:
        return float(self.mod_frequency) * FREQUENCY_UNITS[self.mod_frequency_unit]

    def fm_deviation_hz(self) -> float:
        return float(self.fm_deviation) * FREQUENCY_UNITS[self.fm_deviation_unit]

    def symbol_rate_hz(self) -> float:
        return float(self.symbol_rate) * FREQUENCY_UNITS[self.symbol_rate_unit]

    def fsk_deviation_hz(self) -> float:
        return float(self.fsk_deviation) * FREQUENCY_UNITS[self.fsk_deviation_unit]

    def to_payload(self) -> dict:
        payload = asdict(self)
        payload["modulation_label"] = MODULATION_TYPES.get(self.modulation_type, MODULATION_TYPES["sine"])
        payload["mod_frequency_hz"] = self.mod_frequency_hz()
        payload["fm_deviation_hz"] = self.fm_deviation_hz()
        payload["symbol_rate_hz"] = self.symbol_rate_hz()
        payload["fsk_deviation_hz"] = self.fsk_deviation_hz()
        payload["digital_symbol_count"] = DIGITAL_SYMBOL_COUNT
        payload["digital_pattern_bits"] = self.digital_pattern_bits()
        payload["harmonic_spec"] = self.harmonic_spec
        payload["sawtooth_rise_percent"] = self.sawtooth_rise_percent
        payload["square_duty_percent"] = self.square_duty_percent
        return payload

    def digital_pattern_bits(self) -> str:
        bits = "".join(char for char in str(self.data_pattern) if char in {"0", "1"})
        if not bits:
            bits = "1011"
        return (bits + "0000")[:DIGITAL_SYMBOL_COUNT]


@dataclass
class RfSettings:
    output_path: str = "rf"
    target_amplitude_vpk: float = 1.0
    relay_atten_db: float = 0.0
    relay_atten_mask: int = 0x00
    hmc788_gain_db: float = 14.0

    def to_payload(self) -> dict:
        payload = asdict(self)
        payload["output_path_label"] = OUTPUT_PATHS.get(self.output_path, OUTPUT_PATHS["rf"])
        payload["output_path_sel"] = 0 if self.output_path == "lf" else 1
        payload["relay_atten_mask"] = max(0, min(int(self.relay_atten_mask), 15))
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
    output_mode: str = "jesd_tone",
    rf: RfSettings | None = None,
    modulation: ModulationSettings | None = None,
) -> dict:
    if output_mode not in OUTPUT_MODES:
        output_mode = "jesd_tone"
    if rf is None:
        rf = RfSettings()
    if modulation is None:
        modulation = ModulationSettings()
    return {
        "app": "ku5p_ad9173_host",
        "protocol": "udp_waveform_v1",
        "source": source,
        "output_mode": output_mode,
        "output_mode_label": OUTPUT_MODES[output_mode],
        "rf": rf.to_payload(),
        "modulation": modulation.to_payload(),
        "waveform": waveform.to_payload(),
        "channels": [channel.to_payload() for channel in channels],
        "sample_format": "int16_le_interleaved_ch0_ch1",
        "amplitude_convention": "Vpk; code = volts / dac_full_scale_vpk * 32767",
    }
