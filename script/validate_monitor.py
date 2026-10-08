#!/usr/bin/env python3
"""Synthetic storage scale and real-time passive-loop validation; never opens USB."""
import argparse
import io
import json
from pathlib import Path
import resource
import tempfile
import threading
import time
import uuid
import sys
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from k2up.gui_bridge import Events
from k2up.monitor import run_monitor
from k2up.recording import Recording, summary
from k2up.recording_stats import query_record
from k2up.telemetry import Sample
import struct


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--samples", type=int, default=1_000_000)
    parser.add_argument("--seconds", type=float, default=60)
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix="k2-monitor-scale-") as folder:
        root = Path(folder)
        path = root / "scale.sqlite"
        initial = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
        started = time.monotonic()
        record = Recording(path, 100)
        for n in range(args.samples):
            current = 99 if n == args.samples // 2 else 1
            record.append(Sample(n / 100, 5, current, current * 5, current * 5))
        record.close()
        query = query_record(path, include_stats=True, budget=1200)
        assert query["count"] == args.samples
        assert len(query["points"]) <= 1200
        assert max(p["current"] for p in query["points"]) == 99
        growth = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss - initial
        assert growth < 100 * 1024 * 1024, growth  # Darwin ru_maxrss is bytes.
        print(json.dumps({"samples": args.samples, "plot_points": len(query["points"]), "memory_growth_bytes": growth,
                          "elapsed_seconds": round(time.monotonic() - started, 2)}), flush=True)
        done = threading.Event()
        class Input:
            reads = 0
            def readline(self, _):
                self.reads += 1
                if self.reads == 1: return '{"command":"start","rate":0}\n'
                done.wait(args.seconds + 10)
                return '{"command":"disconnect"}\n' if self.reads == 2 else ""
        class Transport:
            def __init__(self): self.count = 0; self.started = time.monotonic(); self.closed = False
            def read(self, _):
                self.count += 1
                time.sleep(max(0, self.started + self.count / 100 - time.monotonic()))
                data = bytearray(64); data[:2] = b"\xff\x55"; data[8:10] = bytes((0x1a, 52))
                struct.pack_into("<2f2I6fB", data, 14, 0, 0, self.count // 100, self.count // 100, 2.7, 2.7, 40, 25, 5, 1, 0)
                data[62] = sum(data[8:62]) % 256
                data[63] = sum(data[:62]) % 256
                if time.monotonic() - self.started >= args.seconds: done.set()
                return bytes(data)
            def close(self): self.closed = True
            def write(self, _): raise AssertionError("unexpected USB write")
        raw = Transport()
        request = {"id": str(uuid.uuid4()), "operation": "monitor", "device_path_hex": "01", "device_serial": None, "data_directory": str(root)}
        device = {"path": b"\x01", "vendor_id": 0x0716, "product_id": 0x5060}
        with patch("k2up.monitor.enumerate_devices", return_value=[device]):
            result = run_monitor(request, Events(request, io.StringIO()), Input(), lambda _: raw)
        saved = summary(result["record_path"])
        assert raw.closed and saved["metadata"]["closed"] == "1"
        assert saved["count"] >= raw.count - 2
        assert raw.count >= args.seconds * 99
        print(json.dumps({"realtime_seconds": args.seconds, "received": raw.count, "saved": saved["count"], "closed": True}), flush=True)


if __name__ == "__main__": main()
