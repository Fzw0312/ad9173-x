import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from host_app.models import (
    ChannelSettings,
    ModulationSettings,
    NetworkSettings,
    WaveformSettings,
    build_config_payload,
)
from host_app.udp_client import (
    AD9173_MAIN_NCO_HZ,
    AD9173_MAIN_NCO_SIGN,
    CONFIG_FLAG_NCO_ONLY,
    CONFIG_FLAG_RAM_WAVEFORM,
    DAC_DDS_SAMPLE_RATE_HZ,
    UdpWaveformClient,
    build_dac_dds_config_payload,
    iter_data_payloads,
)
from host_app.waveform import WaveformGenerator


def assert_ram_high_frequency_plan() -> None:
    assert abs(AD9173_MAIN_NCO_HZ - (DAC_DDS_SAMPLE_RATE_HZ * 12.0)) < 1.0
    settings = WaveformSettings(sample_count=32768)
    for target_mhz, if_mhz, main_mhz in (
        (150.0, 150.0, 0.0),
        (200.0, 200.0, 0.0),
        (250.0, 200.0, 50.0),
        (400.0, 200.0, 200.0),
        (490.0, 200.0, 290.0),
        (500.0, 200.0, 300.0),
        (800.0, 200.0, 600.0),
        (990.0, 200.0, 790.0),
        (1000.0, 200.0, 800.0),
        (6000.0, 200.0, 5800.0),
    ):
        config = build_config_payload(
            settings,
            [ChannelSettings(amplitude=1.0, amplitude_unit="V", frequency=if_mhz, frequency_unit="MHz")],
            "self_check_ram",
            "ram_waveform",
            modulation=ModulationSettings(modulation_type="sine", loop_coherent=True),
        )
        config["rf"]["output_path"] = "rf"
        config["rf"]["target_frequency_hz"] = target_mhz * 1e6
        config["rf"]["ram_if_hz"] = if_mhz * 1e6
        config["rf"]["ram_main_nco_hz"] = main_mhz * 1e6
        config["rf"]["jesd_main_nco_hz"] = main_mhz * 1e6
        payload = build_dac_dds_config_payload(config)
        ram_ftw = int.from_bytes(payload[12:18], "little")
        main_ftw = int.from_bytes(payload[44:48], "little") | (int.from_bytes(payload[50:52], "little") << 32)
        expected_main_ftw = int(round((AD9173_MAIN_NCO_SIGN * (main_mhz * 1e6) / AD9173_MAIN_NCO_HZ) * (1 << 48))) & 0xFFFFFFFFFFFF
        assert ram_ftw != 0, target_mhz
        assert main_ftw == expected_main_ftw, (target_mhz, main_ftw, expected_main_ftw)
        assert (main_ftw == 0) == (main_mhz == 0.0), (target_mhz, main_ftw)


