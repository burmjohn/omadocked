"""Desktop-action native harness must reject unsafe invocation before activity."""
from contextlib import redirect_stderr
import io
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).parent / "unit/desktop_action_contract.py"


class DesktopActionHarnessGuards(unittest.TestCase):
    def check_guard(self, args, *, optimize=0, wayland=True, expected=SystemExit):
        module = types.ModuleType("owned_action_guard_test")
        module.__file__ = str(SCRIPT)
        exec(compile(SCRIPT.read_text(), str(SCRIPT), "exec", optimize=optimize), module.__dict__)
        env = {"WAYLAND_DISPLAY": "owned-no-native"} if wayland else {}
        with patch.object(sys, "argv", [str(SCRIPT)] + args), patch.dict(os.environ, env, clear=True), \
                patch.object(subprocess, "Popen") as popen, \
                patch.object(tempfile, "TemporaryDirectory") as directory, redirect_stderr(io.StringIO()):
            with self.assertRaises(expected):
                module.run()
            popen.assert_not_called()
            directory.assert_not_called()

    def test_native_execution_requires_explicit_opt_in(self):
        self.check_guard([])
        self.check_guard(["--visible"])

    def test_real_wayland_is_required(self):
        self.check_guard(["--execute-fixtures", "--visible"], wayland=False)

    def test_disabled_assertions_reject_before_activity(self):
        for optimization in (1, 2):
            self.check_guard(["--execute-fixtures", "--visible"], optimize=optimization, expected=RuntimeError)
