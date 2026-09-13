"""Idle lock helpers must inherit overlay OMARCHY_PATH.

A login shell (`bash -lc`) sources /etc/profile.d/omarchy.sh and resets
OMARCHY_PATH to /usr/share/omarchy, so omarchy-system-lock talks to stock
omarchy-shell (not running) and the Omadocked locker never engages.
"""
from pathlib import Path
import unittest

OVERLAY_IDLE = (
    Path.home()
    / ".local/share/omadocked/omarchy/shell/plugins/services/idle/Service.qml"
)


def live_login_shell_lines(qml: str):
    return [
        line
        for line in qml.splitlines()
        if '["bash", "-lc"' in line and not line.lstrip().startswith("//")
    ]


class IdleLockEnvTests(unittest.TestCase):
    def test_commented_login_shell_is_ignored(self):
        qml = (
            '    // Must not be a login shell: `bash -lc` sources /etc/profile.d/omarchy.sh\n'
            '    process.command = ["bash", "-c", command]\n'
        )
        self.assertEqual(live_login_shell_lines(qml), [])

    def test_runprocess_login_shell_is_detected(self):
        qml = '    process.command = ["bash", "-lc", command]\n'
        self.assertEqual(
            live_login_shell_lines(qml),
            ['    process.command = ["bash", "-lc", command]'],
        )

    @unittest.skipUnless(OVERLAY_IDLE.is_file(), "omadocked overlay idle service not installed")
    def test_overlay_idle_helpers_are_not_login_shells(self):
        qml = OVERLAY_IDLE.read_text()
        self.assertIn('process.command = ["bash", "-c", command]', qml)
        self.assertEqual(live_login_shell_lines(qml), [])