def main() -> None:
    settings = WaveformSettings(sample_count=1024)
    channels = [
        ChannelSettings(amplitude=500, frequency=20),
        ChannelSettings(amplitude=350, frequency=30),
    ]
    result = WaveformGenerator().generate(settings, channels)
    modulation_sources = []
    for modulation_type in ("sine", "sawtooth", "square", "harmonic", "am", "fm", "pm", "ask", "fsk", "psk"):
        modulation = ModulationSettings(modulation_type=modulation_type, data_pattern="1010")
        mod_result = WaveformGenerator().generate(settings, channels, modulation)
        assert mod_result.codes.shape == (settings.sample_count, 2), modulation_type
        assert mod_result.codes.dtype.str == "<i2", (modulation_type, mod_result.codes.dtype)
        assert int(abs(mod_result.codes[:, 0]).max()) > 0, modulation_type
        modulation_sources.append(f"{modulation_type}:{mod_result.source}")

    ask = WaveformGenerator().generate(
        settings,
        [ChannelSettings(amplitude=500, frequency=20), ChannelSettings(enabled=False)],
        ModulationSettings(modulation_type="ask", data_pattern="1010", ask_low_percent=0.0),
    )
    quarter = settings.sample_count // 4
    ask_peaks = [
        int(abs(ask.codes[index * quarter : (index + 1) * quarter, 0]).max())
        for index in range(4)
    ]
    assert ask_peaks[0] > 0 and ask_peaks[1] == 0 and ask_peaks[2] > 0 and ask_peaks[3] == 0, ask_peaks

    rf_config = {"pe43711_code": 0x22, "output_path": "rf", "target_amplitude_vpk": 1.0}
    config = build_config_payload(settings, channels, result.source)
    config["rf"].update(rf_config)
    nco_config = build_config_payload(settings, channels, result.source, "nco_only")
    nco_config["rf"].update(rf_config)
    lf_jesd_config = build_config_payload(settings, channels, result.source, "jesd_tone")
    lf_jesd_config["rf"].update({"output_path": "lf", "target_amplitude_vpk": 0.5})
    lf_ram_config = build_config_payload(
        settings,
        [ChannelSettings(amplitude=500, frequency=20), ChannelSettings(enabled=False)],
        result.source,
        "ram_waveform",
    )
    lf_ram_config["rf"].update({"output_path": "lf", "target_amplitude_vpk": 0.5})
    lf_nco_config = build_config_payload(settings, channels, result.source, "nco_only")
    lf_nco_config["rf"].update({"output_path": "lf", "target_amplitude_vpk": 0.5})
    ram_config = build_config_payload(
        settings,
        channels,
        "NumPy AM",
        "ram_waveform",
        modulation=ModulationSettings(modulation_type="am", am_depth_percent=25.0),
    )
    packets = list(iter_data_payloads(result.codes, 1200))
    jesd_payload = build_dac_dds_config_payload(config)
    nco_payload = build_dac_dds_config_payload(nco_config)
    ram_payload = build_dac_dds_config_payload(ram_config)
    lf_jesd_payload = build_dac_dds_config_payload(lf_jesd_config)
    lf_ram_payload = build_dac_dds_config_payload(lf_ram_config)
    lf_nco_payload = build_dac_dds_config_payload(lf_nco_config)
    jesd_mask = int.from_bytes(jesd_payload[6:8], "little")
    jesd_ftws = [int.from_bytes(jesd_payload[12 + index * 6 : 18 + index * 6], "little") for index in range(4)]
    jesd_scales = [int.from_bytes(jesd_payload[36 + index * 2 : 38 + index * 2], "little") for index in range(4)]
    print(f"source={result.source}")
    print(f"codes_shape={result.codes.shape} dtype={result.codes.dtype}")
    print(f"data_packets={len(packets)} first_payload_bytes={len(packets[0])}")
    print(f"config_protocol={config['protocol']}")
    print(f"modulations={','.join(modulation_sources)}")
    print(f"jesd_flags=0x{jesd_payload[5]:02x} ram_flags=0x{ram_payload[5]:02x} nco_flags=0x{nco_payload[5]:02x}")
    print(f"jesd_mask=0x{jesd_mask:04x} scales={[hex(value) for value in jesd_scales]}")
    print(f"rf_code=0x{jesd_payload[48]:02x} output_path_sel={jesd_payload[49]}")
    print(
        "lf_nco "
        f"mask=0x{int.from_bytes(lf_nco_payload[6:8], 'little'):04x} "
        f"scales={[hex(int.from_bytes(lf_nco_payload[36 + i * 2 : 38 + i * 2], 'little')) for i in range(4)]} "
        f"path={lf_nco_payload[49]}"
    )
    assert len(jesd_payload) == 52
    assert (nco_payload[5] & CONFIG_FLAG_NCO_ONLY) != 0
    assert (ram_payload[5] & CONFIG_FLAG_RAM_WAVEFORM) != 0
    assert (lf_ram_payload[5] & CONFIG_FLAG_RAM_WAVEFORM) != 0
    assert ram_config["output_mode"] == "ram_waveform"
    assert ram_config["modulation"]["modulation_type"] == "am"
    assert ram_config["modulation"]["am_depth_percent"] == 25.0
    assert jesd_mask == 0x0005
    assert jesd_ftws[0] != 0 and jesd_ftws[1] == 0 and jesd_ftws[2] != 0 and jesd_ftws[3] == 0
    assert jesd_scales[0] != 0 and jesd_scales[1] == 0 and jesd_scales[2] != 0 and jesd_scales[3] == 0
    assert jesd_payload[48] == 0x22 and jesd_payload[49] in (0, 1)
    for payload in (lf_jesd_payload, lf_ram_payload, lf_nco_payload):
        assert payload[49] == 1
        assert int.from_bytes(payload[6:8], "little") == 0x0004
        assert int.from_bytes(payload[36:38], "little") == 0
        assert int.from_bytes(payload[38:40], "little") == 0
        assert int.from_bytes(payload[40:42], "little") != 0
        assert int.from_bytes(payload[42:44], "little") == 0
    assert_ram_high_frequency_plan()
    UdpWaveformClient(NetworkSettings()).send_config(config)
    print("config frame build/send path OK")


if __name__ == "__main__":
    main()
