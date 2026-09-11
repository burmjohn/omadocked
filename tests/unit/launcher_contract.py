"""Opt-in real execution of owned receipt/failure fixtures, never user launchers."""
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
    args = parser.parse_args()
    if not __debug__:
        raise RuntimeError("Optimized execution is unsupported; run without -O/PYTHONOPTIMIZE")
    if not args.execute_fixtures:
        parser.error("Real command execution requires explicit --execute-fixtures consent")
    if not os.environ.get("WAYLAND_DISPLAY"):
        parser.error("A real Wayland session is required")
    safety.manual_native('launcher_contract')
    safety.manual_native('hidden-backend')
    sys.path.insert(0, str(ROOT / "tests"))
    from test_daily_adapter import DailyAdapterTests
    probe = DailyAdapterTests()
    probe.setUp()
    def snapshot():
        state = probe.call("snapshot")
        assert isinstance(state, dict)
        return state
    def eventually(check, label):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            if check():
                return
            time.sleep(.03)
        raise AssertionError(label)
    try:
        data = probe.directory / "data"
        (data / "applications").mkdir(parents=True)
        probe.start(test_mode="0", extra_env={"XDG_DATA_HOME": str(data), "XDG_DATA_DIRS": str(data)})
        receipt = probe.directory / "receipt.json"
        sentinel = probe.directory / "must-not-execute"
        literal = ["space inside", "$(touch " + str(sentinel) + ")", "; & | > literal", ""]
        record = {"kind": "command", "name": "Owned command fixture", "program": sys.executable,
                  "args": [str(ROOT / "tests/fixtures/launcher_receipt.py"), str(receipt), *literal],
                  "workingDirectory": str(probe.directory), "terminal": False, "enabled": True}
        assert probe.call("saveLauncher", json.dumps(record)) is True
        assert not receipt.exists() and not sentinel.exists(), "Save must never execute"
        ident = snapshot()["launcherRecords"][0]["id"]
        assert probe.call("duplicateLauncher", ident) is True
        assert not receipt.exists(), "Duplicate must never execute"
        duplicate = next(r["id"] for r in snapshot()["launcherRecords"] if r["id"] != ident)
        assert probe.call("removeLauncher", duplicate) is True
        assert probe.call("activate", ident) is True
        eventually(receipt.exists, "Owned command creates receipt")
        assert json.loads(receipt.read_text()) == {"cwd": str(probe.directory), "args": literal}
        assert not sentinel.exists(), "No shell interpretation"
        eventually(lambda: not next(a for a in snapshot()["apps"] if a["id"] == ident)["pending"], "Completed command leaves pending state")
        bad = {"kind": "command", "name": "Owned missing fixture", "program": str(probe.directory / "nonexistent-executable"),
               "args": [], "enabled": True}
        assert probe.call("saveLauncher", json.dumps(bad)) is True
        bad_id = next(r["id"] for r in snapshot()["launcherRecords"] if r["id"] != ident)
        assert probe.call("activate", bad_id) is True
        eventually(lambda: bool(snapshot()["appError"]), "Missing executable produces visible error")
        assert probe.call("saveLauncher", json.dumps({"kind": "link", "name": "Unsafe URI", "target": "javascript:alert(1)", "enabled": True})) is False
        print(json.dumps({"passed": True, "checks": ["save/duplicate never execute", "exact argv and working directory through real helper",
                          "shell metacharacters remain literal", "pending clears after completion", "missing executable error visible",
                          "unsafe URI rejected before execution"], "not_tested": ["user launchers", "terminal UI", "opening real URLs/files", "Omarchy menus"]}, indent=2))
    finally:
        probe.tearDown()


if __name__ == "__main__":
    run()
