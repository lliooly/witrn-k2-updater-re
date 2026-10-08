"""Back up complete resource sectors before writing; verify every byte."""
from datetime import datetime, timezone
import json
import os
from pathlib import Path

from .picture import resource_for, sha
from .protocol import ProtocolError


def read_all(protocol, resource, progress, stage):
    if resource != resource_for(resource.kind):
        raise ValueError("资源范围不是已验证的 K2 固定范围")
    output = bytearray()
    progress(stage, 0, resource.allocation)
    for offset in range(0, resource.allocation, 1024):
        output.extend(protocol.read_memory(resource.address + offset,
                                           min(1024, resource.allocation - offset)))
        progress(stage, len(output), resource.allocation)
    return bytes(output)


def durable_write(path, data):
    with path.open("xb") as file:
        file.write(data)
        file.flush()
        os.fsync(file.fileno())


def backup_resource(protocol, resource, identity, directory, progress, simulation=False):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=False)
    first = read_all(protocol, resource, progress, "resource-backup-read")
    durable_write(directory / "sectors.bin.partial", first)
    second = read_all(protocol, resource, progress, "resource-backup-verify")
    if first != second:
        raise ProtocolError("资源备份两遍读取不一致，未开始擦写")
    (directory / "sectors.bin.partial").rename(directory / "sectors.bin")
    metadata = {"schema": 1, "type": "k2-resource-backup", "kind": resource.kind,
                "created_utc": datetime.now(timezone.utc).isoformat(),
                "address": resource.address, "allocation": resource.allocation,
                "data_size": resource.size, "sha256": sha(first),
                "identity": identity.summary(), "two_reads_match": True,
                "simulation_only": simulation,
                "directory": str(directory.resolve())}
    durable_write(directory / "manifest.json",
                  (json.dumps(metadata, ensure_ascii=False, indent=2) + "\n").encode())
    # Persist directory entries as well as file contents before allowing erase.
    for parent in (directory, directory.parent):
        fd = os.open(str(parent), os.O_RDONLY)
        try:
            os.fsync(fd)
        finally:
            os.close(fd)
    progress("resource-backup-complete", 0, 0)
    return first, metadata


def load_backup(path, manifest_data=None):
    path = Path(path)
    if path.stat().st_size > 65536:
        raise ValueError("资源备份清单过大")
    metadata = json.loads(manifest_data if manifest_data is not None else path.read_bytes())
    if not isinstance(metadata, dict) or metadata.get("schema") != 1 or metadata.get("type") != "k2-resource-backup":
        raise ValueError("不是本应用的资源备份清单")
    resource = resource_for(metadata.get("kind"))
    if (metadata.get("address") != resource.address or
            metadata.get("allocation") != resource.allocation or
            metadata.get("data_size") != resource.size or
            metadata.get("two_reads_match") is not True):
        raise ValueError("资源备份范围或校验状态无效")
    raw_path = path.parent / "sectors.bin"
    if raw_path.stat().st_size != resource.allocation:
        raise ValueError("资源备份文件长度无效")
    raw = raw_path.read_bytes()
    if sha(raw) != metadata.get("sha256"):
        raise ValueError("资源备份摘要不匹配")
    identity = metadata.get("identity", {})
    if not isinstance(identity, dict) or identity.get("confirmed_k2") is not True or not identity.get("info_sha256"):
        raise ValueError("资源备份缺少 K2 设备身份")
    return resource, raw, metadata


def write_resource(protocol, resource, image, progress):
    if resource != resource_for(resource.kind):
        raise ValueError("资源范围不是已验证的 K2 固定范围")
    if len(image) != resource.allocation:
        raise ValueError("写入必须覆盖资源的完整扇区")
    protocol.command(22)
    progress("resource-erase", 0, resource.sectors)
    protocol.command(5)
    for index, address in enumerate(resource.addresses, 1):
        protocol.erase_sector(address)
        progress("resource-erase", index, resource.sectors)
    protocol.command(4)
    progress("resource-write", 0, len(image))
    protocol.command(5)
    for offset in range(0, len(image), 1024):
        block = image[offset:offset + 1024]
        protocol.write_memory(resource.address + offset, block)
        progress("resource-write", offset + len(block), len(image))
    protocol.command(4)
    actual = read_all(protocol, resource, progress, "resource-verify")
    if actual != image:
        offset = next(index for index, pair in enumerate(zip(actual, image)) if pair[0] != pair[1])
        raise ProtocolError(f"资源读回不一致：0x{resource.address + offset:08X}；未结束会话")
    progress("resource-exit", 0, 0)
    protocol.command(23)
    progress("resource-complete", 0, 0)


def transfer_resource(request, events, protocol, identity, directory):
    """Validated payload is captured before USB opens by the bridge."""
    resource = resource_for(request["resource_kind"])
    original, backup = backup_resource(protocol, resource, identity, directory, events.progress,
                                       simulation=request.get("simulation", False))
    events.emit("paths", backup=str(directory))
    operation = request["operation"]
    if operation == "resource-read":
        data = original[:resource.size]
        filenames = {"layout": "layout.pic", "emark": "configurations.k2emarkbin", "emark-copy": "copied.wtemark"}
        path = Path(directory) / filenames.get(resource.kind, resource.kind + ".k2image")
        durable_write(path, data)
        try:
            resource.validate(data)
            invalid = None
        except ValueError as exc:
            invalid = str(exc)
        return {"backup": backup, "resource_path": str(path), "resource_kind": resource.kind,
                "resource_valid": invalid is None, "resource_error": invalid}
    if operation == "resource-restore":
        image = request["_restore_bytes"]
        if request["_restore_identity"] != identity.info_sha256:
            raise ValueError("该资源备份属于其他设备，未开始擦写")
    else:
        payload = request["_resource_bytes"]
        # Preserve all bytes outside the payload, including the trailing sector.
        image = payload + original[len(payload):]
    write_resource(protocol, resource, image, events.progress)
    return {"backup": backup, "resource_kind": resource.kind,
            "verified_sha256": sha(image), "stage": "complete"}
