"""Production folder service + real scanner, offscreen owned fixtures only."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import time
import unittest
import spawn_safety as safety

ROOT = Path(__file__).resolve().parents[1]
SHELL = '''import QtQuick
import Quickshell
import Quickshell.Io
import "services"
import "ui"
ShellRoot {
    FolderService { id: folders }
    AppService { id: apps }
    DockView { id:view; applications:apps.items; launcherRecords:apps.launchers; reducedMotion:true; autoHide:false }
    FolderIntegration { id:integration; view:view; controller:apps }
    IpcHandler {
        target: "folders-test"
        function state(): string { return JSON.stringify({opened:folders.opened, busy:folders.busy, generation:folders.generation, result:folders.result}); }
        function open(path: string): bool { return folders.open("owned", path); }
        function close(): void { folders.close(); }
        function action(kind: string, path: string, generation: int): string { return JSON.stringify(folders.action(kind, path, generation)); }
        function save(path: string): int { return apps.saveLauncher({kind:"folder", name:"Owned", target:path, enabled:true}); }
        function click(): void { view.selectId(apps.launchers[0].id); }
        function manager(): void { view.activeFolderChooser.choose("manager", ""); }
        function integrated(): string { return JSON.stringify({ready:apps.ready, open:view.folderChooserOpen, result:integration.folders.result, busy:integration.folders.busy, pending:apps.items.some(i=>i.pending), records:apps.launchers.length}); }
        function toggle(path: string): int { return apps.toggleFolder(path, "Owned"); }
        function color(value: string): int { return apps.configure({folderColor:value}); }
        function settings(): string { return JSON.stringify(apps.settings); }
        function items(): string { return JSON.stringify(apps.items); }
        function switchClose(a: string, b: string): void { folders.open("a", a); folders.open("b", b); folders.close(); }
    }
}
'''

class FolderServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omadocked-folder-")
        self.root = Path(self.temp.name)
        shutil.copytree(ROOT / "services", self.root / "services")
        shutil.copytree(ROOT / "core", self.root / "core")
        shutil.copytree(ROOT / "ui", self.root / "ui")
        (self.root / "shell.qml").write_text(SHELL)
        self.folder = self.root / "owned ; ' folder"
        self.folder.mkdir()
        self.log = (self.root / "runtime.log").open("w+")
        env = dict(safety.fixture_environment(), QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software", QS_NO_RELOAD_POPUP="1", OMADOCKED_TEST_MODE="1", OMADOCKED_CONFIG_PATH="", OMADOCKED_PARKING_DISABLED="1")
        if self._testMethodName == "test_real_ui_to_launcher_receipt":
            # Replace only the native data source. Keep production service,
            # bridge, chooser, scanner, writer and launch helper untouched.
            (self.root / "services/LiveApps.qml").write_text("import QtQuick\nQtObject { property var entries: []; property var windows: [] }\n")
            binary = self.root / "bin"
            binary.mkdir()
            opener = binary / "xdg-open"
            opener.write_text("#!/usr/bin/python3\nimport json,os,sys\nfrom pathlib import Path\nPath(os.environ['RECEIPT']).write_text(json.dumps(sys.argv[1:]))\n")
            opener.chmod(0o700)
            env.update(OMADOCKED_TEST_MODE="0", OMADOCKED_CONFIG_PATH=str(self.root / "pins.json"), PATH=str(binary) + os.pathsep + os.environ["PATH"], RECEIPT=str(self.root / "receipt.json"))
        for key in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST"):
            env.pop(key, None)
        try:
            self.proc = safety.spawn(["quickshell", "-p", str(self.root / "shell.qml"), "--no-color"], required="offscreen", root=self.root, env=env, stdout=self.log, stderr=subprocess.STDOUT)
        except BaseException:
            self.log.close()
            raise
        for _ in range(100):
            if self.proc.poll() is not None:
                self.fail((self.root / "runtime.log").read_text())
            value = self.call("state", check=False)
            if value is not None and self.call("integrated")["ready"]:
                return
            time.sleep(.03)
        self.fail("folder service did not start")

    def tearDown(self):
        self.proc.terminate()
        try:
            self.proc.wait(timeout=3)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait(timeout=3)
        self.log.close()
        log = (self.root / "runtime.log").read_text()
        self.temp.cleanup()
        for issue in ("TypeError:", "ReferenceError:", "Binding loop", "Cannot assign"):
            self.assertNotIn(issue, log)

    def call(self, method, *args, check=True):
        result = safety.ipc(self.proc, ["quickshell", "ipc", "--pid", str(self.proc.pid), "call", "--", "folders-test", method, *map(str, args)], capture_output=True, text=True, timeout=3)
        if not check and (result.returncode or not result.stdout.strip().startswith("{")):
            return None
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        return json.loads(result.stdout) if result.stdout.strip() else None

    def settled(self):
        for _ in range(100):
            state = self.call("state")
            if not state["busy"]:
                return state
            time.sleep(.02)
        self.fail("scan did not settle")

    def test_production_ui_service_launch_lifecycle(self):
        (self.folder / "entry.txt").write_text("owned")
        self.assertGreater(self.call("save", self.folder), 0)
        state = self.call("integrated")
        self.assertFalse(state["open"])
        self.assertFalse(state["pending"], "save must not launch")
        self.call("click")
        for _ in range(100):
            state = self.call("integrated")
            if state["open"] and not state["busy"]:
                break
            time.sleep(.02)
        self.assertEqual(state["result"]["total"], 1)
        self.call("manager")
        state = self.call("integrated")
        self.assertFalse(state["open"])
        self.assertTrue(state["pending"], "explicit action must reach AppService launch lifecycle")
        self.assertEqual(state["result"], {})

    def test_real_ui_to_launcher_receipt(self):
        self.assertGreater(self.call("save", self.folder), 0)
        for _ in range(100):
            if self.call("integrated")["records"] == 1:
                break
            time.sleep(.02)
        receipt = self.root / "receipt.json"
        self.assertFalse(receipt.exists())
        self.call("click")
        for _ in range(100):
            if not self.call("integrated")["busy"]:
                break
            time.sleep(.02)
        self.call("manager")
        for _ in range(100):
            if receipt.exists() and not self.call("integrated")["pending"]:
                break
            time.sleep(.02)
        self.assertEqual(json.loads(receipt.read_text()), [str(self.folder)])
        self.assertFalse(self.call("integrated")["open"])
        self.assertFalse(self.call("integrated")["pending"])
        self.assertEqual(json.loads((self.root / "pins.json").read_text())["launchers"][0]["target"], str(self.folder))

    def test_folder_settings_presets_and_no_implicit_launch(self):
        self.assertGreater(self.call("toggle", self.folder), 0)
        for color in ("theme", "symbolic", "white", "black", "Yaru-sage", "Yaru-olive", "Yaru-blue", "Yaru-purple", "Yaru-magenta", "Yaru-red", "Yaru-yellow", "Yaru-wartybrown", "Yaru-prussiangreen", "Yaru-dark"):
            self.assertGreater(self.call("color", color), 0)
            self.assertEqual(self.call("settings")["folderColor"], color)
            item = self.call("items")[0]
            self.assertEqual(item["folderTint"], color if color in ("white", "black") else "")
            self.assertEqual(bool(item["folderIconCandidate"]), color.startswith("Yaru-"))
        self.assertGreater(self.call("toggle", self.folder), 0)
        self.assertEqual(self.call("color", "arbitrary/path"), 0)
        self.assertGreater(self.call("toggle", str(self.folder) + "/"), 0)
        self.assertEqual(self.call("integrated")["records"], 1)
        self.assertFalse(self.call("integrated")["pending"])
        self.assertGreater(self.call("toggle", self.folder), 0)
        self.assertEqual(self.call("integrated")["records"], 0)

    def test_signed_timestamps_and_unicode_ties_through_real_service(self):
        values = {'positive': 1000000000, 'zero': 0, 'negative': -1000000000,
                  'ancient': -315619200000000000, '\ue000': -2000000000, '\U00010000': -2000000000}
        for name, ns in values.items():
            child = self.folder / name
            child.write_text('owned')
            os.utime(child, ns=(ns, ns))
            self.assertEqual(child.stat().st_mtime_ns, ns)
        wire = subprocess.run(['/usr/bin/python3', str(ROOT/'services/folder_scan.py')],
            input=json.dumps({'path':str(self.folder),'generation':1,'token':'signed'}),
            capture_output=True, text=True, timeout=3)
        self.assertEqual(wire.returncode, 0, wire.stderr)
        self.call('open', self.folder)
        result = self.settled()['result']
        self.assertEqual(result['status'], 'ok')
        expected = sorted(values, key=lambda name: (-values[name], name))
        self.assertEqual([e['name'] for e in result['entries']], expected)
        self.assertEqual([e['name'] for e in json.loads(wire.stdout)['entries']], expected)
        self.assertEqual([e['mtimeNs'] for e in result['entries']], [str(values[n]) for n in expected])

    def test_real_recent_metadata_and_stale_action(self):
        for i in range(18):
            path = self.folder / f"item {i:02d}.png"
            path.write_text("owned")
            os.utime(path, (1700000000 + i, 1700000000 + i))
        (self.folder / ".private").write_text("hidden")
        self.assertTrue(self.call("open", self.folder))
        state = self.settled()
        self.assertEqual(state["result"]["total"], 18)
        self.assertEqual(len(state["result"]["entries"]), 16)
        self.assertEqual(state["result"]["entries"][0]["name"], "item 17.png")
        self.assertTrue(state["result"]["entries"][0].get("iconUrl", "").startswith("image://"))
        path = state["result"]["entries"][0]["path"]
        action = self.call("action", "entry", path, state["generation"])
        self.assertEqual(action["target"], path)
        self.assertEqual(action["rootIdentity"], state["result"]["rootIdentity"])
        self.call("close")
        self.assertIsNone(self.call("action", "entry", path, state["generation"]))
        self.assertEqual(self.call("state")["result"], {})

    def test_missing_unreadable_large_and_rapid_switch_close(self):
        for i in range(513):
            (self.folder / str(i)).touch()
        self.call("open", self.folder)
        state = self.settled()
        self.assertEqual(state["result"]["status"], "too-large")
        self.assertNotIn("total", state["result"])
        missing = self.root / "missing"
        self.call("open", missing)
        self.assertEqual(self.settled()["result"]["status"], "missing")
        unreadable = self.root / "unreadable"
        unreadable.mkdir(mode=0)
        try:
            self.call("open", unreadable)
            self.assertEqual(self.settled()["result"]["status"], "unreadable")
        finally:
            unreadable.chmod(0o700)
        for _ in range(8):
            self.call("switchClose", self.folder, missing)
        time.sleep(.4)
        self.assertFalse(self.call("state")["opened"])
        self.assertEqual(self.call("state")["result"], {})
        self.call("open", unreadable)
        self.assertEqual(self.settled()["result"]["status"], "empty")

class FolderFailedStartTests(unittest.TestCase):
    def test_failed_start_is_bounded_and_reopen_recovers(self):
        # Own only the Process transport; keep production controller and timer.
        with tempfile.TemporaryDirectory(prefix="omadocked-folder-start-") as directory:
            root = Path(directory)
            for name in ("FolderLogic.js", "LauncherLogic.js"):
                shutil.copy2(ROOT / "services" / name, root / name)
            source = (ROOT / "services/FolderService.qml").read_text()
            source = source.replace("import Quickshell.Io\n", "").replace("import Quickshell\n", "")
            (root / "FolderService.qml").write_text(source)
            (root / "Process.qml").write_text('''import QtQuick
QtObject {
    property var command: []
    property bool running: false
    property bool stdinEnabled: true
    property QtObject stdout
    property int attempts: 0
    property bool failStart: true
    property int lastSignal: 0
    signal exited(int code, int status)
    onRunningChanged: if (running) { attempts++; if (failStart) Qt.callLater(() => running = false); }
    function write(text) {}
    function signal(number) { lastSignal = number; }
}
''')
            (root / "StdioCollector.qml").write_text('import QtQuick\nQtObject { property string text: "" }\n')
            (root / "tst_failed_start.qml").write_text('''import QtQuick
import QtTest
TestCase {
    name: "FolderFailedStart"
    FolderService { id: folders }
    function test_failed_start_and_retry() {
        verify(folders.open("owned", "/owned"));
        tryCompare(folders, "busy", false, 6500);
        compare(folders.result.status, "unreadable");
        verify(folders.result.message.indexOf("Try again") >= 0);
        verify(folders._active === null);
        compare(folders._process.attempts, 1);
        folders.close();
        verify(folders.open("retry", "/owned"));
        tryCompare(folders, "busy", false, 6500);
        compare(folders._process.attempts, 2);
        compare(folders.result.status, "unreadable");
        folders.open("old", "/owned");
        folders.close();
        folders.open("new", "/new");
        tryCompare(folders, "busy", false, 12500);
        compare(folders.launcherId, "new");
        compare(folders._process.attempts, 4);
        folders.close();
        compare(JSON.stringify(folders.result), "{}");
        // A running child is killed exactly once and fenced until its exit.
        folders._deadline.interval = 30;
        folders._process.failStart = false;
        folders.open("hung", "/hung");
        tryCompare(folders, "busy", false, 1000);
        compare(folders._process.lastSignal, 9);
        verify(folders._retiring);
        const attempts = folders._process.attempts;
        folders.open("replacement", "/replacement");
        compare(folders._process.attempts, attempts);
        folders._process.exited(9, 1);
        compare(folders._process.attempts, attempts + 1);
        compare(folders._active.generation, folders.generation);
        compare(JSON.stringify(folders.result), "{}");
        folders._process.running = false;
        folders._process.exited(1, 0);
        compare(folders.busy, false);
        compare(folders.result.status, "unreadable");
        verify(!folders._deadline.running);
        folders.close();
    }
}
''')
            env = dict(safety.fixture_environment(), QT_QPA_PLATFORM="offscreen")
            proc = safety.spawn(["/usr/lib/qt6/bin/qmltestrunner", "-input", str(root), "-o", "-,txt"], required="offscreen", root=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            try:
                output, _ = proc.communicate(timeout=35)
            finally:
                if proc.poll() is None:
                    proc.kill(); proc.wait(timeout=3)
            self.assertEqual(proc.returncode, 0, output)
            for issue in ("TypeError:", "ReferenceError:", "Binding loop", "Cannot assign"):
                self.assertNotIn(issue, output)


if __name__ == "__main__":
    unittest.main()
