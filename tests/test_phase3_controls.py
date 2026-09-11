"""Owned helper/IPC fixtures only; no compositor/user-window operations."""
import json
import subprocess
import spawn_safety as safety
from pathlib import Path
import unittest
import test_parking_service as parking
import test_app_service as app_fixture

ROOT = Path(__file__).resolve().parents[1]

class NativeCloseControls(unittest.TestCase):
    def test_frozen_group_close_revalidates_all_keys_without_optimistic_removal(self):
        f = app_fixture.AppServiceTests(); f.setUp(); self.addCleanup(f.tearDown)
        f.fake_native_source()
        path = f.root / "services/LiveApps.qml"
        source = path.read_text().replace('property var fixtureValues: [first]', '''property QtObject second: QtObject {
            property string appId: "One"; property string title: ""; property bool activated: false
            property int closeRequests: 0
            function close() { closeRequests++; }
            function activate() {}
        }
        property var fixtureValues: [first, second]''')
        path.write_text(source)
        path = f.root / "shell.qml"
        path.write_text(path.read_text().replace('target: "app-test"', '''target: "app-test"
            function group(keys: string): bool { return typeof apps.closeApplication === "function" && apps.closeApplication("one", keys.split("|")); }
            function secondCount(): int { return apps._live.item.second.closeRequests; }
        '''))
        f.start(test_mode="0", extra_env={"QT_QPA_PLATFORM":"offscreen"}, wrapped=False)
        rows=f.call("windowState","one"); keys=[r["key"] for r in rows]
        self.assertFalse(f.call("group","|".join(keys+["missing"])))
        self.assertEqual(f.call("nativeCounts")["close"],0)
        self.assertTrue(f.call("group","|".join(keys)))
        self.assertEqual(f.call("nativeCounts")["close"],1)
        self.assertEqual(f.call("secondCount"),1)
        self.assertEqual(f.call("windowState","one"),rows)
        f.call("nativeRegroup")
        self.assertFalse(f.call("group","|".join(keys)))
        self.assertEqual(f.call("secondCount"),1)

