import contextlib
from dataclasses import replace
from functools import reduce
import io
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch, Mock
import uuid

from k2up import cli
from k2up.firmware import (Firmware, FirmwareError, APP_START, SECTOR_SIZE,
                          MARKER_OFFSET, COMMIT_MARKER)
from k2up.protocol import Protocol, ProtocolError, build_frame, parse_frame
from k2up.simulator import SimulatedTransport
from k2up.transport import (HidTransport, normalize_input, select_device,
                            VID, PID)
from k2up.updater import Updater, UpgradeError, Identity
from k2up.backup import backup_device, FLASH_START

ROOT = Path(__file__).resolve().parents[1]
DECODE = (ROOT / "k2up/data/firmware_decode.bin").read_bytes()
ENCODE = bytes(DECODE.index(i) for i in range(256))


def synthetic_firmware():
    """Build a deterministic, non-vendor container for offline tests."""
    app = bytearray((index * 37 + 11) & 0xFE for index in range(716400))
    struct.pack_into("<II", app, 0, 0x20017D50, 0x08003B11)
    app[2048] = 0x58
    app[MARKER_OFFSET:MARKER_OFFSET + 4] = b"\xff" * 4

    decoded = bytearray(48 + len(app))
    decoded[:7] = b"gzutapp"
    struct.pack_into("<HBB", decoded, 7, 2026, 9, 24)
    decoded[11:20] = b"\xff" * 9
    decoded[20:36] = uuid.UUID("5a3f8522-366b-46cc-aacc-dbfbe2fee02a").bytes_le
    struct.pack_into("<III", decoded, 36, len(app), reduce(int.__xor__, app, 0), sum(app) & 0xFFFFFFFF)
    decoded[48:] = app
    return bytes(decoded).translate(ENCODE)


RAW = synthetic_firmware()
FIRMWARE = Firmware.parse(RAW)


def mutated(offset, data, recalculate=False):
    decoded = bytearray(RAW.translate(DECODE))
    decoded[offset:offset + len(data)] = data
    if recalculate:
        app = decoded[48:]
        struct.pack_into("<III", decoded, 36, len(app), reduce(int.__xor__, app, 0), sum(app) & 0xffffffff)
    return bytes(decoded).translate(ENCODE)


class FirmwareTests(unittest.TestCase):
    def test_recovery_container_resets_marker_and_preserves_image(self):
        app = bytearray(FIRMWARE.app + b"\xff" * 8192)
        app[MARKER_OFFSET:MARKER_OFFSET + 4] = COMMIT_MARKER
        recovery = Firmware.from_app(app)
        expected = bytearray(FIRMWARE.app[:len(recovery.app)])
        expected[MARKER_OFFSET:MARKER_OFFSET + 4] = b"\xff" * 4
        self.assertEqual(recovery.app, expected)
        self.assertEqual(recovery.version, "5.8")
        self.assertTrue(all(b == 255 for b in app[len(recovery.app):]))

    def test_synthetic_firmware_container(self):
        info = FIRMWARE.summary()
        self.assertEqual((FIRMWARE.version, FIRMWARE.date), ("5.8", "2026-09-24"))
        self.assertEqual((len(FIRMWARE.app), len(FIRMWARE.erase_addresses)), (716400, 350))
        self.assertEqual(info["file_size"], 716448)
        self.assertEqual(info["erase_end_exclusive"], "0x080B2800")

    def test_invalid_containers(self):
        cases = [b"", RAW[:47], RAW[:-1], mutated(0, b"X"), mutated(20, b"\x00"),
                 mutated(9, b"\x0d"), mutated(7, struct.pack("<H", 2050)),
                 mutated(100, bytes((RAW.translate(DECODE)[100] ^ 1,))), mutated(40, b"\x00" * 4),
                 mutated(44, b"\x00" * 4),
                 mutated(48 + MARKER_OFFSET, COMMIT_MARKER, True),
                 mutated(48, struct.pack("<I", 0x10000000), True),
                 mutated(52, struct.pack("<I", APP_START), True),
                 mutated(52, struct.pack("<I", APP_START - 1), True),
                 RAW + b"\0" * 1000000]
        for raw in cases:
            with self.subTest(length=len(raw), head=raw[:8]), self.assertRaises(FirmwareError):
                Firmware.parse(raw)

    def test_container_header_counts_toward_erase(self):
        # An app exactly two sectors long still causes three sectors to be
        # erased by the recovered Windows worker, because its header counts.
        decoded = bytearray(RAW.translate(DECODE)[:48 + 4096])
        app = decoded[48:]
        struct.pack_into("<III", decoded, 36, len(app), reduce(int.__xor__, app, 0), sum(app))
        fw = Firmware.parse(bytes(decoded).translate(ENCODE))
        self.assertEqual(len(fw.erase_addresses), 3)

    def test_altered_firmware_object_rejected_before_io(self):
        transport = SimulatedTransport()
        updater = Updater(Protocol(transport))
        with self.assertRaises(UpgradeError):
            updater.flash(replace(FIRMWARE, app=b"bad"))
        self.assertEqual(transport.sent, [])
        self.assertEqual(updater.stage, "validate")


