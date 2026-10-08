"""Development-only resource transport. It does not prove hardware compatibility."""
import struct
from .demo import DemoTransport
from .firmware import APP_START
from .picture import RESOURCES, MAGIC
from .protocol import parse_frame, ProtocolError


class PictureTransport(DemoTransport):
    def __init__(self, *, fault=None):
        super().__init__()
        self.memory.extend(b"\xff" * (0x080ff800 - APP_START - len(self.memory)))
        self.fault = fault
        for resource in RESOURCES.values():
            data = bytearray(resource.size)
            data[:4] = data[-4:] = MAGIC
            offset = resource.address - APP_START
            self.memory[offset:offset + len(data)] = data
        self.read_count = 0

    def _read_memory(self, address, size):
        if any(r.address <= address < address + size <= r.address + r.allocation for r in RESOURCES.values()):
            offset = address - APP_START
            data = bytes(self.memory[offset:offset + size])
            self.read_count += 1
            if self.fault == "verify" and self.written:
                data = bytes((data[0] ^ 1,)) + data[1:]
            return data
        return super()._read_memory(address, size)

    def write(self, frame):
        packet = parse_frame(frame)
        cmd, data = packet.command, packet.payload
        if cmd not in (8, 9, 23):
            return super().write(frame)
        self.sent.append(packet)
        if not self.session:
            raise ProtocolError("先握手")
        if cmd == 23:
            if not self.written or self.batch:
                raise ProtocolError("资源写入未完成")
            self.exited = True
            self._reply(2)
            return 64
        if frame[4] & 0x80 or not self.batch:
            raise ProtocolError("擦写批次或 ACK 标志错误")
        if cmd == 8:
            address, = struct.unpack("<I", data)
            if not any(address in r.addresses for r in RESOURCES.values()):
                raise ProtocolError("拒绝资源范围之外的擦除")
            if self.batch_kind not in (None, "erase"):
                raise ProtocolError("擦除批次错误")
            offset = address - APP_START
            self.memory[offset:offset + 2048] = b"\xff" * 2048
            self.erased = True
            self.batch_kind = "erase"
        else:
            if self.fault == "disconnect":
                raise OSError("模拟拔线")
            address, size = struct.unpack_from("<IB", data)
            chunk = data[5:]
            if not self.erased or len(chunk) != size or not 1 <= size <= 40:
                raise ProtocolError("资源写入长度 / 阶段错误")
            if not any(r.address <= address < address + size <= r.address + r.allocation for r in RESOURCES.values()):
                raise ProtocolError("拒绝越界资源写入")
            offset = address - APP_START
            old = self.memory[offset:offset + size]
            if any(a & b != b for a, b in zip(old, chunk)):
                raise ProtocolError("未擦除的 Flash")
            self.memory[offset:offset + size] = chunk
            self.batch_kind = "write"
            self.written = True
        return 64
