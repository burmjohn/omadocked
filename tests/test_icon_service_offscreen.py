"""Offscreen icon identity regression: no native source, persistence or windows."""
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest
import spawn_safety as safety


class IconServiceTests(unittest.TestCase):
    def test_service_lifecycle(self):
        self.run_fixture("service_lifecycle.qml", "SERVICE_LIFECYCLE")

    def test_canonical_icons_pins_and_launch_identity(self):
        self.run_fixture("icon_service.qml", "ICON_SERVICE")

    def run_fixture(self, name, marker):
        fixture = Path(__file__).parent / "fixtures" / name
        with tempfile.TemporaryDirectory(prefix="omadocked-icons-") as runtime:
            config = Path(runtime) / "config"
            config.mkdir()
            for directory in ("core", "services"):
                shutil.copytree(fixture.parents[2] / directory, config / directory)
            shell = config / "shell.qml"
            shell.write_text(fixture.read_text().replace('"../../services"', '"services"'))
            env = safety.fixture_environment()
            for key in ("DISPLAY", "WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "SWAYSOCK"):
                env.pop(key, None)
            env.update(XDG_RUNTIME_DIR=runtime, QT_QPA_PLATFORM="offscreen",
                       QT_QPA_PLATFORMTHEME="", OMADOCKED_TEST_MODE="1",
                       OMADOCKED_CONFIG_PATH="", OMADOCKED_PARKING_DISABLED="1")
            process = safety.spawn(["quickshell", "-p", str(shell)], required="offscreen",
                                   root=Path(runtime), env=env, text=True,
                                   stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            try:
                output, _ = process.communicate(timeout=20)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.communicate()
            self.assertEqual(process.returncode, 0, output)
            self.assertIn(marker + "_PASS", output)
            for failure in (marker + "_FAIL", "ReferenceError", "TypeError", "Binding loop",
                            "Failed to load configuration", "Cannot assign"):
                self.assertNotIn(failure, output)


if __name__ == "__main__":
    unittest.main()
