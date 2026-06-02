import socket
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))


HEADER = struct.Struct("<4sBBHIIIII")


def main() -> None:
    bind = ("0.0.0.0", 5005)
    print(f"Listening on UDP {bind[0]}:{bind[1]}")
    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.bind(bind)
        while True:
            data, addr = sock.recvfrom(65535)
            if len(data) < HEADER.size:
                print(f"{addr}: short packet {len(data)} bytes")
                continue
            magic, version, frame_type, header_len, sequence, flags, payload_len, crc, reserved = HEADER.unpack(
                data[: HEADER.size]
            )
            print(
                f"{addr}: magic={magic!r} ver={version} type={frame_type} seq={sequence} "
                f"payload={payload_len} total={len(data)}"
            )


if __name__ == "__main__":
    main()
