"""One JSON request per helper process; stdout contains only NDJSON events."""
from contextlib import contextmanager
from datetime import datetime
import json
import sqlite3
from pathlib import Path
import sys
import time
import uuid

from .backup import backup_device
from .cli import Trace, TracedTransport
from .demo import DemoTransport, demo_device, demo_firmware, is_demo_firmware
from .firmware import Firmware
from .protocol import Protocol
from .transport import enumerate_devices, select_device, device_summary, HidTransport
from .updater import Updater, UpgradeError
from .picture import resource_for, sha
from .picture_device import load_backup, transfer_resource

RESOURCE_OPERATIONS = {"resource-read", "resource-write", "resource-restore"}
OPERATIONS = {"devices", "inspect", "firmware-extract", "demo-firmware", "probe", "backup", "upgrade"} | RESOURCE_OPERATIONS
MONITOR_OPERATIONS = {"monitor", "monitor-query", "monitor-import", "monitor-export", "monitor-list"}
OPERATIONS |= MONITOR_OPERATIONS
DEMO_FAULTS = {None, "verify", "disconnect", "batch-nack"}


class Events:
    def __init__(self, request, output=None):
        self.request = request
        self.output = output or sys.stdout
        self.stage = "preflight"
        self.previous = None
        self.trace = None

    def emit(self, event, **fields):
        record = {"schema": 1, "id": self.request["id"], "operation": self.request["operation"],
                  "event": event, **fields}
        self.output.write(json.dumps(record, ensure_ascii=False) + "\n")
        self.output.flush()

    def progress(self, stage, current=0, total=0):
        self.stage = stage
        percent = int(current * 100 / total) if total else 0
        key = (stage, percent)
        if key == self.previous:
            return
        self.previous = key
        self.emit("progress", stage=stage, current=current, total=total)
        if self.trace:
            self.trace.event("stage", stage=stage, current=current, total=total)
        if self.request.get("simulation"):
            time.sleep(self.request.get("demo_delay_ms", 20) / 1000)


def validate_request(request):
    if not isinstance(request, dict) or request.get("operation") not in OPERATIONS:
        raise ValueError("不支持的应用请求")
    if not isinstance(request.get("id"), str):
        raise ValueError("请求 ID 无效")
    uuid.UUID(request["id"])
    if not isinstance(request.get("simulation", False), bool):
        raise ValueError("演示模式必须是布尔值")
    if request.get("fault") not in DEMO_FAULTS:
        raise ValueError("不支持的演示故障")
    delay = request.get("demo_delay_ms", 20)
    if not isinstance(delay, int) or not 0 <= delay <= 100:
        raise ValueError("演示延迟无效")
    if request["operation"] in ({"probe", "backup", "upgrade"} | RESOURCE_OPERATIONS) and not request.get("simulation"):
        if request.get("dfu_confirmed") is not True:
            raise ValueError("请先按减号键进入 DFU，并勾选已进入 DFU")
        if not request.get("device_path_hex"):
            raise ValueError("请先选择一个设备接口")
    if request["operation"] == "upgrade" and request.get("confirmed") is not True:
        raise ValueError("请明确确认备份并升级操作")
    if request["operation"] in ("resource-write", "resource-restore") and request.get("confirmed") is not True:
        raise ValueError("请明确确认资源写入操作")
    if request["operation"] in RESOURCE_OPERATIONS:
        resource_for(request.get("resource_kind"))
    if request["operation"] == "monitor" and (request.get("simulation") or not request.get("device_path_hex")):
        raise ValueError("请选择真实的普通模式 K2 接口")


def selected_device(request):
    if request.get("simulation"):
        return demo_device()
    device = select_device(enumerate_devices(), request.get("device_path_hex"))
    if device.get("serial_number") != request.get("device_serial"):
        raise ValueError("设备序列号已变化，请重新读取设备信息")
    return device


@contextmanager
def connection(request, events, trace, demo=None):
    selected = selected_device(request)
    raw = demo if request.get("simulation") else HidTransport(selected)
    protocol = Protocol(TracedTransport(raw, trace))
    try:
        yield Updater(protocol, events.progress), selected
    finally:
        raw.close()


def verify_identity(identity, request):
    if not identity.confirmed_k2:
        raise ValueError("设备名称无法确认是 K2，停止操作")
    expected = request.get("device_info_sha256")
    if expected and expected != identity.info_sha256:
        raise ValueError("设备信息已变化，请重新读取设备信息；未开始擦写")


