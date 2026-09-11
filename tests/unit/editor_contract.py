"""Opt-in native editor geometry/focus check; synthetic launchers, no capture/input."""
import argparse
import json
import os
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
import spawn_safety as safety


def run():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--visible", action="store_true")
    args = parser.parse_args()
    if not __debug__:
        raise RuntimeError("Python optimized execution is unsupported; run without -O/PYTHONOPTIMIZE")
    if not args.visible:
        parser.error("Native editor checks require explicit --visible consent")
    if not os.environ.get("WAYLAND_DISPLAY"):
        parser.error("A real Wayland session is required")
    safety.manual_native('editor_contract')
    safety.manual_native('monitor_contract')
    safety.manual_native('hidden-backend')
    sys.path.insert(0, str(ROOT / "tests"))
    from test_daily_adapter import DailyAdapterTests
    from monitor_contract import owned_layers
    probe = DailyAdapterTests()
    probe.setUp()
    def snapshot():
        state = probe.call("snapshot")
        if not isinstance(state, dict):
            raise AssertionError("Expected adapter snapshot")
        return state
    def eventually(check, label):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            if check():
                return
            time.sleep(.03)
        raise AssertionError(label)
    try:
        state = probe.start()
        assert state is not None and probe.proc is not None
        pid = probe.proc.pid
        names = state["activeOutputs"]
        assert names, "Need an active output"
        assert probe.call("editor", names[0], "") is False
        probe.call("show")
        for name in names:
            assert probe.call("editor", name, "") is True
            def ready():
                s = snapshot()
                editors = [o for o in s["outputs"] if o["view"]["editorOpen"]]
                return (len(editors) == 1 and editors[0]["name"] == name
                        and editors[0]["popupGrabActive"] and editors[0]["keyboardFocus"] == "exclusive")
            eventually(ready, "Exactly one mapped editor/focus owner")
            s = snapshot()
            surface = next(o for o in s["outputs"] if o["name"] == name)
            layers = owned_layers(pid)
            assert any(row["output"] == name and row["w"] == round(surface["width"])
                       and row["h"] == round(surface["height"]) for row in layers), "Native editor geometry matches view"
        assert probe.call("editor", names[0], "launcher:missing") is False
        probe.call("hide")
        eventually(lambda: all(not o["view"]["editorOpen"] and o["keyboardFocus"] == "none"
                               for o in snapshot()["outputs"]), "Hide cancels editors and native focus")
        assert not probe.config.exists(), "Opening/canceling editor never writes settings or executes a launcher"
        print(json.dumps({"passed": True, "outputs_tested": len(names),
                          "checks": ["hidden editor rejected", "same-popup native geometry", "single cross-output editor/focus owner",
                                     "stale record rejected", "hide cancels without saving"],
                          "not_tested": ["physical input", "desktop capture", "real user launcher execution"]}, indent=2))
    finally:
        probe.tearDown()


if __name__ == "__main__":
    run()
