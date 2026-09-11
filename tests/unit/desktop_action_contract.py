"""Opt-in real desktop-action receipts and native chooser; no user applications."""
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
    parser.add_argument("--execute-fixtures", action="store_true")
    parser.add_argument("--visible", action="store_true")
    args = parser.parse_args()
    if not __debug__:
        raise RuntimeError("Optimized execution is unsupported; remove -O/PYTHONOPTIMIZE")
    if not args.execute_fixtures:
        parser.error("Requires --execute-fixtures before native execution")
    if not os.environ.get("WAYLAND_DISPLAY"):
        parser.error("A real Wayland session is required")
    safety.manual_native('desktop_action_contract')
    safety.manual_native('hidden-backend')
    sys.path.insert(0, str(ROOT / "tests"))
    from test_daily_adapter import DailyAdapterTests
    probe = DailyAdapterTests()
    probe.setUp()
    checks = []

    def snapshot():
        state = probe.call("snapshot")
        assert isinstance(state, dict)
        return state

    def eventually(check, message, timeout=6):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if check():
                return
            time.sleep(.04)
        owners = [{"name": o["name"], "open": o["view"]["desktopActionsOpen"],
                   "grab": o["popupGrabActive"], "keyboard": o["keyboardFocus"]}
                  for o in snapshot()["outputs"]]
        raise AssertionError(message + ": " + json.dumps(owners))

    def pending():
        return next(a for a in snapshot()["apps"] if a["id"] == "owned-action-fixture")["pending"]

    def released():
        return all(not o["view"]["desktopActionsOpen"] and not o["popupGrabActive"]
                   and o["keyboardFocus"] == "none" for o in snapshot()["outputs"])

    try:
        data = probe.directory / "data"
        (data / "applications").mkdir(parents=True)
        receipt = probe.directory / "receipt.json"
        # Literal known fixture paths/arguments, not user Exec parsing.
        script = ROOT / "tests/fixtures/desktop_action_receipt.py"
        argv = f'/usr/bin/python3 "{script}" "{receipt}" "{probe.config}.lock"'
        desktop = data / "applications/owned-action-fixture.desktop"
        base = ("[Desktop Entry]\nType=Application\nName=Owned action fixture\n"
                "Icon=application-x-executable\nTerminal=false\nDBusActivatable=false\n"
                f"Path={probe.directory}\nExec={argv} MAIN-MUST-NOT-RUN\n")
        actions = ('Actions=menu;second;\n'
                   f'[Desktop Action menu]\nName=First action\nExec={argv} first "two words" "; & literal"\n'
                   f'[Desktop Action second]\nName=Second action\nExec={argv} second\n')
        desktop.write_text(base + actions)
        probe.config.write_text(json.dumps({"version": 1, "pins": ["owned-action-fixture"]}))
        original = probe.config.read_bytes()
        probe.start(test_mode="0", extra_env={"XDG_DATA_HOME": str(data), "XDG_DATA_DIRS": str(data)})
        rows = probe.call("desktopActions", "owned-action-fixture")
        assert rows == [{"id": "menu", "name": "First action"}, {"id": "second", "name": "Second action"}]
        assert not receipt.exists(), "Startup/action enumeration must not execute"
        assert probe.call("desktopAction", "owned-action-fixture", "second ") is False
        assert probe.call("desktopAction", "missing", "menu") is False
        assert not receipt.exists()
        checks.append("real DesktopEntries metadata and exact advertised IDs, no startup execution")
        if args.visible:
            probe.call("show")
            for name in snapshot()["activeOutputs"]:
                assert probe.call("actionChooser", name, "owned-action-fixture") is True

                def ready():
                    owners = [o for o in snapshot()["outputs"] if o["view"]["desktopActionsOpen"]]
                    return (len(owners) == 1 and owners[0]["name"] == name
                            and owners[0]["popupGrabActive"] and owners[0]["keyboardFocus"] == "exclusive")

                eventually(ready, "Exactly one native action chooser/focus owner")
                assert not receipt.exists(), "Opening action menus must not execute"
            checks.append("native cross-output chooser ownership; opening is non-executing")
        assert probe.call("desktopAction", "owned-action-fixture", "menu") is True
        eventually(receipt.exists, "Gio action dispatch creates owned receipt")
        assert json.loads(receipt.read_text()) == {
            "cwd": str(probe.directory), "args": ["first", "two words", "; & literal"],
            "writer_metadata": False, "writer_lock": False}
        eventually(lambda: not pending() and not snapshot()["appError"], "Non-window action completes without waiting for a window")
        eventually(released, "Action dispatch releases native popup ownership")
        receipt.unlink()
        assert probe.call("desktopAction", "owned-action-fixture", "second") is True
        eventually(receipt.exists, "Second action creates a distinct owned receipt")
        assert json.loads(receipt.read_text())["args"] == ["second"]
        eventually(lambda: not pending() and not snapshot()["appError"], "Second action pending clears")
        checks.append("Gio selects requested action not main Exec; literal arguments/cwd; no-window pending completion; no writer lease inheritance")
        # The live menu may be cached. The fresh launch helper must reread membership.
        receipt.unlink()
        desktop.write_text(base + 'Actions=menu;\n' + f'[Desktop Action menu]\nName=First action\nExec={argv} first\n')
        accepted = probe.call("desktopAction", "owned-action-fixture", "second")
        assert isinstance(accepted, bool)
        eventually(lambda: bool(snapshot()["appError"]) and not pending(), "Removed action is rejected visibly by service or fresh helper")
        assert not receipt.exists(), "Removed action must not fall back to main Exec"
        assert probe.config.read_bytes() == original, "Actions/menu viewing must not rewrite config"
        checks.append("removed action rejected without main-Exec fallback; configuration byte-preserved")
        print(json.dumps({"passed": True, "visible": args.visible, "checks": checks,
                          "not_tested": ["user application actions", "D-Bus-only actions", "physical input", "desktop capture",
                                         "application readiness after void Gio request"]}, indent=2))
    finally:
        probe.tearDown()


if __name__ == "__main__":
    run()