def dispatch(request, events, input_stream=None):
    validate_request(request)
    operation = request["operation"]
    simulation = request.get("simulation", False)
    if operation == "devices":
        devices = [demo_device()] if simulation else enumerate_devices()
        return {"devices": [device_summary(d) for d in devices], "simulation_only": simulation}
    if operation == "inspect":
        events.progress("validate")
        firmware = Firmware.load(request["firmware_path"])
        return {"firmware": firmware.summary(), "firmware_path": str(Path(request["firmware_path"]).resolve()),
                "demo_firmware": is_demo_firmware(firmware)}
    if operation == "firmware-extract":
        from .official_firmware import import_archive
        events.progress("validate")
        return import_archive(request["firmware_path"], request["data_directory"], request["firmware_version"])
    if operation in MONITOR_OPERATIONS:
        from .monitor import run_monitor
        from .recording import summary
        from .recording_files import import_record, export_record
        from .recording_stats import query_record
        events.stage = "monitor"
        if operation == "monitor":
            return run_monitor(request, events, input_stream or sys.stdin)
        if operation == "monitor-query":
            return query_record(request["record_path"], request.get("range_start"), request.get("range_end"),
                                request.get("include_stats", True), budget=1200)
        if operation == "monitor-import":
            return import_record(request["record_path"], request["output_path"])
        if operation == "monitor-export":
            return export_record(request["record_path"], request["output_path"], request["export_kind"],
                                 request.get("range_start"), request.get("range_end"))
        root = Path(request["data_directory"]) / "Recordings"
        records = []
        for path in sorted(root.glob("*.sqlite"), key=lambda p: p.stat().st_mtime, reverse=True)[:200]:
            try: records.append(summary(path))
            except (ValueError, sqlite3.Error, OSError): continue
        return {"records": records}
    root = Path(request["data_directory"]).expanduser().resolve()
    if simulation:
        root = root / "Offline Demo"
    if operation == "demo-firmware":
        if not simulation:
            raise ValueError("示例固件只能在离线演示中使用")
        root.mkdir(parents=True, exist_ok=True)
        path = root / f"K2_DEMO_{request['id']}.k2"
        firmware = demo_firmware()
        with path.open("xb") as output:
            output.write(firmware.source)
        return {"firmware": firmware.summary(), "firmware_path": str(path), "simulation_only": True}
    firmware = None
    if operation in RESOURCE_OPERATIONS:
        events.progress("resource-validate")
        resource = resource_for(request["resource_kind"])
        if operation != "resource-read" and not request.get("device_info_sha256"):
            raise ValueError("请先读取设备信息再写入资源")
        if operation == "resource-write":
            path = Path(request["resource_path"])
            if path.stat().st_size != resource.size:
                raise ValueError("资源文件长度无效；未打开设备")
            data = resource.validate(path.read_bytes())
            if sha(data) != request.get("resource_sha256"):
                raise ValueError("资源文件在确认后发生变化；未打开设备")
            request = dict(request, _resource_bytes=data)
        elif operation == "resource-restore":
            path = Path(request["restore_manifest_path"])
            if path.stat().st_size > 65536:
                raise ValueError("恢复清单过大；未打开设备")
            manifest_data = path.read_bytes()
            if len(manifest_data) > 65536 or sha(manifest_data) != request.get("restore_manifest_sha256"):
                raise ValueError("恢复清单在确认后发生变化；未打开设备")
            restored, data, metadata = load_backup(path, manifest_data)
            if metadata.get("simulation_only") and not simulation:
                raise ValueError("模拟资源备份不能恢复到真实设备；未打开设备")
            if restored != resource:
                raise ValueError("恢复备份类型不匹配；未打开设备")
            request = dict(request, _restore_bytes=data,
                           _restore_identity=metadata["identity"]["info_sha256"])
    if operation == "upgrade":
        events.progress("validate")
        firmware = Firmware.load(request["firmware_path"])
        if not simulation and is_demo_firmware(firmware):
            raise ValueError("这是合成演示固件，禁止写入真实设备")
        if firmware.summary()["file_sha256"] != request.get("firmware_sha256"):
            raise ValueError("选择的固件已变化，请重新选择；未打开设备")
        if not request.get("device_info_sha256"):
            raise ValueError("请先读取设备信息再升级")
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S") + "-" + request["id"]
    trace_path = root / "Logs" / f"{stamp}.jsonl"
    trace = Trace(trace_path)
    events.trace = trace
    if simulation and operation in RESOURCE_OPERATIONS:
        from .picture_simulator import PictureTransport
        demo = PictureTransport(fault=request.get("fault"))
    else:
        demo = DemoTransport() if simulation else None
    trace.event("start", command=operation, simulation_only=simulation,
                firmware=firmware.summary() if firmware else None,
                resource_kind=request.get("resource_kind"), resource_sha256=request.get("resource_sha256"),
                restore_manifest_sha256=request.get("restore_manifest_sha256"))
    events.emit("paths", trace=str(trace_path))
    try:
        # Probe is read-only; close its handle before backup/upgrade reconnect.
        with connection(request, events, trace, demo) as (updater, selected):
            identity = updater.probe()
            verify_identity(identity, request)
        events.emit("identity", identity=identity.summary(), device=device_summary(selected))
        if operation == "probe":
            return {"identity": identity.summary(), "device": device_summary(selected),
                    "trace": str(trace_path), "simulation_only": simulation}
        if operation in RESOURCE_OPERATIONS:
            directory = root / "Resource Backups" / stamp
            with connection(request, events, trace, demo) as (updater, selected):
                identity = updater.probe()
                verify_identity(identity, request)
                result = transfer_resource(request, events, updater.protocol, identity, directory)
            result.update(identity=identity.summary(), trace=str(trace_path), simulation_only=simulation)
            trace.event("result", **result)
            return result
        directory = root / "Backups" / stamp
        with connection(request, events, trace, demo) as (updater, selected):
            backup = backup_device(updater, directory)
            verify_identity(updater_identity(backup), request)
        backup["simulation_only"] = simulation
        (directory / "manifest.json").write_text(json.dumps(backup, ensure_ascii=False, indent=2) + "\n")
        events.emit("paths", backup=str(directory), trace=str(trace_path))
        if operation == "backup":
            return {"backup": backup, "identity": backup["identity"], "trace": str(trace_path),
                    "simulation_only": simulation}
        # Always bind the second connection to the backup's exact identity.
        bound = dict(request, device_info_sha256=backup["identity"]["info_sha256"])
        with connection(bound, events, trace, demo) as (updater, selected):
            identity = updater.probe()
            verify_identity(identity, bound)
            if identity.current_version != backup["identity"]["current_version"]:
                raise ValueError("设备应用版本在备份后发生变化，停止擦写")
            if simulation:
                demo.fault = request.get("fault")
            # The original core remains one-shot; a fresh updater starts the
            # independently validated flash transaction on this same handle.
            finished = Updater(updater.protocol, events.progress).flash(firmware)
        result = {"identity": finished.summary(), "backup": backup, "firmware": firmware.summary(),
                  "trace": str(trace_path), "simulation_only": simulation,
                  "hardware_flash_validated": not simulation, "stage": "complete"}
        trace.event("result", **result)
        return result
    except (OSError, ValueError, RuntimeError, KeyboardInterrupt) as exc:
        try:
            trace.event("error", stage=events.stage, message=str(exc))
        except OSError:
            pass
        raise
    finally:
        events.trace = None
        trace.close()


def updater_identity(backup):
    from .updater import Identity
    fields = backup["identity"]
    return Identity(tuple(fields["boot_strings"]), fields["info_sha256"],
                    fields.get("current_version"), fields.get("current_marker_hex"))


def main(input_stream=None, output=None):
    request = {"id": str(uuid.uuid4()), "operation": "unknown"}
    events = Events(request, output)
    try:
        raw = (input_stream or sys.stdin).readline(262145)
        if len(raw) > 262144:
            raise ValueError("请求过大")
        request = json.loads(raw)
        validate_request(request)
        events = Events(request, output)
        events.emit("ready")
        value = dispatch(request, events, input_stream or sys.stdin)
        events.emit("result", value=value)
        return 0
    except KeyboardInterrupt:
        events.emit("error", stage=events.stage, message="已取消只读操作", cancelled=True)
        return 130
    except (OSError, ValueError, RuntimeError, KeyError, TypeError, sqlite3.Error) as exc:
        stage = exc.stage if isinstance(exc, UpgradeError) else events.stage
        events.emit("error", stage=stage, message=str(exc), cancelled=False)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
