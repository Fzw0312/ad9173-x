import struct
import sys
import zlib
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "HostApp"))

from host_app.adc_udp_receiver import AdcUdpReceiver


def eth_crc_ok(frame: bytes) -> bool:
    if len(frame) < 4:
        return False
    return (zlib.crc32(frame[:-4]) & 0xFFFFFFFF) == int.from_bytes(frame[-4:], "little")


def ip_checksum(header: bytes) -> int:
    total = 0
    for i in range(0, len(header), 2):
        total += (header[i] << 8) | header[i + 1]
        total = (total & 0xFFFF) + (total >> 16)
    return (~total) & 0xFFFF


def split_frames(raw: bytes) -> list[bytes]:
    frames = []
    i = 0
    preamble = b"\x55" * 7 + b"\xd5"
    while i < len(raw):
        j = raw.find(preamble, i)
        if j < 0:
            break
        k = raw.find(preamble, j + len(preamble))
        if k < 0:
            frame = raw[j + len(preamble) :]
            if frame:
                frames.append(frame)
            break
        frame = raw[j + len(preamble) : k].rstrip(b"\x00")
        if frame:
            frames.append(frame)
        i = k
    return frames


def sample_code(idx: int) -> int:
    return (idx * 257 + 0x1234) & 0xFFFF


def main() -> None:
    byte_file = Path(__file__).with_name("tb_udp_rgmii_loopback_path_bytes.txt")
    raw = bytes(int(line.strip(), 16) for line in byte_file.read_text().splitlines() if line.strip())
    frames = split_frames(raw)
    assert frames, "no frames found"

    captures = []
    messages = []
    receiver = AdcUdpReceiver("127.0.0.1", 0, 3.0e9, captures.append, messages.append)

    for frame in frames:
        assert eth_crc_ok(frame), "bad Ethernet FCS after RGMII reconstruction"
        eth = frame[:-4]
        assert eth[0:6] == b"\xff" * 6
        assert eth[12:14] == b"\x08\x00"
        ip = eth[14:34]
        assert ip[0] == 0x45
        assert ((ip[2] << 8) | ip[3]) == len(eth) - 14
        assert ip_checksum(ip) == 0
        udp = eth[34:42]
        src_port, dst_port, udp_len, udp_sum = struct.unpack("!HHHH", udp)
        assert src_port == 6006
        assert dst_port == 6006
        assert udp_len == len(eth) - 34
        assert udp_sum == 0
        receiver._handle_datagram(eth[42:], ("192.168.1.10", 6006))

    assert len(captures) == 1, f"captures={len(captures)} messages={messages}"
    expected_u16 = np.array([sample_code(i) for i in range(64)], dtype=np.uint16)
    expected_i16 = expected_u16.view(np.int16).astype(np.float64) / 32768.0
    assert np.allclose(captures[0].samples, expected_i16)
    assert receiver.stats.crc_errors == 0
    assert receiver.stats.protocol_errors == 0
    print(
        f"udp_rgmii_loopback_path_check_ok frames={len(frames)} "
        f"samples={captures[0].samples.size}"
    )


if __name__ == "__main__":
    main()
