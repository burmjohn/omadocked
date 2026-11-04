"""Offscreen AppService controller tests with inert exact-child transports."""
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

import spawn_safety as safety

ROOT = Path(__file__).resolve().parents[1]


class AppServiceLifecycleTests(unittest.TestCase):
    def run_qml(self, body, *, env=None):
        with tempfile.TemporaryDirectory(prefix="app lifecycle #%-") as directory:
            root = Path(directory)
            shutil.copytree(ROOT / "core", root / "core")
            shutil.copytree(ROOT / "services", root / "services")
            service = root / "services/AppService.qml"
            service.write_text(service.read_text().replace("import Quickshell.Io\n", "")
                               .replace("import Quickshell\n", 'import "TestShell.js" as Quickshell\n'))
            fixture_env = dict(OMADOCKED_TEST_MODE="1", OMADOCKED_TEST_ROOT=str(root),
                               OMADOCKED_CONFIG_PATH="", OMADOCKED_PARKING_DISABLED="1")
            fixture_env.update(env or {})
            (root / "services/TestShell.js").write_text(
                '.pragma library\nvar values = ' + json.dumps(fixture_env) + ';\n'
                'function env(key) { return values[key] || ""; }\n'
                'function iconPath(name) { return "image://fixture/" + name; }\n')
            (root / "services/Process.qml").write_text('''import QtQuick
QtObject {
    property var command: []
    property bool running: false
    property bool stdinEnabled: false
    property QtObject stdout
    property QtObject stderr
    property var signals: []
    property var writes: []
    signal exited(int exitCode, int exitStatus)
    function write(text) { writes = writes.concat([JSON.parse(text)]); }
    function signal(number) { signals = signals.concat([number]); }
}
''')
            (root / "services/StdioCollector.qml").write_text('import QtQuick\nQtObject { property string text: "" }\n')
            (root / "services/SplitParser.qml").write_text('import QtQuick\nQtObject { signal read(string line) }\n')
            (root / "tst_service.qml").write_text('''import QtQuick
import QtTest
import "services"
TestCase {
    name: "AppServiceLifecycle"
    AppService { id: apps }
    function test_behavior() {
''' + body + '\n    }\n}\n')
            environment = dict(safety.fixture_environment(), QT_QPA_PLATFORM="offscreen",
                               OMADOCKED_TEST_MODE="1", OMADOCKED_CONFIG_PATH="",
                               OMADOCKED_PARKING_DISABLED="1")
            # Overrides belong to the inert JS environment, never child IO.
            proc = safety.spawn(["/usr/lib/qt6/bin/qmltestrunner", "-input", str(root), "-o", "-,txt"],
                                required="offscreen", root=root, env=environment,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                output, _ = proc.communicate(timeout=25)
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.wait(timeout=3)
            self.assertEqual(proc.returncode, 0, output)
            for issue in ("ReferenceError:", "TypeError:", "Binding loop", "Cannot assign"):
                self.assertNotIn(issue, output)

    def test_recovery_budget_scales_with_records_but_stalls_fail_closed(self):
        self.run_qml('''
        apps._parking.running = true;
        apps._parkedWindows = [{key:"a"}, {key:"b"}, {key:"c"}];
        const id = apps.recoverParked("here");
        verify(id > 0);
        verify(apps._parkingDeadline.interval > (1 + 4 * 3) * 3000);
        verify(apps._parkingDeadline.interval < 60000);
        // A completed batch still requires independent status reconciliation.
        apps._parkingMessage(JSON.stringify({id:id, ok:true, status:"restored"}));
        compare(apps._parkingDeadline.interval, 5000);
        apps._parkingMessage(JSON.stringify({id:apps._parkingActive.id, ok:true, records:[]}));
        verify(apps.lastParkingReceipt.ok);
        apps._parkedWindows = [{key:"unresolved"}];
        verify(apps.recoverParked("origin") > 0);
        // Accelerate only the clock for a genuinely stalled transaction.
        apps._parkingDeadline.interval = 20;
        apps._parkingDeadline.restart();
        tryCompare(apps, "_parkingDead", true, 500);
        verify(!apps.lastParkingReceipt.ok);
        compare(apps.lastParkingReceipt.status, "helper-timeout-unresolved");
        compare(apps._parkedWindows[0].key, "unresolved");
        compare(apps._parking.signals, [15]);
        tryCompare(apps._parking, "signals", [15, 9], 1000);
        compare(apps.recoverParked("here"), 0);
''')

    def test_restore_aggregate_budget_and_correlated_status(self):
        self.run_qml('''
        apps._parking.running = true;
        const id = apps._enqueueParking({op:"restore", key:"owned", mode:"here"});
        verify(id > 0);
        // Five sequential helper calls can each legally take nearly 3 seconds.
        verify(apps._parkingDeadline.interval > 5 * 3000);
        wait(3500);
        verify(!apps._parkingDead);
        apps._parkingMessage(JSON.stringify({id:id, ok:true, status:"restored", key:"owned"}));
        compare(apps.parkingRevision, 0); // receipt needs matching status read-back
        const statusId = apps._parkingActive.id;
        apps._parkingMessage(JSON.stringify({id:statusId + 1, ok:true, records:[]}));
        compare(apps.parkingRevision, 0);
        apps._parkingMessage(JSON.stringify({id:statusId, ok:true, records:[]}));
        compare(apps.parkingRevision, 1);
        verify(apps.lastParkingReceipt.ok);
        verify(!apps._parkingDeadline.running);
''')

    def test_unowned_or_noncanonical_paths_never_start_helpers(self):
        cases = [
            ("/owned", "/owned-sibling/pins.json"),
            ("/owned", "/other/pins.json"),
            ("/owned", "/owned/../other/pins.json"),
            ("/owned", "/owned/./pins.json"),
            ("/owned", "owned/pins.json"),
            ("/owned", "/owned"),
            ("/", "/owned/pins.json"),
            ("", "/tmp/pins.json"),
            ("", "/var/tmp/pins.json"),
            ("owned", "/owned/pins.json"),
            ("/owned/../other", "/owned/../other/pins.json"),
        ]
        for fixture_root, path in cases:
            with self.subTest(root=fixture_root, path=path):
                self.run_qml('''
        verify(!apps._pathAllowed);
        verify(!apps._parkingPathAllowed);
        verify(!apps._lease.running);
        verify(!apps._parking.running);
''', env={"OMADOCKED_TEST_ROOT": fixture_root, "OMADOCKED_CONFIG_PATH": path,
          "OMADOCKED_PARKING_DISABLED": "0", "OMADOCKED_PARKING_JOURNAL": path})

    def test_failed_start_retires_without_exit_signal(self):
        self.run_qml('''
        apps._launchTimeout = 50;
        const helper = apps._launcherFactory.createObject(apps, {
            requestId:"missing", requestToken:1, requestRecord:{kind:"command"}});
        apps._launcher = helper;
        // A failed start can remain not-running without ever emitting exited.
        tryCompare(apps, "_launcher", null, 500);
''')

    def test_normal_exit_cancels_helper_deadlines(self):
        self.run_qml('''
        apps._launchTimeout = 50;
        const helper = apps._launcherFactory.createObject(apps, {
            requestId:"done", requestToken:1, requestRecord:{kind:"command"}});
        apps._launcher = helper;
        helper.running = true;
        helper.running = false;
        helper.exited(0, 0);
        compare(apps._launcher, null);
        compare(helper.signals, []);
        verify(!helper.runtimeDeadline.running);
        verify(!helper.killDeadline.running);
''')

    def test_explicit_shared_roots_are_bounded(self):
        self.run_qml('''
        verify(apps._pathAllowed);
        verify(apps._parkingPathAllowed);
''', env={"OMADOCKED_TEST_ROOTS": json.dumps(["/fixture-a", "/fixture-b"]),
          "OMADOCKED_CONFIG_PATH": "/fixture-b/pins.json",
          "OMADOCKED_PARKING_DISABLED": "0",
          "OMADOCKED_PARKING_JOURNAL": "/fixture-a/parking.json"})
        for roots in ('invalid', '{}', '[]', '["/"]', '["/fixture", "../escape"]'):
            with self.subTest(roots=roots):
                self.run_qml('''
        verify(!apps._pathAllowed);
        verify(!apps._lease.running);
''', env={"OMADOCKED_TEST_ROOTS": roots,
          "OMADOCKED_CONFIG_PATH": "/fixture/pins.json"})
        self.run_qml('''
        verify(!apps._pathAllowed);
        verify(!apps._lease.running);
''', env={"OMADOCKED_TEST_ROOTS": '["/fixture"]',
          "OMADOCKED_CONFIG_PATH": "/fixture-sibling/pins.json"})

    def test_explicit_owned_scratch_paths_are_accepted(self):
        self.run_qml('''
        verify(apps._pathAllowed);
        verify(apps._parkingPathAllowed);
        verify(apps._lease.running);
        verify(apps._parking.running);
''', env={"OMADOCKED_TEST_ROOT": "/owned scratch #%-fixture",
          "OMADOCKED_CONFIG_PATH": "/owned scratch #%-fixture/config/pins.json",
          "OMADOCKED_PARKING_DISABLED": "0",
          "OMADOCKED_PARKING_JOURNAL": "/owned scratch #%-fixture/state/parking.json"})

    def test_matching_window_does_not_cancel_helper_retirement(self):
        self.run_qml('''
        apps._launchTimeout = 100;
        apps.fixtureSet([{id:"one", name:"One", launchable:true}], []);
        verify(apps._requestLaunch("one", {kind:"application", desktopId:"one", enabled:true}));
        const token = apps._pending.one.token;
        const helper = apps._launcherFactory.createObject(apps, {
            requestId:"one", requestToken:token,
            requestRecord:{kind:"application", desktopId:"one"}});
        apps._launcher = helper;
        helper.running = true;
        apps.fixtureSet([{id:"one", name:"One", launchable:true}], [{key:"new", appId:"one"}]);
        verify(!apps._pending.one);
        verify(!apps._pendingTimer.running);
        tryCompare(helper, "signals", [15], 600);
        tryCompare(helper, "signals", [15, 9], 1000);
        // Signals target only this transport, never the launched descendants.
        compare(apps._lease.signals, []);
        compare(apps._parking.signals, []);
        helper.running = false;
        helper.exited(9, 1);
        compare(apps._launcher, null);
        verify(apps._requestLaunch("one", {kind:"application", desktopId:"one", enabled:true}));
        const replacement = apps._pending.one.token;
        verify(replacement > token);
        apps._finishLaunch("one", false, "late", token);
        compare(apps._pending.one.token, replacement);
''')


if __name__ == "__main__":
    unittest.main()
