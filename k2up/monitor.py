"""Interactive, passive capture session. Controls affect host files only."""
from collections import deque
from dataclasses import replace
import json
import math
from pathlib import Path
import queue
import signal
from statistics import median
import threading
import time
import uuid

from .recording import Recording
from .protocol import ProtocolError
from .telemetry import decode_report, dfu_checksum_matches, Sampler
from .transport import enumerate_devices, HidTransport, VID, PID


class AutoStop:
    def __init__(self, kind="current", threshold=0, duration=0):
        if kind not in ("current", "power") or not all(math.isfinite(v) for v in (threshold, duration)) or threshold < 0 or duration < 0:
            raise ValueError("自动停止参数无效")
        self.kind, self.threshold, self.duration = kind, threshold, duration
        self.since = None

    def reset(self): self.since = None

    def accept(self, sample):
        if not self.duration: return False
        value = abs(sample.current) if self.kind == "current" else sample.power
        if value >= self.threshold: self.since = None; return False
        if self.since is None: self.since = sample.time
        return sample.time - self.since >= self.duration


class Capture:
    def __init__(self, directory, rate=10):
        self.directory = Path(directory)
        self.rate = rate
        self.sampler = Sampler(rate)
        self.record = None
        self.paused = False
        self.segment = 0
        self.previous = None
        self.intervals = deque(maxlen=101)
        self.auto = AutoStop()
        self.closed_path = None
        self.closed_count = 0

    def control(self, command):
        name = command.get("command")
        if name == "start":
            if self.record: raise ValueError("已有记录正在进行")
            rate = command.get("rate", self.rate)
            sampler = Sampler(rate)
            auto = AutoStop(command.get("auto_kind", "current"), float(command.get("threshold", 0)), float(command.get("duration", 0)))
            path = command.get("path") or str(self.directory / (str(uuid.uuid4()) + ".sqlite"))
            self.record = Recording(path, rate)
            self.rate, self.sampler, self.auto = rate, sampler, auto
            self.paused = False; self.segment += 1
        elif name == "pause":
            if not self.record: raise ValueError("没有进行中的记录")
            self.record.commit(); self.paused = True; self.auto.reset()
        elif name == "resume":
            if not self.record or not self.paused: raise ValueError("记录没有暂停")
            self.paused = False; self.segment += 1; self.sampler = Sampler(self.rate); self.auto.reset()
        elif name == "stop": self.stop()
        else: raise ValueError("不支持的采集控制")

    def stop(self, complete=True):
        if self.record:
            record = self.record
            self.closed_path, self.closed_count = str(record.path), record.count
            self.record = None
            record.close(complete)
        self.paused = False; self.auto.reset()

    def feed(self, sample):
        previous = self.previous
        if previous:
            dt = sample.time - previous.time
            interval = median(self.intervals) if self.intervals else .01
            if dt <= 0 or dt > max(2, 5 * (1 / self.rate if self.rate else interval)) or (sample.uptime is not None and previous.uptime is not None and sample.uptime < previous.uptime):
                self.segment += 1; self.auto.reset()
            elif dt > 0: self.intervals.append(dt)
        self.previous = sample
        sample = replace(sample, segment=self.segment)
        if self.record and not self.paused:
            if self.sampler.accept(sample.time): self.record.append(sample)
            if self.auto.accept(sample):
                self.stop()
                return sample, True
        return sample, False

    def state(self):
        return {"recording": self.record is not None, "paused": self.paused,
                "record_path": str(self.record.path) if self.record else self.closed_path,
                "record_count": self.record.count if self.record else self.closed_count}


