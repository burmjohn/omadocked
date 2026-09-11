"""Owned native type + production identity resolver contracts; never capture a user window."""
import json
from pathlib import Path
import shutil
import unittest
import test_app_service as harness

ROOT = Path(__file__).resolve().parents[1]
SHELL = '''import QtQuick
import Quickshell
import Quickshell.Io
import "services"
ShellRoot {
    id: root
    property int created:0
    property int disposed:0
    AppService { id: apps }
    PanelWindow {
        visible:false
        Loader {
            id: native
            active:false
            sourceComponent: NativeCapture {
                captureSource:null
                Component.onCompleted: root.created++
                Component.onDestruction: root.disposed++
            }
        }
    }
    IpcHandler {
        target:"app-test"
        function snapshot(): string { return JSON.stringify({ready:apps.ready, created:root.created,
            disposed:root.disposed, content:native.item ? native.item.hasContent : false,
            sourceForwarded:native.item ? native.item.children[0].captureSource === native.item.captureSource : false,
            nativeSourceNull:native.item ? native.item.children[0].captureSource === null : true}); }
        function nativeActive(value:bool): bool { native.active=value; return true; }
        function requestOwnedUnsupported(): bool {
            native.item.captureSource=apps._live.item.fixtureHandle;
            native.item.live=false;
            return native.item.captureSource !== null;
        }
        function targets(): string {
            const rows=apps.windowGroups.owned || [];
            const key=rows.length ? rows[0].key : "";
            return JSON.stringify({available:typeof apps.previewTarget==="function",
                valid:typeof apps.previewTarget==="function" && apps.previewTarget("owned",key)===apps._live.item.fixtureHandle,
                stale:typeof apps.previewTarget==="function" && apps.previewTarget("owned","stale")===null,
                regrouped:typeof apps.previewTarget==="function" && apps.previewTarget("wrong",key)===null,
                key:key});
        }
        function removeOwned(): bool { apps._live.item.fixtureCollection=[]; apps._refresh(); return true; }
        function targetMissing(key:string): bool { return apps.previewTarget("owned",key)===null; }
        function parked(): bool {
            const key=apps.windowGroups.owned[0].key;
            apps._parkedWindows=[{key:key,state:"parked"}]; apps._refresh();
            return apps.previewTarget("owned",key)===null;
        }
    }
}
'''

class PreviewNativeTests(unittest.TestCase):
    setUp = harness.AppServiceTests.setUp
    tearDown = harness.AppServiceTests.tearDown
    stop = harness.AppServiceTests.stop
    start = harness.AppServiceTests.start
    call = harness.AppServiceTests.call

    def prepare(self):
        (self.root/'shell.qml').write_text(SHELL)
        live=(ROOT/'services/LiveApps.qml').read_text()
        live=live.replace('ToplevelManager.toplevels.values','fixtureCollection')
        live=live.replace('DesktopEntries.applications.values','[{id:"owned", name:"Owned", icon:"application-x-executable", startupClass:"owned", execString:"/usr/bin/true", actions:[]}]')
        live=live.replace('QtObject {', '''QtObject {
    property QtObject fixtureHandle: QtObject { property string appId:"owned"; property string title:"OWNED-PRIVATE-SENTINEL"; property bool activated:true }
    property var fixtureCollection:[fixtureHandle]
''', 1)
        (self.root/'services/LiveApps.qml').write_text(live)

    def test_preview_preferences_persist_without_private_pixels_or_titles(self):
        self.start()
        self.call('seed', json.dumps({'entries':harness.ENTRIES, 'windows':[
            {'key':'fixture','appId':'One','title':'OWNED-PRIVATE-SENTINEL','active':True}]}))
        self.assertTrue(self.call('configure', '{"previewsEnabled":false,"livePreviews":true}'))
        self.assertNotIn('OWNED-PRIVATE-SENTINEL', self.config.read_text())
        self.assertNotIn('image://', self.config.read_text())
        self.stop()
        state=self.start()
        self.assertFalse(state['settings']['previewsEnabled'])
        self.assertTrue(state['settings']['livePreviews'])

    def test_native_null_source_loader_disposal(self):
        self.prepare()
        self.start(test_mode='0')
        for i in range(12):
            self.assertTrue(self.call('nativeActive','true'))
            state=self.call('snapshot')
            self.assertFalse(state['content'])
            self.assertTrue(state['nativeSourceNull'])
            self.assertTrue(self.call('requestOwnedUnsupported'))
            state=self.call('snapshot')
            self.assertTrue(state['sourceForwarded'])
            self.assertFalse(state['nativeSourceNull'])
            self.assertFalse(state['content'])
            self.assertTrue(self.call('nativeActive','false'))
        state=self.call('snapshot')
        self.assertEqual(state['created'],12)
        self.assertEqual(state['disposed'],12)
        self.assertNotIn('OWNED-PRIVATE-SENTINEL',(self.root/'runtime.log').read_text())

    def test_production_resolver_rejects_stale_regrouped_removed_and_parked(self):
        self.prepare()
        self.start(test_mode='0')
        state=self.call('targets')
        self.assertTrue(state['available'])
        for name in ('valid','stale','regrouped'): self.assertTrue(state[name],name)
        self.assertTrue(self.call('parked'))
        self.assertTrue(self.call('removeOwned'))
        self.assertTrue(self.call('targetMissing',state['key']))
        self.assertNotIn('OWNED-PRIVATE-SENTINEL',(self.root/'runtime.log').read_text())
