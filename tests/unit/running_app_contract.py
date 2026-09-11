#!/usr/bin/env python3
"""Opt-in real Wayland app launch, window actions and durable pin contract.

Run: python3 tests/unit/running_app_contract.py --native-apps [--visible]
--native-apps consents to temporary owned application windows (including a focus
sentinel); --visible additionally permits temporary dock/popup keyboard capture.
No installed plugin, user pins, pointer, screenshots or arbitrary windows are
changed. DesktopEntries is isolated to ONE temporary desktop entry. Raw service
snapshots/compositor responses stay transient and are NEVER printed or saved.
Only safe check names are emitted; all launch/config/build artifacts are temporary.
Requires Linux pidfds, Hyprland, Quickshell and g++/pkg-config Qt6Widgets.
"""
import argparse
import json
import os
from pathlib import Path
import select
import shlex
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tests"))
import spawn_safety as safety
TARGET = "omadocked-prototype"
FIELDS = ("id", "name", "icon", "running", "active", "pinned", "canPin", "windowCount", "pending")


class ContractError(RuntimeError):
    """Messages must be constants, not raw external output."""


def require(ok, message):
    if not ok:
        raise ContractError(message)


def preflight(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native-apps", action="store_true", help="Consent to launch/focus/close only owned native fixture windows")
    parser.add_argument("--visible", action="store_true", help="Also exercise owned visible dock/popup keyboard release")
    parser.add_argument("--popup-focus", action="store_true", help="Test activation from a popup; does not prove pointer-away plain activation")
    args = parser.parse_args(argv)
    # These checks precede filesystem writes, builds and ALL subprocess calls.
    if not args.native_apps:
        parser.error("--native-apps is required before any native test activity")
    if args.popup_focus and not args.visible:
        parser.error("--popup-focus requires --visible")
    require(__debug__, "Optimized Python is unsupported; remove -O/PYTHONOPTIMIZE")
    require(bool(os.environ.get("WAYLAND_DISPLAY")), "Requires a live Wayland session")
    require(bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")), "Requires a live Hyprland session")
    require(hasattr(os, "pidfd_open") and hasattr(signal, "pidfd_send_signal"), "Requires Linux pidfd support")
    for name in ("quickshell", "hyprctl", "g++", "pkg-config"):
        require(shutil.which(name) is not None, "Missing required native test tool")
    # Fail once, not repeatedly wait for another worker to build the bridge.
    source = (ROOT / "shell.qml").read_text()
    require(all("function " + name + "(" in source for name in ("pin", "activate", "reorderApps")),
            "BLOCKED: public Phase 2 shell IPC bridge is not ready")
    require(all("function " + name + "(" in source for name in
                ("windows", "activateWindow", "closeWindow", "cycleWindows")),
            "BLOCKED: public Phase 3 window IPC bridge is not ready")
    require((ROOT / "services/AppService.qml").is_file(), "BLOCKED: native AppService is not ready")
    require((ROOT / "tests/fixtures/app_window.cpp").is_file(), "BLOCKED: native fixture source is missing")
    return args


def command(argv, env=None):
    try:
        result = safety.manual_process('run', 'running_app_contract', argv, env=env, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                text=True, timeout=5)
    except subprocess.TimeoutExpired:
        raise ContractError("Native command exceeded five-second timeout") from None
    require(result.returncode == 0, "Native command failed (private output suppressed)")
    return result.stdout.strip()


def eventually(predicate, label, timeout=10):
    """Bounded observation of the running test, never build-dependency polling."""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        result = predicate()
        if result:
            return result
        time.sleep(.1)
    raise ContractError("Timed out: " + label)


class NativeContract:
    def __init__(self, root, visible, popup_focus=False):
        self.root, self.visible = root, visible
        self.popup_focus = popup_focus
        self.app_id = "omadocked-test-app-" + uuid.uuid4().hex
        self.sentinel_id = self.app_id + "-sentinel"
        self.binary = root / "app-window"
        self.receipts = root / "owned-pids"
        self.config = root / "pins.json"
        self.adapter = None
        self.sentinel = None
        self.owned = {}  # PID -> pidfd, verified against this run's unique binary.
        self.checks = []
        self.env = dict(os.environ, QT_QPA_PLATFORM="wayland", OMADOCKED_VISIBLE="0",
                        OMADOCKED_TEST_MODE="0", OMADOCKED_CONFIG_PATH=str(self.config),
                        QS_NO_RELOAD_POPUP="1", XDG_DATA_HOME=str(root / "data"),
                        XDG_DATA_DIRS=str(root / "empty-data"), XDG_CONFIG_HOME=str(root / "config"),
                        XDG_CACHE_HOME=str(root / "cache"), XDG_STATE_HOME=str(root / "state"))
        for key in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST", "OMADOCKED_SCREEN",
                    "OMADOCKED_SCREENS", "OMADOCKED_OFFSET", "QT_LOGGING_RULES"):
            self.env.pop(key, None)

    def prepare(self):
        flags = shlex.split(command(["pkg-config", "--cflags", "--libs", "Qt6Widgets"]))
        result = safety.manual_process('run', 'running_app_contract', ["g++", "-std=c++17", "-fPIC", "-Wall", "-Wextra", "-Werror",
                                 str(ROOT / "tests/fixtures/app_window.cpp"), "-o", str(self.binary), *flags],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
        if result.returncode:
            # Compiler diagnostics only: no native process has been launched yet.
            print(result.stderr, file=sys.stderr)
            raise ContractError("Qt6Widgets fixture compilation failed")
        for path in ("data/applications", "empty-data", "config", "cache", "state", "shell"):
            (self.root / path).mkdir(parents=True, exist_ok=True)
        # Immutable project-shell copy avoids development reloads racing this run.
        for path in ROOT.glob("*.qml"):
            shutil.copy2(path, self.root / "shell" / path.name)
        for name in ("core", "ui", "services"):
            shutil.copytree(ROOT / name, self.root / "shell" / name)
        argv = [str(self.binary), self.app_id, str(self.root), str(self.receipts)]
        # These paths/IDs contain no desktop Exec metacharacters or whitespace.
        require(all(not any(c in value for c in ' \t\n%"\\`$') for value in argv), "Unsafe fixture launch path")
        desktop = self.root / "data/applications" / (self.app_id + ".desktop")
        desktop.write_text("[Desktop Entry]\nType=Application\nName=Omadocked owned test app\n"
                           "Icon=application-x-executable\nTerminal=false\nDBusActivatable=false\n"
                           + "StartupWMClass=" + self.app_id + "\nExec=" + " ".join(argv) + "\n")
        require(list((self.root / "data/applications").glob("*.desktop")) == [desktop], "DesktopEntries isolation failed")
        # The dock lists running apps and pins, not an all-installed-app launcher.
        # Seed ONLY this temporary file so its closed desktop entry can be launched.
        self.config.write_text(json.dumps({"version": 1, "pins": [self.app_id]}) + "\n")
        self.checks.append("compiled-Qt6Widgets-fixture-and-isolated-single-desktop-entry")

    def ipc(self, method, *args):
        if self.adapter is None or self.adapter.poll() is not None:
            raise ContractError("Owned adapter exited unexpectedly")
        return command(["quickshell", "ipc", "--pid", str(self.adapter.pid), "call", "--", TARGET, method, *args], self.env)

    def snapshot(self):
        raw = json.loads(self.ipc("snapshot"))
        require(all(row.get("id") == self.app_id or not row.get("canPin") for row in raw.get("apps", [])),
                "DesktopEntries isolation leaked a nonfixture launchable application")
        # Drop unknown desktop IDs, names, titles and all unrelated output state.
        app = [row for row in raw.get("apps", []) if row.get("id") == self.app_id]
        require(len(app) <= 1, "Fixture appears as duplicate app groups")
        require(not app or all(field in app[0] for field in FIELDS), "App snapshot schema is incomplete")
        return {"phase": raw.get("phase"), "testMode": raw.get("testMode"),
                "ready": raw.get("appsReady"), "error": bool(raw.get("appError")),
                "visible": raw.get("visible"), "app": ({key: app[0][key] for key in FIELDS} if app else None),
                "keyboardReleased": all(row.get("keyboardFocus") == "none" for row in raw.get("outputs", [])),
                "output": raw.get("output", "")}

    def start(self):
        self.adapter = safety.manual_process('Popen', 'running_app_contract', ["/usr/bin/python3", str(ROOT / "tools/preview.py"), "--", "-p", str(self.root / "shell/shell.qml"), "--no-color"],
                                        env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        def ready():
            require(self.adapter is not None and self.adapter.poll() is None, "Owned adapter failed to load project shell")
            try:
                state = self.snapshot()
            except ContractError:
                return False
            require(state["phase"] == 3 and state["testMode"] is False, "Expected Phase 3 live backend, not fixtures")
            require(not state["error"], "AppService reported an error (private text suppressed)")
            return state if state["ready"] else False
        state = eventually(ready, "live adapter IPC readiness", 12)
        require(state["visible"] is False and state["keyboardReleased"], "Adapter must start hidden without keyboard capture")
        return state

    def refresh_owned(self):
        if not self.receipts.exists():
            return
        for line in self.receipts.read_text().splitlines():
            if not line.isdecimal():
                continue
            pid = int(line)
            if pid in self.owned:
                continue
            try:
                fd = os.pidfd_open(pid)
                if Path("/proc", str(pid), "exe").resolve() != self.binary:
                    os.close(fd)
                    raise ContractError("Fixture receipt PID does not match owned binary")
                self.owned[pid] = fd
            except ProcessLookupError:
                continue

    def fixture_pids(self, app_id):
        self.refresh_owned()
        result = []
        for pid, fd in self.owned.items():
            if select.select([fd], [], [], 0)[0]:
                continue
            argv = Path("/proc", str(pid), "cmdline").read_bytes().split(b"\0")
            if len(argv) > 1 and argv[1] == app_id.encode():
                result.append(pid)
        return result

    def owned_clients(self, app_id):
        self.refresh_owned()
        # Private compositor response is used only in memory, filtered immediately.
        raw = json.loads(command(["hyprctl", "-j", "clients"]))
        return [{key: row.get(key) for key in ("pid", "class", "address")}
                for row in raw if row.get("pid") in self.owned and row.get("class") == app_id]

    def has_owned_layers(self, pid):
        raw = json.loads(command(["hyprctl", "-j", "layers"]))
        return any(row.get("pid") == pid for output in raw.values()
                   for rows in output.get("levels", {}).values() for row in rows)

    def active_owned(self, app_id):
        pids = self.fixture_pids(app_id)
        raw = json.loads(command(["hyprctl", "-j", "activewindow"]))
        return raw.get("pid") in pids and raw.get("class") == app_id

    def focused_owned_client(self, app_id):
        pids = self.fixture_pids(app_id)
        raw = json.loads(command(["hyprctl", "-j", "activewindow"]))
        # Never return/log titles, unrelated PIDs, or unrelated window addresses.
        if raw.get("pid") in pids and raw.get("class") == app_id:
            return {key: raw.get(key) for key in ("pid", "address")}
        return None

    def windows(self, app_id):
        require(app_id in (self.app_id, "window:" + self.sentinel_id),
                "Refusing to enumerate nonfixture window keys")
        rows = json.loads(self.ipc("windows", app_id))
        require(isinstance(rows, list), "Window IPC must return a JSON array")
        require(all(isinstance(row, dict) and set(row) == {"key", "active"}
                    and isinstance(row["key"], str) and bool(row["key"])
                    and isinstance(row["active"], bool) for row in rows),
                "Window IPC must expose only nonempty string keys and boolean active flags")
        require(len({row["key"] for row in rows}) == len(rows), "Window keys must be unique")
        return rows

    def window_actions(self, pid, second_address):
        """Map opaque keys by real focus, never by title or presumed key format."""
        sentinel_group = "window:" + self.sentinel_id  # No desktop entry by design.
        app_clients = {(row["pid"], row["address"]) for row in self.owned_clients(self.app_id)}
        sentinel_clients = {(row["pid"], row["address"]) for row in self.owned_clients(self.sentinel_id)}
        require(len(app_clients) == 2 and all(owner == pid for owner, _ in app_clients),
                "Window actions require two windows of the exact owned app process")
        require(bool(sentinel_clients), "Window actions require an owned sentinel")
        def window_count(app_id, count):
            rows = self.windows(app_id)
            return rows if len(rows) == count else False

        rows = eventually(lambda: window_count(self.app_id, 2), "two native window keys")
        keys = {row["key"] for row in rows}
        sentinel_rows = eventually(lambda: window_count(sentinel_group, len(sentinel_clients)), "owned sentinel window keys")
        sentinel_keys = {row["key"] for row in sentinel_rows}
        require(keys.isdisjoint(sentinel_keys), "Window keys collide across owned app groups")
        key_clients = {}

        def stable_rows(expected_keys):
            current = self.windows(self.app_id)
            require({row["key"] for row in current} == expected_keys,
                    "Native window keys changed without a window lifetime change")
            return current

        def focused(key, expected_client=None, expected_keys=keys):
            client = self.focused_owned_client(self.app_id)
            current = stable_rows(expected_keys)
            active = {row["key"] for row in current if row["active"]}
            if not client or active != {key}:
                return False
            identity = (client["pid"], client["address"])
            require(identity in app_clients, "Window action focused a nonmember of the owned app pair")
            return identity if expected_client is None or identity == expected_client else False

        def unchanged(expected_clients, expected_keys):
            require({(row["pid"], row["address"]) for row in self.owned_clients(self.app_id)} == expected_clients,
                    "Window action changed an unselected owned app window")
            require({(row["pid"], row["address"]) for row in self.owned_clients(self.sentinel_id)} == sentinel_clients,
                    "Window action changed an owned sentinel window")
            stable_rows(expected_keys)
            require({row["key"] for row in self.windows(sentinel_group)} == sentinel_keys,
                    "Window action changed owned sentinel keys")
            require(self.fixture_pids(self.app_id) == [pid], "Window action killed or relaunched the owned app")

        # Establish a one-to-one key/address map through two explicit activations.
        # The two windows share a PID, so a PID-only focus assertion cannot pass.
        for key in sorted(keys):
            require(self.ipc("activateWindow", self.app_id, key) == "true", "Specific owned window activation rejected")
            key_clients[key] = eventually(lambda: focused(key), "selected native window key and compositor focus")
            require(self.snapshot()["keyboardReleased"], "Specific window activation retained keyboard capture")
        require(set(key_clients.values()) == app_clients, "Different window keys did not focus different owned addresses")
        unchanged(app_clients, keys)
        self.checks.append("specific-window-keys-focus-two-distinct-owned-compositor-addresses")

        current_key = sorted(keys)[-1]
        for delta in (1, 1, -1, -1):
            next_key = next(value for value in keys if value != current_key)
            require(self.ipc("cycleWindows", self.app_id, str(delta)) == "true", "Owned window cycling rejected")
            eventually(lambda: focused(next_key, key_clients[next_key]), "cycle changes exact owned native window focus")
            require(self.snapshot()["keyboardReleased"], "Window cycling retained keyboard capture")
            current_key = next_key
        unchanged(app_clients, keys)
        self.checks.append("forward-and-reverse-window-cycling-wrap-between-owned-addresses")

        def rejects(pairs, expected_clients, expected_keys, focus_key):
            before = key_clients[focus_key]
            for method, app_id, wrong_key in pairs:
                require(self.ipc(method, app_id, wrong_key) == "false", "Stale or cross-app window pair was accepted")
                # Observe asynchronously delivered Wayland actions too, not just
                # the immediate bool. No dispatch/control is sent to user apps.
                deadline = time.monotonic() + .5
                while True:
                    unchanged(expected_clients, expected_keys)
                    require(focused(focus_key, before, expected_keys),
                            "Rejected window action changed actual owned focus")
                    if time.monotonic() >= deadline:
                        break
                    time.sleep(.1)

        sentinel_key = sorted(sentinel_keys)[0]
        rejects([(method, group, wrong_key)
                 for method in ("activateWindow", "closeWindow")
                 for group, wrong_key in ((self.app_id, sentinel_key), (sentinel_group, current_key))],
                app_clients, keys, current_key)
        self.checks.append("cross-app-activation-and-close-rejected-with-owned-windows-and-focus-intact")

        # Select the window created by control(second), independent of key order.
        # This replaces the old close-second step, preserving later 1/0/1/2 counts.
        closing_key = next((key for key, client in key_clients.items() if client == (pid, second_address)), None)
        require(closing_key is not None, "Second owned fixture address has no window key")
        survivor_key = next(key for key in keys if key != closing_key)
        require(self.ipc("activateWindow", self.app_id, closing_key) == "true", "Pre-close selected activation rejected")
        eventually(lambda: focused(closing_key, key_clients[closing_key]), "exact selected owned window before close")
        require(self.ipc("closeWindow", self.app_id, closing_key) == "true", "Targeted owned window close rejected")
        remaining_clients = {key_clients[survivor_key]}
        remaining_keys = {survivor_key}
        # QWidget accepts the protocol close request. This bounded assertion does
        # not claim that arbitrary applications must accept a close request.
        eventually(lambda: {(row["pid"], row["address"]) for row in self.owned_clients(self.app_id)} == remaining_clients,
                   "exact selected owned window disappears while its sibling remains", 5)
        eventually(lambda: {row["key"] for row in self.windows(self.app_id)} == remaining_keys,
                   "closed window key removed from native model", 5)
        eventually(lambda: self.app_state(running=True, windowCount=1), "targeted close decrements group count", 5)
        unchanged(remaining_clients, remaining_keys)
        self.checks.append("targeted-close-removes-only-selected-owned-address-and-key-preserving-sibling-and-sentinel")

        require(self.ipc("activateWindow", self.app_id, survivor_key) == "true", "Surviving owned window activation rejected")
        eventually(lambda: focused(survivor_key, key_clients[survivor_key], remaining_keys), "surviving owned window focus")
        rejects([(method, self.app_id, closing_key) for method in ("activateWindow", "closeWindow")],
                remaining_clients, remaining_keys, survivor_key)
        self.checks.append("stale-closed-key-activation-and-close-rejected-with-survivors-intact")
        require(self.snapshot()["error"], "Rejected stale action should leave visible error feedback")
        require(self.ipc("activateWindow", self.app_id, survivor_key) == "true", "Valid action after stale rejection failed")
        eventually(lambda: focused(survivor_key, key_clients[survivor_key], remaining_keys)
                   and not self.snapshot()["error"], "successful owned action clears prior rejection feedback")
        self.checks.append("stale-action-feedback-cleared-by-successful-owned-window-activation")

    def control(self, pid, operation):
        require(pid in self.owned, "Refusing to control an unverified PID")
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as sock:
            sock.settimeout(3)
            sock.connect(str(self.root / (str(pid) + ".sock")))
            sock.sendall(operation.encode())
            require(sock.recv(32) == b"ok", "Owned fixture control failed")

    def app_state(self, **expected):
        state = self.snapshot()
        require(not state["error"], "AppService reported an error (private text suppressed)")
        if not self.visible:
            require(state["visible"] is False and state["keyboardReleased"], "Hidden adapter mapped or captured keyboard")
        app = state["app"]
        return app if app and all(app.get(key) == value for key, value in expected.items()) else False

    def disk_pin(self, expected):
        if not self.config.exists():
            return False
        data = json.loads(self.config.read_text())
        return data.get("version") in (1, 2) and data.get("pins") == expected and not data.get("launchers", [])

    def stop_adapter(self):
        if self.adapter is None:
            return
        if self.adapter.poll() is None:
            self.adapter.terminate()
            try:
                self.adapter.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.adapter.kill()
                self.adapter.wait(timeout=5)
        require(self.adapter.poll() is not None, "Owned adapter survived cleanup")
        pid = self.adapter.pid
        eventually(lambda: not self.has_owned_layers(pid), "owned adapter layer disappearance", 3)
        self.adapter = None

    def exercise(self):
        self.start()
        eventually(lambda: self.app_state(pinned=True, running=False, windowCount=0, canPin=True), "closed pinned app")
        if self.adapter is None:
            raise ContractError("Owned adapter is unavailable")
        require(not self.has_owned_layers(self.adapter.pid), "Hidden adapter unexpectedly mapped a layer")
        require(self.ipc("pin", self.app_id, "true") == "true", "Idempotent pin of isolated desktop entry failed")
        eventually(lambda: self.disk_pin([self.app_id]), "pin persistence")
        self.checks.append("seeded-temporary-closed-pin-resolves-real-desktop-entry")
        require(self.ipc("activate", self.app_id) == "true", "Desktop-entry launch was rejected")
        eventually(lambda: len(self.owned_clients(self.app_id)) == 1, "owned native window creation")
        eventually(lambda: self.app_state(running=True, windowCount=1, pending=False), "real running app grouping")
        pids = self.fixture_pids(self.app_id)
        require(len(pids) == 1, "Expected exactly one owned desktop-entry launch")
        pid = pids[0]
        self.checks.append("desktop-entry-launched-one-owned-PID-and-native-window")
        first_addresses = {row["address"] for row in self.owned_clients(self.app_id)}
        require(len(first_addresses) == 1, "Expected exactly one owned first-window address")
        self.control(pid, "second")
        eventually(lambda: len(self.owned_clients(self.app_id)) == 2, "second owned window")
        second_addresses = {row["address"] for row in self.owned_clients(self.app_id)} - first_addresses
        require(len(second_addresses) == 1, "Expected one newly created owned second-window address")
        second_address = second_addresses.pop()
        eventually(lambda: self.app_state(running=True, windowCount=2), "two windows grouped under one desktop ID")
        self.checks.append("two-real-windows-grouped-under-one-app")
        self.sentinel = safety.manual_process('Popen', 'running_app_contract', [str(self.binary), self.sentinel_id, str(self.root), str(self.receipts)],
                                         env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        eventually(lambda: self.active_owned(self.sentinel_id), "owned focus sentinel activation")
        eventually(lambda: self.app_state(active=False), "fixture loses focus to owned sentinel")
        if self.visible:
            self.ipc("show")
            state = self.snapshot()
            require(bool(state["output"]), "Visible test needs an active output")
            adapter_pid = self.adapter.pid
            eventually(lambda: self.has_owned_layers(adapter_pid), "mapped dock without an open popup")
            if self.popup_focus:
                require(self.ipc("settings", state["output"], "true") == "true", "Owned settings popup failed to open")
                eventually(lambda: not self.snapshot()["keyboardReleased"], "owned popup keyboard capture")
            else:
                # Quickshell 0.3.1 ignores Toplevel.activate() until Qt has a
                # lastInputDevice. A native keyboard enter supplies that seat,
                # just as a real dock click would; no popup or input injection.
                self.ipc("keyboard")
                eventually(lambda: not self.snapshot()["keyboardReleased"], "native keyboard enter without popup")
        require(self.ipc("activate", self.app_id) == "true", "Running owned app activation was rejected")
        try:
            eventually(lambda: self.active_owned(self.app_id), "exact owned fixture native focus")
        except ContractError:
            state = self.snapshot()
            print(json.dumps({"focus_diagnostic": {
                "owned_app_active": self.active_owned(self.app_id),
                "owned_sentinel_active": self.active_owned(self.sentinel_id),
                "model_app_active": bool(state["app"] and state["app"]["active"]),
                "dock_keyboard_released": state["keyboardReleased"],
                "owned_app_window_count": len(self.owned_clients(self.app_id))}}), file=sys.stderr)
            raise
        eventually(lambda: self.app_state(active=True), "native active app state")
        require(self.snapshot()["keyboardReleased"], "Dock keyboard capture was not released before app focus")
        require(self.fixture_pids(self.app_id) == [pid], "Activating running app launched a duplicate")
        self.checks.append(("popup-" if self.popup_focus else "plain-") + "focus-moved-from-owned-sentinel-to-owned-app-without-duplicate-launch")
        if self.visible:
            # Verify normal icon focus separately from the settings workaround.
            # A newly created owned sentinel window takes focus without touching
            # any existing user window or injecting pointer/keyboard input.
            sentinel_pids = self.fixture_pids(self.sentinel_id)
            require(len(sentinel_pids) == 1, "Expected one owned sentinel process")
            self.control(sentinel_pids[0], "second")
            eventually(lambda: self.active_owned(self.sentinel_id), "second sentinel activation")
            eventually(lambda: self.app_state(active=False), "app loses focus before popup test")
            state = self.snapshot()
            require(self.ipc("settings", state["output"], "true") == "true", "Owned settings popup failed to open")
            eventually(lambda: not self.snapshot()["keyboardReleased"], "owned popup keyboard capture")
            require(self.ipc("activate", self.app_id) == "true", "Activation from popup was rejected")
            eventually(lambda: self.active_owned(self.app_id) and self.snapshot()["keyboardReleased"], "popup closes and exact app receives focus")
            self.checks.append("visible-settings-keyboard-grab-released-for-native-app-focus")
            self.ipc("hide")
        require(self.ipc("pin", self.app_id, "false") == "true", "Unpinning running app failed")
        eventually(lambda: self.app_state(pinned=False, running=True, windowCount=2), "unpinned running app retained")
        eventually(lambda: self.disk_pin([]), "unpin persistence")
        require(self.ipc("pin", self.app_id, "true") == "true", "Repinning running app failed")
        eventually(lambda: self.app_state(pinned=True), "repinned running app")
        # Identity reorder includes transient unknown groups without printing/storing
        # their IDs or changing their order. Only our single pin can reach disk.
        ids = [row["id"] for row in json.loads(self.ipc("snapshot"))["apps"]]
        require(self.ipc("reorderApps", " " + json.dumps(ids)) == "true", "Identity reorder IPC failed")
        del ids
        eventually(lambda: self.disk_pin([self.app_id]), "repin and reorder persistence")
        self.checks.append("unpin-retains-running-app-repin-and-reorder-persist")
        self.window_actions(pid, second_address)
        eventually(lambda: len(self.owned_clients(self.app_id)) == 1, "second owned window closed")
        eventually(lambda: self.app_state(windowCount=1), "group count decremented")
        self.control(pid, "quit")
        eventually(lambda: not self.owned_clients(self.app_id), "owned app window disappearance")
        eventually(lambda: self.app_state(pinned=True, running=False, active=False, windowCount=0), "closed pin retained")
        self.checks.append("owned-window-close-decrements-group-and-preserves-closed-pin")
        self.stop_adapter()
        state = self.start()
        require(state["app"] is not None, "Closed pin did not survive adapter restart")
        eventually(lambda: self.app_state(pinned=True, running=False, windowCount=0), "closed pin restored after restart")
        require(self.disk_pin([self.app_id]), "Restart changed persisted pin")
        self.checks.append("closed-pin-survives-live-adapter-restart")
        require(self.ipc("newInstance", self.app_id) == "true", "Closed pin new-instance request rejected")
        eventually(lambda: self.app_state(running=True, windowCount=1, pending=False), "new instance of closed pin")
        require(self.ipc("newInstance", self.app_id) == "true", "Running app new-instance request rejected")
        eventually(lambda: len(self.fixture_pids(self.app_id)) == 2, "second independently launched owned PID")
        eventually(lambda: self.app_state(running=True, windowCount=2, pending=False), "new instance joins existing app group")
        for owned_pid in self.fixture_pids(self.app_id):
            self.control(owned_pid, "quit")
        eventually(lambda: self.app_state(pinned=True, running=False, windowCount=0), "new-instance windows close without losing pin")
        self.checks.append("new-instance-launches-closed-and-running-apps-and-groups-owned-processes")

    @staticmethod
    def signal_owned(fd, signum):
        try:
            signal.pidfd_send_signal(fd, signum)
        except ProcessLookupError:
            pass  # Exit between readiness check and pidfd signal is benign.

    def cleanup(self):
        # Stop launch source first, then re-read receipts to include late children.
        self.stop_adapter()
        self.refresh_owned()
        # The exact Popen child is owned even if Qt fails before writing its receipt.
        if self.sentinel is not None and self.sentinel.poll() is None:
            self.sentinel.terminate()
        for fd in self.owned.values():
            if not select.select([fd], [], [], 0)[0]:
                self.signal_owned(fd, signal.SIGTERM)
        try:
            for fd in self.owned.values():
                if not select.select([fd], [], [], 3)[0]:
                    self.signal_owned(fd, signal.SIGKILL)
                    require(bool(select.select([fd], [], [], 3)[0]), "Owned fixture survived cleanup")
            if self.sentinel is not None:
                self.sentinel.wait(timeout=3)
            eventually(lambda: not self.owned_clients(self.app_id) and not self.owned_clients(self.sentinel_id),
                       "owned window disappearance after cleanup", 3)
        finally:
            for fd in self.owned.values():
                os.close(fd)
        self.checks.append("exact-owned-adapter-and-fixture-processes-cleaned-up")


def main(argv=None):
    args = preflight(argv)
    safety.manual_native('running_app_contract')
    with tempfile.TemporaryDirectory(prefix="omadocked-native-apps-") as directory:
        test = NativeContract(Path(directory), args.visible, args.popup_focus)
        try:
            test.prepare()
            test.exercise()
        finally:
            test.cleanup()
        report = {"passed": True, "visible": args.visible, "popup_focus_only": args.popup_focus, "checks": test.checks,
                  "not_tested": ["physical pointer/keyboard", "user applications", "multi-pin order changes", "XWayland/PWA matching",
                                 "applications that refuse protocol close", "window identity across title changes"]}
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ContractError, OSError, ValueError, subprocess.TimeoutExpired) as error:
        # No traceback or raw output: JSON decoding errors could expose private data.
        message = str(error) if isinstance(error, ContractError) else "Native harness failure (private details suppressed): " + type(error).__name__
        print(json.dumps({"passed": False, "error": message}), file=sys.stderr)
        sys.exit(1)
