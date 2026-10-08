from dataclasses import replace
import tempfile
from pathlib import Path
import unittest
from k2up.telemetry import Sample
from k2up.recording import Recording
from k2up.recording_stats import direction_area, plot_points, query_record, statistics


class StatisticsTests(unittest.TestCase):
    def test_cross_zero_and_exact_boundaries(self):
        # Current goes -2 to +2 over two seconds: each triangle is 1 A.s.
        items = [Sample(0, 5, -2, 10, -10), Sample(2, 5, 2, 10, 10)]
        stats = statistics(items)
        self.assertAlmostEqual(stats["ah_positive"] * 3600, 1)
        self.assertAlmostEqual(stats["ah_negative"] * 3600, 1)
        self.assertEqual(stats["wh_net"], 0)
        selected = statistics(items, .5, 1.5)
        self.assertAlmostEqual(selected["ah_absolute"] * 3600, .5)
        self.assertAlmostEqual(selected["coverage"], 1)
        self.assertEqual(selected["channels"]["current"]["min"], -1)
        self.assertEqual(selected["channels"]["current"]["max"], 1)

    def test_gaps_and_time_weighting(self):
        items = [Sample(0, 5, 1, 5, 5), Sample(1, 5, 3, 15, 15),
                 Sample(10, 5, 100, 500, 500, segment=1), Sample(11, 5, 100, 500, 500, segment=1)]
        stats = statistics(items)
        self.assertEqual(stats["coverage"], 2)
        self.assertAlmostEqual(stats["ah_absolute"] * 3600, 102)
        self.assertAlmostEqual(stats["channels"]["current"]["average"], 51)
        self.assertEqual(statistics([items[0]])["ah_absolute"], 0)
        self.assertEqual(statistics(items, 2, 9)["coverage"], 0)

    def test_peak_kept_with_bounded_plot(self):
        items = (Sample(i / 100, 5, 99 if i == 12345 else 1, 495 if i == 12345 else 5, 5) for i in range(100000))
        points = plot_points(items, 0, 1000)
        self.assertLessEqual(len(points), 6000)
        self.assertEqual(max(p["current"] for p in points), 99)
        self.assertEqual(points[0]["time"], 0)
        self.assertEqual(points[-1]["time"], 999.99)

    def test_sql_neighbor_interpolation(self):
        with tempfile.TemporaryDirectory() as root:
            path = Path(root) / "record.sqlite"
            record = Recording(path, 1)
            record.append(Sample(0, 5, 1, 5, 5)); record.append(Sample(1, 5, 3, 15, 15)); record.close()
            selected = query_record(path, .25, .75)["statistics"]
            self.assertAlmostEqual(selected["ah_absolute"] * 3600, 1)
            self.assertAlmostEqual(selected["percentages"]["coverage"], 50)


if __name__ == "__main__": unittest.main()
