"""Exercise only this project's isolated Quickshell configuration."""
import json
import os
from pathlib import Path
import subprocess
import spawn_safety as safety
import time

ROOT = Path(__file__).resolve().parents[1]


def run():
    evidence = ROOT / "evidence"
    evidence.mkdir(exist_ok=True)
    # Historical foundation.json is never a current-attempt result.
    (evidence / "smoke.json").write_text(json.dumps({"passed": False, "status": "attempt not completed (including cleanup)"}) + "\n")
    if not __debug__:
        raise RuntimeError("Python optimized execution is unsupported; run without -O/PYTHONOPTIMIZE")
    if not os.environ.get("WAYLAND_DISPLAY"):
        raise RuntimeError("A live Wayland session is required")
    safety.manual_native('smoke')
    config = ROOT / "shell.qml"
    assert config.is_file(), "Missing isolated prototype entry point"
    safety.manual_process('run', 'smoke', ["omarchy", "plugin", "validate", str(ROOT)], check=True, timeout=20)
    env = dict(os.environ, QT_QPA_PLATFORM="wayland", OMADOCKED_VISIBLE="0", OMADOCKED_TEST_MODE="1", OMADOCKED_CONFIG_PATH="", QS_NO_RELOAD_POPUP="1")
    for key in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST"):
        env.pop(key, None)
    with (evidence / "smoke-runtime.log").open("w+") as log:
        proc = safety.manual_process('Popen', 'smoke', ["quickshell", "-p", str(config), "--no-color"], env=env, stdout=log, stderr=subprocess.STDOUT)
        try:
            deadline = time.monotonic() + 15
            while True:
                assert proc.poll() is None, "Prototype exited: " + (evidence / "smoke-runtime.log").read_text()
                result = safety.manual_process('run', 'smoke', ["quickshell", "ipc", "--pid", str(proc.pid), "call", "--", "omadocked-prototype", "snapshot"], env=env, text=True, capture_output=True, timeout=3)
                if result.returncode == 0 and result.stdout.strip().startswith("{"):
                    state = json.loads(result.stdout)
                    break
                assert time.monotonic() < deadline, result.stdout + result.stderr
                time.sleep(.1)
            assert state["screenCount"] > 0, state
            assert state["visible"] is False, state
            assert state["nonlaunching"] is True, state
            assert state["phase"] == 3 and state["testMode"] is True, state
            time.sleep(.3)
            log.flush()
            log.seek(0)
            output = log.read()
            for error in ("ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration", "Error:"):
                assert error not in output, output
            report = {"passed": True, "state": state, "checks": ["manifest", "real Wayland QML load", "exact-PID IPC", "hidden/nonlaunching snapshot contract", "runtime error scan"], "not_tested": ["owned-layer absence at compositor", "child-process launch tracing", "visible input", "frame presentation", "hotplug", "John's feel approval"]}
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)
    # Publish only after process teardown and log-file close both succeeded.
    (evidence / "smoke.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    run()
