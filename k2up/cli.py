import argparse
from collections import Counter
from datetime import datetime, timezone
import json
from pathlib import Path
import sys
import time
from . import __version__
from .firmware import Firmware, FirmwareError
from .protocol import Protocol, ProtocolError
from .simulator import SimulatedTransport
from .transport import enumerate_devices, select_device, device_summary, HidTransport
from .updater import Updater, UpgradeError
from .backup import backup_device


class Trace:
    def __init__(self, path):
        path.parent.mkdir(parents=True, exist_ok=True)
        # An existing capture must never be silently overwritten.
        self.file = path.open("x", encoding="utf-8", buffering=1)

    def event(self, kind, **fields):
        self.file.write(json.dumps({"time": datetime.now(timezone.utc).isoformat(),
                                    "kind": kind, **fields}, ensure_ascii=False) + "\n")

    def close(self):
        self.file.close()


class TracedTransport:
    def __init__(self, transport, trace):
        self.transport = transport
        self.trace = trace

    def write(self, raw):
        self.trace.event("tx-attempt", hex=raw.hex())
        count = self.transport.write(raw)
        self.trace.event("tx-result", count=count)
        return count

    def read(self, timeout_ms):
        raw = self.transport.read(timeout_ms)
        if raw:
            self.trace.event("rx", hex=raw.hex())
        return raw


class Progress:
    def __init__(self, trace=None):
        self.trace = trace
        self.previous = None
        self.percent = -1

    def __call__(self, stage, current, total):
        percent = int(current * 100 / total) if total else 0
        if stage != self.previous or (total and percent // 10 > self.percent // 10):
            print(f"[{stage}]" + (f" {percent}% ({current}/{total})" if total else ""), file=sys.stderr)
            if self.trace:
                self.trace.event("stage", stage=stage, current=current, total=total)
            self.previous, self.percent = stage, percent


def record_failure(trace, kind, **fields):
    if trace:
        try:
            trace.event(kind, **fields)
        except OSError as exc:
            print(f"通信日志无法继续写入：{exc}", file=sys.stderr)


def parser():
    root = argparse.ArgumentParser(description="WITRN K2 实验性命令行升级器")
    root.add_argument("--version", action="version", version=__version__)
    commands = root.add_subparsers(dest="command", required=True)
    commands.add_parser("devices", help="仅枚举 0716:5060 HID 接口")
    inspect = commands.add_parser("inspect", help="离线验证 .k2 固件")
    inspect.add_argument("firmware", type=Path)
    dry = commands.add_parser("dry-run", help="用内存模拟设备执行完整升级；不访问 USB")
    dry.add_argument("firmware", type=Path)
    dry.add_argument("--fault", choices=("timeout", "nack", "wrong-ack", "bad-frame", "verify",
                                       "marker", "disconnect", "short-write", "batch-nack"))
    dry.add_argument("--model", default="K2", help="模拟设备名称，可验证型号拒绝路径")
    for command in ("probe", "backup", "flash"):
        help_text = {"probe": "握手并读取设备信息，不擦写", "backup": "只读两遍校验备份并生成恢复文件", "flash": "执行真实升级"}
        sub = commands.add_parser(command, help=help_text[command])
        if command == "flash":
            sub.add_argument("firmware", type=Path)
            sub.add_argument("--yes", action="store_true", help="明确执行擦除和写入")
        if command == "backup":
            sub.add_argument("--output-dir", type=Path, help="新的备份目录，禁止覆盖已有备份")
        sub.add_argument("--dfu", action="store_true", help="声明设备已按减号键进入 DFU")
        sub.add_argument("--path-hex", help="devices 输出的接口路径")
        sub.add_argument("--timeout-ms", type=int, default=1000)
        sub.add_argument("--trace", type=Path, help="保存 JSONL 通信日志；默认 k2_logs/<时间>.jsonl")
    return root


def main(argv=None):
    args = parser().parse_args(argv)
    transport = trace = None
    updater = None
    try:
        if args.command == "devices":
            devices = enumerate_devices()
            print(json.dumps([device_summary(d) for d in devices], ensure_ascii=False, indent=2))
            if not devices:
                print("未发现 0716:5060 接口。按住减号键，从 CC1/HID 口连接后再试。", file=sys.stderr)
            return 0
        firmware = Firmware.load(args.firmware) if hasattr(args, "firmware") else None
        if args.command == "inspect":
            print(json.dumps(firmware.summary(), ensure_ascii=False, indent=2))
            return 0
        if args.command == "dry-run":
            transport = SimulatedTransport(model=args.model, fault=args.fault)
            updater = Updater(Protocol(transport), Progress())
            identity = updater.flash(firmware)
            counts = Counter(packet.command for packet in transport.sent)
            result = {"simulation_only": True, "usb_accessed": False,
                      "hardware_validated": False, "firmware": firmware.summary(),
                      "identity": identity.summary(), "tx_frames": len(transport.sent),
                      "commands": {str(k): v for k, v in sorted(counts.items())},
                      "stage": updater.stage}
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0
        if not args.dfu:
            raise ValueError("请先让 K2 进入 DFU；连接好后用 --dfu 明确声明")
        if args.command == "flash" and not args.yes:
            raise ValueError("真实升级会擦除应用区，需显式添加 --yes；可先运行 probe 和 dry-run")
        if not 1 <= args.timeout_ms <= 60000:
            raise ValueError("超时必须在 1–60000 毫秒之间")
        devices = enumerate_devices()
        selected = select_device(devices, args.path_hex)
        path = args.trace or Path("k2_logs") / (datetime.now().strftime("%Y%m%d-%H%M%S") + f"-{time.time_ns()}.jsonl")
        trace = Trace(path)
        trace.event("start", command=args.command, tool_version=__version__,
                    device=device_summary(selected), firmware=firmware.summary() if firmware else None,
                    hardware_validated=False)
        print(f"通信日志：{path.resolve()}", file=sys.stderr)
        transport = HidTransport(selected)
        updater = Updater(Protocol(TracedTransport(transport, trace), args.timeout_ms), Progress(trace))
        if args.command == "backup":
            directory = args.output_dir or Path("k2_backups") / datetime.now().strftime("%Y%m%d-%H%M%S")
            result = backup_device(updater, directory)
            trace.event("result", stage=updater.stage, backup=result)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            return 0
        identity = updater.flash(firmware) if firmware else updater.probe()
        trace.event("result", stage=updater.stage, identity=identity.summary())
        print(json.dumps({"stage": updater.stage, "identity": identity.summary(),
                          "trace": str(path.resolve())}, ensure_ascii=False, indent=2))
        return 0
    except (OSError, ValueError, ProtocolError, UpgradeError) as exc:
        stage = updater.stage if updater else "preflight"
        print(f"失败：{exc}", file=sys.stderr)
        record_failure(trace, "error", stage=stage, message=str(exc))
        return 1
    except KeyboardInterrupt:
        stage = updater.stage if updater else "preflight"
        print(f"[{stage}] 用户中断，已停止，未发送自动收尾或重试命令。", file=sys.stderr)
        record_failure(trace, "interrupted", stage=stage)
        return 130
    finally:
        for resource in (transport, trace):
            if resource:
                try:
                    resource.close()
                except OSError as exc:
                    print(f"关闭连接或日志失败：{exc}", file=sys.stderr)


if __name__ == "__main__":
    raise SystemExit(main())
