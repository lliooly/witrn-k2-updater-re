import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid

from k2up.demo import demo_firmware, is_demo_firmware
from k2up.gui_bridge import main


class GuiBridgeTests(unittest.TestCase):
    def request(self, root, **fields):
        return {"id": str(uuid.uuid4()), "operation": "probe", "simulation": True,
                "data_directory": str(root), "demo_delay_ms": 0, **fields}

    def execute(self, request):
        output = io.StringIO()
        code = main(io.StringIO(json.dumps(request) + "\n"), output)
        events = [json.loads(line) for line in output.getvalue().splitlines()]
        return code, events

    def upgrade_request(self, root, **fields):
        firmware = demo_firmware()
        path = Path(root) / "input.k2"
        path.write_bytes(firmware.source)
        _, probe = self.execute(self.request(root))
        identity = probe[-1]["value"]["identity"]
        return self.request(root, operation="upgrade", firmware_path=str(path),
                            firmware_sha256=firmware.summary()["file_sha256"],
                            device_info_sha256=identity["info_sha256"], confirmed=True, **fields)

    def test_full_demo_backs_up_before_flash_without_hid(self):
        with tempfile.TemporaryDirectory() as root, patch("k2up.transport._hid", side_effect=AssertionError("USB accessed")):
            request = self.upgrade_request(root)
            code, events = self.execute(request)
            self.assertEqual(code, 0)
            result = events[-1]["value"]
            self.assertTrue(result["simulation_only"])
            self.assertFalse(result["hardware_flash_validated"])
            self.assertTrue(result["backup"]["two_independent_reads_match"])
            self.assertTrue(result["backup"]["simulation_only"])
            stages = [e["stage"] for e in events if e["event"] == "progress"]
            self.assertLess(stages.index("backup-complete"), stages.index("erase"))
            self.assertTrue(all(e["id"] == request["id"] for e in events))

    def test_failed_backup_never_reaches_flash(self):
        with tempfile.TemporaryDirectory() as root:
            request = self.upgrade_request(root)
            with patch("k2up.gui_bridge.backup_device", side_effect=OSError("backup disk full")), patch("k2up.gui_bridge.Updater.flash") as flash:
                code, events = self.execute(request)
            self.assertEqual(code, 1)
            flash.assert_not_called()
            self.assertIn("backup disk full", events[-1]["message"])

    def test_changed_identity_never_reaches_flash(self):
        with tempfile.TemporaryDirectory() as root:
            request = self.upgrade_request(root)
            request["device_info_sha256"] = "other-device"
            with patch("k2up.gui_bridge.Updater.flash") as flash:
                code, events = self.execute(request)
            self.assertEqual(code, 1)
            flash.assert_not_called()
            self.assertIn("设备信息已变化", events[-1]["message"])

    def test_changed_file_rejected_before_hid(self):
        with tempfile.TemporaryDirectory() as root:
            request = self.upgrade_request(root)
            request["firmware_sha256"] = "other-file"
            with patch("k2up.transport._hid", side_effect=AssertionError("USB accessed")):
                code, events = self.execute(request)
            self.assertEqual(code, 1)
            self.assertIn("固件已变化", events[-1]["message"])

    def test_missing_write_confirmation_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            request = self.upgrade_request(root)
            request["confirmed"] = False
            with patch("k2up.transport._hid", side_effect=AssertionError("USB accessed")):
                code, events = self.execute(request)
            self.assertEqual(code, 1)
            self.assertIn("确认", events[-1]["message"])

    def test_demo_and_demo_recovery_cannot_flash_hardware(self):
        with tempfile.TemporaryDirectory() as root:
            for version in (0x34, 0x58):
                firmware = demo_firmware(version)
                self.assertTrue(is_demo_firmware(firmware))
                path = Path(root) / "demo.k2"; path.write_bytes(firmware.source)
                request = self.request(root, operation="upgrade", simulation=False, dfu_confirmed=True,
                                       confirmed=True, device_path_hex="00", firmware_path=str(path),
                                       firmware_sha256=firmware.summary()["file_sha256"])
                with patch("k2up.transport._hid", side_effect=AssertionError("USB accessed")):
                    code, events = self.execute(request)
                self.assertEqual(code, 1)
                self.assertIn("禁止写入真实设备", events[-1]["message"])

    def test_verify_fault_keeps_backup_and_does_not_complete(self):
        with tempfile.TemporaryDirectory() as root:
            request = self.upgrade_request(root, fault="verify")
            code, events = self.execute(request)
            self.assertEqual(code, 1)
            self.assertEqual(events[-1]["stage"], "verify")
            backups = list(Path(root).glob("Offline Demo/Backups/*/manifest.json"))
            self.assertEqual(len(backups), 1)
            self.assertFalse(any(e["event"] == "result" for e in events))


if __name__ == "__main__":
    unittest.main()
