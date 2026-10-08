"""K2 container validation. No hardware access or optional dependencies."""
from dataclasses import dataclass
from datetime import date
from functools import reduce
import hashlib
from pathlib import Path
import struct
import uuid

DATA = Path(__file__).with_name("data")
HEADER_SIZE = 48
APP_START = 0x08003800
INFO_START = 0x08003000
NAME_START = 0x08001400
K2_GUID = uuid.UUID("5a3f8522-366b-46cc-aacc-dbfbe2fee02a")
SECTOR_SIZE = 2048
SECTOR_COUNT = 447
APP_LIMIT = APP_START + SECTOR_SIZE * SECTOR_COUNT
MARKER_OFFSET = 3072
COMMIT_MARKER = b"\xfe\xff\xff\xff"


class FirmwareError(ValueError):
    pass


@dataclass(frozen=True)
class Firmware:
    source: bytes
    app: bytes
    date: str
    version: str
    model_guid: uuid.UUID

    @classmethod
    def parse(cls, raw: bytes):
        table = (DATA / "firmware_decode.bin").read_bytes()
        if len(table) != 256 or len(set(table)) != 256:
            raise FirmwareError("固件解码表损坏")
        if len(raw) < HEADER_SIZE:
            raise FirmwareError("文件不足 48 字节")
        if len(raw) > SECTOR_SIZE * SECTOR_COUNT:
            raise FirmwareError("文件超出 K2 配置的应用扇区范围")
        decoded = raw.translate(table)
        if decoded[:7] != b"gzutapp":
            raise FirmwareError("固件魔数不匹配")
        year, month, day = struct.unpack_from("<HBB", decoded, 7)
        try:
            release = date(year, month, day)
        except ValueError as exc:
            raise FirmwareError("固件日期无效") from exc
        if year >= 2050:
            raise FirmwareError("固件日期超出原升级器范围")
        model = uuid.UUID(bytes_le=decoded[20:36])
        if model != K2_GUID:
            raise FirmwareError(f"固件型号不是 K2：{model}")
        size, xor, checksum = struct.unpack_from("<III", decoded, 36)
        app = decoded[HEADER_SIZE:]
        if size != len(app):
            raise FirmwareError("固件声明长度与实际长度不一致")
        if size < MARKER_OFFSET + 4:
            raise FirmwareError("固件缺少应用版本或提交标记区域")
        if reduce(int.__xor__, app, 0) != xor or sum(app) & 0xFFFFFFFF != checksum:
            raise FirmwareError("固件 XOR / 加法校验失败")
        if app[MARKER_OFFSET:MARKER_OFFSET + 4] != b"\xff" * 4:
            raise FirmwareError("固件提交标记不是未提交状态 FFFFFFFF")
        sp, reset = struct.unpack_from("<II", app)
        if not (0x20000000 < sp <= 0x20020000 and sp % 4 == 0):
            raise FirmwareError("K2 栈指针超出预期 SRAM 范围")
        if not reset & 1 or not APP_START <= (reset & ~1) < APP_START + size:
            raise FirmwareError("复位向量不在当前应用范围")
        version = app[2048]
        return cls(bytes(raw), app, release.isoformat(),
                   f"{version >> 4}.{version & 15}", model)

    @classmethod
    def load(cls, path):
        return cls.parse(Path(path).read_bytes())

    @classmethod
    def from_app(cls, app, release=None):
        """Wrap a backed-up image for recovery; the commit marker is reset.

        Remove only erased FF tail bytes, retain four-byte alignment and the
        marker region. The recovered bootloader consumes app bytes, not this
        host-side header. This creates a recovery file, not a vendor release.
        """
        app = bytearray(app)
        if len(app) < MARKER_OFFSET + 4:
            raise FirmwareError("备份缺少提交标记区域")
        app[MARKER_OFFSET:MARKER_OFFSET + 4] = b"\xff" * 4
        size = max(MARKER_OFFSET + 4, (len(app.rstrip(b"\xff")) + 3) // 4 * 4)
        app = bytes(app[:size])
        release = release or date.today()
        header = (b"gzutapp" + struct.pack("<HBB", release.year, release.month, release.day)
                  + b"\xff" * 9 + K2_GUID.bytes_le
                  + struct.pack("<III", len(app), reduce(int.__xor__, app, 0), sum(app) & 0xffffffff))
        decode = (DATA / "firmware_decode.bin").read_bytes()
        encode = bytes(decode.index(i) for i in range(256))
        return cls.parse((header + app).translate(encode))

    @property
    def erase_addresses(self):
        # RID 440 passes the entire container length to RID 165, including header.
        count = (len(self.source) + SECTOR_SIZE - 1) // SECTOR_SIZE
        return tuple(APP_START + i * SECTOR_SIZE for i in range(count))

    def chunks(self, size=1024):
        for offset in range(0, len(self.app), size):
            yield APP_START + offset, self.app[offset:offset + size]

    def summary(self):
        return {
            "model": "K2", "model_guid": str(self.model_guid),
            "version": self.version, "date": self.date,
            "file_size": len(self.source), "app_size": len(self.app),
            "file_sha256": hashlib.sha256(self.source).hexdigest(),
            "app_sha256": hashlib.sha256(self.app).hexdigest(),
            "app_start": f"0x{APP_START:08X}",
            "app_end_exclusive": f"0x{APP_START + len(self.app):08X}",
            "erase_sectors": len(self.erase_addresses),
            "erase_end_exclusive": f"0x{self.erase_addresses[-1] + SECTOR_SIZE:08X}",
            "commit_address": f"0x{APP_START + MARKER_OFFSET:08X}",
            "commit_value_hex": COMMIT_MARKER.hex(),
        }
