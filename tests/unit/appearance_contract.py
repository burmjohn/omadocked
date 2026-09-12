"""Opt-in native compact dock/settings geometry; never captures the desktop."""
import argparse
import json
import os
from pathlib import Path
import sys
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
import spawn_safety as safety


def main():
    if not __debug__:
        raise RuntimeError("Optimized execution is unsupported")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--visible", action="store_true")
    args = parser.parse_args()
    if not args.visible:
        parser.error("--visible is required to show owned test surfaces")
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise RuntimeError("Requires the live Wayland session")
    safety.manual_native('appearance_contract')
    safety.manual_native('monitor_contract')
    from monitor_contract import command, owned_layers

    evidence = ROOT / "evidence"
    target = evidence / "appearance-contract.json"
    target.write_text(json.dumps({"passed": False, "status": "attempt incomplete, including cleanup"}) + "\n")
    monitors = json.loads(command(["hyprctl", "-j", "monitors"]))
    assert monitors and all(m.get("transform") == 0 for m in monitors), "Unrotated monitors required"
    names = [m["name"] for m in monitors]
    env = dict(os.environ, QT_QPA_PLATFORM="wayland", OMADOCKED_VISIBLE="0", OMADOCKED_TEST_MODE="1", OMADOCKED_CONFIG_PATH="", OMADOCKED_SCREENS="all", QS_NO_RELOAD_POPUP="1")
    for key in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST", "OMADOCKED_SCREEN", "OMADOCKED_OFFSET"):
        env.pop(key, None)
    checks = []
    with (evidence / "appearance-contract.log").open("w+") as log:
        proc = safety.manual_process('Popen', 'appearance_contract', ["quickshell", "-p", str(ROOT / "shell.qml"), "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
        def ipc(method, *values):
            return command(["quickshell", "ipc", "--pid", str(proc.pid), "call", "--", "omadocked-prototype", method, *values], env)
        def snapshot():
            return json.loads(ipc("snapshot"))
        def layout():
            deadline = time.monotonic() + 8
            while True:
                state = snapshot()
                layers = owned_layers(proc.pid)
                by_name = {o["name"]: o for o in state["outputs"]}
                if set(r["output"] for r in layers) == set(names) and all(
                    r["w"] == by_name[r["output"]]["width"] and r["h"] == by_name[r["output"]]["height"]
                    and r.get("alpha", 0) >= .99 for r in layers
                ):
                    for r in layers:
                        m = next(m for m in monitors if m["name"] == r["output"])
                        assert abs(r["y"] + r["h"] - m["y"] - m["height"] / m["scale"]) <= 1, (r, m)
                    return state, layers
                assert proc.poll() is None and time.monotonic() < deadline, (state, layers)
                time.sleep(.05)
        def popup_position(state, layers, name):
            view = next(o["view"] for o in state["outputs"] if o["name"] == name)
            r = next(r for r in layers if r["output"] == name)
            p = view["popupRect"]
            assert p["width"] > 0 and p["height"] > 0
            assert any(rect["x"] == p["x"] and rect["y"] == p["y"] and rect["width"] == p["width"] and rect["height"] == p["height"] for rect in view["inputRects"])
            return [r["x"] + p["x"], r["y"] + p["y"], p["width"], p["height"]]
        try:
            deadline = time.monotonic() + 15
            while True:
                assert proc.poll() is None, "QML startup failed"
                try:
                    state = snapshot()
                    break
                except (subprocess.CalledProcessError, json.JSONDecodeError):
                    assert time.monotonic() < deadline, "IPC readiness timeout"
                    time.sleep(.1)
            assert ipc("settings", names[0], "true") == "false", "Hidden settings must not map a surface or grab focus"
            assert not owned_layers(proc.pid)
            assert ipc("settings", "NOT-A-CONNECTED-OUTPUT", "true") == "false"
            assert state["height"] <= 110, "Closed dock should be a compact icon row"
            assert all(o["view"]["order"][0] == "omarchy-menu" for o in state["outputs"])
            ipc("autohide", "false")
            ipc("reducedMotion", "true")
            ipc("show")
            state, layers = layout()
            checks.append({"check": "compact-bottom-edge", "layers": layers})
            assert ipc("settings", names[0], "true") == "true"
            state, layers = layout()
            position = popup_position(state, layers, names[0])
            assert next(o for o in state["outputs"] if o["name"] == names[0]).get("popupGrabActive") is True, "Settings need compositor outside-click dismissal"
            sizes = []
            for size in (28, 72, 44):
                assert ipc("iconSize", str(size)) == "true"
                state, layers = layout()
                current = popup_position(state, layers, names[0])
                assert all(abs(a - b) <= 1 for a, b in zip(position, current)), (position, current)
                assert all(o["view"]["iconSize"] == size for o in state["outputs"])
                sizes.append({"size": size, "popup": current})
            checks.append({"check": "slider-resize-keeps-popup-stationary", "sizes": sizes})
            assert ipc("transparency", "100") == "true"
            state = snapshot()
            assert all(o["view"]["transparency"] == 100 for o in state["outputs"])
            for output in names:
                assert ipc("settings", output, "true") == "true"
                state, layers = layout()
                owners = [o for o in state["outputs"] if o["view"]["settingsOpen"]]
                assert len(owners) == 1 and owners[0]["name"] == output, owners
                assert owners[0]["popupGrabActive"] is True
                assert [o["name"] for o in state["outputs"] if o["keyboardFocus"] == "exclusive"] == [output]
            assert ipc("settings", names[-1], "false") == "true"
            state, layers = layout()
            assert all(o["height"] <= 110 and not o["view"]["settingsOpen"] and o["keyboardFocus"] == "none" for o in state["outputs"])
            checks.append({"check": "shared-transparency-single-popup-owner-close-releases-focus"})
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
            assert not owned_layers(proc.pid), "Owned layers survived cleanup"
    report = {"passed": True, "checks": checks, "not_tested": ["physical pointer input", "physical outside-click dismissal", "hotplug", "mixed DPI", "frame pacing"]}
    target.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
