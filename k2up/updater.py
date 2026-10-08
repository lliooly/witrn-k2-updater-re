"""Flash stages reconstructed from RIDs 165–169 and worker RID 440."""
from dataclasses import dataclass, replace
import hashlib
from .firmware import (APP_START, INFO_START, NAME_START, MARKER_OFFSET,
                       COMMIT_MARKER, Firmware)
from .protocol import ProtocolError


class UpgradeError(RuntimeError):
    def __init__(self, stage, message):
        self.stage = stage
        super().__init__(f"[{stage}] {message}")


@dataclass(frozen=True)
class Identity:
    boot_strings: tuple
    info_sha256: str
    current_version: str = None
    current_marker_hex: str = None

    @property
    def confirmed_k2(self):
        return any(part.upper() in ("K2", "WITRN K2", "K2(C)WITRN") for part in self.boot_strings)

    def summary(self):
        return {"boot_strings": list(self.boot_strings), "info_sha256": self.info_sha256,
                "confirmed_k2": self.confirmed_k2,
                "current_version": self.current_version,
                "current_marker_hex": self.current_marker_hex}


class Updater:
    def __init__(self, protocol, progress=None):
        self.protocol = protocol
        self.progress = progress or (lambda *args: None)
        self.stage = "idle"
        self.used = False

    def _stage(self, name, current=0, total=0):
        self.stage = name
        self.progress(name, current, total)

    def _identify(self):
        self._stage("handshake")
        self.protocol.command(3)
        self._stage("identify")
        info = self.protocol.read_memory(INFO_START, 1024)
        names = self.protocol.read_memory(NAME_START, 256)
        parts = names.split(b"\0", 3)
        if len(parts) != 4:
            raise ProtocolError("Bootloader 名称区缺少三个字符串终止符")
        try:
            strings = tuple(part.decode("utf-8").strip() for part in parts[:3])
        except UnicodeDecodeError as exc:
            raise ProtocolError("Bootloader 名称不是有效 UTF-8") from exc
        # A host-side VID/PID or firmware GUID alone doesn't identify the board.
        # Fail closed until the device's own name confirms this model.
        return Identity(strings, hashlib.sha256(info).hexdigest())

    def probe(self):
        if self.used:
            raise UpgradeError(self.stage, "此会话已使用，请重新连接")
        self.used = True
        try:
            identity = self._identify()
            self._stage("inspect-app")
            version = self.protocol.read_memory(APP_START + 2048, 1)[0]
            marker = self.protocol.read_marker(APP_START + MARKER_OFFSET)
            identity = replace(identity, current_version=f"{version >> 4}.{version & 15}",
                               current_marker_hex=marker.hex())
            self._stage("probe-complete")
            return identity
        except (OSError, ProtocolError) as exc:
            raise UpgradeError(self.stage, str(exc)) from exc

    def flash(self, firmware):
        if self.used:
            raise UpgradeError(self.stage, "此会话已使用，禁止自动重试")
        # Revalidate before *any* device I/O, including library calls outside CLI.
        self._stage("validate")
        try:
            checked = Firmware.parse(firmware.source)
            if checked != firmware:
                raise ValueError("固件对象与原始文件不一致")
        except ValueError as exc:
            raise UpgradeError(self.stage, str(exc)) from exc
        self.used = True
        try:
            identity = self._identify()
            if not identity.confirmed_k2:
                raise ProtocolError(f"设备名称尚不能确认是 K2：{identity.boot_strings!r}；请保留 probe 日志核对")
            self._stage("log-reset")
            self.protocol.command(22)
            self._stage("erase", 0, len(checked.erase_addresses))
            self.protocol.command(5)
            for index, address in enumerate(checked.erase_addresses, 1):
                self.protocol.erase_sector(address)
                self._stage("erase", index, len(checked.erase_addresses))
            self.protocol.command(4)
            self._stage("write", 0, len(checked.app))
            self.protocol.command(5)
            for address, data in checked.chunks():
                self.protocol.write_memory(address, data)
                self._stage("write", address - APP_START + len(data), len(checked.app))
            self.protocol.command(4)
            self._stage("verify", 0, len(checked.app))
            for address, expected in checked.chunks():
                actual = self.protocol.read_memory(address, len(expected))
                if actual != expected:
                    offset = next(i for i, (a, b) in enumerate(zip(actual, expected)) if a != b)
                    raise ProtocolError(f"读回不一致，地址 0x{address + offset:08X}")
                self._stage("verify", address - APP_START + len(expected), len(checked.app))
            self._stage("commit")
            self.protocol.command(5)
            self.protocol.write_memory(APP_START + MARKER_OFFSET, COMMIT_MARKER)
            if self.protocol.read_marker(APP_START + MARKER_OFFSET) != COMMIT_MARKER:
                raise ProtocolError("提交标记读回不一致")
            self.protocol.command(4)
            self._stage("exit")
            self.protocol.command(23)
            self._stage("complete")
            return identity
        except (OSError, ProtocolError) as exc:
            # No best-effort cmd 4/23 on failure: they may finalize bad data.
            raise UpgradeError(self.stage, str(exc)) from exc
