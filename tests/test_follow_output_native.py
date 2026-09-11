"""Exact controller + surface bridges with owned native-shaped outputs, no layers."""
import json
import shutil
import time
import test_app_service as base


class FollowOutputNativeTests(base.AppServiceTests):
    def test_controller_routing_and_durable_preference(self):
        surface = (base.ROOT / "DockSurface.qml").read_text()
        self.assertIn("readonly property bool outputRoutingLocked:", surface)
        for name in ("Dock.qml",):
            shutil.copy2(base.ROOT / name, self.root / name)
        shutil.copytree(base.ROOT / "ui", self.root / "ui")
        self.fake_native_source()
        path = self.root / "Dock.qml"
        source = path.read_text().replace("Quickshell.screens", "root.ownedScreens").replace("backend: Hyprland", "backend: root.ownedBackend")
        source = source.replace("    id: root", '''    id: root
    property QtObject leftOutput: QtObject { property string name: "left" }
    property QtObject rightOutput: QtObject { property string name: "right" }
    property var ownedScreens: [leftOutput,rightOutput]
    property QtObject ownedBackend: QtObject { property QtObject focusedMonitor: root.leftOutput }
''', 1)
        path.write_text(source)
        lock = next(line for line in surface.splitlines() if "readonly property bool outputRoutingLocked:" in line)
        bindings = "\n".join(line for line in surface.splitlines() if any(line.strip().startswith(k+":") for k in
            ("followActiveOutput", "onFollowActiveOutputRequested", "monitorMode", "selectedOutputs")))
        # Replace native window only; preserve exact routing lock and preference
        # bridges, real DockView and native Variants delegate ownership.
        (self.root / "DockSurface.qml").write_text('''import QtQuick
import "ui"
Item {
    id: root
    required property var outputScreen
    required property var controller
    readonly property string outputName: outputScreen.name
    property bool mapped: controller.surfaceEnabled && controller.activeOutputs.indexOf(outputScreen.name)>=0
    readonly property bool attentionVisible:false
LOCK
    function releaseInteractions() { view.releaseInteractions(); }
    function setSettingsOpen(value) { view.settingsOpen=value; return true; }
    function toggle() { view.followActiveOutputRequested(!view.followActiveOutput); }
    onMappedChanged: if (!mapped) view.resetSurface()
    DockView { id:view; settingsManaged:true; BINDINGS }
}'''.replace("LOCK",lock).replace("BINDINGS",bindings))
        (self.root / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    Dock { id:dock; surfaceEnabled:true }
    IpcHandler {
        target:"app-test"
        function snapshot(): string { return JSON.stringify({ready:dock.ready,active:dock.activeOutputs,follow:dock.followActiveOutput,mode:dock.monitorMode,names:dock.selectedOutputs}); }
        function follow(value:bool): int { return dock.setFollowActiveOutput(value); }
        function monitors(): int { return dock.monitors("selected", '["left","missing"]'); }
        function policy(mode:string, names:string): int { return dock.monitors(mode,names); }
        function focus(right:bool): bool { dock.ownedBackend.focusedMonitor=right?dock.rightOutput:dock.leftOutput; return true; }
        function outputs(which:int): bool { dock.ownedScreens=which===0?[]:which===1?[dock.leftOutput]:[dock.leftOutput,dock.rightOutput]; return true; }
        function popup(value:bool): bool { return dock.settings("left",value); }
    }
}''')
        self.start(test_mode="0", extra_env={"QT_QPA_PLATFORM":"offscreen"}, wrapped=False)
        def settle(expected):
            deadline=time.monotonic()+4
            while time.monotonic()<deadline:
                s=self.call("snapshot")
                if s["active"]==expected: return s
                time.sleep(.02)
            self.fail(str(s))
        self.assertFalse(settle(["left","right"])["follow"])
        # Follow-off All reconnects while the existing left Settings owns a lock.
        self.call("outputs","1"); settle(["left"])
        self.assertTrue(self.call("popup","true"))
        self.call("outputs","2"); settle(["left","right"])
        # Committed Selected policy and reconnects must also bypass follow locks.
        self.assertGreater(self.call("policy","selected",json.dumps(["left","right"])),0)
        time.sleep(.1)
        self.assertEqual(self.call("snapshot")["mode"],"selected")
        self.call("outputs","1"); settle(["left"])
        self.call("outputs","2"); settle(["left","right"])
        self.assertGreater(self.call("policy","selected",json.dumps(["right"])),0)
        settle(["right"])
        self.assertGreater(self.call("policy","all","[]"),0); settle(["left","right"])
        self.assertTrue(self.call("popup","true"))
        self.assertGreater(self.call("policy","selected",json.dumps(["missing"])),0); settle([])
        self.assertGreater(self.call("policy","all","[]"),0); settle(["left","right"])
        self.assertTrue(self.call("popup","true"))
        self.call("outputs","0"); settle([])
        self.call("outputs","2"); settle(["left","right"])
        # Enable retains interacting base routes; release settles to latest focus.
        self.assertTrue(self.call("popup","true"))
        self.call("focus","true")
        self.assertGreater(self.call("follow","true"),0); time.sleep(.1)
        self.assertTrue(self.call("snapshot")["follow"])
        self.assertEqual(self.call("snapshot")["active"],["left","right"])
        self.call("popup","false"); settle(["right"])
        self.call("focus","false"); settle(["left"])
        self.assertTrue(self.call("popup","true"))
        self.assertGreater(self.call("follow","false"),0); settle(["left","right"])
        self.call("popup","false")
        self.assertGreater(self.call("monitors"),0)
        settle(["left"])
        self.assertGreater(self.call("follow","true"),0)
        time.sleep(.1)
        self.assertTrue(self.call("popup","true"))
        self.call("focus","true"); time.sleep(.1)
        self.assertEqual(self.call("snapshot")["active"],["left"])
        self.call("popup","false"); settle(["right"])
        self.call("outputs","1"); settle(["left"])
        self.call("outputs","0"); settle([])
        self.call("outputs","2"); settle(["right"])
        saved=json.loads(self.config.read_text())["settings"]
        self.assertTrue(saved["followActiveOutput"])
        self.assertEqual(saved["monitorMode"],"selected")
        self.assertEqual(saved["selectedOutputs"],["left","missing"])
        self.stop()
        self.start(test_mode="0", extra_env={"QT_QPA_PLATFORM":"offscreen"}, wrapped=False)
        self.assertTrue(settle(["left"])["follow"])
        before=self.config.read_bytes(); self.config.chmod(0o444)
        self.call("follow","false"); time.sleep(.15)
        self.assertTrue(self.call("snapshot")["follow"])
        self.assertEqual(self.config.read_bytes(),before)
        self.config.chmod(0o600)
        self.stop()
        self.start(test_mode="0", extra_env={"QT_QPA_PLATFORM":"offscreen"}, wrapped=False)
        self.assertGreater(self.call("follow","false"),0); time.sleep(.15)
        self.assertFalse(settle(["left"])["follow"])
        self.assertEqual(self.call("snapshot")["names"],["left","missing"])


for _name in dir(base.AppServiceTests):
    if _name.startswith("test_"):
        setattr(FollowOutputNativeTests, _name, None)
