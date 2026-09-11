import importlib.util
import contextlib
import io
import pathlib
import unittest

SPEC = importlib.util.spec_from_file_location("measure_process", pathlib.Path(__file__).resolve().parents[1] / "tools/measure_process.py")
module = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(module)


class MeasurementTests(unittest.TestCase):
    def test_stat_names_can_contain_spaces_and_parentheses(self):
        fields = ["S"] + ["0"] * 21
        fields[11], fields[12], fields[19], fields[21] = "17", "3", "12345", "512"
        result = module.parse_stat("321 (dock (prototype)) " + " ".join(fields), 4096)
        self.assertEqual(result, {"pid": 321, "start_ticks": 12345, "cpu_ticks": 20, "rss_bytes": 2097152})

    def test_sample_rejects_pid_reuse_and_negative_time(self):
        before = {"pid": 1, "start_ticks": 99, "cpu_ticks": 10, "rss_bytes": 4096}
        after = dict(before, cpu_ticks=20)
        self.assertAlmostEqual(module.summarize([before, after], 2.0, 100)["cpu_percent_one_core"], 5.0)
        with self.assertRaises(ValueError):
            module.summarize([before, dict(after, start_ticks=100)], 2.0, 100)
        with self.assertRaises(ValueError):
            module.summarize([before, after], 0, 100)
        with self.assertRaises(ValueError):
            module.summarize([before, dict(after, cpu_ticks=1)], 2, 100)

    def test_cli_rejects_invalid_duration_before_reading_process(self):
        for seconds in ("0", "-1", "nan", "inf"):
            with contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit):
                module.arguments(["--pid", "99999999", "--seconds", seconds])
