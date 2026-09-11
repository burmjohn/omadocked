"""Hidden root-adapter daily-use tests. Temporary configuration; no real actions."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
import spawn_safety as safety

ROOT = Path(__file__).resolve().parents[1]


class DailyAdapterTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omadocked-daily-adapter-")
        self.directory = Path(self.temp.name)
        self.config = self.directory / "pins.json"
        for filename in ("shell.qml", "Dock.qml", "DockSurface.qml"):
            shutil.copy2(ROOT / filename, self.directory / filename)
        for directory in ("core", "services", "ui"):
            shutil.copytree(ROOT / directory, self.directory / directory)
        self.proc = None
        self.log = None

    def stop(self):
        if self.proc is not None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=5)
            self.proc = None
        if self.log is not None:
            self.log.close()

    def tearDown(self):
        self.stop()
        self.temp.cleanup()

    def start(self, test_mode="1", extra_env=None):
        env = {k: v for k, v in safety.fixture_environment().items() if not k.startswith("OMADOCKED_") and k not in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST")}
        env.update(QT_QPA_PLATFORM="wayland", OMADOCKED_VISIBLE="0", OMADOCKED_TEST_MODE=test_mode,
                   OMADOCKED_CONFIG_PATH=str(self.config), QS_NO_RELOAD_POPUP="1")
        env.update(extra_env or {})
        self.log = (self.directory / "runtime.log").open("w+")
        try:
            self.proc = safety.spawn(["/usr/bin/python3", str(ROOT / "tools/preview.py"), "--", "-n", "-p", str(self.directory / "shell.qml"), "--no-color"],
                                         required="native", root=self.directory, env=env, stdout=self.log, stderr=subprocess.STDOUT)
        except BaseException:
            self.log.close()
            raise
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            self.assertIsNone(self.proc.poll(), (self.directory / "runtime.log").read_text())
            try:
                state = self.call("snapshot")
                if state.get("appsReady"):
                    return state
            except (ValueError, AssertionError):
                pass
            time.sleep(.05)
        self.fail((self.directory / "runtime.log").read_text())

    def call(self, method, *args):
        result = safety.ipc(self.proc, ["quickshell", "ipc", "--pid", str(self.proc.pid), "call", "--",
                                 "omadocked-prototype", method, *args], text=True, capture_output=True, timeout=3)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout) if result.stdout.strip() else None

    def test_magnification_persists_and_binds_without_touching_other_settings(self):
        # Test-only IPC drives the production controller, never a live dock.
        shell = self.directory / "shell.qml"
        shell.write_text(shell.read_text().replace('function iconSize(value: real): bool {', '''function zoomSize(value: real): bool { return typeof dock.setZoomSize === "function" && dock.setZoomSize(value); }
        function waveWidth(value: real): bool { return typeof dock.setWaveWidth === "function" && dock.setWaveWidth(value); }
        function iconSize(value: real): bool {'''))
        self.config.write_text(json.dumps({"version":2,"pins":["fixture"],"launchers":[],"overrides":{},
            "settings":{"iconSize":50,"transparency":46,"autoHide":True,"monitorMode":"selected","selectedOutputs":["fixture-output"]}}))
        initial = self.start()
        self.assertTrue(self.call("zoomSize", "200"))
        self.assertTrue(self.call("waveWidth", "50"))
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            saved = json.loads(self.config.read_text())
            if saved["settings"].get("waveWidth") == 50:
                break
            time.sleep(.02)
        self.assertEqual(saved["settings"]["zoomSize"], 200)
        self.assertEqual(saved["settings"]["waveWidth"], 50)
        for method, value in [("zoomSize","201"),("zoomSize","145.5"),("waveWidth","26"),("waveWidth","5")]:
            self.assertFalse(self.call(method,value))
        self.assertEqual(saved["pins"], ["fixture"])
        for key, value in {"iconSize":50,"transparency":46,"autoHide":True,"monitorMode":"selected","selectedOutputs":["fixture-output"]}.items():
            self.assertEqual(saved["settings"][key],value)
        self.stop()
        state = self.start()
        for surface in state["outputs"]:
            self.assertEqual(surface["view"]["zoomSize"],200)
            self.assertEqual(surface["view"]["waveWidth"],50)
        self.assertEqual(json.loads(self.config.read_text()),saved)

    def test_settings_persist_and_bind_to_every_output(self):
        original = '{"version":1,"pins":[]}'
        self.config.write_text(original)
        initial = self.start()
        self.assertEqual(self.config.read_text(), original, "Loading v1 must not write a migration")
        for method, value in (("iconSize", "58"), ("transparency", "80"), ("mode", "off"),
                              ("reducedMotion", "true"), ("autohide", "false")):
            self.call(method, value)
        output = initial["outputs"][0]["name"]
        self.assertTrue(self.call("monitors", "selected", " " + json.dumps([output])))
        saved = json.loads(self.config.read_text())
        self.assertEqual(saved["version"], 2)
        self.assertEqual(saved["settings"]["iconSize"], 58)
        self.assertEqual(saved["settings"]["transparency"], 80)
        self.assertFalse(self.call("iconSize", "27"))
        self.assertEqual(json.loads(self.config.read_text()), saved)
        self.stop()
        state = self.start()
        self.assertEqual(state["iconSize"], 58)
        self.assertEqual(state["transparency"], 80)
        self.assertEqual(state["mode"], "off")
        self.assertTrue(state["reducedMotion"])
        self.assertFalse(state["autoHide"])
        self.assertEqual(state["activeOutputs"], [output])
        for surface in state["outputs"]:
            self.assertEqual(surface["view"]["iconSize"], 58)
            self.assertEqual(surface["view"]["transparency"], 80)

    def test_launcher_save_duplicate_remove_and_restart_never_launch(self):
        self.start()
        record = {"id": "", "kind": "command", "name": "Literal arguments", "program": "/nonexistent/omadocked-fixture",
                  "args": ["space inside", "$(touch /nonexistent/must-not-run)", ";not-shell"],
                  "workingDirectory": "/tmp", "terminal": False, "enabled": True}
        self.assertTrue(self.call("saveLauncher", json.dumps(record)))
        state = self.call("snapshot")
        item = state["launcherRecords"][0]
        self.assertEqual(item["args"], record["args"])
        self.assertFalse(state["apps"][0]["pending"])
        self.assertTrue(self.call("duplicateLauncher", item["id"]))
        copies = self.call("snapshot")["launcherRecords"]
        self.assertEqual(len(copies), 2)
        self.assertNotEqual(copies[0]["id"], copies[1]["id"])
        self.assertTrue(self.call("removeLauncher", item["id"]))
        self.stop()
        state = self.start()
        self.assertEqual(len(state["launcherRecords"]), 1)
        self.assertEqual(state["launcherRecords"][0]["args"], record["args"])
        self.assertTrue(all(not app["pending"] for app in state["apps"]))
        self.assertFalse(self.call("editor", state["output"], ""), "Hidden surfaces cannot acquire editor focus")

    def test_explicit_override_persists_and_matches_exactly(self):
        self.start()
        fixtures = {"entries": [{"id": "fixture-app", "name": "Fixture", "icon": "application-x-executable", "launchable": True}],
                    "windows": [{"key": "one", "appId": "DifferentCase", "active": True}]}
        self.assertTrue(self.call("fixtureApps", json.dumps(fixtures)))
        self.assertTrue(self.call("setOverride", "DifferentCase", "fixture-app"))
        self.assertEqual(self.call("snapshot")["apps"][0]["id"], "fixture-app")
        self.stop()
        self.start()
        self.assertTrue(self.call("fixtureApps", json.dumps(fixtures)))
        self.assertEqual(self.call("snapshot")["apps"][0]["id"], "fixture-app")
        self.assertTrue(self.call("setOverride", "DifferentCase", ""))
        self.assertTrue(self.call("snapshot")["apps"][0]["id"].startswith("window:"))

    def test_second_root_cannot_write_until_writer_restarts_after_release(self):
        self.start()
        self.assertTrue(self.call("iconSize", "50"))
        second = DailyAdapterTests()
        second.setUp()
        try:
            second.config = self.config
            state = second.start()
            self.assertTrue(state["appError"], "competing writer must be visibly read-only")
            before = self.config.read_bytes()
            self.assertFalse(second.call("iconSize", "60"))
            self.assertFalse(second.call("recoverConfiguration"))
            self.assertEqual(self.config.read_bytes(), before)
            self.assertTrue(self.call("iconSize", "48"))
            self.stop()
            second.stop()
            second.start()
            self.assertTrue(second.call("iconSize", "58"))
            self.assertEqual(json.loads(self.config.read_text())["settings"]["iconSize"], 58)
        finally:
            second.tearDown()

    def test_explicit_recovery_preserves_damage_and_refuses_future_versions(self):
        self.start()
        self.assertTrue(self.call("iconSize", "48"))
        self.assertTrue(self.call("iconSize", "58"))
        backup = json.loads(Path(str(self.config) + ".lkg").read_text())
        self.stop()
        damaged = "{intentionally damaged fixture"
        self.config.write_text(damaged)
        state = self.start()
        self.assertTrue(state["appError"] and state["canRecover"])
        self.assertEqual(self.config.read_text(), damaged)
        self.assertTrue(self.call("recoverConfiguration"))
        self.assertEqual(self.call("snapshot")["iconSize"], backup["settings"]["iconSize"])
        preserved = list(self.directory.glob("pins.json.damaged-*"))
        self.assertEqual(len(preserved), 1)
        self.assertEqual(preserved[0].read_text(), damaged)
        self.stop()
        future = '{"version":99,"pins":[]}'
        self.config.write_text(future)
        state = self.start()
        self.assertFalse(state["canRecover"])
        self.assertFalse(self.call("recoverConfiguration"))
        self.assertEqual(self.config.read_text(), future)
