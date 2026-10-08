import csv
import tempfile
from pathlib import Path
import unittest
from k2up.telemetry import Sample
from k2up.recording import Recording, readonly, samples, summary
from k2up.recording_files import import_record, export_record, parse_time, elapsed_text


class RecordingTests(unittest.TestCase):
    def test_cross_day_and_official_roundtrip(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root); source = root / "source.sqlite"
            record = Recording(source, 10)
            record.append(Sample(86401.234, 5, -2, 10, -10, temp_out=25, dp=2.7))
            record.append(Sample(86401.334, 6, 2, 12, 12, temp_out=26))
            record.close()
            self.assertEqual(summary(source)["count"], 2)
            for kind in ("csv", "official-sqlite", "local-sqlite"):
                output = root / kind; recovered = root / (kind + ".local")
                export_record(source, output, kind)
                import_record(output, recovered)
                db = readonly(recovered)
                try: items = list(samples(db))
                finally: db.close()
                self.assertAlmostEqual(items[0].time, 86401.234)
                self.assertEqual(items[0].current, -2)
                self.assertEqual(items[0].signed_power, -10)
                self.assertIsNone(items[1].dp)

    def test_optional_columns_and_atomic_failure(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root); source = root / "official.csv"; dest = root / "import.sqlite"
            source.write_text('Time(D.hh:mm:ss.ms),Voltage(V),Current(A),\n="00:00:00.000",5,1,\n="00:00:05.000",5,-1,\n')
            import_record(source, dest)
            db = readonly(dest)
            try: items = list(samples(db))
            finally: db.close()
            self.assertIsNone(items[0].temp_out)
            # Without rate metadata this gap defines the inferred rate.
            self.assertEqual(items[1].segment, 0)
            source.write_text('Time(D.hh:mm:ss.ms),Voltage(V),Current(A)\n00:00:01.000,5,1\n00:00:00.000,5,1\n')
            bad = root / "bad.sqlite"
            with self.assertRaisesRegex(ValueError, "倒退"): import_record(source, bad)
            self.assertFalse(bad.exists())
            with self.assertRaises(FileExistsError): Recording(dest)
            self.assertEqual(summary(dest)["count"], 2)

    def test_crash_marker_and_cancel(self):
        with tempfile.TemporaryDirectory() as root:
            root = Path(root); source = root / "source.sqlite"
            record = Recording(source)
            record.append(Sample(0, 5, 1, 5, 5)); record.commit(); record.close(False)
            self.assertEqual(summary(source)["metadata"]["closed"], "0")
            destination = root / "export.csv"; destination.write_text("keep")
            with self.assertRaises(InterruptedError): export_record(source, destination, "csv", cancelled=lambda: True)
            self.assertEqual(destination.read_text(), "keep")
            self.assertEqual(list(root.glob(".k2-export-*")), [])
            with self.assertRaises(ValueError): export_record(source, source, "local-sqlite")

    def test_time_strict(self):
        self.assertEqual(parse_time('="2.03:04:05.006"'), 183845.006)
        self.assertEqual(elapsed_text(183845.006), "2.03:04:05.006")
        for value in ("24:00:00.000", "00:60:00.000", "-1:00:00.000", "nan", "00:00:00"):
            with self.assertRaises(ValueError): parse_time(value)


if __name__ == "__main__": unittest.main()
