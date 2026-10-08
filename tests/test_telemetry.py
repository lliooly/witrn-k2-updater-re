import math
import struct
import unittest
from k2up.telemetry import decode_report, Sampler


def checksummed(data):
    data = bytearray(data)
    data[62] = sum(data[8:62]) % 256
    data[63] = sum(data[:62]) % 256
    return bytes(data)


def report(current=-2):
    data = bytearray(64)
    data[:2] = b"\xff\x55"
    data[8:10] = bytes((0x1A, 52))
    struct.pack_into("<2f2I6fB", data, 14, 1.5, 7.5, 100, 200,
                     2.7, 2.8, 40, 25, 5, current, 2)
    return checksummed(data)


class TelemetryTests(unittest.TestCase):
    def test_mapping_direction_and_report_id(self):
        s = decode_report(b"\0" + report(), 1.25)
        self.assertEqual((s.voltage, s.current, s.power, s.signed_power), (5, -2, 10, -10))
        self.assertEqual((s.ah, s.wh, s.record_seconds, s.uptime, s.group), (1.5, 7.5, 100, 200, 3))
        self.assertEqual((s.temp_in, s.temp_out), (40, 25))

    def test_malformed_and_other_commands(self):
        with self.assertRaises(ValueError): decode_report(report(float("nan")), 0)
        for length in (0, 44, 53):
            data = bytearray(report()); data[9] = length
            with self.assertRaises(ValueError): decode_report(data, 0)
        data = bytearray(report()); data[8] = 3
        self.assertIsNone(decode_report(data, 0))

    def test_temperature_missing_not_zero(self):
        data = bytearray(report()); struct.pack_into("<2f", data, 38, float("nan"), 0)
        s = decode_report(checksummed(data), 0)
        self.assertIsNone(s.temp_in); self.assertIsNone(s.temp_out)

    def test_sampler_never_duplicates_or_catches_up(self):
        sampler = Sampler(10)
        self.assertEqual([sampler.accept(t) for t in (0, .03, .1, .11, 5, 5.01)], [True, False, True, False, True, False])
        self.assertTrue(Sampler(0).accept(0))

    def test_jitter_does_not_drift_or_create_samples(self):
        sampler = Sampler(100)
        arrivals = [.005 + n * .01 + (.0002 if n % 2 else -.0002) for n in range(1000)]
        self.assertEqual(sum(sampler.accept(t) for t in arrivals), 1000)
        sampler = Sampler(10)
        self.assertEqual(sum(sampler.accept(t) for t in arrivals), 100)
        # Bursts in one bucket are still limited; missing buckets aren't filled.
        sampler = Sampler(100)
        self.assertEqual([sampler.accept(t) for t in (.003, .004, .007, .033, .034)], [True, False, False, True, False])

    def test_bad_checksum_is_rejected(self):
        for offset in (20, 62, 63):
            data = bytearray(report()); data[offset] ^= 1
            with self.assertRaisesRegex(ValueError, "校验"): decode_report(data, 0)


if __name__ == "__main__": unittest.main()
