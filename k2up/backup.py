"""Read-only, two-pass flash backup and host-side recovery container."""
from datetime import datetime, timezone
from dataclasses import replace
import hashlib
import json
from pathlib import Path
from .firmware import APP_START, APP_LIMIT, Firmware, MARKER_OFFSET
from .updater import Updater, UpgradeError
from .protocol import ProtocolError

FLASH_START = 0x08000000


def backup_device(updater, directory):
    if updater.used:
        raise UpgradeError(updater.stage, "此会话已使用，请重新连接")
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=False)
    updater.used = True
    try:
        identity = updater._identify()
        if not identity.confirmed_k2:
            raise ProtocolError(f"备份设备名称无法确认是 K2：{identity.boot_strings!r}")
        size = APP_LIMIT - FLASH_START
        partial = directory / "flash.bin.partial"
        updater._stage("backup-read", 0, size)
        with partial.open("xb") as output:
            for offset in range(0, size, 1024):
                block = updater.protocol.read_memory(FLASH_START + offset, min(1024, size - offset))
                output.write(block)
                updater._stage("backup-read", offset + len(block), size)
        updater._stage("backup-verify", 0, size)
        with partial.open("rb") as stored:
            for offset in range(0, size, 1024):
                expected = stored.read(min(1024, size - offset))
                actual = updater.protocol.read_memory(FLASH_START + offset, len(expected))
                if actual != expected:
                    raise ProtocolError(f"备份第二遍读取不一致：0x{FLASH_START + offset:08X}")
                updater._stage("backup-verify", offset + len(actual), size)
        data = partial.read_bytes()
        partial.rename(directory / "flash.bin")
        prefix = data[:APP_START - FLASH_START]
        app = data[APP_START - FLASH_START:]
        version = app[2048]
        identity = replace(identity, current_version=f"{version >> 4}.{version & 15}",
                           current_marker_hex=app[MARKER_OFFSET:MARKER_OFFSET + 4].hex())
        (directory / "bootloader-and-info.bin").write_bytes(prefix)
        (directory / "app.bin").write_bytes(app)
        updater._stage("backup-recovery")
        recovery = Firmware.from_app(app)
        recovery_path = directory / f"K2_RECOVERY_{recovery.version}.k2"
        recovery_path.write_bytes(recovery.source)
        checked = Firmware.load(recovery_path)
        expected_app = bytearray(app[:len(checked.app)])
        expected_app[MARKER_OFFSET:MARKER_OFFSET + 4] = b"\xff" * 4
        if checked.app != expected_app or any(b != 255 for b in app[len(checked.app):]):
            raise ProtocolError("恢复文件与备份不一致")
        def sha(raw):
            return hashlib.sha256(raw).hexdigest()
        result = {"created_utc": datetime.now(timezone.utc).isoformat(),
                  "directory": str(directory.resolve()), "identity": identity.summary(),
                  "flash_start": f"0x{FLASH_START:08X}", "flash_end_exclusive": f"0x{APP_LIMIT:08X}",
                  "flash_size": len(data), "flash_sha256": sha(data),
                  "app_sha256": sha(app), "bootloader_and_info_sha256": sha(prefix),
                  "two_independent_reads_match": True,
                  "recovery_file": str(recovery_path.resolve()), "recovery": checked.summary(),
                  "recovery_flash_hardware_validated": False,
                  "erase_or_write_commands_sent": False}
        (directory / "manifest.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
        updater._stage("backup-complete")
        return result
    except (OSError, ValueError, ProtocolError) as exc:
        raise UpgradeError(updater.stage, str(exc)) from exc