class ControlsTests(unittest.TestCase):
    def setUp(self):
        self.f = parking.ParkingServiceTests()
        self.f.setUp()
        # Count calls in the owned copy without replacing production dispatch logic.
        service=self.f.root/'services/AppService.qml'
        service.write_text(service.read_text().replace('    id: root','    id: root\n    property int ownedActivationCount: 0',1).replace(
            '                _windows = _windows.map(w => Object.assign({}, w, {active: w.key === key}));',
            '                ownedActivationCount++;\n                _windows = _windows.map(w => Object.assign({}, w, {active: w.key === key}));'))
        self.addCleanup(self.f.doCleanups)
        self.addCleanup(self.f.tearDown)
        extra = '''
        function minimizeActive(): int { return typeof apps.minimizeActive === "function" ? apps.minimizeActive() : 0; }
        function minimize(app: string): int { return apps.minimizeApplication(app); }
        function group(app: string, keys: string, mode: string): int {
            return typeof apps.restoreApplication === "function" ? apps.restoreApplication(app, keys.split("|"), mode) : 0;
        }
        function closeGroup(app: string, keys: string): bool {
            return typeof apps.closeApplication === "function" ? apps.closeApplication(app, keys.split("|")) : false;
        }
        function activationCount(): int { return apps.ownedActivationCount; }
        function active(): string { return JSON.stringify(apps._windows.filter(w=>w.active).map(w=>w.key)); }
        function focused(key: string): bool { apps._windows=apps._windows.map(w=>Object.assign({},w,{active:w.key===key})); apps._refresh(); return true; }
        function regroup(key: string): bool { apps._windows=apps._windows.map(w=>Object.assign({},w,{appId:w.key===key?"foreign":w.appId})); apps._refresh(); return true; }
'''
        dock=(ROOT/'Dock.qml').read_text()
        ipc=dock[dock.index('    IpcHandler {'):dock.index('    readonly property int screenCount:')]
        minimize=dock[dock.index('\n    function minimizeActive(): int {'):dock.index('\n    function minimizeApplication(')]
        # Exact hosted recovery IpcHandler plus production minimize bridge, no host services.
        hosted='\n    id: root\n    property var appService: apps\n    QtObject { id: surfaces; property var instances: [] }\n'+ipc+minimize
        (self.f.root/'shell.qml').write_text(parking.SHELL.replace('ShellRoot {','ShellRoot {'+hosted,1).replace('        function seed(',extra+'        function seed('))
        self.f.start(platform='offscreen')
        self.keys = self.f.seed()['items'][0]['windows']
        self.call = self.f.call

    def test_partial_group_failure_remains_visible_without_final_focus(self):
        for key in self.keys:
            before=self.call('snapshot')['revision']; self.call('park','one',key); self.f.wait_revision(before)
        self.call('focused','none')
        data=json.loads(self.f.state.read_text()); data['clients'][1]['stableId']='99'; self.f.write_state(data)
        before=self.call('snapshot')['revision']
        self.assertGreater(self.call('group','one','|'.join(self.keys[::-1]),'here'),0)
        done=self.f.wait_revision(before,2)
        self.assertEqual(self.call('active'),[])
        self.assertEqual(self.call('activationCount'),0)
        self.assertIn('group',done['error'])
        self.assertEqual([r['key'] for r in done['parked']],[self.keys[1]])

    def test_queued_group_regroup_refuses_second_restore_and_final_focus(self):
        for key in self.keys:
            before=self.call('snapshot')['revision']; self.call('park','one',key); self.f.wait_revision(before)
        self.call('focused','none')
        data=json.loads(self.f.state.read_text()); data['delay']=.3; self.f.write_state(data)
        before=self.call('snapshot')['revision']
        self.assertGreater(self.call('group','one','|'.join(self.keys[::-1]),'here'),0)
        self.call('regroup',self.keys[0])
        done=self.f.wait_revision(before,2)
        self.assertFalse(done['last']['ok']); self.assertEqual(done['last']['status'],'membership-changed')
        self.assertEqual([r['key'] for r in done['parked']],[self.keys[0]])
        self.assertEqual(self.call('active'),[])
        self.assertEqual(self.call('activationCount'),0)

    def test_context_minimize_background_app_uses_recent_then_first(self):
        self.call('focused',self.keys[1]); self.call('focused','none')
        before=self.call('snapshot')['revision']
        self.assertGreater(self.call('minimize','one'),0)
        done=self.f.wait_revision(before)
        self.assertEqual(done['last']['key'],self.keys[1])
        self.call('focused','none')
        before=done['revision']
        self.assertGreater(self.call('minimize','one'),0)
        self.assertEqual(self.f.wait_revision(before)['last']['key'],self.keys[0])

    def test_group_restore_frozen_scope_receipts_then_one_final_focus(self):
        for key in self.keys:
            before=self.call('snapshot')['revision']
            self.assertGreater(self.call('park','one',key),0)
            self.f.wait_revision(before)
        before=self.call('snapshot')['revision']
        self.assertEqual(self.call('group','foreign',"|".join(self.keys),'here'),0)
        self.assertEqual(self.call('group','one',"|".join(self.keys+['missing']),'here'),0)
        data=json.loads(self.f.state.read_text()); data['delay']=.2; self.f.write_state(data)
        transaction=self.call('group','one',"|".join(self.keys[::-1]),'here')
        self.assertGreater(transaction,0)
        self.assertEqual(len(self.call('snapshot')['parked']),2)
        done=self.f.wait_revision(before,2)
        self.assertEqual(done['parked'],[])
        self.assertEqual(self.call('active'),[self.keys[1]],'first frozen key is the one intended final focus')
        self.assertEqual(self.call('activationCount'),1)
        foreign=json.loads(self.f.state.read_text())['clients'][2]
        self.assertEqual(foreign['workspace']['name'],'1')

    def test_active_ipc_ignores_disabled_click_minimize_mode(self):
        self.assertTrue(self.call('configure','{"minimizeMode":"off"}'))
        self.f.wait_mode('off')
        before=self.call('snapshot')['revision']
        result=safety.ipc(self.f.proc, ['quickshell','ipc','--pid',str(self.f.proc.pid),'call','--','omadocked-recovery','minimizeActive'],capture_output=True,text=True,timeout=4)
        self.assertEqual(result.returncode,0,result.stderr)
        transaction=json.loads(result.stdout)
        self.assertGreater(transaction,0)
        done=self.f.wait_revision(before)
        self.assertEqual(done['last']['key'],self.keys[0])
        self.assertEqual([r['key'] for r in done['parked']],[self.keys[0]])
        self.assertEqual(done['minimizeMode'],'off')