class FrameTests(unittest.TestCase):
    def test_golden_packet(self):
        # Independently expanded from RID 104 integer divisions and RID 103
        # sums: header FF 55 40 15 1A 87 59 29; checksums 51 / 1D.
        expected = bytes.fromhex("ff5540151a87592909090038000804feffffff" + "00" * 43 + "511d")
        frame = build_frame(9, bytes.fromhex("0038000804feffffff"), tick=123456789, reply=False)
        self.assertEqual(frame, expected)
        self.assertEqual(parse_frame(frame).payload, bytes.fromhex("0038000804feffffff"))

    def test_bad_packets(self):
        frame = build_frame(2, tick=0)
        for index in (0, 8, 62, 63):
            bad = bytearray(frame)
            bad[index] ^= 1
            with self.subTest(index=index), self.assertRaises(ProtocolError):
                parse_frame(bad)
        with self.assertRaises(ProtocolError):
            parse_frame(frame[:-1])
        bad = bytearray(frame)
        bad[9] = 53
        bad[62] = sum(bad[8:62]) & 255
        bad[63] = sum(bad[:62]) & 255
        with self.assertRaises(ProtocolError):
            parse_frame(bad)

    def test_limits_and_reply_flag(self):
        with self.assertRaises(ValueError):
            build_frame(9, b"x" * 53)
        self.assertTrue(build_frame(3, tick=0)[4] & 128)
        self.assertFalse(build_frame(8, tick=0, reply=False)[4] & 128)
        self.assertEqual(build_frame(3, tick=0), build_frame(3, tick=2**32))

    def test_stale_ack_is_never_reused(self):
        sim = SimulatedTransport()
        sim.queue.append(build_frame(2))
        with self.assertRaisesRegex(ProtocolError, "未消费"):
            Protocol(sim).command(3)
        self.assertEqual(sim.sent, [])

    def test_async_nack_stops_before_next_erase(self):
        sim = SimulatedTransport()
        protocol = Protocol(sim)
        protocol.command(3)
        protocol.command(5)
        protocol.erase_sector(APP_START)
        sim.queue.append(build_frame(1))
        with self.assertRaises(ProtocolError):
            protocol.erase_sector(APP_START + SECTOR_SIZE)
        self.assertEqual([p.command for p in sim.sent], [3, 5, 8])

    def test_logs_can_interleave_with_response(self):
        sim = SimulatedTransport()
        original = sim._reply
        def log_first(command, data=b""):
            sim.queue.append(build_frame(21, b"log"))
            original(command, data)
        sim._reply = log_first
        Protocol(sim).command(3)
        self.assertEqual(len(sim.queue), 0)

    def test_wrong_read_length_fails(self):
        sim = SimulatedTransport()
        protocol = Protocol(sim)
        protocol.command(3)
        original = sim._reply
        sim._reply = lambda command, data=b"": original(command, data[:-1])
        with self.assertRaisesRegex(ProtocolError, "分包长度"):
            protocol.read_memory(0x08003000, 1024)


