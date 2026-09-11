"""Opt-in native chooser geometry/focus check: synthetic windows, no capture/input."""
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
        parser.error("Native chooser checks require explicit --visible consent")
    if not os.environ.get("WAYLAND_DISPLAY"):
        parser.error("A real Wayland session is required")
    safety.manual_native('window_contract')
    safety.manual_native('monitor_contract')
    safety.manual_native('hidden-backend')
    sys.path.insert(0, str(ROOT / "tests"))
    from test_daily_adapter import DailyAdapterTests
    from monitor_contract import owned_layers
    probe = DailyAdapterTests()
    probe.setUp()

    def snapshot():
        state = probe.call("snapshot")
        assert isinstance(state, dict), "Expected root adapter snapshot"
        assert "PRIVATE_FIXTURE_TITLE" not in json.dumps(state), "Private chooser data leaked into diagnostics"
        return state

    def eventually(check, label):
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            if check():
                return
            time.sleep(.03)
        raise AssertionError(label)

    def released():
        return all(not o["view"]["windowChooserOpen"] and o["keyboardFocus"] == "none"
                   and not o["popupGrabActive"] for o in snapshot()["outputs"])

    try:
        state = probe.start()
        assert state is not None and probe.proc is not None
        names = state["activeOutputs"]
        assert names, "Need an active output"
        fixture = {"entries": [{"id": "fixture-chooser", "name": "Fixture Chooser", "launchable": True}],
                   "windows": [{"key": str(i), "appId": "fixture-chooser", "active": i == 0,
                                "title": "PRIVATE_FIXTURE_TITLE_" + str(i)} for i in range(40)]}
        assert probe.call("fixtureApps", json.dumps(fixture))
        keys = probe.call("windows", "fixture-chooser")
        assert isinstance(keys, list) and len(keys) == 40
        assert probe.call("windowChooser", names[0], "fixture-chooser") is False
        probe.call("show")
        for name in names:
            assert probe.call("windowChooser", name, "fixture-chooser") is True

            def ready():
                owners = [o for o in snapshot()["outputs"] if o["view"]["windowChooserOpen"]]
                return (len(owners) == 1 and owners[0]["name"] == name
                        and owners[0]["popupGrabActive"] and owners[0]["keyboardFocus"] == "exclusive")

            eventually(ready, "Exactly one mapped chooser/focus owner")
            surface = next(o for o in snapshot()["outputs"] if o["name"] == name)
            assert surface["height"] <= 642, "Large window groups must not grow native surfaces"
            assert any(row["output"] == name and row["w"] == round(surface["width"])
                       and row["h"] == round(surface["height"]) for row in owned_layers(probe.proc.pid)), "Native chooser geometry matches view"
        assert probe.call("closeWindow", "fixture-chooser", keys[0]["key"]) is True
        eventually(released, "Close releases chooser and keyboard before native save prompts")
        remaining = probe.call("windows", "fixture-chooser")
        assert isinstance(remaining, list) and len(remaining) == 39
        assert probe.call("windowChooser", names[0], "fixture-chooser") is True
        fixture["windows"] = []
        assert probe.call("fixtureApps", json.dumps(fixture))
        eventually(released, "Disappearing app tears down private chooser and focus")
        probe.call("hide")
        assert not probe.config.exists(), "Chooser interactions never write configuration"
        print(json.dumps({"passed": True, "outputs_tested": len(names), "fixture_windows": 40,
                          "checks": ["hidden chooser rejected", "bounded native geometry", "single cross-output focus owner",
                                     "title-free diagnostics", "close releases popup focus", "empty group tears down chooser"],
                          "not_tested": ["physical input", "desktop capture", "real application save dialog"]}, indent=2))
    finally:
        probe.tearDown()


if __name__ == "__main__":
    run()
