"""Offline transport for exercising stages; it is not a bootloader emulator.

Its assumptions are documented and do not establish hardware compatibility.
The simulator checks flash bit transitions, address ranges and phase boundaries.
"""
from collections import deque
import struct
from .firmware import (APP_START, APP_LIMIT, INFO_START, NAME_START,
                       SECTOR_SIZE, MARKER_OFFSET, COMMIT_MARKER)
from .protocol import build_frame, parse_frame, ProtocolError


class SimulatedTransport:
    def __init__(self, *, model="K2", fault=None):
        self.model = model
        self.fault = fault
        self.memory = bytearray(b"\x00" * (APP_LIMIT - APP_START))
        self.queue = deque()
        self.sent = []
        self.session = False
        self.batch = False
        self.batch_kind = None
        self.erased = False
        self.written = False
        self.committed = False
        self.exited = False
        self.closed = False

    def _reply(self, command, data=b""):
        frame = build_frame(command, data, tick=0x12345678)
        if self.fault == "bad-frame" and not self.sent[:-1]:
            frame = frame[:-1] + bytes((frame[-1] ^ 1,))
        self.queue.append(frame)

    def _read_memory(self, address, size):
        if address == INFO_START and size == 1024:
            return b"\xff" * 1024
        if address == NAME_START and size == 256:
            return (self.model.encode() + b"\0WITRN\0DFU\0").ljust(256, b"\xff")
        if not APP_START <= address < address + size <= APP_LIMIT:
            raise ProtocolError("模拟设备拒绝越界读取")
        data = bytes(self.memory[address - APP_START:address - APP_START + size])
        if self.fault == "verify" and size > 4:
            data = bytes((data[0] ^ 1,)) + data[1:]
        if self.fault == "marker" and size == 4 and self.committed:
            data = b"\xff" * 4
        return data

    def write(self, frame):
        packet = parse_frame(frame)
        cmd, data = packet.command, packet.payload
        self.sent.append(packet)
        if self.fault == "disconnect" and cmd == 9:
            raise OSError("模拟拔线")
        if self.fault == "short-write" and cmd == 9:
            return 32
        if not self.session and cmd != 3:
            raise ProtocolError("模拟设备要求先握手")
        if cmd == 3:
            if self.fault == "timeout":
                return 64
            if self.fault == "nack":
                self._reply(1, b"\x01")
                return 64
            if self.fault == "wrong-ack":
                self._reply(4)
                return 64
            self.session = True
        elif cmd == 22:
            pass
        elif cmd == 5:
            if self.batch:
                raise ProtocolError("模拟设备拒绝重复打开写入批次")
            self.batch = True
            self.batch_kind = None
        elif cmd == 4:
            if not self.batch:
                raise ProtocolError("模拟设备没有活动写入批次")
            self.batch = False
            if self.fault == "batch-nack" and self.batch_kind == "erase":
                self._reply(1)
                return 64
        elif cmd == 8:
            address, = struct.unpack("<I", data)
            if not self.batch or self.batch_kind not in (None, "erase"):
                raise ProtocolError("模拟设备擦除阶段错误")
            if not APP_START <= address <= APP_LIMIT - SECTOR_SIZE or (address - APP_START) % SECTOR_SIZE:
                raise ProtocolError("模拟设备拒绝越界或非对齐擦除")
            offset = address - APP_START
            self.memory[offset:offset + SECTOR_SIZE] = b"\xff" * SECTOR_SIZE
            self.erased = True
            self.batch_kind = "erase"
        elif cmd == 9:
            address, size = struct.unpack_from("<IB", data)
            chunk = data[5:]
            if not self.batch or not self.erased or not 1 <= size <= 40 or size != len(chunk):
                raise ProtocolError("模拟设备写入状态 / 长度错误")
            if not APP_START <= address < address + size <= APP_LIMIT:
                raise ProtocolError("模拟设备拒绝越界写入")
            offset = address - APP_START
            old = self.memory[offset:offset + size]
            if any(a & b != b for a, b in zip(old, chunk)):
                raise ProtocolError("Flash 不能在未擦除时把 0 写回 1")
            self.memory[offset:offset + size] = chunk
            self.batch_kind = "write"
            self.written = True
            if address == APP_START + MARKER_OFFSET and chunk == COMMIT_MARKER:
                self.committed = True
        elif cmd in (10, 11):
            address, size = struct.unpack("<IB" if cmd == 10 else "<IH", data)
            result = self._read_memory(address, size)
            for offset in range(0, size, 40):
                self._reply(cmd, result[offset:offset + 40])
            return 64
        elif cmd == 23:
            if not self.committed or self.batch:
                raise ProtocolError("模拟设备拒绝退出未提交应用")
            self.exited = True
        else:
            raise ProtocolError(f"模拟设备不支持命令 {cmd}")
        expects_reply = bool(frame[4] & 0x80)
        if cmd in (8, 9) and expects_reply:
            raise ProtocolError("擦写分包不应要求 ACK")
        if cmd not in (8, 9) and not expects_reply:
            raise ProtocolError("控制命令应要求 ACK")
        if expects_reply:
            self._reply(2)
        return 64

    def read(self, timeout_ms):
        return self.queue.popleft() if self.queue else b""

    def close(self):
        self.closed = True
