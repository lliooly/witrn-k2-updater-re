"""64-byte frames and synchronous command protocol from method RIDs 102–160."""
from dataclasses import dataclass
import math
import struct
import time

FRAME_SIZE = 64
PAYLOAD_SIZE = 52
WRITE_SIZE = 40


class ProtocolError(RuntimeError):
    pass


def build_frame(command, payload=b"", *, reply=True, tick=None):
    if not 0 <= command <= 255 or len(payload) > PAYLOAD_SIZE:
        raise ValueError("命令或负载长度无效")
    tick = (int(time.monotonic() * 1000) if tick is None else tick) & 0xFFFFFFFF
    header = (0xFF, 0x55, tick // 1000, tick % 1000,
              ((tick // 30) | 0x80) if reply else ((tick // 30) & 0x7F),
              tick // 100, tick % 100, tick // 80)
    frame = bytearray(x & 255 for x in header)
    frame.extend(bytes((command, len(payload))) + payload.ljust(PAYLOAD_SIZE, b"\0"))
    frame.append(sum(frame[8:62]) & 255)
    # RID 103 excludes the inner checksum at offset 62.
    frame.append(sum(frame[:62]) & 255)
    return bytes(frame)


@dataclass(frozen=True)
class Packet:
    command: int
    payload: bytes
    raw: bytes


def parse_frame(raw):
    if len(raw) != FRAME_SIZE:
        raise ProtocolError(f"HID 帧长度错误：{len(raw)}，预期 64")
    if raw[:2] != b"\xff\x55":
        raise ProtocolError("回包魔数错误")
    if raw[9] > PAYLOAD_SIZE:
        raise ProtocolError("回包负载长度超过 52")
    if raw[62] != sum(raw[8:62]) & 255:
        raise ProtocolError("回包内层校验失败")
    if raw[63] != sum(raw[:62]) & 255:
        raise ProtocolError("回包外层校验失败")
    return Packet(raw[8], raw[10:10 + raw[9]], bytes(raw))


class Protocol:
    def __init__(self, transport, timeout_ms=1000):
        if not 1 <= timeout_ms <= 60000:
            raise ValueError("超时必须在 1–60000 毫秒之间")
        self.transport = transport
        self.timeout_ms = timeout_ms

    def drain(self):
        # There is no request ID/ACK sequence in the recovered protocol. Remove
        # already-arrived reports before each transaction; never reuse an ACK.
        for _ in range(256):
            raw = self.transport.read(0)
            if not raw:
                return
            packet = parse_frame(raw)
            if packet.command == 1:
                raise ProtocolError("设备在下一请求前报告错误")
            if packet.command != 21:
                raise ProtocolError(f"发现未消费回包 0x{packet.command:02X}，停止以免误配 ACK")
        raise ProtocolError("接收队列持续产生数据，请确认已进入 DFU")

    def _send(self, command, payload=b"", reply=True):
        raw = build_frame(command, payload, reply=reply)
        if self.transport.write(raw) != FRAME_SIZE:
            raise ProtocolError(f"命令 0x{command:02X} 未完整写入")

    def _receive(self, expected, deadline):
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise ProtocolError(f"等待命令 0x{expected:02X} 回包超时")
            raw = self.transport.read(max(1, math.ceil(remaining * 1000)))
            if not raw:
                raise ProtocolError(f"等待命令 0x{expected:02X} 回包超时")
            packet = parse_frame(raw)
            if packet.command == 1:
                raise ProtocolError(f"设备拒绝请求：{packet.payload.hex()}")
            if packet.command == 21:
                continue
            if packet.command != expected:
                raise ProtocolError(f"回包命令 0x{packet.command:02X} 与预期 0x{expected:02X} 不一致")
            return packet.payload

    def command(self, command, payload=b""):
        self.drain()
        self._send(command, payload)
        self._receive(2, time.monotonic() + self.timeout_ms / 1000)

    def erase_sector(self, address):
        # RID 145: no per-sector ACK; cmd 4 closes the batch with an ACK.
        self.drain()
        self._send(8, struct.pack("<I", address), reply=False)

    def write_memory(self, address, data):
        for offset in range(0, len(data), WRITE_SIZE):
            self.drain()
            chunk = data[offset:offset + WRITE_SIZE]
            self._send(9, struct.pack("<IB", address + offset, len(chunk)) + chunk,
                       reply=False)

    def read_memory(self, address, size):
        if not 1 <= size <= 1024:
            raise ValueError("每次读回长度必须在 1–1024 字节之间")
        self.drain()
        self._send(11, struct.pack("<IH", address, size))
        deadline = time.monotonic() + self.timeout_ms / 1000
        result = bytearray()
        while len(result) < size:
            chunk = self._receive(11, deadline)
            expected = min(WRITE_SIZE, size - len(result))
            if len(chunk) != expected:
                raise ProtocolError(f"读回分包长度错误：{len(chunk)}，预期 {expected}")
            result.extend(chunk)
        return bytes(result)

    def read_marker(self, address):
        self.drain()
        self._send(10, struct.pack("<IB", address, 4))
        result = self._receive(10, time.monotonic() + self.timeout_ms / 1000)
        if len(result) != 4:
            raise ProtocolError("提交标记回包长度错误")
        return result
