"""Validate a downloaded official ZIP without extracting arbitrary entries."""
from pathlib import Path
import uuid
import zipfile

from .demo import is_demo_firmware
from .firmware import Firmware, SECTOR_SIZE, SECTOR_COUNT


def import_archive(path, directory, expected_version):
    path = Path(path)
    if path.stat().st_size > 8 * 1024 * 1024:
        raise ValueError("官网固件包过大，请选择本地固件")
    try:
        with zipfile.ZipFile(path) as archive:
            entries = archive.infolist()
            if len(entries) > 32:
                raise ValueError("官网固件包内容异常")
            candidates = [item for item in entries if not item.is_dir() and item.filename.lower().endswith(".k2")]
            if len(candidates) != 1:
                raise ValueError("官网压缩包需要包含唯一的 .k2 固件，请选择本地固件")
            item = candidates[0]
            if item.file_size > SECTOR_SIZE * SECTOR_COUNT:
                raise ValueError("固件超出 K2 大小限制")
            with archive.open(item) as source:
                raw = source.read(SECTOR_SIZE * SECTOR_COUNT + 1)
            firmware = Firmware.parse(raw)
    except (zipfile.BadZipFile, NotImplementedError) as exc:
        raise ValueError("官网固件包无效或压缩格式不支持") from exc
    if is_demo_firmware(firmware):
        raise ValueError("这是演示固件，不能作为官网固件使用")
    if firmware.version != expected_version:
        raise ValueError("官网标注版本与固件实际版本不一致，请选择本地固件")
    destination = Path(directory) / "Downloaded Firmware"
    destination.mkdir(parents=True, exist_ok=True)
    output = destination / f"K2_{firmware.version}_{uuid.uuid4()}.k2"
    with output.open("xb") as file:
        file.write(raw)
    return {"firmware": firmware.summary(), "firmware_path": str(output.resolve()), "demo_firmware": False}
