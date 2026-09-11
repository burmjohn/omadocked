"""Exercise the production sound Process using an owned non-audio executable."""
import json
import os
import time
import signal
from pathlib import Path
import test_app_service as base


class AttentionSoundTests(base.AppServiceTests):
    def _prepare_lifecycle(self):
        self.owned_players = []
        self.player = self.root / "canberra-gtk-play"
        self.receipt = self.root / "owned-player.json"
        self.player.write_text('#!/usr/bin/python3\nimport json,os,signal,time\nfrom pathlib import Path\n'
                               'signal.signal(signal.SIGTERM, signal.SIG_IGN)\n'
                               'pid=os.getpid()\n'
                               'Path(os.environ["OWNED_PLAYER_RECEIPT"]).write_text(json.dumps([pid, Path(f"/proc/{pid}/stat").read_text().split()[21]]))\n'
                               'time.sleep(60)\n')
        self.player.chmod(0o700)
        shell = (self.root / "shell.qml").read_text().replace('AppService { id: apps }', '''AppService { id: apps }
    Loader { id: soundLoader; source: "services/AttentionSound.qml" }''')
        shell = shell.replace('target: "app-test"', '''target: "app-test"
        function soundState(): string { return JSON.stringify({loaded:!!soundLoader.item,
            status:soundLoader.item ? soundLoader.item.status : "missing",
            busy:soundLoader.item ? soundLoader.item.busy : false,
            pid:soundLoader.item ? soundLoader.item.playback.processId : 0}); }
        function soundAllow(value: bool): bool { soundLoader.item.allowed=value; return true; }
        function play(name: string): bool { return soundLoader.item.play(name); }
        function unloadSound(): bool { soundLoader.active=false; return true; }
        function playAndCancel(): bool { const accepted=soundLoader.item.play("bell"); soundLoader.item.allowed=false; return accepted; }
        function lateExit(): bool { soundLoader.item.playback.exited(9, 1); return true; }
        function reloadSound(): bool { soundLoader.active=true; return true; }''')
        (self.root / "shell.qml").write_text(shell)
        self.start(extra_env={"PATH":str(self.root) + ":" + os.environ["PATH"],
                              "OWNED_PLAYER_RECEIPT":str(self.receipt)})
        self._wait_sound(lambda s: s["status"] != "checking")
        self.assertEqual(self.call("soundState")["status"], "available")
        self.call("soundAllow", "true")

    def _wait_sound(self, predicate, timeout=3):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            state = self.call("soundState")
            if predicate(state):
                return state
            time.sleep(.02)
        self.fail(f"sound state did not settle: {state}")

    def _start_resistant(self):
        self.receipt.unlink(missing_ok=True)
        self.assertTrue(self.call("play", "bell"))
        deadline = time.monotonic() + 2
        while not self.receipt.exists() and time.monotonic() < deadline:
            time.sleep(.02)
        identity = json.loads(self.receipt.read_text())
        self.owned_players.append(identity)
        self.assertEqual(self.call("soundState")["pid"], identity[0])
        return identity

    def _assert_gone(self, identity, timeout=1):
        deadline = time.monotonic() + timeout
        while Path(f"/proc/{identity[0]}").exists() and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertFalse(Path(f"/proc/{identity[0]}").exists(), f"owned player survived: {identity}")

    def tearDown(self):
        # Failures must not leave resistant fixtures behind. Match PID AND start
        # time, never a process name or a PID whose ownership has expired.
        try:
            identities = list(getattr(self, "owned_players", []))
            if hasattr(self, "receipt") and self.receipt.exists():
                identities.append(json.loads(self.receipt.read_text()))
            for pid, started in identities:
                stat = Path(f"/proc/{pid}/stat")
                if stat.exists() and stat.read_text().split()[21] == started:
                    os.kill(pid, signal.SIGKILL)
                    self._assert_gone([pid, started])
        finally:
            super().tearDown()

    def _prepare_sample(self, exit_code=0):
        import re
        import shutil
        source = base.ROOT
        controller = (source / "Dock.qml").read_text()
        surface = (source / "DockSurface.qml").read_text()
        method = re.search(r'    function sampleSound\(\): bool \{[^\n]+\}', controller)
        self.assertIsNotNone(method, "production controller sample route required")
        route = re.search(r'            onSoundSampleRequested: [^\n]+', surface)
        self.assertIsNotNone(route, "production surface sample route required")
        gate = re.search(r'        allowed: root.attentionAllowed[^\n]+\n[^\n]+', controller)
        self.assertIsNotNone(gate, "existing production playback gate required")
        shutil.copytree(source / "ui", self.root / "ui")
        player = self.root / "canberra-gtk-play"
        self.sample_receipt = self.root / "sample.json"
        player.write_text('#!/usr/bin/python3\nimport json,os,sys,time\nfrom pathlib import Path\n'
                          'Path(os.environ["SAMPLE_RECEIPT"]).write_text(json.dumps(sys.argv[1:]))\n'
                          f'time.sleep(.3)\nsys.exit({exit_code})\n')
        player.chmod(0o700)
        # Preserve the production controller method, surface signal forwarding,
        # service, UI control and player. Only host authorities are owned QObjects.
        shell = (self.root / "shell.qml").read_text().replace('import "services"', 'import "services"\nimport "ui"\nimport QtTest')
        shell = shell.replace('AppService { id: apps }', '''AppService { id: apps }
    property bool mapped: true
    property bool unlocked: true
    property bool optedIn: false
    readonly property bool attentionAllowed: mapped && unlocked
    readonly property bool attentionVisible: mapped
    readonly property string previewLockState: unlocked ? "unlocked" : "unknown"
    readonly property bool urgentSound: optedIn
    property bool testMode: false
    property QtObject host: QtObject {
        property ListModel popupModel: ListModel {}
        property bool settingsLoaded: true
        property bool doNotDisturb: false
        function isRestoredRow(row) { return false; }
    }
    QtObject { id: ownedShell; function serviceFor(id) { return probe.host; } }
    QtObject { id: registry; function resolveEnabledId(id) { return id; } }
    AttentionService {
        id: attention; hostShell: ownedShell; pluginRegistry: registry
        enabled: probe.mapped && probe.unlocked
        urgentSound: probe.optedIn; urgentSoundName: view.urgentSoundName
        soundPlayer: sound
    }
    AttentionSound {
        id: sound
''' + gate.group().replace('root.', 'probe.') + '''
    }
    QtObject { id: controller
''' + method.group() + '''
    }
    DockView {
        id: view; settingsOpen: true; autoHide: false; reducedMotion: true
        urgentSound: probe.optedIn
        soundSampleStatus: attention.soundSampleStatus
''' + route.group().replace('root.controller', 'controller') + '''
    }
    TestCase { id: tester; when: false }
    function childNamed(item, name) { return tester.findChild(item, name); }
''')
        shell = shell.replace('target: "app-test"', '''target: "app-test"
        function soundState(): string { return JSON.stringify({status:attention.soundSampleStatus,
            busy:sound.busy, enabled:probe.childNamed(view,"urgent-sound-sample").enabled}); }
        function sample(): bool { return controller.sampleSound(); }
        function pressSample(): bool { probe.childNamed(view,"urgent-sound-sample").Accessible.pressAction(); return true; }
        function gate(name: string, value: bool): bool {
            if (name === "dnd") probe.host.doNotDisturb=value;
            else if (name === "known") probe.host.settingsLoaded=value;
            else probe[name]=value;
            return true;
        }
        function sampleName(name: string): bool { view.urgentSoundName=name; return true; }
        function reopen(): bool { view.settingsOpen=false; view.settingsOpen=true; return true; }
''')
        (self.root / "shell.qml").write_text(shell)
        self.start(extra_env={"PATH":str(self.root) + ":" + os.environ["PATH"],
                              "SAMPLE_RECEIPT":str(self.sample_receipt)})

    def test_sample_production_control_receipt_gates_and_cooldown(self):
        self._prepare_sample()
        self.assertFalse(self.call("sample"))
        self.call("gate", "optedIn", "true")
        self._wait_sound(lambda s: s["status"] == "ready")
        self.call("sampleName", "complete")
        self.call("reopen")
        self.assertFalse(self.sample_receipt.exists(), "open/enable/select never play")
        for gate in ("mapped", "unlocked", "known", "dnd", "testMode"):
            blocked = "true" if gate in ("dnd", "testMode") else "false"
            self.call("gate", gate, blocked)
            self.assertFalse(self.call("sample"), gate)
            self.assertFalse(self.call("soundState")["enabled"], gate)
            self.call("gate", gate, "false" if gate in ("dnd", "testMode") else "true")
        for name in ("none", "bell; touch nope"):
            self.call("sampleName", name)
            self.assertFalse(self.call("sample"))
        self.call("sampleName", "complete")
        self.call("pressSample")
        self._wait_sound(lambda s: s["busy"])
        self.assertFalse(self.call("sample"), "busy request refused without queue")
        self._wait_sound(lambda s: not s["busy"])
        self.assertEqual(json.loads(self.sample_receipt.read_text()), ["--id", "complete", "--loop", "1"])
        self.assertEqual(self.call("soundState")["status"], "cooldown: wait briefly")
        self.assertFalse(self.call("sample"))
        self._wait_sound(lambda s: s["status"] == "ready")
        self.sample_receipt.unlink()
        time.sleep(.1)
        self.assertFalse(self.sample_receipt.exists(), "no queued replay")

    def test_sample_production_control_reports_player_failure(self):
        self._prepare_sample(exit_code=7)
        self.call("gate", "optedIn", "true")
        self._wait_sound(lambda s: s["status"] == "ready")
        self.call("pressSample")
        state = self._wait_sound(lambda s: "playback failed" in s["status"])
        self.assertFalse(state["enabled"])
        self.assertFalse(self.call("sample"))
        self.assertEqual(json.loads(self.sample_receipt.read_text()), ["--id", "bell", "--loop", "1"])

    def test_sample_production_control_reports_failed_start(self):
        self._prepare_sample()
        self.call("gate", "optedIn", "true")
        self._wait_sound(lambda s: s["status"] == "ready")
        (self.root / "canberra-gtk-play").unlink()
        self.call("pressSample")
        state = self._wait_sound(lambda s: "failed to start" in s["status"])
        self.assertFalse(state["enabled"])
        self.assertFalse(state["busy"])
        self.assertFalse(self.sample_receipt.exists())
        self.assertFalse(self.call("sample"))

    def test_resistant_cancel_then_second_timeout_and_late_exits(self):
        self._prepare_lifecycle()
        first = self._start_resistant()
        self.call("soundAllow", "false")
        self._assert_gone(first)
        self._wait_sound(lambda s: not s["busy"])
        self.call("lateExit")
        self.call("lateExit")
        self.assertEqual(self.call("soundState")["status"], "available")
        time.sleep(2.1)
        self.call("soundAllow", "true")
        second = self._start_resistant()
        # An old/duplicate terminal callback must not terminalize a new child.
        self.call("lateExit")
        self.assertTrue(self.call("soundState")["busy"])
        self.assertEqual(self.call("soundState")["status"], "available")
        self._wait_sound(lambda s: not s["busy"], timeout=2.7)
        self._assert_gone(second)
        self.assertEqual(self.call("soundState")["status"], "unavailable: sound playback timed out")
        self.call("lateExit")
        self.assertEqual(self.call("soundState")["status"], "unavailable: sound playback timed out")

    def test_cancel_before_spawn_acknowledgement(self):
        self._prepare_lifecycle()
        self.assertTrue(self.call("playAndCancel"))
        state = self._wait_sound(lambda s: not s["busy"], timeout=1)
        self.assertEqual(state["status"], "available")
        self.call("lateExit")
        self.assertEqual(self.call("soundState"), state)

    def test_resistant_unload(self):
        self._prepare_lifecycle()
        identity = self._start_resistant()
        self.call("unloadSound")
        self._assert_gone(identity)
        self.assertFalse(self.call("soundState")["loaded"])
        self.call("reloadSound")
        self._wait_sound(lambda s: s["status"] != "checking")
        self.assertEqual(self.call("soundState")["status"], "available")
        self.assertFalse(self.call("soundState")["busy"])

    def _failed_start(self, mode):
        self._prepare_lifecycle()
        if mode == "missing":
            self.player.unlink()
        elif mode == "permission":
            self.player.chmod(0o600)
        else:
            self.player.write_text("#!/owned-missing-interpreter\n")
        self.assertTrue(self.call("play", "bell"), "true means accepted, not spawn acknowledged")
        state = self._wait_sound(lambda s: not s["busy"], timeout=1.5)
        self.assertEqual(state["status"], "unavailable: sound player failed to start")
        self.assertFalse(self.call("play", "bell"))
        self.assertFalse(self.receipt.exists(), "fixture executable never started")
        self.call("lateExit")
        self.call("lateExit")
        self.assertEqual(self.call("soundState"), state)

    def test_player_disappears_after_discovery(self):
        self._failed_start("missing")

    def test_player_loses_execute_permission_after_discovery(self):
        self._failed_start("permission")

    def test_player_interpreter_missing_after_discovery(self):
        self._failed_start("interpreter")

    def test_missing_player_is_explicit_and_inert(self):
        (self.root / "sh").symlink_to("/usr/bin/sh")
        (self.root / "quickshell").symlink_to("/usr/bin/quickshell")
        shell = (self.root / "shell.qml").read_text().replace('AppService { id: apps }', '''AppService { id: apps }
    AttentionSound { id: sound; allowed:true }''')
        shell = shell.replace('target: "app-test"', '''target: "app-test"
        function soundState(): string { return JSON.stringify({status:sound.status, busy:sound.busy}); }
        function play(name: string): bool { return sound.play(name); }''')
        (self.root / "shell.qml").write_text(shell)
        self.start(extra_env={"PATH":str(self.root)})
        deadline = time.monotonic() + 3
        while self.call("soundState")["status"] == "checking" and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertEqual(self.call("soundState")["status"], "unavailable: canberra-gtk-play missing")
        self.assertFalse(self.call("play", "bell"))
        self.assertFalse(self.call("soundState")["busy"])

    def test_sound_argv_gate_and_cancel(self):
        player = self.root / "canberra-gtk-play"
        receipt = self.root / "sound-receipt.json"
        player.write_text('#!/usr/bin/python3\nimport json,os,sys,time\nfrom pathlib import Path\n'
                          'Path(os.environ["FIXTURE_SOUND_RECEIPT"]).write_text(json.dumps(sys.argv[1:]))\n'
                          'time.sleep(5)\n')
        player.chmod(0o700)
        shell = (self.root / "shell.qml").read_text().replace('AppService { id: apps }', '''AppService { id: apps }
    Loader { id: soundLoader; source: "services/AttentionSound.qml" }''')
        shell = shell.replace('target: "app-test"', '''target: "app-test"
        function soundState(): string { return JSON.stringify({loaded:!!soundLoader.item,
            status:soundLoader.item ? soundLoader.item.status : "missing",
            busy:soundLoader.item ? soundLoader.item.busy : false,
            pid:soundLoader.item ? soundLoader.item.playback.processId : 0}); }
        function soundAllow(value: bool): bool { soundLoader.item.allowed=value; return true; }
        function play(name: string): bool { return soundLoader.item.play(name); }
        function unloadSound(): bool { soundLoader.active=false; return true; }''')
        shell = shell.replace('function unloadSound()', 'function reloadSound(): bool { soundLoader.active=true; return true; }\n        function unloadSound()')
        (self.root / "shell.qml").write_text(shell)
        self.start(extra_env={"PATH":str(self.root) + ":" + os.environ["PATH"],
                              "FIXTURE_SOUND_RECEIPT":str(receipt)})
        self.assertTrue(self.call("soundState")["loaded"])
        deadline = time.monotonic() + 3
        while self.call("soundState")["status"] == "checking" and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertEqual(self.call("soundState")["status"], "available")
        self.assertFalse(self.call("play", "bell"))
        self.call("soundAllow", "true")
        self.assertFalse(self.call("play", "none"))
        self.assertFalse(self.call("play", "bell; touch injected"))
        self.assertTrue(self.call("play", "bell"))
        deadline = time.monotonic() + 3
        while not receipt.exists() and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertEqual(json.loads(receipt.read_text()), ["--id", "bell", "--loop", "1"])
        self.assertFalse(self.call("play", "bell"), "one owned process, no queue")
        pid = self.call("soundState")["pid"]
        self.call("soundAllow", "false")
        self._wait_sound(lambda s: not s["busy"], timeout=1)
        self.assertFalse(self.call("soundState")["busy"])
        deadline = time.monotonic() + 3
        while os.path.exists(f"/proc/{pid}") and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertFalse(os.path.exists(f"/proc/{pid}"), "hide/lock cancels exact owned player")
        time.sleep(2.1)
        self.call("soundAllow", "true")
        self.assertTrue(self.call("play", "dialog-information"))
        deadline = time.monotonic() + 4
        while self.call("soundState")["busy"] and time.monotonic() < deadline:
            time.sleep(.03)
        self.assertFalse(self.call("soundState")["busy"], "second playback also has a deadline")
        self.assertTrue(self.call("soundState")["status"].startswith("unavailable:"))
        self.call("unloadSound")
        self.assertFalse(self.call("soundState")["loaded"])
        self.call("reloadSound")
        deadline = time.monotonic() + 3
        while self.call("soundState")["status"] == "checking" and time.monotonic() < deadline:
            time.sleep(.02)
        self.call("soundAllow", "true")
        self.assertTrue(self.call("play", "bell"))
        pid = self.call("soundState")["pid"]
        self.assertGreater(pid, 0)
        self.call("unloadSound")
        deadline = time.monotonic() + 3
        while os.path.exists(f"/proc/{pid}") and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertFalse(os.path.exists(f"/proc/{pid}"), "unload cancels the exact active player")


for _name in dir(base.AppServiceTests):
    if _name.startswith("test_"):
        setattr(AttentionSoundTests, _name, None)
