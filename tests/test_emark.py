import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid

from k2up.emark import validate_record, validate_bank, sample_record, sample_bank
from k2up.picture import resource_for, sha
from k2up.gui_bridge import main


class EmarkTests(unittest.TestCase):
    def test_exact_record_layout_and_checksum(self):
        data = sample_record("Cable A")
        self.assertEqual(len(data), 66)
        self.assertEqual(data[:8], b"Cable A\0")
        self.assertEqual(data[20], 2)
        self.assertEqual(data[65], (sum(data[:65]) + 165) % 256)
        for index in (0, 19, 21, 37, 49, 61, 65):
            wrong = bytearray(data); wrong[index] ^= 1
            with self.assertRaises(ValueError): validate_record(wrong)

    def test_bounds_and_unsupported_version(self):
        for size in (0, 65, 67):
            with self.assertRaises(ValueError): validate_record(bytes(size))
        data = bytearray(sample_record()); data[20] = 1
        data[65] = (sum(data[:65]) + 165) % 256
        self.assertEqual(validate_record(data)[20], 1)
        for mutation in ("name", "pd"):
            data = bytearray(sample_record())
            if mutation == "name": data[:19] = b"A" * 19
            else: data[20] = 4
            data[65] = (sum(data[:65]) + 165) % 256
            with self.assertRaises(ValueError): validate_record(data)

    def test_bank_preserves_unknown_header_and_inactive_slots(self):
        data = bytearray(sample_bank()); data[:4] = b"abcd"
        data[72:] = bytes((i * 17) % 256 for i in range(594))
        self.assertEqual(validate_bank(data), data)
        for selected, count in ((10, 10), (0, 11), (1, 0), (1, 1)):
            wrong = bytearray(data); wrong[4:6] = bytes((selected, count))
            with self.assertRaises(ValueError): validate_bank(wrong)
        data[4:6] = bytes((0, 0)); self.assertEqual(validate_bank(data), data)

    def test_all_ten_active_records_require_valid_checksums(self):
        data = bytearray(sample_bank()); data[4:6] = bytes((9, 10))
        for i in range(10): data[6 + i * 66:72 + i * 66] = sample_record(f"Cable {i}")
        validate_bank(data)
        data[6 + 9 * 66 + 65] ^= 1
        with self.assertRaises(ValueError): validate_bank(data)

    def test_fixed_emark_ranges_end_at_layout_and_do_not_overlap(self):
        copied, bank, layout = (resource_for(kind) for kind in ("emark-copy", "emark", "layout"))
        self.assertEqual((copied.address, copied.size, copied.allocation), (0x080E3000, 66, 2048))
        self.assertEqual((bank.address, bank.size, bank.allocation), (0x080E3800, 666, 2048))
        self.assertEqual(copied.address + copied.allocation, bank.address)
        self.assertEqual(bank.address + bank.allocation, layout.address)

    def test_bridge_invalid_configuration_is_rejected_before_usb(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "invalid.resource"
            raw = bytearray(sample_bank()); raw[5] = 11; path.write_bytes(raw)
            request = {"id": str(uuid.uuid4()), "operation": "resource-write", "resource_kind": "emark",
                       "simulation": False, "data_directory": root, "resource_path": str(path),
                       "resource_sha256": sha(raw), "dfu_confirmed": True, "device_path_hex": "00",
                       "device_info_sha256": "device", "confirmed": True}
            output = io.StringIO()
            with patch("k2up.transport._hid", side_effect=AssertionError("USB accessed")):
                code = main(io.StringIO(json.dumps(request) + "\n"), output)
            self.assertEqual(code, 1)
            self.assertIn("默认组", output.getvalue())


if __name__ == "__main__": unittest.main()
