import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import uuid
import zipfile

from k2up.demo import demo_firmware
from k2up.firmware import Firmware, SECTOR_SIZE, SECTOR_COUNT
from k2up.gui_bridge import main
from k2up.official_firmware import import_archive


class OfficialFirmwareTests(unittest.TestCase):
    def firmware(self):
        app = bytearray(demo_firmware().app)
        app[100] ^= 1  # Distinct synthetic fixture, never sent to hardware.
        return Firmware.from_app(app)

    def archive(self, root, entries):
        path = Path(root) / 'input.zip'
        with zipfile.ZipFile(path, 'w', zipfile.ZIP_DEFLATED) as archive:
            for name, data in entries:
                archive.writestr(name, data)
        return path

    def test_import_validates_before_saving_and_never_accesses_usb(self):
        with tempfile.TemporaryDirectory() as root:
            firmware = self.firmware()
            path = self.archive(root, [('folder/K2.k2', firmware.source), ('说明.txt', '说明')])
            request = {'id': str(uuid.uuid4()), 'operation': 'firmware-extract',
                       'firmware_path': str(path), 'firmware_version': firmware.version,
                       'data_directory': root}
            output = io.StringIO()
            with patch('k2up.transport._hid', side_effect=AssertionError('USB accessed')):
                code = main(io.StringIO(json.dumps(request) + '\n'), output)
            self.assertEqual(code, 0)
            result = json.loads(output.getvalue().splitlines()[-1])['value']
            self.assertEqual(Path(result['firmware_path']).read_bytes(), firmware.source)
            self.assertFalse(result['demo_firmware'])

    def test_wrong_version_corrupt_and_demo_firmware_are_not_saved(self):
        with tempfile.TemporaryDirectory() as root:
            cases = [(self.firmware().source, '5.7'), (b'corrupt', '5.8'),
                     (demo_firmware().source, '5.8')]
            for raw, version in cases:
                with self.subTest(version=version, size=len(raw)):
                    path = self.archive(root, [('input.k2', raw)])
                    with self.assertRaises(ValueError): import_archive(path, root, version)
                    self.assertFalse((Path(root) / 'Downloaded Firmware').exists())

    def test_ambiguous_and_oversized_entries_are_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            for entries in [[('a.k2', b'a'), ('b.k2', b'b')], [('README.txt', 'no firmware')],
                            [('big.k2', b'x' * (SECTOR_SIZE * SECTOR_COUNT + 1))]]:
                path = self.archive(root, entries)
                with self.assertRaises(ValueError): import_archive(path, root, '5.8')

    def test_archive_paths_cannot_write_outside_destination(self):
        with tempfile.TemporaryDirectory() as root:
            firmware = self.firmware()
            path = self.archive(root, [('../../escape.k2', firmware.source),
                                       ('../../escape.txt', 'not extracted')])
            result = import_archive(path, root, firmware.version)
            output = Path(result['firmware_path'])
            self.assertEqual(output.parent, (Path(root) / 'Downloaded Firmware').resolve())
            self.assertFalse((Path(root) / 'escape.txt').exists())
            self.assertEqual(output.read_bytes(), firmware.source)

    def test_bad_zip_reports_a_user_error(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / 'input.zip'
            path.write_bytes(b'not zip')
            with self.assertRaisesRegex(ValueError, '固件包无效'):
                import_archive(path, root, '5.8')


if __name__ == '__main__': unittest.main()
