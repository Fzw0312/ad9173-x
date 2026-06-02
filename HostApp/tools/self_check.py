import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from host_app.models import ChannelSettings, NetworkSettings, WaveformSettings, build_config_payload
from host_app.udp_client import UdpWaveformClient, iter_data_payloads
from host_app.waveform import WaveformGenerator


def main() -> None:
    settings = WaveformSettings(sample_count=1024)
    channels = [
        ChannelSettings(amplitude=500, frequency=20),
        ChannelSettings(amplitude=350, frequency=30),
    ]
    result = WaveformGenerator().generate(settings, channels)
    config = build_config_payload(settings, channels, result.source)
    packets = list(iter_data_payloads(result.codes, 1200))
    print(f"source={result.source}")
    print(f"codes_shape={result.codes.shape} dtype={result.codes.dtype}")
    print(f"data_packets={len(packets)} first_payload_bytes={len(packets[0])}")
    print(f"config_protocol={config['protocol']}")
    UdpWaveformClient(NetworkSettings()).send_config(config)
    print("config frame build/send path OK")


if __name__ == "__main__":
    main()
