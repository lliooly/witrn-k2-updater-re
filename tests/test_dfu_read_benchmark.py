import struct
import unittest
from unittest.mock import Mock

from k2up.firmware import APP_START
from k2up.protocol import Protocol, ProtocolError, build_frame, parse_frame
from k2up.simulator import SimulatedTransport
from reverse.benchmark_dfu_reads import ReadOnlyTransport, read_bulk, read_region, read_short


class ShortReplyTransport(SimulatedTransport):
    """Models the recovered command-10 handler's single reply, not device timing."""
    def write(self, frame):
        packet = parse_frame(frame)
        if packet.command != 10:
            return super().write(frame)
        if not self.session:
            raise ProtocolError("Handshake required")
        address, size = struct.unpack("<IB", packet.payload)
        self.sent.append(packet)
        self._reply(10, self._read_memory(address, size))
        return 64


class DFUReadBenchmarkTests(unittest.TestCase):
    def test_guard_rejects_every_non_read_command_before_transport(self):
        device = Mock()
        guard = ReadOnlyTransport(device)
        for command in range(256):
            if command in (3, 10, 11):
                continue
            with self.subTest(command=command), self.assertRaises(ProtocolError):
                guard.write(build_frame(command))
        device.write.assert_not_called()

    def test_short_payload_sizes_and_unaligned_tail_match_bulk(self):
        for block in (40, 48, 52):
            sim = ShortReplyTransport()
            expected = bytes((index * 37 + 11) & 255 for index in range(2051))
            sim.memory[:len(expected)] = expected
            protocol = Protocol(ReadOnlyTransport(sim))
            protocol.command(3)
            baseline = read_region(protocol, APP_START, len(expected), 1024)
            self.assertEqual(baseline, expected)
            actual = read_region(protocol, APP_START, len(expected), block, short=True)
            self.assertEqual(actual, baseline)
            self.assertTrue(all(packet.command in (3, 10, 11) for packet in sim.sent))
            self.assertFalse(sim.erased or sim.written or sim.committed)

    def test_wrong_length_stops_without_retry_or_fallback(self):
        class Truncated(ShortReplyTransport):
            def _reply(self, command, data=b""):
                super()._reply(command, data[:-1] if command == 10 else data)
        sim = Truncated()
        protocol = Protocol(sim)
        protocol.command(3)
        with self.assertRaisesRegex(ProtocolError, "expected 52"):
            read_short(protocol, APP_START, 52)
        self.assertEqual([packet.command for packet in sim.sent], [3, 10])

    def test_invalid_size_does_not_touch_device(self):
        protocol = Mock()
        for size in (0, -1, 53, 255):
            with self.subTest(size=size), self.assertRaises(ValueError):
                read_short(protocol, APP_START, size)
        self.assertEqual(protocol.mock_calls, [])

    def test_large_bulk_and_tail_preserve_all_bytes(self):
        sim = ShortReplyTransport()
        expected = bytes((index * 37 + 11) & 255 for index in range(32771))
        sim.memory[:len(expected)] = expected
        protocol = Protocol(ReadOnlyTransport(sim))
        protocol.command(3)
        for block in (1000, 4000, 16000):
            self.assertEqual(read_region(protocol, APP_START, len(expected), block), expected)
        self.assertFalse(sim.erased or sim.written or sim.committed)

    def test_invalid_bulk_size_does_not_touch_device(self):
        protocol = Mock()
        for size in (0, -1, 65521, 65535):
            with self.subTest(size=size), self.assertRaises(ValueError):
                read_bulk(protocol, APP_START, size)
        self.assertEqual(protocol.mock_calls, [])

    def test_corrupt_checksum_is_rejected(self):
        class Corrupt(ShortReplyTransport):
            def _reply(self, command, data=b""):
                if command != 10:
                    return super()._reply(command, data)
                frame = build_frame(command, data)
                self.queue.append(frame[:-1] + bytes([frame[-1] ^ 1]))
        sim = Corrupt()
        protocol = Protocol(sim)
        protocol.command(3)
        with self.assertRaisesRegex(ProtocolError, "校验"):
            read_short(protocol, APP_START, 52)
        self.assertFalse(sim.erased or sim.written)