def run_monitor(request, events, input_stream, transport_factory=HidTransport):
    selected = [d for d in enumerate_devices() if d["path"].hex() == request.get("device_path_hex")]
    if len(selected) != 1 or selected[0].get("serial_number") != request.get("device_serial"):
        raise ValueError("普通模式设备接口已变化，请刷新设备后重新连接")
    device = selected[0]
    if (device.get("vendor_id"), device.get("product_id")) != (VID, PID): raise ValueError("接口不是 K2")
    capture = Capture(Path(request["data_directory"]) / "Recordings")
    preview = None
    raw = None
    controls = queue.Queue(maxsize=64)
    stopped = threading.Event()
    def read_controls():
        try:
            while not stopped.is_set():
                line = input_stream.readline(16385)
                if not line: stopped.set(); break
                if len(line) > 16384: stopped.set(); break
                try:
                    value = json.loads(line)
                    if not isinstance(value, dict): raise ValueError()
                    controls.put(value, timeout=1)
                except (ValueError, queue.Full): stopped.set(); break
        except OSError: stopped.set()
    thread = threading.Thread(target=read_controls, daemon=True)
    old_handler = signal.getsignal(signal.SIGINT)
    signal.signal(signal.SIGINT, lambda *_: stopped.set())
    started = last_event = last_data = last_maintenance = time.monotonic()
    received = invalid = unmatched = checksum_ok = 0
    last_sample = None
    try:
        preview = Recording(Path(request["data_directory"]) / "Preview" / (str(uuid.uuid4()) + ".sqlite"), 0)
        raw = transport_factory(device)
        thread.start()
        events.emit("monitor", value={"preview_path": str(preview.path), **capture.state()})
        while not stopped.is_set():
            while True:
                try: command = controls.get_nowait()
                except queue.Empty: break
                if command.get("command") == "disconnect": stopped.set(); break
                try:
                    capture.control(command)
                    events.emit("monitor", value={**capture.state(), "control_ack": command.get("command")})
                except (ValueError, OSError) as exc:
                    events.emit("monitor", value={**capture.state(), "control_ack": command.get("command"), "notice": str(exc)})
            if stopped.is_set(): break
            try: data = raw.read(100)
            except ProtocolError:
                invalid += 1; data = b""
            now = time.monotonic()
            if data:
                try: sample = decode_report(data, now - started)
                except ValueError: sample = None; invalid += 1
                if sample:
                    received += 1; last_data = now
                    checksum_ok += int(dfu_checksum_matches(data))
                    sample, automatic = capture.feed(sample)
                    preview.append(sample)
                    last_sample = sample
                    if automatic: events.emit("monitor", value={**capture.state(), "notice": "达到条件，记录已自动停止并保存"})
                else: unmatched += 1
            if now - last_event >= .1:
                if now - last_maintenance >= 1:
                    preview.db.execute("DELETE FROM samples WHERE time < ? OR id < (SELECT max(id)-180000 FROM samples)", (now - started - 1800,))
                    preview.commit()
                    last_maintenance = now
                    if capture.record:
                        interval = 1 / capture.rate if capture.rate else (median(capture.intervals) if capture.intervals else .01)
                        capture.record.db.execute("INSERT OR REPLACE INTO metadata VALUES('interval',?)", (str(interval),))
                        capture.record.commit()
                events.emit("monitor", value={**capture.state(), "latest": last_sample.dictionary() if last_sample else None,
                            "received": received, "invalid": invalid, "unmatched": unmatched,
                            "checksum_matches": checksum_ok, "receive_rate": received / max(now - started, .001),
                            "elapsed": now - started, "stale": now - last_data > 2})
                last_event = now
            if now - last_data > 5:
                raise OSError("未收到 K2 遥测：请检查正常模式、USB 数据线及 CC1/HID 口，然后重新连接；已收到的数据会保存")
        capture.stop()
        return capture.state()
    except BaseException:
        capture.stop(False)
        raise
    finally:
        stopped.set(); signal.signal(signal.SIGINT, old_handler)
        if raw: raw.close()
        if preview:
            path = preview.path
            preview.close()
            for suffix in ("", "-wal", "-shm"): Path(str(path) + suffix).unlink(missing_ok=True)
