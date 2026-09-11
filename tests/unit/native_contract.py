"""Hidden native adapter contract: owns one process; never maps a surface."""
import json
import os
from pathlib import Path
import sys
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
import spawn_safety as safety

def run():
    if not __debug__:
        raise RuntimeError("Python optimized execution is unsupported; run without -O/PYTHONOPTIMIZE")
    safety.manual_native('native_contract')
    env = dict(os.environ, QT_QPA_PLATFORM="wayland", OMADOCKED_VISIBLE="0", OMADOCKED_TEST_MODE="1", OMADOCKED_CONFIG_PATH="",
               OMADOCKED_SCREEN="__omadocked_missing_output__", QS_NO_RELOAD_POPUP="1")
    for key in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST"):
        env.pop(key, None)
    with (ROOT / "evidence/native-contract-runtime.log").open("w+") as log:
        proc = safety.manual_process('Popen', 'native_contract', ["quickshell", "-p", str(ROOT / "shell.qml"), "--no-color"],
                                env=env, stdout=log, stderr=subprocess.STDOUT)
        def ipc(method, *args):
            return safety.manual_process('run', 'native_contract', ["quickshell", "ipc", "--pid", str(proc.pid), "call", "--",
                                   "omadocked-prototype", method, *args], env=env,
                                  text=True, capture_output=True, timeout=3)
        try:
            deadline = time.monotonic() + 12
            while True:
                assert proc.poll() is None, "QML startup failed"
                result = ipc("snapshot")
                if result.returncode == 0 and result.stdout.strip().startswith("{"):
                    state = json.loads(result.stdout)
                    break
                assert time.monotonic() < deadline, result.stderr
                time.sleep(.1)
            assert state["phase"] == 3, state
            assert state["nonlaunching"] and not state["visible"], state
            assert state["testMode"] is True and state["apps"] == [], state
            assert all(row["view"]["order"] == ["menu"] for row in state["outputs"]), "No app fixtures in the native dock"
            assert state["screenCount"] > 0 and state["output"], state
            assert state["fallback"] and state["fallbackReason"] == "requested-output-unavailable", state
            assert state["offset"] == 0 and state["width"] < 700, state
            assert state["keyboardFocus"] == "none", state
            assert state["view"]["state"] == "hidden", state
            assert list(state["icons"]) == ["menu"] and state["icons"]["menu"], state
            assert state.get("iconSize") == 44, "Shared icon size should default to 44px"
            for size in (28, 72, 44):
                assert ipc("iconSize", str(size)).stdout.strip() == "true"
                resized = json.loads(ipc("snapshot").stdout)
                assert resized["iconSize"] == size
                assert all(row["view"].get("iconSize") == size for row in resized["outputs"]), "All views follow shared size"
            for size in (27, 73, 44.5):
                assert ipc("iconSize", str(size)).stdout.strip() == "false"
                assert json.loads(ipc("snapshot").stdout)["iconSize"] == 44
            assert state.get("transparency") == 0, "Background should default to opaque"
            for value in (0, 50, 100):
                assert ipc("transparency", str(value)).stdout.strip() == "true"
                faded = json.loads(ipc("snapshot").stdout)
                assert faded["transparency"] == value
                assert all(row["view"].get("transparency") == value for row in faded["outputs"]), "All views follow shared background transparency"
            for value in (-1, 101, 25.5):
                assert ipc("transparency", str(value)).stdout.strip() == "false"
                assert json.loads(ipc("snapshot").stdout)["transparency"] == 100
            for method, value in [("mode", "off"), ("reducedMotion", "true"), ("autohide", "false")]:
                changed = ipc(method, value)
                assert changed.returncode == 0, changed.stderr
            assert ipc("hide").returncode == 0
            updated = json.loads(ipc("snapshot").stdout)
            assert updated["mode"] == "off" and updated["reducedMotion"] and not updated["autoHide"], updated
            assert not updated["visible"] and updated["keyboardFocus"] == "none", updated
            assert ipc("mode", "invalid").stdout.strip() == "false"
            assert json.loads(ipc("snapshot").stdout)["mode"] == "off"
            assert ipc("quit").returncode == 0
            proc.wait(timeout=5)
            log.flush()
            log.seek(0)
            output = log.read()
            for error in ("ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration", "Error:"):
                assert error not in output, output
            print(json.dumps({"passed": True, "initial": state, "updated": updated}, indent=2))
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)

if __name__ == "__main__":
    run()
