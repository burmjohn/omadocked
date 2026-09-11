"""App/pin adapter integration with synthetic identities and temporary storage only.

--visible additionally maps owned dock/context surfaces; no capture or pointer input.
"""
import argparse
import json
import os
from pathlib import Path
import sys
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
import spawn_safety as safety
ENTRIES = [
    {"id": "fixture-one", "name": "Fixture One", "startupClass": "FixtureOne", "icon": "application-x-executable", "launchable": True},
    {"id": "fixture-two", "name": "Fixture Two", "startupClass": "FixtureTwo", "icon": "application-x-executable", "launchable": True},
]
WINDOWS = [{"key": "first", "appId": "FixtureOne", "active": True}, {"key": "second", "appId": "FixtureTwo"}]


def main():
    if not __debug__:
        raise RuntimeError("Optimized execution is unsupported")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--visible", action="store_true")
    args = parser.parse_args()
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise RuntimeError("Requires the live Wayland session")
    safety.manual_native('apps_contract')
    safety.manual_native('monitor_contract')
    from monitor_contract import owned_layers
    checks = []
    with tempfile.TemporaryDirectory(prefix="omadocked-app-adapter-") as temp:
        config = Path(temp) / "pins.json"
        env = dict(os.environ, QT_QPA_PLATFORM="wayland", OMADOCKED_VISIBLE="0", OMADOCKED_TEST_MODE="1",
                   OMADOCKED_CONFIG_PATH=str(config), OMADOCKED_SCREENS="all", QS_NO_RELOAD_POPUP="1")
        for key in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST", "OMADOCKED_SCREEN", "OMADOCKED_OFFSET"):
            env.pop(key, None)
        for restart in (False, True):
            with (Path(temp) / "runtime.log").open("w+") as log:
                proc = safety.manual_process('Popen', 'apps_contract', ["/usr/bin/python3", str(ROOT / "tools/preview.py"), "--", "-n", "-p", str(ROOT / "shell.qml"), "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
                def ipc(method, *values):
                    result = safety.manual_process('run', 'apps_contract', ["quickshell", "ipc", "--pid", str(proc.pid), "call", "--", "omadocked-prototype", method, *values],
                                            env=env, capture_output=True, text=True, timeout=3)
                    if result.returncode:
                        raise RuntimeError(result.stdout + result.stderr)
                    return result.stdout.strip()
                def snapshot():
                    return json.loads(ipc("snapshot"))
                def wait_state(predicate):
                    deadline = time.monotonic() + 10
                    last = None
                    while time.monotonic() < deadline:
                        assert proc.poll() is None, "QML exited before readiness"
                        try:
                            last = snapshot()
                            if predicate(last):
                                return last
                        except (RuntimeError, json.JSONDecodeError):
                            pass
                        time.sleep(.05)
                    raise AssertionError("Adapter did not reach expected fixture state: " + repr(last))
                def seed(windows):
                    assert ipc("fixtureApps", json.dumps({"entries": ENTRIES, "windows": windows})) == "true"
                    return snapshot()
                try:
                    initial = wait_state(lambda s: s.get("appsReady"))
                    assert initial["phase"] == 3 and initial["testMode"] and initial["nonlaunching"]
                    assert not owned_layers(proc.pid)
                    if restart:
                        s = seed([])
                        assert [(a["id"], a["running"], a["pinned"]) for a in s["apps"]] == [("fixture-two", False, True), ("fixture-one", False, True)]
                        assert all(o["view"]["order"] == ["menu", "fixture-two", "fixture-one"] for o in s["outputs"])
                        assert ipc("pin", "fixture-two", "false") == "true"
                        assert json.loads(config.read_text())["pins"] == ["fixture-one"]
                        checks.append("closed pins and order restored after process restart; unpin removes closed icon")
                    else:
                        assert initial["apps"] == [] and not config.exists()
                        s = seed(WINDOWS)
                        assert len(s["apps"]) == 2 and all(a["running"] for a in s["apps"])
                        assert all(o["view"]["order"] == ["menu", "fixture-one", "fixture-two"] for o in s["outputs"])
                        for app in ENTRIES:
                            assert ipc("pin", app["id"], "true") == "true"
                        saved = json.loads(config.read_text())
                        assert saved["version"] == 2 and saved["pins"] == ["fixture-one", "fixture-two"]
                        assert saved["launchers"] == [] and saved["overrides"] == {}
                        assert ipc("reorderApps", ' ["fixture-two", "fixture-one"]') == "true"
                        assert json.loads(config.read_text())["pins"] == ["fixture-two", "fixture-one"]
                        assert ipc("reorderApps", ' ["fixture-two", "fixture-two"]') == "false"
                        s = snapshot()
                        assert all(o["view"]["order"] == ["menu", "fixture-two", "fixture-one"] for o in s["outputs"])
                        checks.append("shared running model; atomic pin/reorder read-back; invalid reorder rejected")
                        if args.visible:
                            names = s["activeOutputs"]
                            assert ipc("context", names[0], "fixture-one") == "false", "hidden menu cannot acquire focus"
                            ipc("autohide", "false")
                            ipc("show")
                            for output in names:
                                assert ipc("context", output, "fixture-one") == "true"
                                s = wait_state(lambda state: any(o["name"] == output and o["popupGrabActive"] for o in state["outputs"]))
                                owners = [o for o in s["outputs"] if o["keyboardFocus"] == "exclusive"]
                                assert len(owners) == 1 and owners[0]["name"] == output
                                assert owners[0]["view"]["contextIndex"] >= 1
                            ipc("activate", "fixture-one")
                            s = wait_state(lambda state: all(not o["popupGrabActive"] and o["keyboardFocus"] == "none" for o in state["outputs"]))
                            assert all(o["view"]["contextIndex"] == -1 for o in s["outputs"])
                            checks.append("native context grabs; single-output focus owner; activation releases all menus")
                    ipc("quit")
                    assert proc.wait(timeout=5) == 0
                    log.flush(); log.seek(0)
                    output = log.read()
                    for marker in ("ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration", "Cannot assign", "Error:"):
                        assert marker not in output, output
                finally:
                    if proc.poll() is None:
                        proc.terminate()
                        try:
                            proc.wait(timeout=5)
                        except subprocess.TimeoutExpired:
                            proc.kill(); proc.wait(timeout=5)
                    assert not owned_layers(proc.pid), "Owned surfaces survived teardown"
    print(json.dumps({"passed": True, "checks": checks, "not_tested": ["real application launch/focus (separate contract)", "physical input/hotplug"]}, indent=2))


if __name__ == "__main__":
    main()
