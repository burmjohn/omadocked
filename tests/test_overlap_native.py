"""Owned persisted preference and shared native adapter integration; no mapped layers."""
import json
import test_app_service as base


class OverlapPersistenceTests(base.AppServiceTests):
    def test_shared_production_bridge(self):
        import shutil
        surface = (base.ROOT / "DockSurface.qml").read_text()
        self.assertIn("readonly property var overlapPolicy:", surface)
        self.assertIn("onPointerInsideChanged:", surface)
        self.assertIn("onOverTriggerChanged:", surface)
        for name in ("Dock.qml", "DockSurface.qml"):
            shutil.copy2(base.ROOT / name, self.root / name)
        shutil.copytree(base.ROOT / "ui", self.root / "ui")
        dock = self.root / "Dock.qml"
        dock.write_text(dock.read_text().replace("Quickshell.screens", "[]"))
        # Offscreen has no PanelWindow backend. This never-instantiated delegate
        # substitutes only the native surface type; its production bridges below
        # are exercised verbatim in the owned Qt Window.
        (self.root / "DockSurface.qml").write_text("import QtQuick\nItem { required property var outputScreen; required property var controller }")
        self.fake_native_source()
        # Replace only the transport with owned acknowledged projections; the
        # real Socket is independently exercised against a private Unix server.
        (self.root / "services/OverlapSnapshot.qml").write_text('''import QtQuick
QtObject {
    id: root
    required property var source
    required property var backend
    property string socketPath
    property Connections requests: Connections {
        target: root.source
        function onRequested(generation) {
            root.backend.refreshToplevels();
            root.source.complete(generation, true, {
                monitors:root.backend.monitors.values.map(m=>({name:m.name,x:m.x,y:m.y,workspace:m.activeWorkspace.id,special:m.lastIpcObject.specialWorkspace.id})),
                windows:root.backend.toplevels.values.map(w=>({workspace:w.workspace.id,monitor:w.monitor.name,mapped:w.lastIpcObject.mapped,
                    hidden:w.lastIpcObject.hidden,pinned:w.lastIpcObject.pinned,fullscreen:w.wayland.fullscreen,
                    x:w.lastIpcObject.at[0],y:w.lastIpcObject.at[1],width:w.lastIpcObject.size[0],height:w.lastIpcObject.size[1]}))
            });
        }
    }
}''')
        path = self.root / "services/LiveApps.qml"
        source = path.read_text().replace("backend: Hyprland", "backend: ownedBackend")
        source = source.replace("QtObject {", '''QtObject {
    property QtObject ownedBackend: QtObject {
        property QtObject monitors: QtObject { property var values: [ownedMonitor] }
        property QtObject toplevels: QtObject { property var values: [ownedWindow] }
        signal rawEvent(var event)
        property int refreshes:0
        function refreshToplevels() { refreshes++; }
        function refreshMonitors() {}
        function refreshWorkspaces() {}
    }
    property QtObject ownedMonitor: QtObject {
        property string name: "owned"
        property int x: -1200
        property int y: -100
        property QtObject activeWorkspace: QtObject { property int id: 1 }
        property var lastIpcObject: ({specialWorkspace:{id:0}})
    }
    property QtObject ownedWindow: QtObject {
        property var workspace: ownedMonitor.activeWorkspace
        property var monitor: ownedMonitor
        property QtObject wayland: QtObject { property bool fullscreen:false; property bool minimized:false }
        property var lastIpcObject: ({mapped:true,hidden:false,pinned:false,at:[-1200,400],size:[1200,300],fullscreen:0})
    }
''', 1)
        path.write_text(source)
        # Exact production per-output geometry and input bindings, hosted inside
        # an owned offscreen Window, never instantiate a native layer surface.
        start = surface.index("    readonly property var overlapPolicy:")
        end = surface.index("    readonly property bool popupReady:", start)
        bridge = surface[start:end]
        consumer_start = surface.index("    OverlapConsumer {")
        consumer_end = surface.index("    readonly property var overlapPolicy:", consumer_start)
        bridge = surface[consumer_start:consumer_end] + bridge
        bindings = "\n".join(line for line in surface.splitlines() if any(line.strip().startswith(key + ":") for key in
            ("reserveSpace", "onReserveSpaceRequested", "intelligentHide", "nativeOverlapAvailable", "nativeOverlap", "nativeFullscreen", "onPointerInsideChanged", "onOverTriggerChanged", "onIntelligentHideRequested")))
        zone = next(line.strip() for line in surface.splitlines() if line.strip().startswith("exclusiveZone:"))
        shell = '''import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "services"
import "ui"
ShellRoot {
    Dock { id: dock }
    Window {
        id: root
        visible:true; width:1200; height:800
        property var controller: dock
        property string outputName:"owned"
        property bool mapped:true
        QtObject { id: panel; property bool backingWindowVisible:true; property int ZONE }
        property QtObject outputScreen: QtObject { property int width:1200; property int height:800 }
BRIDGE
        DockView { id: view; settingsManaged:true; autoHide:true; reducedMotion:true; BINDINGS }
    }
    IpcHandler {
        target:"app-test"
        function snapshot(): string { return JSON.stringify({ready:dock.ready, available:root.overlapPolicy.available,
            overlap:view.nativeOverlap, fullscreen:view.nativeFullscreen, state:view.visibilityState,
            settings: view.settingsOpen, intelligent:view.intelligentHide, refreshes:dock.overlapSource ? dock.overlapSource.backend.refreshes : 0,
            zone:panel.exclusiveZone, inputRects:view.inputRects.length}); }
        function reserve(value: bool): bool { view.reserveSpaceRequested(value); return true; }
        function map(value: bool): bool { root.mapped=value; return true; }
        function pointer(): bool { view.shelfEntered(); view.shelfExited(); return true; }
        function setup(): bool { dock.setIntelligentHide(true); return true; }
        function toggle(): bool { view.intelligentHideRequested(!view.intelligentHide); return true; }
        function settings(value: bool): bool { view.settingsOpen=value; return true; }
        function fullscreen(value: bool): bool { dock.overlapSource.backend.toplevels.values[0].wayland.fullscreen=value; dock.overlapSource.refresh(); return true; }
        function geometry(): bool { dock.overlapSource.backend.toplevels.values[0].lastIpcObject={mapped:true,hidden:false,at:[-1200,0],size:[100,100],fullscreen:0}; dock.overlapSource.refresh(); return true; }
    }
}'''.replace("BRIDGE", bridge).replace("BINDINGS", bindings).replace("ZONE", zone)
        (self.root / "shell.qml").write_text(shell)
        self.start(test_mode="0", extra_env={"QT_QPA_PLATFORM":"offscreen"}, wrapped=False)
        self.assertEqual(self.call("snapshot")["zone"], 0)
        self.call("reserve", "true")
        import time
        time.sleep(.1)
        self.assertGreater(self.call("snapshot")["zone"], 0)
        self.assertTrue(json.loads(self.config.read_text())["settings"]["reserveSpace"])
        self.call("map", "false")
        self.assertEqual(self.call("snapshot")["zone"], 0)
        self.call("map", "true")
        self.call("setup")
        import time
        time.sleep(.4)
        before = self.call("snapshot")["refreshes"]
        self.call("pointer")
        time.sleep(.35)
        self.assertGreater(self.call("snapshot")["refreshes"], before)
        self.assertTrue(self.call("snapshot")["overlap"])
        self.call("geometry")
        time.sleep(.1)
        self.assertFalse(self.call("snapshot")["overlap"])
        self.call("settings", "true")
        self.call("fullscreen", "true")
        time.sleep(.1)
        state = self.call("snapshot")
        self.assertTrue(state["fullscreen"])
        self.assertTrue(state["settings"])
        self.assertEqual(state["state"], "interacting")
        self.call("settings", "false")
        self.assertEqual(self.call("snapshot")["state"], "hidden")
        self.call("toggle")
        time.sleep(.1)
        self.assertFalse(self.call("snapshot")["intelligent"])
        self.assertFalse(json.loads(self.config.read_text())["settings"]["intelligentHide"])
        before = self.config.read_bytes()
        self.config.chmod(0o444)
        self.call("toggle")
        time.sleep(.1)
        self.assertFalse(self.call("snapshot")["intelligent"])
        self.assertEqual(self.config.read_bytes(), before)

    def test_overlap_setting(self):
        state = self.start(extra_env={"QT_QPA_PLATFORM":"offscreen"}, wrapped=False)
        self.assertIs(state["settings"].get("intelligentHide"), False)
        self.assertTrue(self.call("configure", json.dumps({"intelligentHide":True})))
        self.assertIs(self.call("snapshot")["settings"]["intelligentHide"], True)
        self.stop()
        self.start(extra_env={"QT_QPA_PLATFORM":"offscreen"}, wrapped=False)
        self.assertIs(self.call("snapshot")["settings"]["intelligentHide"], True)
        before = self.config.read_bytes()
        for value in (1, "true", None, [], {}):
            self.assertFalse(self.call("configure", json.dumps({"intelligentHide":value})))
            self.assertEqual(self.config.read_bytes(), before)

    def test_reserve_setting(self):
        state = self.start(extra_env={"QT_QPA_PLATFORM":"offscreen"}, wrapped=False)
        self.assertIs(state["settings"].get("reserveSpace"), False)
        self.assertTrue(self.call("configure", json.dumps({"reserveSpace":True})))
        self.stop(); self.start(extra_env={"QT_QPA_PLATFORM":"offscreen"}, wrapped=False)
        self.assertIs(self.call("snapshot")["settings"]["reserveSpace"], True)
        before = self.config.read_bytes()
        for value in (1, "true", None, [], {}):
            self.assertFalse(self.call("configure", json.dumps({"reserveSpace":value})))
            self.assertEqual(self.config.read_bytes(), before)
        self.config.chmod(0o444)
        self.assertFalse(self.call("configure", json.dumps({"reserveSpace":False})))
        self.assertEqual(self.config.read_bytes(), before)


for _name in dir(base.AppServiceTests):
    if _name.startswith("test_"):
        setattr(OverlapPersistenceTests, _name, None)
