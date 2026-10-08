import io
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import uuid

from k2up.gui_bridge import Events, main
from k2up.monitor import AutoStop, Capture, run_monitor
from k2up.recording import readonly, samples, summary
from k2up.telemetry import Sample
from tests.test_telemetry import report


class MonitorTests(unittest.TestCase):
    def test_pause_resume_and_auto_stop_reset_on_gap(self):
        with tempfile.TemporaryDirectory() as root:
            capture = Capture(root)
            capture.control({"command": "start", "rate": 0, "threshold": 2, "duration": 2})
            path = capture.state()["record_path"]
            capture.feed(Sample(0, 5, 1, 5, 5, uptime=0))
            capture.control({"command": "pause"})
            capture.feed(Sample(1, 5, 1, 5, 5, uptime=1))
            capture.control({"command": "resume"})
            self.assertFalse(capture.feed(Sample(2, 5, 1, 5, 5, uptime=2))[1])
            self.assertFalse(capture.feed(Sample(10, 5, 1, 5, 5, uptime=10))[1])
            self.assertFalse(capture.feed(Sample(11, 5, 1, 5, 5, uptime=11))[1])
            self.assertTrue(capture.feed(Sample(12, 5, 1, 5, 5, uptime=12))[1])
            self.assertEqual(summary(path)["metadata"]["closed"], "1")
            db = readonly(path)
            try: items = list(samples(db))
            finally: db.close()
            self.assertEqual(len(items), 5)
            self.assertNotEqual(items[0].segment, items[1].segment)
            self.assertNotEqual(items[1].segment, items[2].segment)

    def test_passive_session_control_and_handle_close(self):
        with tempfile.TemporaryDirectory() as root:
            finished = threading.Event()
            class Transport:
                def __init__(self, _): self.count = 0; self.closed = False
                def read(self, timeout):
                    time.sleep(.005); self.count += 1
                    if self.count >= 6: finished.set()
                    return report()
                def close(self): self.closed = True
                def write(self, *_): raise AssertionError("monitor wrote to USB")
            transport = Transport(None)
            class Input:
                count = 0
                def readline(self, _):
                    self.count += 1
                    if self.count == 1: return json.dumps({"command": "start", "rate": 0}) + "\n"
                    finished.wait(2)
                    return '{"command":"disconnect"}\n' if self.count == 2 else ""
            request = {"id": str(uuid.uuid4()), "operation": "monitor", "device_path_hex": "01", "device_serial": None, "data_directory": root}
            device = {"path": b"\x01", "vendor_id": 0x0716, "product_id": 0x5060}
            with patch("k2up.monitor.enumerate_devices", return_value=[device]):
                result = run_monitor(request, Events(request, io.StringIO()), Input(), lambda _: transport)
            self.assertTrue(transport.closed)
            self.assertGreater(summary(result["record_path"])["count"], 0)
            self.assertEqual(list((Path(root) / "Preview").glob("*")), [])

    def test_monitor_bridge_rejects_missing_path_before_usb(self):
        request = {"id": str(uuid.uuid4()), "operation": "monitor", "data_directory": "/tmp"}
        with patch("k2up.transport._hid", side_effect=AssertionError("USB accessed")):
            output = io.StringIO(); code = main(io.StringIO(json.dumps(request) + "\n"), output)
        self.assertEqual(code, 1)
        self.assertIn("普通模式", output.getvalue())

    def test_auto_stop_threshold_strict(self):
        auto = AutoStop("current", 1, 1)
        self.assertFalse(auto.accept(Sample(0, 5, -1, 5, -5)))
        self.assertFalse(auto.accept(Sample(1, 5, -.5, 2.5, -2.5)))
        self.assertTrue(auto.accept(Sample(2, 5, -.5, 2.5, -2.5)))
        with self.assertRaises(ValueError): AutoStop("current", float("nan"), 1)


if __name__ == "__main__": unittest.main()
