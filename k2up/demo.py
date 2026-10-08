"""Synthetic demo image and read-only flash contents; no vendor firmware."""
import struct
from .firmware import Firmware, APP_START, MARKER_OFFSET, COMMIT_MARKER
from .simulator import SimulatedTransport


def demo_firmware(version=0x58):
    app = bytearray((i * 37 + 11) & 0xfe for i in range(716400))
    struct.pack_into("<II", app, 0, 0x20017d50, APP_START + 0x311)
    app[2048] = version
    app[MARKER_OFFSET:MARKER_OFFSET + 4] = b"\xff" * 4
    return Firmware.from_app(app)


def is_demo_firmware(firmware):
    template = demo_firmware().app
    app = firmware.app
    # Include recovery containers generated from the demo's old 3.4 image.
    return len(app) == len(template) and app[:2048] == template[:2048] and app[2049:] == template[2049:]


class DemoTransport(SimulatedTransport):
    def __init__(self):
        super().__init__()
        self.memory[:] = b"\xff" * len(self.memory)
        old = demo_firmware(0x34)
        self.memory[:len(old.app)] = old.app
        self.memory[MARKER_OFFSET:MARKER_OFFSET + 4] = COMMIT_MARKER

    def _read_memory(self, address, size):
        if 0x08000000 <= address < APP_START and size == 1024:
            return b"\xff" * size
        return super()._read_memory(address, size)


def demo_device():
    return {"path": b"K2-OFFLINE-DEMO", "vendor_id": 0x0716, "product_id": 0x5060,
            "release_number": 0, "manufacturer_string": "离线演示",
            "product_string": "K2 模拟设备", "serial_number": "DEMO",
            "usage_page": 1, "usage": 0, "interface_number": 0}
