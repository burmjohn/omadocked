"""Opt-in visible integration of owned layer surfaces; never changes the host.

Run only in the local graphical session. This tests native surface/IPC geometry,
not physical pointer input, compositor frame pacing or actual display hotplug.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import spawn_safety as safety
import time

ROOT = Path(__file__).resolve().parents[1]
NAMESPACE = "omadocked-prototype"


def run_json(argv):
    return json.loads(safety.manual_process('run', 'live', argv, text=True, capture_output=True, check=True, timeout=5).stdout)


def layers(pid):
    result = []
    for output, info in run_json(["hyprctl", "-j", "layers"]).items():
        for rows in info.get("levels", {}).values():
            for row in rows:
                if row.get("pid") == pid and row.get("namespace") == NAMESPACE:
                    result.append(dict(row, output=output))
    return result


def unchanged_digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest() if path.exists() else None


def main():
    evidence = ROOT / "evidence"
    evidence.mkdir(exist_ok=True)
    # Fail closed for this attempt, including guard/argument/cleanup failures.
    (evidence / "native.json").write_text(json.dumps({"passed": False, "status": "attempt not completed (including cleanup)"}) + "\n")
    if not __debug__:
        raise RuntimeError("Python optimized execution is unsupported; run without -O/PYTHONOPTIMIZE")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--visible", action="store_true", help="Required consent to briefly display only this prototype on outputs")
    parser.add_argument("--capture-composited-region", "--capture", action="store_true", help="Opt in to cropped composited desktop region screenshots; may include private background and overlapping windows, NOT isolated surface pixels")
    args = parser.parse_args()
    if not args.visible:
        raise RuntimeError("Pass --visible only when a temporary native prototype test is appropriate")
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise RuntimeError("Requires live Wayland")
    safety.manual_native('live')
    host = Path.home() / ".config/omarchy/shell.json"
    host_hash = unchanged_digest(host)
    monitors = run_json(["hyprctl", "-j", "monitors"])
    assert monitors, "No outputs"
    for monitor in monitors:
        if monitor.get("transform") != 0:
            raise RuntimeError(f"Monitor transform {monitor.get('transform')!r} unsupported: only unrotated, unflipped outputs are tested")
    output_names = [row["name"] for row in monitors]
    reports = []
    for requested in output_names + ["OMADOCKED-ABSENT-PROBE"]:
        env = dict(os.environ, QT_QPA_PLATFORM="wayland", OMADOCKED_VISIBLE="0", OMADOCKED_TEST_MODE="1", OMADOCKED_CONFIG_PATH="", OMADOCKED_SCREEN=requested, OMADOCKED_OFFSET="96", QS_NO_RELOAD_POPUP="1")
        for key in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST"):
            env.pop(key, None)
        with (evidence / ("native-" + requested + ".log")).open("w+") as log:
            proc = safety.manual_process('Popen', 'live', ["quickshell", "-p", str(ROOT / "shell.qml"), "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
            def ipc(method, *values):
                r = safety.manual_process('run', 'live', ["quickshell", "ipc", "--pid", str(proc.pid), "call", "--", NAMESPACE, method, *values], env=env, text=True, capture_output=True, timeout=4)
                assert r.returncode == 0, r.stdout + r.stderr
                return r.stdout.strip()
            try:
                deadline = time.monotonic() + 15
                while True:
                    assert proc.poll() is None, "Prototype exited: " + (evidence / ("native-" + requested + ".log")).read_text()
                    try:
                        state = json.loads(ipc("snapshot"))
                        break
                    except (AssertionError, json.JSONDecodeError):
                        assert time.monotonic() < deadline, "IPC readiness timeout"
                        time.sleep(.1)
                assert state["phase"] == 3 and state["testMode"] is True, state
                assert state["nonlaunching"] and not state["visible"], state
                assert not layers(proc.pid), "Hidden prototype has mapped layer"
                ipc("mode", "off")
                ipc("reducedMotion", "true")
                ipc("autohide", "false")
                ipc("show")
                deadline = time.monotonic() + 15
                while True:
                    state = json.loads(ipc("snapshot"))
                    owned = layers(proc.pid)
                    if state["visible"] and owned:
                        break
                    assert time.monotonic() < deadline, (state, owned)
                    time.sleep(.05)
                expected = requested if requested in output_names else state["output"]
                assert state["output"] == expected and expected in output_names, state
                assert state["fallback"] == (requested not in output_names), state
                assert state["mode"] == "off" and state["reducedMotion"] is True and state["autoHide"] is False, state
                assert state["offset"] == 96, state
                assert len(owned) == 1 and owned[0]["output"] == expected, owned
                layer = owned[0]
                monitor = next(m for m in monitors if m["name"] == expected)
                logical_width = monitor["width"] / monitor["scale"]
                logical_height = monitor["height"] / monitor["scale"]
                assert 0 < layer["w"] < logical_width, layer
                assert 0 < layer["h"] < logical_height, layer
                assert layer["x"] >= monitor["x"] and layer["x"] + layer["w"] <= monitor["x"] + logical_width + 1, layer
                assert layer["y"] >= monitor["y"] and layer["y"] + layer["h"] <= monitor["y"] + logical_height - 95, layer
                report = {"requested": requested, "state": state, "layer": layer, "refresh_hz": monitor["refreshRate"], "scale": monitor["scale"]}
                if args.capture_composited_region and requested in output_names:
                    # grim crops the composited desktop: background/overlap may be private.
                    # This is not isolated surface capture, even within owned geometry.
                    time.sleep(.15)
                    image = evidence / ("native-" + requested + ".png")
                    geometry = f'{layer["x"]},{layer["y"]} {layer["w"]}x{layer["h"]}'
                    safety.manual_process('run', 'live', ["grim", "-g", geometry, str(image)], check=True, timeout=5)
                    assert image.stat().st_size > 0
                    report["screenshot"] = str(image)
                    report["screenshot_scope"] = "cropped composited desktop region; may include background and overlapping windows, not isolated surface pixels"
                ipc("mode", "wave")
                assert json.loads(ipc("snapshot"))["mode"] == "wave"
                ipc("mode", "zoom")
                assert json.loads(ipc("snapshot"))["mode"] == "zoom"
                ipc("hide")
                deadline = time.monotonic() + 5
                while layers(proc.pid):
                    assert time.monotonic() < deadline, "Layer did not unmap"
                    time.sleep(.05)
                assert not json.loads(ipc("snapshot"))["visible"]
                log.flush()
                log.seek(0)
                output = log.read()
                for marker in ("ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration", "Error:"):
                    assert marker not in output, output
                reports.append(report)
            finally:
                if proc.poll() is None:
                    proc.terminate()
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                        proc.wait(timeout=5)
                assert not layers(proc.pid), "Owned surface survived process exit"
    assert unchanged_digest(host) == host_hash, "Host settings changed during test"
    result = {"passed": True, "checks": reports, "host_config_unchanged": True, "not_tested": ["physical pointer/keyboard delivery", "actual hotplug", "mixed DPI", "bottom-edge coexistence", "presentation frame timings", "John's feel approval"]}
    (evidence / "native.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
