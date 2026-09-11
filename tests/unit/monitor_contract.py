"""Real Wayland monitor policy; --visible opts into bottom-edge layer checks.

Only this test's PID is controlled. Never captures the desktop or changes monitors,
windows, plugin selection, or the installed shell. Physical input/hotplug untested.
"""
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
TARGET = "omadocked-prototype"


def json_ipc_argument(value):
    # Quickshell's CLI expands bracket-wrapped arrays into multiple argv values.
    # Legal JSON whitespace prevents that expansion without changing the data.
    return " " + value


def command(argv, env=None):
    return safety.manual_process('run', 'monitor_contract', argv, env=env, check=True, capture_output=True, text=True, timeout=5).stdout.strip()


def owned_layers(pid):
    data = json.loads(command(["hyprctl", "-j", "layers"]))
    return [dict(layer, output=output) for output, info in data.items()
            for rows in info.get("levels", {}).values() for layer in rows
            if layer.get("pid") == pid and layer.get("namespace") == TARGET]


def main():
    if not __debug__:
        raise RuntimeError("Optimized execution is unsupported; run without -O/PYTHONOPTIMIZE")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--visible", action="store_true", help="Temporarily show owned prototype layers at the bottom of connected monitors")
    args = parser.parse_args()
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise RuntimeError("Requires the live Wayland session")
    safety.manual_native('monitor_contract')
    evidence = ROOT / "evidence"
    evidence.mkdir(exist_ok=True)
    stem = "monitor-contract-visible" if args.visible else "monitor-contract-hidden"
    target = evidence / (stem + ".json")
    target.write_text(json.dumps({"passed": False, "status": "attempt incomplete, including cleanup"}) + "\n")
    monitors = json.loads(command(["hyprctl", "-j", "monitors"]))
    assert monitors, "No connected monitors"
    if args.visible and any(m.get("transform") != 0 for m in monitors):
        raise RuntimeError("Visible geometry test supports only unrotated/unflipped monitors")
    names = [m["name"] for m in monitors]
    env = dict(os.environ, QT_QPA_PLATFORM="wayland", OMADOCKED_VISIBLE="0", OMADOCKED_TEST_MODE="1", OMADOCKED_CONFIG_PATH="", QS_NO_RELOAD_POPUP="1")
    for key in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST", "OMADOCKED_SCREEN", "OMADOCKED_SCREENS", "OMADOCKED_OFFSET"):
        env.pop(key, None)
    checks = []
    with (evidence / (stem + ".log")).open("w+") as log:
        proc = safety.manual_process('Popen', 'monitor_contract', ["quickshell", "-p", str(ROOT / "shell.qml"), "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
        def ipc(method, *args):
            if method == "monitors":
                args = (args[0], json_ipc_argument(args[1]))
            return command(["quickshell", "ipc", "--pid", str(proc.pid), "call", "--", TARGET, method, *args], env)
        def snapshot():
            return json.loads(ipc("snapshot"))
        def choose(mode, selected):
            result = ipc("monitors", mode, json.dumps(selected))
            assert result == "true", result
        def layers_match(expected):
            deadline = time.monotonic() + 8
            while True:
                rows = owned_layers(proc.pid)
                if sorted(r["output"] for r in rows) == sorted(expected):
                    return rows
                assert proc.poll() is None, "Prototype exited"
                assert time.monotonic() < deadline, (expected, rows, snapshot())
                time.sleep(.05)
        try:
            deadline = time.monotonic() + 15
            while True:
                assert proc.poll() is None, "QML startup failed"
                try:
                    initial = snapshot()
                    break
                except (subprocess.CalledProcessError, json.JSONDecodeError):
                    assert time.monotonic() < deadline, "IPC readiness timeout"
                    time.sleep(.1)
            assert initial["phase"] == 3 and initial["testMode"] is True and initial["nonlaunching"] is True
            assert initial["offset"] == 0, "Dock should default to the bottom edge"
            assert initial["monitorMode"] == "all", initial
            assert set(initial["activeOutputs"]) == set(names), initial
            assert initial["visible"] is False and not owned_layers(proc.pid), initial
            assert set(row["name"] for row in initial["outputs"]) == set(names), initial
            assert all(not row["visible"] and row["keyboardFocus"] == "none" for row in initial["outputs"]), initial
            checks.append({"check": "default-all-bottom-hidden", "activeOutputs": initial["activeOutputs"]})
            for mode, payload in [("invalid", "[]"), ("selected", "[]"), ("selected", "not json"), ("selected", "[1]"), ("selected", '[""]')]:
                before = snapshot()
                result = ipc("monitors", mode, payload)
                assert result == "false", (mode, payload, result)
                after = snapshot()
                for field in ("monitorMode", "selectedOutputs", "activeOutputs"):
                    assert after[field] == before[field], (field, before, after)
            subset = list(dict.fromkeys([names[0], names[-1]]))
            choose("selected", subset + subset)
            state = snapshot()
            assert state["selectedOutputs"] == subset, state
            assert set(state["activeOutputs"]) == set(subset), state
            missing = "OMADOCKED-NOT-A-CONNECTED-OUTPUT"
            assert missing not in names
            choose("selected", [missing])
            state = snapshot()
            assert state["selectedOutputs"] == [missing] and state["activeOutputs"] == [], state
            assert not state["visible"] and not owned_layers(proc.pid), state
            choose("all", [])
            assert set(snapshot()["activeOutputs"]) == set(names)
            assert not owned_layers(proc.pid), "Hidden controls unexpectedly mapped a surface"
            checks.append({"check": "validated-subset-dedupe-missing-output-no-fallback-recovery"})
            if args.visible:
                ipc("autohide", "false")
                ipc("reducedMotion", "true")
                ipc("mode", "off")
                response = ipc("show")
                assert not response, response
                rows = layers_match(names)
                for layer in rows:
                    monitor = next(m for m in monitors if m["name"] == layer["output"])
                    width = monitor["width"] / monitor["scale"]
                    height = monitor["height"] / monitor["scale"]
                    assert 0 < layer["w"] < width and 0 < layer["h"] < height, layer
                    assert abs(layer["y"] + layer["h"] - (monitor["y"] + height)) <= 1, (layer, monitor)
                    assert abs(layer["x"] + layer["w"] / 2 - (monitor["x"] + width / 2)) <= 1, (layer, monitor)
                checks.append({"check": "one-bottom-centered-layer-per-monitor", "layers": rows})
                for expected in (subset, [names[0]], [missing], subset):
                    choose("selected", expected)
                    present = [name for name in expected if name in names]
                    rows = layers_match(present)
                    state = snapshot()
                    assert set(state["activeOutputs"]) == set(present), state
                    assert all(row["keyboardFocus"] == "none" for row in state["outputs"]), state
                    checks.append({"check": "live-selected-policy", "requested": expected, "layers": rows})
                choose("all", [])
                layers_match(names)
                ipc("hide")
                layers_match([])
                assert snapshot()["visible"] is False
                checks.append({"check": "restore-all-hide-all-no-duplicate-layers"})
            ipc("quit")
            assert proc.wait(timeout=5) == 0
            log.flush()
            log.seek(0)
            output = log.read()
            for marker in ("ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration", "Cannot assign", "Error:"):
                assert marker not in output, output
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)
            assert not owned_layers(proc.pid), "Owned layers survived cleanup"
    report = {"passed": True, "visible_test": args.visible, "checks": checks,
              "not_tested": ["physical input", "actual monitor unplug/replug", "mixed DPI", "frame pacing", "coexistence with old dock triggers"]}
    target.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