class UpgradeTests(unittest.TestCase):
    def test_probe_against_simulator(self):
        transport = SimulatedTransport(model="K2")
        identity = Updater(Protocol(transport)).probe()
        self.assertTrue(identity.confirmed_k2)
        self.assertEqual(identity.boot_strings, ("K2", "WITRN", "DFU"))
        self.assertEqual(identity.current_version, "0.0")
        self.assertEqual(identity.current_marker_hex, "00000000")
        self.assertFalse(transport.erased or transport.written or transport.exited)

    def test_full_upgrade_order_and_image(self):
        sim = SimulatedTransport()
        updater = Updater(Protocol(sim))
        identity = updater.flash(FIRMWARE)
        self.assertTrue(identity.confirmed_k2)
        self.assertEqual(updater.stage, "complete")
        expected = bytearray(FIRMWARE.app)
        expected[MARKER_OFFSET:MARKER_OFFSET + 4] = COMMIT_MARKER
        self.assertEqual(sim.memory[:len(expected)], expected)
        self.assertTrue(sim.committed and sim.exited)
        commands = [p.command for p in sim.sent]
        self.assertEqual(commands[:5], [3, 11, 11, 22, 5])
        self.assertEqual(commands.count(8), 350)
        self.assertEqual(commands.count(9), 18191)
        self.assertEqual(len(commands), 19253)
        commit = next(i for i, p in enumerate(sim.sent) if p.command == 9 and p.payload == struct.pack("<IB", APP_START + MARKER_OFFSET, 4) + COMMIT_MARKER)
        self.assertEqual(commands[commit - 1:], [5, 9, 10, 4, 23])
        self.assertTrue(all(p.command != 9 for p in sim.sent[commands.index(11, 3):commit - 1]))
        with self.assertRaises(UpgradeError):
            updater.flash(FIRMWARE)

    def test_faults_stop_without_cleanup_or_retry(self):
        cases = {"timeout": "handshake", "nack": "handshake", "wrong-ack": "handshake",
                 "bad-frame": "handshake", "batch-nack": "erase", "disconnect": "write",
                 "short-write": "write", "verify": "verify", "marker": "commit"}
        for fault, stage in cases.items():
            with self.subTest(fault=fault):
                sim = SimulatedTransport(fault=fault)
                updater = Updater(Protocol(sim))
                with self.assertRaises(UpgradeError) as raised:
                    updater.flash(FIRMWARE)
                self.assertEqual(raised.exception.stage, stage)
                self.assertEqual(updater.stage, stage)
                self.assertFalse(sim.exited)
                self.assertNotIn(23, [p.command for p in sim.sent])
                if stage != "commit":
                    self.assertFalse(sim.committed)
                if stage in ("handshake", "erase"):
                    self.assertNotIn(9, [p.command for p in sim.sent])
                if stage == "write":
                    self.assertEqual(sim.sent[-1].command, 9)

    def test_wrong_model_rejected_before_erase(self):
        sim = SimulatedTransport(model="C5")
        with self.assertRaisesRegex(UpgradeError, "不能确认"):
            Updater(Protocol(sim)).flash(FIRMWARE)
        self.assertEqual([p.command for p in sim.sent], [3, 11, 11])

    def test_probe_reports_unknown_model_without_writes(self):
        sim = SimulatedTransport(model="unknown")
        identity = Updater(Protocol(sim)).probe()
        self.assertFalse(identity.confirmed_k2)
        self.assertEqual([p.command for p in sim.sent], [3, 11, 11, 11, 10])
        self.assertFalse(sim.erased or sim.written or sim.committed)

    def test_captured_hardware_identity_is_recognized(self):
        identity = Identity(("Dec 26 2024", "09:56:02", "K2(C)WITRN"), "hash")
        self.assertTrue(identity.confirmed_k2)
        self.assertFalse(Identity(("C5(C)WITRN", "", ""), "hash").confirmed_k2)


class HidTests(unittest.TestCase):
    def setUp(self):
        self.selected = {"path": b"test", "vendor_id": VID, "product_id": PID}

    def test_selection_requires_unique_interface(self):
        other = dict(self.selected, path=b"other")
        for candidates in ([], [self.selected, other], [dict(self.selected, product_id=1)]):
            with self.subTest(candidates=candidates), self.assertRaises(OSError):
                select_device(candidates)
        self.assertEqual(select_device([self.selected, other], b"other".hex()), other)
        with self.assertRaises(OSError):
            select_device([self.selected], "invalid")

    def test_report_id_normalization(self):
        frame = build_frame(2)
        self.assertEqual(normalize_input(frame), frame)
        self.assertEqual(normalize_input(b"\0" + frame), frame)
        self.assertEqual(normalize_input([]), b"")
        for raw in (b"\x01" + frame, frame[:63], frame + b"xx"):
            with self.assertRaises(ProtocolError):
                normalize_input(raw)

    def test_backend_adds_report_id_and_checks_count(self):
        device = Mock()
        with patch("k2up.transport._hid", return_value=Mock(device=lambda: device)):
            transport = HidTransport(self.selected)
        device.open_path.assert_called_once_with(b"test")
        frame = build_frame(3)
        device.write.return_value = 65
        self.assertEqual(transport.write(frame), 64)
        device.write.assert_called_once_with(b"\0" + frame)
        device.write.return_value = 64
        with self.assertRaises(ProtocolError):
            transport.write(frame)
        device.read.return_value = list(frame)
        self.assertEqual(transport.read(123), frame)
        device.read.assert_called_once_with(65, 123)

    def test_zero_timeout_is_explicitly_nonblocking(self):
        device = Mock()
        with patch("k2up.transport._hid", return_value=Mock(device=lambda: device)):
            transport = HidTransport(self.selected)
        device.reset_mock()
        device.read.return_value = []
        self.assertEqual(transport.read(0), b"")
        self.assertEqual(device.set_nonblocking.call_args_list, [((1,),), ((0,),)])
        device.read.assert_called_once_with(65)
        device.reset_mock()
        device.read.side_effect = OSError("disconnected")
        with self.assertRaises(OSError):
            transport.read(0)
        self.assertEqual(device.set_nonblocking.call_args_list, [((1,),), ((0,),)])


