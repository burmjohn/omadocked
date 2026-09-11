"""Hidden native probes; every process and config belongs to a temporary directory."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
import spawn_safety as safety
from backend_requirements import backend_for

ROOT = Path(__file__).resolve().parents[1]
SHELL = '''import QtQuick
import Quickshell
import Quickshell.Io
import "services"
ShellRoot {
    id: probe
    property bool invalidIconSeen: false
    property int emissions: 0
    property int windowEmissions: 0
    property int persistenceReceipts: 0
    property int lastPersistenceTransactionId: 0
    AppService { id: apps }
    Connections {
        target: apps
        function onPersistenceCompleted(transactionId, ok, message) {
            probe.persistenceReceipts++;
            probe.lastPersistenceTransactionId = transactionId;
        }
        function onWindowGroupsChanged() { probe.windowEmissions++; }
        function onItemsChanged() {
            probe.emissions++;
            if (apps.items.some(i => !i.icon.startsWith("image://") && !i.icon.startsWith("file://"))) probe.invalidIconSeen = true;
        }
    }
    IpcHandler {
        target: "app-test"
        function snapshot(): string { return JSON.stringify({ready: apps.ready, error: apps.error, items: apps.items, settings: apps.settings, launchers: apps.launchers, overrides: apps.overrides, entries: apps.entries, canRecover: apps.canRecover, persistenceBusy: apps.persistenceBusy, persistenceRevision: apps.persistenceRevision, lastPersistenceOk: apps.lastPersistenceOk, persistenceReceipts: probe.persistenceReceipts, lastPersistenceTransactionId: probe.lastPersistenceTransactionId, emissions: probe.emissions, pendingTimer: apps._pendingTimer.running, invalidIconSeen: probe.invalidIconSeen}); }
        function seed(data: string): bool { const d = JSON.parse(data); return apps.fixtureSet(d.entries, d.windows); }
        function pin(id: string, value: bool): bool { return apps.setPinned(id, value); }
        function order(data: string): bool { return apps.reorder(JSON.parse(data)); }
        function activate(id: string): bool { return apps.activate(id); }
        function windowState(id: string): string { return JSON.stringify((apps.windowGroups && apps.windowGroups[id] || []).map(w => ({key:w.key, active:w.active}))); }
        function activateWindow(id: string, key: string): bool { return typeof apps.activateWindow === "function" && apps.activateWindow(id, key); }
        function closeWindow(id: string, key: string): bool { return typeof apps.closeWindow === "function" && apps.closeWindow(id, key); }
        function cycleWindows(id: string, delta: string): bool { return typeof apps.cycleWindows === "function" && apps.cycleWindows(id, JSON.parse(delta)); }
        function windowChecks(): string { return JSON.stringify({emissions: probe.windowEmissions, available: apps.windowGroups !== undefined, fallback: !!apps.windowGroups && !!apps.windowGroups.one && apps.windowGroups.one[0].title === "One", privateTitle: !!apps.windowGroups && !!apps.windowGroups.one && apps.windowGroups.one[0].title === "PRIVATE fixture title"}); }
        function desktopActions(): string { return JSON.stringify(apps.desktopActions || {}); }
        function desktopAction(id: string, action: string): bool { return typeof apps.desktopAction === "function" && apps.desktopAction(id, action); }
        function newInstance(id: string): bool { return apps.newInstance(id); }
        function complete(id: string, ok: bool): bool { if (!apps.testMode) return false; apps._finishLaunch(id, ok, "fixture failure", apps._pending[id] ? apps._pending[id].token : 0); return true; }
        function configure(data: string): bool { return apps.configure(JSON.parse(data)); }
        function recover(): bool { return apps.recoverConfiguration(); }
        function leasePid(): string { return JSON.stringify(apps._lease.processId); }
        function save(data: string): bool { return apps.saveLauncher(JSON.parse(data)); }
        function saveTransaction(data: string): int { return apps.saveLauncher(JSON.parse(data)); }
        function duplicate(id: string): bool { return apps.duplicateLauncher(id); }
        function remove(id: string): bool { return apps.removeLauncher(id); }
        function override(appId: string, desktopId: string): bool { return apps.setOverride(appId, desktopId); }
        function fastTimeout(): bool { if (!apps.testMode) return false; apps._launchTimeout = 500; return true; }
    }
}
'''
ENTRIES = [{"id": "one", "name": "One", "startupClass": "One", "icon": "application-x-executable", "launchable": True},
           {"id": "two", "name": "Two", "startupClass": "Two", "icon": "application-x-executable", "launchable": True}]
WINDOWS = [{"key": "w1", "appId": "One", "active": True}, {"key": "w2", "appId": "Two"}]


class AppServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omadocked app-test-")
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT / "core", self.root / "core")
        if (ROOT / "services").exists():
            shutil.copytree(ROOT / "services", self.root / "services")
        (self.root / "shell.qml").write_text(SHELL)
        self.config = self.root / "config" / "pins.json"
        self.proc = None

    def tearDown(self):
        self.stop()
        self.temp.cleanup()

    def stop(self):
        if self.proc is not None:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=5)
            self.proc = None
            self.log.close()
            output = (self.root / "runtime.log").read_text()
            for issue in ("ReferenceError:", "TypeError:", "Binding loop", "Failed to load configuration", "Cannot assign"):
                self.assertNotIn(issue, output)

    def start(self, test_mode="1", extra_env=None, wrapped=True, wrapper=None):
        required = backend_for(self.id())
        env = dict(safety.fixture_environment(), OMADOCKED_TEST_MODE=test_mode, OMADOCKED_CONFIG_PATH=str(self.config),
                   OMADOCKED_PARKING_DISABLED="1", QS_NO_RELOAD_POPUP="1", QT_QPA_PLATFORM="wayland" if required == "native" else "offscreen")
        env.update(extra_env or {})
        for key in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST"):
            env.pop(key, None)
        self.log = (self.root / "runtime.log").open("w+")
        command = ["/usr/bin/python3", str(wrapper or ROOT / "tools/preview.py"), "--"] if wrapped else ["quickshell"]
        try:
            self.proc = safety.spawn(command + ["-p", str(self.root / "shell.qml"), "--no-color"],
                                         required=required, root=self.root, env=env, stdout=self.log, stderr=subprocess.STDOUT)
        except BaseException:
            self.log.close()
            raise
        deadline = time.monotonic() + 8
        while time.monotonic() < deadline:
            self.assertIsNone(self.proc.poll(), (self.root / "runtime.log").read_text())
            result = self.call("snapshot", check=False)
            if result and result.get("ready"):
                return result
            time.sleep(.05)
        self.fail((self.root / "runtime.log").read_text())

    def call(self, method, *args, check=True, wait_persistence=True):
        persistent = method in {"pin", "order", "configure", "recover", "save", "duplicate", "remove", "override"}
        before_revision = self.call("snapshot")["persistenceRevision"] if persistent and wait_persistence else None
        # Quickshell CLI expands bracket-delimited args; whitespace preserves a JSON string.
        args = tuple(" " + arg if arg.startswith("[") else arg for arg in args)
        result = safety.ipc(self.proc, ["quickshell", "ipc", "--pid", str(self.proc.pid), "call", "--", "app-test", method, *args],
                                text=True, capture_output=True, timeout=3)
        if not check and (result.returncode or not result.stdout.strip().startswith("{")):
            return None
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        value = json.loads(result.stdout)
        if persistent and wait_persistence and value is True:
            deadline = time.monotonic() + 3
            while time.monotonic() < deadline:
                state = self.call("snapshot")
                if state["persistenceRevision"] != before_revision:
                    return state["lastPersistenceOk"]
                if not state["persistenceBusy"]:
                    return True
                time.sleep(.01)
            self.fail("persistence transaction did not complete")
        return value

    def seed(self, windows=WINDOWS):
        self.assertTrue(self.call("seed", json.dumps({"entries": ENTRIES, "windows": windows})))
        return self.call("snapshot")

    def test_desktop_actions_are_metadata_for_current_normal_apps(self):
        self.start()
        entries = [dict(ENTRIES[0], actions=[{"id": "New", "name": "New window", "execString": "PRIVATE EXEC"}]), ENTRIES[1]]
        self.call("seed", json.dumps({"entries": entries, "windows": WINDOWS}))
        self.assertEqual(self.call("desktopActions"), {"one": [{"id": "New", "name": "New window"}], "two": []})
        self.assertNotIn("PRIVATE EXEC", json.dumps(self.call("snapshot")))
        self.seed([])
        self.assertEqual(self.call("desktopActions"), {})

    def test_unchanged_launcher_emits_explicit_correlated_completion(self):
        self.start()
        self.assertTrue(self.call("save", '{"kind":"command","name":"No-op","program":"/usr/bin/true","enabled":true}'))
        record = self.call("snapshot")["launchers"][0]
        before = self.call("snapshot")["persistenceReceipts"]
        transaction_id = self.call("saveTransaction", json.dumps(record))
        self.assertGreater(transaction_id, 0)
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            state = self.call("snapshot")
            if state["persistenceReceipts"] > before:
                break
            time.sleep(.01)
        self.assertGreater(state["persistenceReceipts"], before)
        self.assertEqual(state["lastPersistenceTransactionId"], transaction_id)
        self.assertTrue(state["lastPersistenceOk"])
        self.assertFalse(state["persistenceBusy"])

    def test_menu_is_an_exact_desktop_action_not_a_reserved_app_id(self):
        self.start()
        actions = [{"id": ident, "name": ident} for ident in ("menu", "Menu", "__proto__")]
        entries = [dict(ENTRIES[0], actions=actions),
                   {"id": "menu", "name": "Settings", "launchable": True, "actions": actions}]
        windows = [WINDOWS[0], {"key": "settings", "appId": "menu"}]
        self.call("seed", json.dumps({"entries": entries, "windows": windows}))
        self.assertEqual(self.call("desktopActions"), {"one": actions})
        self.assertFalse(self.call("desktopAction", "menu", "menu"))
        for ident in ("MENU", " menu", "menu ", ".", "..", "a/b", "a\\b", "a;b"):
            self.assertFalse(self.call("desktopAction", "one", ident))
        for action in actions:
            self.assertTrue(self.call("desktopAction", "one", action["id"]))
            self.call("complete", "one", "true")
        entries[0]["actions"] = [actions[0], actions[0], actions[1]]
        self.call("seed", json.dumps({"entries": entries, "windows": windows}))
        self.assertEqual(self.call("desktopActions"), {"one": [actions[1]]})
        self.assertFalse(self.call("desktopAction", "one", "menu"))
        self.assertFalse(self.call("snapshot")["pendingTimer"])
        self.assertFalse(self.config.exists())

    def test_desktop_action_submission_finishes_without_a_new_window(self):
        self.start()
        entries = [dict(ENTRIES[0], actions=[{"id": "New", "name": "New window"}]), ENTRIES[1]]
        self.call("seed", json.dumps({"entries": entries, "windows": WINDOWS}))
        self.assertTrue(self.call("desktopAction", "one", "New"))
        self.assertTrue(self.call("snapshot")["items"][0]["pending"])
        self.assertFalse(self.call("desktopAction", "one", "New"))
        self.call("complete", "one", "true")
        state = self.call("snapshot")
        self.assertFalse(state["items"][0]["pending"])
        self.assertFalse(state["pendingTimer"])
        self.assertFalse(self.config.exists())
        self.assertEqual(state["error"], "Launch already pending")
        self.assertTrue(self.call("desktopAction", "one", "New"))
        self.call("complete", "one", "false")
        self.assertIn("fixture failure", self.call("snapshot")["error"])

    def test_desktop_actions_reject_ambiguous_malformed_custom_and_stale(self):
        self.start()
        actions = [{"id": "New", "name": ""}, {"id": "dup", "name": "A"}, {"id": "dup", "name": "B"},
                   {"id": " bad", "name": "Bad"}, {"id": "x;y", "name": "Bad"}, {"id": "", "name": "Bad"},
                   {"id": "../x", "name": "Bad"}, {"id": "x\x7f", "name": "Bad"}, None]
        entries = [dict(ENTRIES[0], actions=actions), dict(ENTRIES[1], actions=[{"id": "Other", "name": "Other"}])]
        self.call("seed", json.dumps({"entries": entries, "windows": WINDOWS}))
        self.assertEqual(self.call("desktopActions")["one"], [{"id": "New", "name": "New"}])
        self.assertTrue(self.call("save", '{"kind":"application","name":"Copy","desktopId":"one","enabled":true}'))
        custom = self.call("snapshot")["launchers"][0]["id"]
        before = self.config.read_bytes()
        for app, action in [("two", "New"), (custom, "New"), ("one", "dup"), ("one", "new"), (" one", "New"), ("one", "New ")]:
            self.assertFalse(self.call("desktopAction", app, action))
        self.assertFalse(self.call("save", '{"kind":"desktop-action","name":"No","desktopId":"one","actionId":"New","enabled":true}'))
        self.assertEqual(self.config.read_bytes(), before)
        self.call("seed", json.dumps({"entries": entries + [entries[0]], "windows": WINDOWS}))
        self.assertNotIn("one", self.call("desktopActions"))
        self.assertFalse(self.call("desktopAction", "one", "New"))
        self.call("seed", json.dumps({"entries": [dict(ENTRIES[0], actions=[]), ENTRIES[1]], "windows": WINDOWS}))
        self.assertFalse(self.call("desktopAction", "one", "New"))
        self.call("seed", json.dumps({"entries": [ENTRIES[1]], "windows": WINDOWS}))
        self.assertFalse(self.call("desktopAction", "one", "New"))
        self.assertFalse(self.call("snapshot")["pendingTimer"])

    def test_native_desktop_action_receipt_without_window_or_config_write(self):
        data = self.root / "action-data"
        applications = data / "applications"
        applications.mkdir(parents=True)
        receipt = self.root / "action-receipt.json"
        script = self.root / "owned-action.py"
        script.write_text("import json,os,pathlib,sys\npathlib.Path(sys.argv[1]).write_text(json.dumps([sys.argv[2:], [k for k in os.environ if k.startswith('OMADOCKED_WRITER_') or k == 'OMADOCKED_BOOTSTRAP_FD']]))\n")
        desktop = applications / "omadocked-action-fixture.desktop"
        desktop.write_text('[Desktop Entry]\nType=Application\nName=Action fixture\nExec=/usr/bin/true\nActions=Receipt;Empty;\n'
                           '[Desktop Action Receipt]\nName=Write receipt\nExec=/usr/bin/python3 "' + str(script) + '" "' + str(receipt) + '" "literal argument"\n'
                           '[Desktop Action Empty]\nName=No command\n'
                           '[Desktop Action Unadvertised]\nName=Not advertised\nExec=/usr/bin/false\n')
        self.config.parent.mkdir()
        before = '{"version":1,"pins":["omadocked-action-fixture"]}'
        self.config.write_text(before)
        self.start(test_mode="0", extra_env={"XDG_DATA_HOME": str(data), "XDG_DATA_DIRS": str(data)})
        self.assertEqual(self.call("desktopActions"), {"omadocked-action-fixture": [{"id": "Receipt", "name": "Write receipt"}]})
        self.assertFalse(receipt.exists())
        self.assertFalse(self.call("desktopAction", "omadocked-action-fixture", "Unadvertised"))
        self.assertTrue(self.call("desktopAction", "omadocked-action-fixture", "Receipt"))
        deadline = time.monotonic() + 4
        while time.monotonic() < deadline:
            state = self.call("snapshot")
            if receipt.exists() and not state["pendingTimer"]:
                break
            time.sleep(.03)
        self.assertTrue(receipt.exists(), "Owned Gio action did not write its receipt")
        self.assertEqual(json.loads(receipt.read_text()), [["literal argument"], []])
        self.assertFalse(state["pendingTimer"])
        self.assertEqual(state["error"], "")
        self.assertFalse(state["items"][0]["pending"])
        self.assertEqual(self.config.read_text(), before)

    def test_desktop_action_busy_timeout_and_missing_helper_are_bounded(self):
        self.fake_native_source()
        source = self.root / "services/LiveApps.qml"
        source.write_text(source.read_text().replace('execString:"fixture"', 'execString:"fixture", actions:[{id:"New", name:"New", execString:"fixture"}]'))
        service = self.root / "services/AppService.qml"
        service.write_text(service.read_text().replace('property int _launchTimeout: 10000', 'property int _launchTimeout: 700'))
        helper = self.root / "services/launch_app.py"
        helper.write_text("import time; time.sleep(60)\n")
        self.start(test_mode="0")
        self.assertTrue(self.call("desktopAction", "one", "New"))
        self.assertFalse(self.call("desktopAction", "one", "New"))
        self.assertIn("pending", self.call("snapshot")["error"])
        self.assertTrue(self.call("save", '{"kind":"command","name":"Busy fixture","program":"/usr/bin/true","enabled":true}'))
        custom = self.call("snapshot")["launchers"][0]["id"]
        self.assertFalse(self.call("activate", custom))
        self.assertIn("busy", self.call("snapshot")["error"])
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            state = self.call("snapshot")
            if not state["pendingTimer"]:
                break
            time.sleep(.03)
        self.assertFalse(state["pendingTimer"])
        self.assertIn("Launcher timed out", state["error"])
        self.assertNotIn("matching window", state["error"])
        self.stop()
        helper.unlink()
        self.start(test_mode="0")
        self.assertTrue(self.call("desktopAction", "one", "New"))
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            state = self.call("snapshot")
            if not state["pendingTimer"]:
                break
            time.sleep(.03)
        self.assertFalse(state["pendingTimer"])
        self.assertIn("Launch failed", state["error"])

    def test_window_groups_are_private_view_metadata(self):
        self.start()
        self.seed()
        self.assertTrue(self.call("windowChecks")["available"])
        self.assertTrue(self.call("windowChecks")["fallback"])
        rows = self.call("windowState", "one")
        self.assertEqual(len(rows), 1)
        self.assertTrue(rows[0]["active"])
        before = self.call("snapshot")["emissions"]
        self.seed([dict(WINDOWS[0], title="PRIVATE fixture title"), WINDOWS[1]])
        self.assertTrue(self.call("windowChecks")["privateTitle"])
        self.assertEqual(self.call("windowState", "one"), rows)
        state = self.call("snapshot")
        self.assertEqual(state["emissions"], before)
        self.assertNotIn("PRIVATE fixture title", json.dumps(state))
        self.assertNotIn("windowGroups", state)

    def test_activate_window_revalidates_exact_group(self):
        self.start()
        self.seed(WINDOWS + [{"key": "w3", "appId": "One"}])
        rows = self.call("windowState", "one")
        key = rows[1]["key"]
        self.assertTrue(self.call("activateWindow", "one", key))
        self.assertEqual([w["active"] for w in self.call("windowState", "one")], [False, True])
        self.assertFalse(self.call("activateWindow", "two", key))
        self.assertFalse(self.call("activateWindow", "one", "missing"))
        self.assertTrue(self.call("override", "One", "two"))
        self.assertFalse(self.call("activateWindow", "one", key))
        self.assertTrue(self.call("activateWindow", "two", key))

    def test_close_window_only_removes_chosen_fixture_and_reappearance_is_new(self):
        self.start()
        windows = WINDOWS + [{"key": "w3", "appId": "One"}]
        self.seed(windows)
        rows = self.call("windowState", "one")
        key = rows[1]["key"]
        self.assertFalse(self.call("closeWindow", "two", key))
        self.assertTrue(self.call("closeWindow", "one", key))
        self.assertEqual(self.call("windowState", "one"), rows[:1])
        self.assertFalse(self.call("closeWindow", "one", key))
        self.seed(windows)
        fresh = self.call("windowState", "one")
        self.assertNotEqual(fresh[1]["key"], key)
        self.assertEqual(fresh[0]["key"], rows[0]["key"])
        self.assertFalse(self.call("activateWindow", "one", key))
        self.assertFalse(self.call("closeWindow", "one", key))

    def test_cycle_windows_simulates_only_exact_group(self):
        self.start()
        self.seed(WINDOWS + [{"key": "w3", "appId": "One"}])
        rows = self.call("windowState", "one")
        self.assertTrue(self.call("cycleWindows", "one", "1"))
        self.assertEqual([w["active"] for w in self.call("windowState", "one")], [False, True])
        self.assertTrue(self.call("cycleWindows", "one", "1"))
        self.assertEqual(self.call("windowState", "one"), rows)
        self.assertTrue(self.call("cycleWindows", "one", "-1"))
        for step in ["0", "2", "0.5", '"1"', "null", "true"]:
            self.assertFalse(self.call("cycleWindows", "one", step))
        self.assertFalse(self.call("cycleWindows", "missing", "1"))
        self.seed([])
        self.assertFalse(self.call("cycleWindows", "one", "1"))

    def fake_native_source(self):
        # Exercise the real binding/dispatch code with owned QObjects, not user windows.
        path = self.root / "services/LiveApps.qml"
        source = path.read_text().replace("ToplevelManager.toplevels.values", "fixtureValues")
        source = source.replace("DesktopEntries.applications.values", "fixtureEntries")
        source = source.replace("QtObject {", '''QtObject {
    property var fixtureEntries: [{id:"one", name:"One", icon:"", startupClass:"One", execString:"fixture"}]
    property QtObject first: QtObject {
        property string appId: "One"
        property string title: ""
        property bool activated: true
        property int closeRequests: 0
        property int activateRequests: 0
        function close() { closeRequests++; }
        function activate() { activateRequests++; }
    }
    property var fixtureValues: [first]
''', 1)
        path.write_text(source)
        shell = (self.root / "shell.qml").read_text().replace('        target: "app-test"', '''        target: "app-test"
        function nativeTitle(): bool { apps._live.item.first.title = "PRIVATE fixture title"; return true; }
        function nativeActive(): bool { apps._live.item.first.activated = false; return true; }
        function nativeRemove(): bool { apps._live.item.fixtureValues = []; return true; }
        function nativeReappear(): bool { apps._live.item.fixtureValues = [apps._live.item.first]; return true; }
        function nativeRegroup(): bool { apps._live.item.first.appId = "Unmatched"; return true; }
        function nativeCounts(): string { return JSON.stringify({close: apps._live.item.first.closeRequests, activate: apps._live.item.first.activateRequests}); }
''')
        (self.root / "shell.qml").write_text(shell)

    def test_native_title_events_are_private_and_do_not_churn_items(self):
        self.fake_native_source()
        self.start(test_mode="0")
        rows = self.call("windowState", "one")
        self.assertEqual(len(rows), 1)
        before = self.call("snapshot")["emissions"]
        self.assertTrue(self.call("nativeTitle"))
        self.assertTrue(self.call("windowChecks")["privateTitle"])
        self.assertEqual(self.call("windowState", "one"), rows)
        self.assertEqual(self.call("snapshot")["emissions"], before)
        count = self.call("windowChecks")["emissions"]
        self.call("nativeTitle")
        self.assertEqual(self.call("windowChecks")["emissions"], count)
        self.call("nativeActive")
        self.assertEqual(self.call("windowState", "one"), [{"key": rows[0]["key"], "active": False}])
        self.call("nativeRemove")
        self.assertEqual(self.call("windowState", "one"), [])
        self.call("nativeReappear")
        self.assertNotEqual(self.call("windowState", "one")[0]["key"], rows[0]["key"])
        self.assertNotIn("PRIVATE fixture title", (self.root / "runtime.log").read_text())

    def test_native_close_requests_wait_for_removal_and_revalidate(self):
        self.fake_native_source()
        self.start(test_mode="0")
        rows = self.call("windowState", "one")
        key = rows[0]["key"]
        self.assertTrue(self.call("closeWindow", "one", key))
        self.assertEqual(self.call("nativeCounts"), {"close": 1, "activate": 0})
        self.assertEqual(self.call("windowState", "one"), rows)
        self.assertTrue(self.call("activateWindow", "one", key))
        self.assertEqual(self.call("nativeCounts"), {"close": 1, "activate": 1})
        self.call("nativeRegroup")
        self.assertFalse(self.call("closeWindow", "one", key))
        self.assertFalse(self.call("activateWindow", "one", key))
        self.assertEqual(self.call("nativeCounts"), {"close": 1, "activate": 1})
        self.assertTrue(self.call("closeWindow", "window:Unmatched", key))
        self.call("nativeRemove")
        self.assertFalse(self.call("closeWindow", "window:Unmatched", key))
        self.assertEqual(self.call("nativeCounts"), {"close": 2, "activate": 1})

    def test_window_metadata_noop_and_app_reorder_do_not_emit_groups(self):
        self.start()
        self.seed()
        rows = self.call("windowState", "one")
        before = self.call("windowChecks")["emissions"]
        self.seed()
        self.assertEqual(self.call("windowChecks")["emissions"], before)
        self.assertTrue(self.call("order", '["two","one"]'))
        self.assertEqual(self.call("windowState", "one"), rows)
        self.assertEqual(self.call("windowChecks")["emissions"], before)

    def test_window_custom_launchers_never_alias_normal_group(self):
        self.start()
        self.seed()
        key = self.call("windowState", "one")[0]["key"]
        self.assertTrue(self.call("save", '{"kind":"application","name":"Copy","desktopId":"one","enabled":true}'))
        custom = self.call("snapshot")["launchers"][0]["id"]
        self.assertTrue(self.call("duplicate", custom))
        for item in self.call("snapshot")["launchers"]:
            self.assertEqual(self.call("windowState", item["id"]), [])
            self.assertFalse(self.call("activateWindow", item["id"], key))
            self.assertFalse(self.call("closeWindow", item["id"], key))
            self.assertFalse(self.call("cycleWindows", item["id"], "1"))
        self.assertTrue(self.call("activateWindow", "one", key))
        self.assertNotIn("title", self.config.read_text())
        self.assertNotIn("windowGroups", self.config.read_text())

    def test_window_removal_and_reappearance_never_reuses_fixture_key(self):
        self.start()
        self.seed()
        key = self.call("windowState", "one")[0]["key"]
        self.seed([])
        self.seed()
        self.assertNotEqual(self.call("windowState", "one")[0]["key"], key)
        self.assertFalse(self.call("activateWindow", "one", key))
        self.assertFalse(self.call("closeWindow", "one", key))

    def test_two_instances_single_writer_and_recovery_owner(self):
        self.start()
        other = AppServiceTests()
        other.setUp()
        self.addCleanup(other.tearDown)
        other.config = self.config
        state = other.start()
        self.assertIn("another instance", state["error"])
        self.assertFalse(other.call("configure", '{"iconSize":60}'))
        self.assertFalse(self.config.exists())
        self.assertTrue(self.call("configure", '{"iconSize":56}'))
        committed = self.config.read_bytes()
        self.assertFalse(other.call("configure", '{"iconSize":60}'))
        self.assertEqual(self.config.read_bytes(), committed)
        other.stop()
        state = other.start()
        self.assertIn("another instance", state["error"])
        self.assertEqual(state["settings"]["iconSize"], 44)
        self.assertFalse(other.call("configure", '{"iconSize":60}'))
        self.assertEqual(Path(str(self.config) + ".lkg").read_bytes(), committed)
        other.stop()
        self.config.write_text("{broken")
        self.assertFalse(self.call("configure", '{"iconSize":60}'))
        self.assertFalse(self.call("snapshot")["canRecover"])
        self.stop()
        state = other.start()
        self.assertTrue(state["canRecover"])
        self.assertTrue(other.call("recover"))
        self.assertEqual(self.config.read_bytes(), committed)
        other.stop()
        self.assertEqual(other.start()["error"], "")
        self.assertTrue(other.call("configure", '{"iconSize":60}'))
        self.assertEqual(json.loads(self.config.read_text())["settings"]["iconSize"], 60)

    def test_helper_missing_and_startup_timeout_fail_closed(self):
        helper = self.root / "services" / "config_store.py"
        helper.unlink()
        state = self.start()
        self.assertIn("helper unavailable", state["error"])
        self.assertFalse(self.call("configure", '{"iconSize":56}'))
        self.assertFalse(self.config.exists())
        self.stop()
        helper.write_text("import time; time.sleep(60)\n")
        state = self.start()
        self.assertIn("startup failed", state["error"])
        self.assertFalse(state["canRecover"])
        self.assertFalse(self.call("configure", '{"iconSize":56}'))
        self.assertFalse(self.config.exists())

    def test_preview_and_configuration_paths_with_spaces_hash_percent_colon(self):
        checkout = self.root / "preview space # % :"
        (checkout / "tools").mkdir(parents=True)
        shutil.copy2(ROOT / "tools/preview.py", checkout / "tools/preview.py")
        self.config = self.root / "config space # % :.json"
        state = self.start(wrapper=checkout / "tools/preview.py",
                           extra_env={"OMADOCKED_WRITER_PID": "1", "OMADOCKED_WRITER_FD": "9999"})
        self.assertEqual(state["error"], "")
        environment = Path(f"/proc/{self.proc.pid}/environ").read_bytes()
        self.assertNotIn(b"OMADOCKED_WRITER_PID=", environment)
        self.assertNotIn(b"OMADOCKED_WRITER_FD=", environment)
        self.assertNotIn(b"LD_PRELOAD=", environment)
        self.assertEqual(Path(f"/proc/{self.proc.pid}/exe").resolve(), Path("/usr/bin/quickshell").resolve())
        self.assertTrue(self.call("configure", '{"iconSize":58}'))
        self.assertEqual(json.loads(self.config.read_text())["settings"]["iconSize"], 58)

    def test_unwrapped_host_uses_owned_helper_without_writer_environment(self):
        state = self.start(wrapped=False)
        self.assertEqual(state["error"], "")
        self.assertTrue(self.call("configure", '{"iconSize":60}'))
        deadline = time.monotonic() + 3
        while not self.config.exists() and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertEqual(json.loads(self.config.read_text())["settings"]["iconSize"], 60)
        environment = Path(f"/proc/{self.proc.pid}/environ").read_bytes()
        self.assertNotIn(b"OMADOCKED_WRITER_FD=", environment)
        self.assertNotIn(b"LD_PRELOAD=", environment)

    def test_helper_loss_disables_writes_and_releases_lock_for_competitor(self):
        self.assertEqual(self.start()["error"], "")
        helper_pid = self.call("leasePid")
        os.kill(helper_pid, 9)
        deadline = time.monotonic() + 3
        while "stopped" not in self.call("snapshot")["error"] and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertIn("stopped", self.call("snapshot")["error"])
        self.assertFalse(self.call("configure", '{"iconSize":56}'))
        other = AppServiceTests()
        other.setUp()
        self.addCleanup(other.tearDown)
        other.config = self.config
        self.assertEqual(other.start()["error"], "")
        self.assertTrue(other.call("configure", '{"iconSize":60}'))

    def test_inflight_helper_loss_reports_failed_completion_without_publishing(self):
        marker = self.root / "request-seen"
        helper = self.root / "services/config_store.py"
        helper.write_text(
            "import json,sys,time\n"
            "from pathlib import Path\n"
            "print(json.dumps({'type':'ready','ok':True,'missing':True,'text':'','backup':''}),flush=True)\n"
            "for line in sys.stdin:\n"
            " Path(" + repr(str(marker)) + ").touch(); time.sleep(60)\n")
        self.assertEqual(self.start()["settings"]["iconSize"], 44)
        self.assertTrue(self.call("configure", '{"iconSize":60}', wait_persistence=False))
        deadline = time.monotonic() + 3
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(.01)
        os.kill(self.call("leasePid"), 9)
        deadline = time.monotonic() + 3
        state = self.call("snapshot")
        while state["persistenceRevision"] == 0 and time.monotonic() < deadline:
            time.sleep(.01)
            state = self.call("snapshot")
        self.assertFalse(state["persistenceBusy"])
        self.assertFalse(state["lastPersistenceOk"])
        self.assertEqual(state["persistenceRevision"], 1)
        self.assertEqual(state["settings"]["iconSize"], 44)
        self.assertIn("stopped", state["error"])

    def test_model_is_not_published_before_verified_helper_receipt(self):
        marker = self.root / "request-seen"
        release = self.root / "release"
        helper = self.root / "services/config_store.py"
        helper.write_text(helper.read_text().replace('def emit(value):',
            'def emit(value):\n'
            '    if "id" in value:\n'
            '        import time\n'
            '        Path(' + repr(str(marker)) + ').touch()\n'
            '        while not Path(' + repr(str(release)) + ').exists(): time.sleep(.01)'))
        self.assertEqual(self.start()["settings"]["iconSize"], 44)
        self.assertTrue(self.call("configure", '{"iconSize":60}', wait_persistence=False))
        deadline = time.monotonic() + 3
        while not marker.exists() and time.monotonic() < deadline:
            time.sleep(.01)
        state = self.call("snapshot")
        self.assertTrue(state["persistenceBusy"])
        self.assertEqual(state["settings"]["iconSize"], 44)
        release.touch()
        deadline = time.monotonic() + 3
        while self.call("snapshot")["persistenceBusy"] and time.monotonic() < deadline:
            time.sleep(.01)
        state = self.call("snapshot")
        self.assertTrue(state["lastPersistenceOk"])
        self.assertEqual(state["settings"]["iconSize"], 60)

    def test_folder_color_and_record_roundtrip_without_implicit_launch(self):
        self.start()
        folder = self.root / "owned folder"
        folder.mkdir()
        self.assertTrue(self.call("save", json.dumps({"kind":"folder", "name":"Owned", "target":str(folder), "enabled":True})))
        self.assertTrue(self.call("configure", json.dumps({"folderColor":"black"})))
        state = self.call("snapshot")
        self.assertFalse(any(item["pending"] for item in state["items"]))
        disk = json.loads(self.config.read_text())
        self.assertEqual(disk["settings"]["folderColor"], "black")
        self.assertEqual(disk["launchers"][0]["target"], str(folder))
        self.stop()
        state = self.start()
        self.assertEqual(state["settings"]["folderColor"], "black")
        self.assertEqual(state["launchers"], disk["launchers"])
        self.assertFalse(any(item["pending"] for item in state["items"]))

    def test_v1_migrates_in_memory_without_startup_write(self):
        self.config.parent.mkdir()
        before = '{"version":1,"pins":["one"]}'
        self.config.write_text(before)
        state = self.start()
        self.assertEqual(state.get("settings"), {"iconSize": 44, "transparency": 0, "shape": "rounded", "itemSpacing": 4,
                         "backgroundColor": "theme", "themeOpacity": False, "zoomSize": 145, "waveWidth": 25, "motionMode": "wave",
                         "reducedMotion": False, "showAppNames": True, "advancedTooltips": False, "launchBounce": True, "tooltipDelay": 450, "revealDelay": 160, "autoHide": True, "intelligentHide": False, "minimizeMode": "active",
                         "reserveSpace": False, "followActiveOutput": False, "monitorMode": "all", "selectedOutputs": [], "folderColor": "theme",
                         "previewsEnabled": True, "livePreviews": False, "showUrgentHint": True,
                         "urgentOnNotification": True, "urgentSound": False, "urgentSoundName": "bell"})
        self.assertEqual(state["launchers"], [])
        self.assertEqual(state["overrides"], {})
        self.assertEqual(self.config.read_text(), before)
        self.assertEqual(set(self.config.parent.iterdir()), {self.config, Path(str(self.config) + ".lock")})

    def test_app_names_persist_restart_and_reject_failed_write(self):
        state = self.start()
        self.assertTrue(state["settings"]["showAppNames"])
        self.assertTrue(self.call("configure", '{"showAppNames":false}'))
        self.assertFalse(json.loads(self.config.read_text())["settings"]["showAppNames"])
        self.stop()
        self.assertFalse(self.start()["settings"]["showAppNames"])
        before = self.config.read_bytes()
        for value in (0, "false", None):
            self.assertFalse(self.call("configure", json.dumps({"showAppNames": value})))
            self.assertEqual(self.config.read_bytes(), before)
        self.config.chmod(0o444)
        self.assertFalse(self.call("configure", '{"showAppNames":true}'))
        self.assertFalse(self.call("snapshot")["settings"]["showAppNames"])
        self.assertEqual(self.config.read_bytes(), before)

    def test_settings_patch_is_validated_persisted_and_preserves_pins(self):
        self.start()
        self.seed()
        self.assertTrue(self.call("pin", "one", "true"))
        self.assertTrue(self.call("configure", json.dumps({"iconSize": 56, "motionMode": "off", "selectedOutputs": ["fixture-A"]})))
        before = self.config.read_bytes()
        for patch in ({"iconSize": 100}, {"iconSize": "44"}, {"motionMode": "invalid"}, {"minimizeMode": "invalid"}, {"unknown": 1},
                      {"transparency": -1}, {"reducedMotion": 1}, {"autoHide": "false"},
                      {"monitorMode": "invalid"}, {"selectedOutputs": ["a", "a"]}):
            self.assertFalse(self.call("configure", json.dumps(patch)), patch)
            self.assertEqual(self.config.read_bytes(), before)
        self.stop()
        state = self.start()
        self.assertEqual(state["settings"]["iconSize"], 56)
        self.assertEqual(state["settings"]["motionMode"], "off")
        self.assertEqual(state["settings"]["selectedOutputs"], ["fixture-A"])
        self.assertEqual([i["id"] for i in state["items"]], ["one"])

    def test_lkg_contains_latest_successful_commit_not_uncommitted_change(self):
        self.start()
        self.seed()
        self.assertTrue(self.call("pin", "one", "true"))
        backup = Path(str(self.config) + ".lkg")
        self.assertEqual(json.loads(backup.read_text())["pins"], ["one"])
        self.config.chmod(0o444)
        self.assertFalse(self.call("pin", "two", "true"))
        self.assertEqual(json.loads(backup.read_text())["pins"], ["one"])

    def test_explicit_recovery_preserves_damage_and_refuses_future_version(self):
        self.start()
        self.seed()
        self.call("pin", "one", "true")
        self.call("configure", '{"iconSize":56}')
        self.assertTrue(Path(str(self.config) + ".lkg").exists(), "No last-known-good backup was created")
        self.assertEqual(json.loads(Path(str(self.config) + ".lkg").read_text())["pins"], ["one"])
        self.stop()
        damaged = '{broken configuration'
        self.config.write_text(damaged)
        state = self.start()
        self.assertTrue(state["canRecover"])
        self.assertEqual(self.config.read_text(), damaged)
        self.assertTrue(self.call("recover"))
        self.assertEqual(json.loads(self.config.read_text())["pins"], ["one"])
        backups = list(self.config.parent.glob("pins.json.damaged-*"))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), damaged)
        self.assertEqual(self.call("snapshot")["error"], "")
        self.stop()
        future = '{"version":999,"pins":[]}'
        self.config.write_text(future)
        self.assertFalse(self.start()["canRecover"])
        self.assertFalse(self.call("recover"))
        self.assertEqual(self.config.read_text(), future)

    def test_launcher_save_edit_reload_is_inert_and_typed(self):
        self.start()
        self.seed()
        self.call("pin", "one", "true")
        record = {"id": "", "kind": "command", "name": "Fixture", "program": "/nonexistent/fixture",
                  "args": ["", "a b", "$(touch /tmp/not-executed)", "'quoted'"], "enabled": True}
        self.assertTrue(self.call("save", json.dumps(record)))
        state = self.call("snapshot")
        saved = state["launchers"][0]
        self.assertRegex(saved["id"], r"^launcher:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
        self.assertEqual(saved["args"], record["args"])
        self.assertEqual(saved["workingDirectory"], "")
        self.assertFalse(saved["terminal"])
        item = next(i for i in state["items"] if i["id"] == saved["id"])
        for key in ("canEdit", "canDuplicate", "canRemove"):
            self.assertTrue(item[key])
        for key in ("running", "pending", "canPin", "canNewInstance"):
            self.assertFalse(item[key])
        self.assertEqual([i["id"] for i in state["items"]], ["one", saved["id"], "two"])
        self.assertTrue(self.call("save", json.dumps(dict(saved, name="Renamed"))))
        before = self.config.read_bytes()
        for bad in (dict(saved, args="split me"), dict(saved, kind="shell"), dict(saved, shell=True),
                    dict(saved, program=""), dict(saved, workingDirectory="relative")):
            self.assertFalse(self.call("save", json.dumps(bad)))
            self.assertEqual(self.config.read_bytes(), before)
        self.stop()
        state = self.start()
        self.assertEqual(state["launchers"][0]["name"], "Renamed")
        self.assertFalse(any(i["running"] or i["pending"] for i in state["items"]))

    def test_launcher_duplicate_remove_and_grouped_order_commit_atomically(self):
        self.start()
        self.seed()
        self.call("pin", "one", "true")
        self.call("pin", "two", "true")
        self.assertTrue(self.call("save", '{"kind":"separator","name":"Divider","enabled":true}'))
        original = self.call("snapshot")["launchers"][0]
        self.assertTrue(self.call("duplicate", original["id"]))
        copied = self.call("snapshot")["launchers"][1]
        self.assertNotEqual(copied["id"], original["id"])
        self.assertEqual(copied["kind"], original["kind"])
        self.assertFalse(self.call("activate", original["id"]))
        self.assertTrue(self.call("order", json.dumps([copied["id"], "two", original["id"], "one"])))
        saved = json.loads(self.config.read_text())
        self.assertEqual(saved["pins"], ["two", "one"])
        self.assertEqual([r["id"] for r in saved["launchers"]], [copied["id"], original["id"]])
        self.assertEqual([i["id"] for i in self.call("snapshot")["items"]], ["two", "one", copied["id"], original["id"]])
        before = self.config.read_bytes()
        self.config.chmod(0o444)
        self.assertFalse(self.call("remove", copied["id"]))
        self.assertEqual(self.config.read_bytes(), before)
        self.assertEqual(len(self.call("snapshot")["launchers"]), 2)
        self.config.chmod(0o600)
        self.stop()
        self.start()
        self.assertTrue(self.call("remove", copied["id"]))
        self.assertFalse(self.call("duplicate", copied["id"]))
        self.assertFalse(self.call("remove", "one"))
        self.assertEqual([r["id"] for r in self.call("snapshot")["launchers"]], [original["id"]])

    def test_exact_override_persists_and_deletion_restores_matching(self):
        self.start()
        self.seed()
        self.assertTrue(self.call("override", "One", "two"))
        self.assertEqual(self.call("snapshot")["items"][0]["windowCount"], 2)
        self.assertFalse(self.call("override", "One", "missing"))
        self.assertFalse(self.call("override", "", "one"))
        self.stop()
        self.start()
        state = self.seed()
        self.assertEqual(state["overrides"], {"One": "two"})
        self.assertEqual([i["id"] for i in state["items"]], ["two"])
        self.assertEqual(state["entries"], [{"id": "one", "name": "One"}, {"id": "two", "name": "Two"}])
        self.assertTrue(self.call("override", "One", ""))
        self.assertEqual(len(self.call("snapshot")["items"]), 2)

    def test_new_instance_waits_for_new_membership_not_existing_running_window(self):
        self.start()
        state = self.seed()
        self.assertTrue(state["items"][0].get("canNewInstance"), "Missing new-instance capability")
        self.assertTrue(self.call("newInstance", "one"))
        self.assertFalse(self.call("newInstance", "one"))
        self.assertTrue(self.seed()["items"][0]["pending"])
        self.call("complete", "one", "true")
        self.assertFalse(self.call("newInstance", "one"))
        state = self.seed(WINDOWS + [{"key":"w3", "appId":"One"}])
        self.assertFalse(state["items"][0]["pending"])
        self.assertTrue(self.call("newInstance", "one"))
        self.assertFalse(self.call("newInstance", "missing"))

    def test_noop_refresh_and_settings_do_not_emit_model_or_write_config(self):
        self.start()
        before = self.seed()["emissions"]
        self.assertEqual(self.seed()["emissions"], before)
        self.assertTrue(self.call("configure", '{"iconSize":56}'))
        self.assertEqual(self.call("snapshot")["emissions"], before)
        stamp = self.config.stat().st_mtime_ns
        self.assertTrue(self.call("configure", '{"iconSize":56}'))
        self.assertEqual(self.config.stat().st_mtime_ns, stamp)
        self.assertTrue(self.call("order", '["one","two"]'))
        state = self.call("snapshot")
        self.assertEqual(state["emissions"], before)
        self.assertFalse(state["pendingTimer"])

    def test_testmode_refuses_non_temporary_paths_without_reading(self):
        state = self.start(extra_env={"OMADOCKED_CONFIG_PATH": "/home/omadocked-test-must-not-read.json"})
        self.assertIn("temporary", state["error"])
        self.assertFalse(state["canRecover"])
        self.seed()
        self.assertFalse(self.call("pin", "one", "true"))

    def test_external_empty_creation_is_not_confused_with_missing_config(self):
        self.start()
        self.seed()
        self.config.parent.mkdir(exist_ok=True)
        self.config.write_text("")
        self.assertFalse(self.call("pin", "one", "true"))
        self.assertEqual(self.config.read_text(), "")

    def test_valid_external_replacement_requires_restart_not_recovery(self):
        self.start()
        self.seed()
        self.call("pin", "one", "true")
        external = '{"version":1,"pins":["two"]}'
        self.config.write_text(external)
        self.assertFalse(self.call("configure", '{"iconSize":56}'))
        self.assertFalse(self.call("snapshot")["canRecover"])
        self.assertFalse(self.call("recover"))
        self.assertEqual(self.config.read_text(), external)

    def test_custom_launch_pending_is_bounded_and_never_fakes_running(self):
        self.start()
        self.seed([])
        self.call("fastTimeout")
        records = [{"kind":"command", "program":"fixture"}, {"kind":"link", "target":"https://example.com"},
                   {"kind":"file", "target":"/tmp/fixture"}, {"kind":"folder", "target":"/tmp"},
                   {"kind":"action", "action":"quick-menu"}, {"kind":"application", "desktopId":"one"}]
        for record in records:
            self.assertTrue(self.call("save", json.dumps(dict(record, name="Fixture", enabled=True))))
            ident = self.call("snapshot")["launchers"][-1]["id"]
            self.assertTrue(self.call("activate", ident), record)
            self.assertFalse(self.call("activate", ident))
            state = self.call("snapshot")
            item = next(i for i in state["items"] if i["id"] == ident)
            self.assertTrue(item["pending"])
            self.assertFalse(item["running"])
            self.assertFalse(self.call("newInstance", ident))
            self.call("complete", ident, "true")
            if record["kind"] == "application":
                self.seed([{"key":"new", "appId":"One"}])
            item = next(i for i in self.call("snapshot")["items"] if i["id"] == ident)
            self.assertFalse(item["pending"])
        self.assertTrue(self.call("save", '{"kind":"command","name":"Timeout","program":"fixture","enabled":true}'))
        ident = self.call("snapshot")["launchers"][-1]["id"]
        self.assertTrue(self.call("activate", ident))
        time.sleep(.6)
        self.assertFalse(next(i for i in self.call("snapshot")["items"] if i["id"] == ident)["pending"])
        self.assertIn("timed out", self.call("snapshot")["error"])
        self.assertTrue(self.call("save", '{"kind":"command","name":"Disabled","program":"fixture"}'))
        disabled = self.call("snapshot")["launchers"][-1]["id"]
        self.assertFalse(self.call("activate", disabled))

    def test_pin_commits_then_restores_closed_pin(self):
        self.start()
        self.assertEqual(len(self.seed()["items"]), 2)
        self.assertTrue(self.call("pin", "two", "true"))
        self.assertEqual(json.loads(self.config.read_text())["version"], 2)
        self.assertEqual(json.loads(self.config.read_text())["pins"], ["two"])
        self.assertEqual(self.call("snapshot")["items"][0]["id"], "two")
        self.stop()
        self.start()
        items = self.seed([])["items"]
        self.assertEqual([i["id"] for i in items], ["two"])
        self.assertFalse(items[0]["running"])
        self.assertTrue(items[0]["pinned"])

    def test_reorder_persists_pins_before_transients(self):
        self.start()
        self.seed()
        self.assertTrue(self.call("pin", "one", "true"))
        self.assertTrue(self.call("pin", "two", "true"))
        self.assertTrue(self.call("order", ' ["two", "one"]'))
        self.assertEqual(json.loads(self.config.read_text())["pins"], ["two", "one"])
        self.assertFalse(self.call("order", ' ["two", "two"]'))
        self.assertFalse(self.call("order", ' ["menu", "two", "one"]'))
        self.assertTrue(self.call("pin", "two", "false"))
        self.assertEqual([i["id"] for i in self.call("snapshot")["items"]], ["one", "two"])

    def test_activation_fixture_pending_and_stale_membership(self):
        self.start()
        self.seed()
        self.assertTrue(self.call("activate", "one"))
        self.assertTrue(self.call("pin", "one", "true"))
        self.seed([])
        self.assertTrue(self.call("activate", "one"))
        self.assertTrue(self.call("snapshot")["items"][0]["pending"])
        self.assertFalse(self.call("activate", "one"))
        self.assertFalse(self.call("activate", "two"))
        self.seed(WINDOWS)
        self.assertFalse(self.call("snapshot")["items"][0]["pending"])

    @unittest.skipUnless(os.environ.get("OMADOCKED_TEST_LIVE_READONLY") == "1", "opt-in read-only live native probe")
    def test_readonly_live_source_no_actions(self):
        self.start(test_mode="0")
        time.sleep(.2)
        state = self.call("snapshot")
        self.assertTrue(any(i["running"] for i in state["items"]), "Expected existing native toplevels")
        self.assertTrue(all(i["icon"].startswith(("image://", "file://")) for i in state["items"]))
        self.assertFalse(self.call("seed", json.dumps({"entries": [], "windows": []})))
        self.assertFalse(self.config.exists())

    def test_native_custom_command_runs_only_after_explicit_activation(self):
        data = self.root / "isolated-data"
        data.mkdir()
        self.start(test_mode="0", extra_env={"XDG_DATA_HOME": str(data), "XDG_DATA_DIRS": str(data)})
        marker = self.root / "explicit-command-only"
        record = {"kind":"command", "name":"Owned fixture", "enabled":True, "program":"/usr/bin/python3",
                  "args":["-c", "import pathlib,sys;pathlib.Path(sys.argv[1]).write_text('explicit');sys.exit(7)", str(marker)]}
        self.assertTrue(self.call("save", json.dumps(record)))
        ident = self.call("snapshot")["launchers"][0]["id"]
        self.assertTrue(self.call("duplicate", ident))
        self.assertFalse(marker.exists())
        self.stop()
        self.start(test_mode="0", extra_env={"XDG_DATA_HOME": str(data), "XDG_DATA_DIRS": str(data)})
        self.assertFalse(marker.exists())
        self.assertTrue(self.call("activate", ident))
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            state = self.call("snapshot")
            if "exit code 7" in state["error"]:
                self.assertEqual(marker.read_text(), "explicit")
                self.assertFalse(next(i for i in state["items"] if i["id"] == ident)["pending"])
                self.assertFalse(state["pendingTimer"])
                return
            time.sleep(.03)
        self.fail("Explicit owned command completion was not surfaced")

    def test_native_launch_failure_is_visible_no_executable_exists(self):
        # Gio resolves this fixture to no executable: no application can be launched.
        data = self.root / "data"
        applications = data / "applications"
        applications.mkdir(parents=True)
        (applications / "omadocked-invalid-fixture.desktop").write_text(
            "[Desktop Entry]\nType=Application\nName=Invalid fixture\nExec=/nonexistent/omadocked-test-do-not-execute\n")
        self.config.parent.mkdir()
        self.config.write_text('{"version":1,"pins":["omadocked-invalid-fixture"]}')
        self.start(test_mode="0", extra_env={"XDG_DATA_HOME": str(data), "XDG_DATA_DIRS": str(data)})
        time.sleep(.1)
        self.assertTrue(self.call("activate", "omadocked-invalid-fixture"))
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            state = self.call("snapshot")
            if state["error"]:
                self.assertIn("Launch failed", state["error"])
                self.assertIn("Desktop entry no longer exists or cannot be launched", state["error"])
                item = next(i for i in state["items"] if i["id"] == "omadocked-invalid-fixture")
                self.assertFalse(item["pending"])
                return
            time.sleep(.03)
        self.fail("Native launch failure was not surfaced")

    def test_pending_deadlines_independent_and_success_cancels_timer(self):
        self.start()
        self.seed()
        self.call("pin", "one", "true")
        self.call("pin", "two", "true")
        self.seed([])
        self.assertTrue(self.call("fastTimeout"))
        self.assertTrue(self.call("activate", "one"))
        time.sleep(.3)
        self.assertTrue(self.call("activate", "two"))
        time.sleep(.25)
        items = {i["id"]: i for i in self.call("snapshot")["items"]}
        self.assertFalse(items["one"]["pending"])
        self.assertTrue(items["two"]["pending"])
        self.seed()
        self.assertTrue(self.call("activate", "two"))
        time.sleep(.6)
        self.assertEqual(self.call("snapshot")["error"], "")

    def test_items_never_publish_intermediate_non_native_icons(self):
        self.start()
        self.assertFalse(self.seed()["invalidIconSeen"])

    def test_malformed_and_future_configs_are_never_overwritten(self):
        self.config.parent.mkdir()
        for text in ('{broken', '', '{"version":999,"pins":["one"]}'):
            with self.subTest(text=text):
                self.config.write_text(text)
                self.start()
                self.assertTrue(self.seed()["error"])
                self.assertFalse(self.call("pin", "one", "true"))
                self.assertEqual(self.config.read_text(), text)
                self.stop()

    def test_external_corruption_preserves_last_known_pins(self):
        self.start()
        self.seed()
        self.assertTrue(self.call("pin", "one", "true"))
        self.config.write_text("{broken")
        self.assertFalse(self.call("pin", "two", "true"))
        self.assertEqual(self.config.read_text(), "{broken")
        state = self.call("snapshot")
        self.assertTrue(state["error"])
        self.assertEqual([i["id"] for i in state["items"] if i["pinned"]], ["one"])

    def test_io_failure_never_claims_pin_success(self):
        self.start()
        self.seed()
        self.assertTrue(self.call("pin", "one", "true"))
        before = self.config.read_bytes()
        self.config.chmod(0o444)
        self.assertFalse(self.call("pin", "two", "true"))
        self.assertEqual(self.config.read_bytes(), before)
        state = self.call("snapshot")
        self.assertIn("save failed", state["error"])
        self.assertEqual([i["id"] for i in state["items"] if i["pinned"]], ["one"])

    def test_test_mode_default_empty_and_memory_only(self):
        (self.root / "services" / "config_store.py").unlink()
        state = self.start(extra_env={"OMADOCKED_CONFIG_PATH": "", "XDG_CONFIG_HOME": str(self.root / "unused")})
        self.assertEqual(state["items"], [])
        self.seed()
        self.assertTrue(self.call("pin", "one", "true"))
        # Qt's input method may create its own fcitx directory, not a dock write.
        self.assertFalse((self.root / "unused" / "omadocked").exists())
        self.assertFalse(self.config.exists())
        self.assertFalse(Path(str(self.config) + ".lock").exists())

    def test_desktop_ids_cannot_inherit_pending_from_object_prototype(self):
        self.start()
        entries = [{"id": name, "name": name, "launchable": True} for name in ("toString", "__proto__")]
        windows = [{"key": str(i), "appId": e["id"]} for i, e in enumerate(entries)]
        self.call("seed", json.dumps({"entries": entries, "windows": windows}))
        for entry in entries:
            self.assertTrue(self.call("pin", entry["id"], "true"))
        self.call("seed", json.dumps({"entries": entries, "windows": []}))
        self.assertTrue(all(not i["pending"] for i in self.call("snapshot")["items"]))
        self.assertTrue(self.call("activate", "__proto__"))

    def test_pin_limit_cannot_write_config_its_reader_rejects(self):
        entries = [{"id": "app-" + str(i), "name": "Fixture", "launchable": True} for i in range(257)]
        self.config.parent.mkdir()
        before = json.dumps({"version": 1, "pins": [e["id"] for e in entries[:256]]})
        self.config.write_text(before)
        self.start()
        self.call("seed", json.dumps({"entries": entries, "windows": [{"key": "last", "appId": "app-256"}]}))
        self.assertFalse(self.call("pin", "app-256", "true"))
        self.assertEqual(self.config.read_text(), before)

    def test_icon_fallback_and_file_url_encoding(self):
        self.start()
        entries = [dict(ENTRIES[0], icon="no-such-omadocked-fixture-icon"), dict(ENTRIES[1], icon="/tmp/icon #a%.png")]
        self.call("seed", json.dumps({"entries": entries, "windows": WINDOWS}))
        items = self.call("snapshot")["items"]
        self.assertTrue(items[0]["icon"].startswith("image://"))
        self.assertEqual(items[1]["icon"], "file:///tmp/icon%20%23a%25.png")


if __name__ == "__main__":
    unittest.main()
