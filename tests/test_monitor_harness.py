"""Preflight regression checks for the monitor integration harness; no desktop use."""
import os
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch

from test_harness import load_harness


class MonitorHarnessTests(unittest.TestCase):
    def test_json_arrays_are_preserved_as_one_cli_argument(self):
        module = load_harness("unit/monitor_contract")
        encode = getattr(module, "json_ipc_argument", None)
        self.assertTrue(callable(encode), "Quickshell array-expansion guard is required")
        for names in ([], ["DP-2"], ["DP-2", "HDMI-A-1"]):
            value = encode(json.dumps(names))
            self.assertFalse(value.startswith("["))
            self.assertEqual(json.loads(value), names)

    def test_optimized_execution_stops_before_file_or_process_activity(self):
        for name, optimization in [(n, o) for n in ("unit/monitor_contract", "unit/appearance_contract", "unit/apps_contract") for o in (1, 2)]:
            with self.subTest(harness=name, optimization=optimization):
                module = load_harness(name, optimize=optimization)
                opened = Mock(side_effect=AssertionError("unexpected file activity"))
                run = Mock(side_effect=AssertionError("unexpected command"))
                spawn = Mock(side_effect=AssertionError("unexpected process"))
                with patch.object(Path, "open", opened), patch.object(module.subprocess, "run", run), patch.object(module.subprocess, "Popen", spawn):
                    with self.assertRaisesRegex(RuntimeError, "Optimized execution"):
                        module.main()
                opened.assert_not_called()
                run.assert_not_called()
                spawn.assert_not_called()

    def test_appearance_requires_visible_and_wayland_before_activity(self):
        for arguments, environment, exception in [
            ([], {"WAYLAND_DISPLAY": "test"}, SystemExit),
            (["--visible"], {}, RuntimeError),
        ]:
            with self.subTest(arguments=arguments):
                module = load_harness("unit/appearance_contract")
                with patch.dict(os.environ, environment, clear=True), patch.object(sys, "argv", ["appearance_contract.py", *arguments]), patch.object(sys, "stderr"), patch.object(Path, "open") as opened, patch.object(module.subprocess, "run") as run, patch.object(module.subprocess, "Popen") as spawn:
                    with self.assertRaises(exception):
                        module.main()
                    opened.assert_not_called()
                    run.assert_not_called()
                    spawn.assert_not_called()

    def test_missing_wayland_stops_before_file_or_process_activity(self):
        module = load_harness("unit/monitor_contract")
        with patch.dict(os.environ, {}, clear=True), patch.object(sys, "argv", ["monitor_contract.py"]), patch.object(Path, "open") as opened, patch.object(module.subprocess, "run") as run, patch.object(module.subprocess, "Popen") as spawn:
            with self.assertRaisesRegex(RuntimeError, "Wayland"):
                module.main()
            opened.assert_not_called()
            run.assert_not_called()
            spawn.assert_not_called()


if __name__ == "__main__":
    unittest.main()
