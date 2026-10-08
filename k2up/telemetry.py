"""Passive K2 telemetry. Field mapping adapted from MIT witrn-driver.

Copyright (c) 2022 didim99. See third_party/witrn-driver-LICENSE.txt.
No DFU commands, acknowledgements, USB resets or device writes belong here.
"""
from dataclasses import asdict, dataclass
import math
import struct

from .transport import normalize_input


@dataclass(frozen=True)
class Sample:
    time: float
    voltage: float
    current: float
    power: float
    signed_power: float
    temp_in: float = None
    temp_out: float = None
    dp: float = None
    dn: float = None
    ah: float = None
    wh: float = None
    record_seconds: int = None
    uptime: int = None
    group: int = None
    segment: int = 0

    def dictionary(self):
        return asdict(self)


def decode_report(raw, elapsed):
    """Return None for other commands; reject malformed telemetry.

    Both checksum sums were confirmed on normal-mode K2 telemetry captures.
    """
    data = normalize_input(raw)
    if not data or data[:2] != b"\xff\x55" or data[8] != 0x1A:
        return None
    if not 45 <= data[9] <= 52:
        raise ValueError("遥测载荷长度无效")
    if not dfu_checksum_matches(data):
        raise ValueError("遥测校验不一致")
    # Time counters between Ah/Wh and D+/D- are integers, not floats.
    ah, wh = struct.unpack_from("<2f", data, 14)
    rectime, uptime = struct.unpack_from("<2I", data, 22)
    dp, dn, ti, to, voltage, current = struct.unpack_from("<6f", data, 30)
    if not all(math.isfinite(v) for v in (elapsed, voltage, current, ah, wh, dp, dn)):
        raise ValueError("遥测包含非有限测量值")
    if elapsed < 0 or not 0 <= voltage <= 100 or abs(current) > 100:
        raise ValueError("遥测电压、电流或时间超出有效范围")
    def temperature(v, external=False):
        return v if math.isfinite(v) and -100 <= v <= 200 and (not external or v > 0) else None
    return Sample(elapsed, voltage, current, voltage * abs(current), voltage * current,
                  temperature(ti), temperature(to, True), dp, dn, ah, wh,
                  rectime, uptime, data[54] + 1)


def dfu_checksum_matches(raw):
    data = normalize_input(raw)
    return (len(data) == 64 and data[62] == sum(data[8:62]) % 256
            and data[63] == sum(data[:62]) % 256)


class Sampler:
    """Host-side upper bound; never manufacture samples or change device rate."""
    def __init__(self, rate=10):
        if rate not in (0, 1, 10, 100):
            raise ValueError("采样率应为全部、1、10 或 100 样本/秒")
        self.interval = 1 / rate if rate else 0
        self.last_slot = None

    def accept(self, time):
        if not math.isfinite(time) or time < 0:
            raise ValueError("采样时间无效")
        if not self.interval: return True
        # Fixed elapsed-time buckets avoid shifting the deadline on each packet.
        # Otherwise a 9.999 ms arrival after a 10 ms sample skips a whole packet,
        # drifting a 100 Hz source down to roughly 65 Hz in hardware testing.
        slot = math.floor(time / self.interval + 1e-9)
        if self.last_slot is None or slot > self.last_slot:
            self.last_slot = slot
            return True
        return False