class BackupTests(unittest.TestCase):
    class BackupSim(SimulatedTransport):
        def __init__(self, corrupt_second=False):
            super().__init__()
            self.memory[:] = b"\xff" * len(self.memory)
            self.memory[:len(FIRMWARE.app)] = FIRMWARE.app
            self.memory[MARKER_OFFSET:MARKER_OFFSET + 4] = COMMIT_MARKER
            self.first_count = 0
            self.corrupt_second = corrupt_second
        def _read_memory(self, address, size):
            if address == FLASH_START:
                self.first_count += 1
            if FLASH_START <= address < APP_START and size == 1024:
                data = b"\xff" * size
                if address == FLASH_START and self.corrupt_second and self.first_count == 2:
                    data = b"\xfe" + data[1:]
                return data
            return super()._read_memory(address, size)

    def test_backup_twice_verified_and_recovery_parses(self):
        sim = self.BackupSim()
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / "backup"
            result = backup_device(Updater(Protocol(sim)), directory)
            self.assertTrue(result["two_independent_reads_match"])
            self.assertEqual(result["identity"]["current_version"], "5.8")
            self.assertEqual(result["identity"]["current_marker_hex"], "feffffff")
            self.assertEqual((directory / "app.bin").read_bytes(), bytes(sim.memory))
            recovery = Firmware.load(result["recovery_file"])
            self.assertEqual(recovery.version, "5.8")
            self.assertTrue((directory / "manifest.json").exists())
            self.assertFalse((directory / "flash.bin.partial").exists())
        self.assertTrue(all(p.command in (3, 11) for p in sim.sent))
        self.assertFalse(sim.erased or sim.written)

    def test_second_read_mismatch_stops_without_recovery(self):
        sim = self.BackupSim(corrupt_second=True)
        with tempfile.TemporaryDirectory() as temp:
            directory = Path(temp) / "backup"
            with self.assertRaisesRegex(UpgradeError, "第二遍"):
                backup_device(Updater(Protocol(sim)), directory)
            self.assertTrue((directory / "flash.bin.partial").exists())
            self.assertFalse((directory / "manifest.json").exists())
            self.assertEqual(list(directory.glob("*.k2")), [])
        self.assertTrue(all(p.command in (3, 11) for p in sim.sent))


class CliTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tempdir = tempfile.TemporaryDirectory()
        cls.sample = Path(cls.tempdir.name) / "synthetic.k2"
        cls.sample.write_bytes(RAW)

    @classmethod
    def tearDownClass(cls):
        cls.tempdir.cleanup()

    def run_cli(self, arguments):
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            return cli.main(arguments)

    def test_offline_commands_do_not_load_hid(self):
        with patch("k2up.transport._hid", side_effect=AssertionError("USB touched")):
            self.assertEqual(self.run_cli(["inspect", str(self.sample)]), 0)
            self.assertEqual(self.run_cli(["dry-run", str(self.sample)]), 0)

    def test_preflight_stops_before_enumeration(self):
        with patch("k2up.cli.enumerate_devices", side_effect=AssertionError("USB touched")):
            self.assertEqual(self.run_cli(["flash", str(self.sample)]), 1)
            self.assertEqual(self.run_cli(["flash", str(self.sample), "--dfu"]), 1)
            self.assertEqual(self.run_cli(["flash", str(self.sample), "--dfu", "--yes", "--timeout-ms", "0"]), 1)
            self.assertEqual(self.run_cli(["flash", str(self.sample / "missing"), "--dfu", "--yes"]), 1)

    def test_cli_returns_failure_on_verify(self):
        self.assertEqual(self.run_cli(["dry-run", str(self.sample), "--fault", "verify"]), 1)

    def test_failed_log_and_close_do_not_mask_original_error(self):
        transport = Mock()
        transport.write.side_effect = OSError("disconnected")
        transport.read.return_value = b""
        transport.close.side_effect = OSError("close failed")
        trace = Mock()
        # The initial metadata and stage events succeed; only failure logging fails.
        trace.event.side_effect = lambda kind, **kw: (_ for _ in ()).throw(OSError("disk full")) if kind == "error" else None
        selected = {"path": b"test", "vendor_id": VID, "product_id": PID}
        with patch("k2up.cli.enumerate_devices", return_value=[selected]), patch("k2up.cli.HidTransport", return_value=transport), patch("k2up.cli.Trace", return_value=trace):
            self.assertEqual(self.run_cli(["probe", "--dfu"]), 1)
        transport.close.assert_called_once()
        trace.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
