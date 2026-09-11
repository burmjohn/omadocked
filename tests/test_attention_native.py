"""Production LiveApps → AppService → AttentionService, owned native collections only."""
import json
import time
import test_app_service as base


class AttentionNativeTests(base.AppServiceTests):
    # Limit this derived harness to the attention probe (the base suite runs separately).
    def test_root_lock_and_standalone_capabilities(self):
        import shutil
        from pathlib import Path
        for name in ("Dock.qml", "DockSurface.qml"):
            shutil.copy2(base.ROOT / name, self.root / name)
        shutil.copytree(base.ROOT / "ui", self.root / "ui")
        dock = self.root / "Dock.qml"
        dock.write_text(dock.read_text().replace("Quickshell.screens", "[]"))
        (self.root / "shell.qml").write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    QtObject { id: lock; property bool locked:false; property bool strandedLock:false; property bool strandedLockResolved:true }
    QtObject {
        id: notifications
        property bool settingsLoaded:true
        property bool doNotDisturb:false
        property ListModel popupModel: ListModel {}
        function isRestoredRow(row) { return false; }
    }
    QtObject { id: host; function serviceFor(id) { return id === "omarchy.lock" ? lock : notifications; } }
    QtObject { id: registry; function resolveEnabledId(id) { return "fixture.clone"; } }
    Dock { id: dock; surfaceEnabled:true; shell:host; pluginRegistry:registry }
    IpcHandler {
        target:"app-test"
        function snapshot(): string { return JSON.stringify({ready:dock.ready, allowed:dock.attentionAllowed,
            lock:dock.previewLockState, notification:dock.notificationStatus, sound:dock.soundStatus,
            standalone:!dock.shell, attentionVisible:dock.attentionVisible, normalItems:Array.isArray(dock.applications)}); }
        function lockFixture(value: bool): bool { lock.locked=value; return true; }
        function strandFixture(value: bool): bool { lock.strandedLock=value; return true; }
        function standalone(): bool { dock.shell=null; return true; }
        function hideFixture(): bool { dock.hide(); return true; }
    }
}''')
        self.start()
        self.assertTrue(self.call("snapshot")["allowed"])
        self.assertIs(self.call("snapshot").get("attentionVisible"), False)
        self.call("lockFixture", "true")
        self.assertFalse(self.call("snapshot")["allowed"])
        self.call("lockFixture", "false")
        self.call("strandFixture", "true")
        self.assertFalse(self.call("snapshot")["allowed"])
        self.call("standalone")
        state = self.call("snapshot")
        self.assertTrue(state["allowed"])
        self.assertTrue(state["normalItems"])
        self.assertEqual(state["notification"], "unavailable")
        self.assertTrue(state["sound"].startswith("unavailable:"))
        self.call("hideFixture")
        self.assertFalse(self.call("snapshot")["allowed"])

    def test_attention_settings_persist_without_action(self):
        self.start()
        patch = {"showUrgentHint":False, "urgentOnNotification":False, "urgentSound":True,
                 "urgentSoundName":"dialog-warning"}
        self.assertTrue(self.call("configure", json.dumps(patch)))
        self.stop()
        state = self.start()
        self.assertEqual({k:state["settings"][k] for k in patch}, patch)
        self.assertFalse(any(item.get("pending") for item in state["items"]))

    def test_urgent_activation_failure_and_submission_do_not_ack_until_exact_focus(self):
        self.fake_native_source()
        path=self.root/'services/LiveApps.qml'
        source=path.read_text().replace('Hyprland.toplevels.values.some(h => h.wayland === w && h.urgent)', 'true')
        source=source.replace('property bool activated: true','property bool activated: false\n        property bool failActivation: true')
        source=source.replace('function activate() { activateRequests++; }',
            'function activate() { if (failActivation) throw new Error("owned failure"); activateRequests++; }')
        path.write_text(source)
        shell=(self.root/'shell.qml').read_text().replace('AppService { id: apps }', 'AppService { id: apps }\n    property int ackCount: 0\n    Connections { target:apps; function onUrgentAcknowledged(appId,key) { ackCount++; } }')
        shell=shell.replace('target: "app-test"', 'target: "app-test"\n        function ackState(): string { return JSON.stringify({acks:ackCount,requests:apps._live.item.first.activateRequests}); }\n        function acceptOnly(): bool { apps._live.item.first.failActivation=false; return true; }\n        function focusExact(): bool { apps._live.item.first.activated=true; return true; }')
        (self.root/'shell.qml').write_text(shell)
        self.start(test_mode='0')
        self.assertFalse(self.call('activate','one'))
        self.assertEqual(self.call('ackState'),{'acks':0,'requests':0})
        self.call('acceptOnly'); self.assertTrue(self.call('activate','one'))
        self.assertEqual(self.call('ackState'),{'acks':0,'requests':1})
        self.call('focusExact')
        self.assertEqual(self.call('ackState'),{'acks':1,'requests':1})

    def test_fresh_native_urgent_edge_before_scheduled_refresh_has_priority(self):
        self.fake_native_source()
        path=self.root/'services/LiveApps.qml'
        source=path.read_text().replace('Hyprland.toplevels.values.some(h => h.wayland === w && h.urgent)', 'w.urgent')
        source=source.replace('property bool activated: true', 'property bool urgent: false\n        property bool activated: true')
        source=source.replace('property var fixtureValues: [first]', '''property QtObject second: QtObject {
        property string appId:"One"
        property string title:""
        property bool activated:false
        property bool urgent:false
        property int activateRequests:0
        function activate() { activateRequests++; }
    }
    property var fixtureValues: [first, second]''')
        path.write_text(source)
        shell=(self.root/'shell.qml').read_text().replace('target: "app-test"', '''target: "app-test"
        function edgeClick(): string {
            apps._live.item.second.urgent=true;
            const accepted=apps.activate("one");
            return JSON.stringify({accepted:accepted, first:apps._live.item.first.activateRequests, second:apps._live.item.second.activateRequests});
        }''')
        (self.root/'shell.qml').write_text(shell)
        self.start(test_mode='0')
        self.assertEqual(self.call('edgeClick'),{'accepted':True,'first':0,'second':1})

    def test_attention_adapter(self):
        self.fake_native_source()
        path = self.root / "services/LiveApps.qml"
        source = path.read_text().replace("Hyprland.toplevels.values", "fixtureHypr")
        source = source.replace('property var fixtureValues: [first]', '''property QtObject hyprFixture: QtObject {
        property var wayland: first
        property bool urgent: false
    }
    property var fixtureHypr: [hyprFixture]
    property var fixtureValues: [first]''')
        path.write_text(source)
        shell = (self.root / "shell.qml").read_text().replace('AppService { id: apps }', '''AppService { id: apps }
    AttentionService { id: attention; apps: apps.attentionApps || [] }''')
        shell = shell.replace('target: "app-test"', '''target: "app-test"
        function urgent(value: bool): bool { apps._live.item.hyprFixture.urgent = value; return true; }
        function attentionState(): string { return JSON.stringify({hints:attention.hints,
            model:apps.attentionApps || [], status:attention.notificationStatus}); }
        function focusFixture(value: bool): bool { apps._live.item.first.activated=value; return true; }''')
        (self.root / "shell.qml").write_text(shell)
        self.start(test_mode="0")
        self.call("focusFixture", "false")
        state = self.call("attentionState")
        self.assertEqual(len(state["model"]), 1)
        self.assertNotIn("title", json.dumps(state))
        self.call("urgent", "true")
        self.assertEqual(self.call("attentionState")["hints"], [], "new window suppression")
        self.call("urgent", "false")
        time.sleep(3.1)  # Actual policy age threshold, no polling of compositor state.
        self.call("urgent", "true")
        self.assertEqual(self.call("attentionState")["hints"], ["one"])
        self.call("focusFixture", "true")
        self.assertEqual(self.call("attentionState")["hints"], [])
        self.call("nativeRemove")
        self.assertEqual(self.call("attentionState")["model"], [])


# unittest otherwise repeats the inherited general suite in this module.
for _name in dir(base.AppServiceTests):
    if _name.startswith("test_"):
        setattr(AttentionNativeTests, _name, None)
