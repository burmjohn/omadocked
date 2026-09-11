"""Owned offscreen row input -> production bridges -> real parking helper/receipts.
Only the compositor is simulated, by the private executable in ParkingServiceTests.
No user window collection, focus, movement, capture or close is requested.
"""
import json
from pathlib import Path
import shutil
import unittest
import test_parking_service as parking

ROOT = Path(__file__).resolve().parents[1]


class WindowRestoreIntegration(unittest.TestCase):
    def setUp(self):
        self.fixture = parking.ParkingServiceTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.doCleanups)
        self.addCleanup(self.fixture.tearDown)
        root = self.fixture.root
        shutil.copytree(ROOT / 'ui', root / 'ui')
        dock = (ROOT / 'Dock.qml').read_text()
        methods = dock[dock.index('    function activateWindow('):dock.index('    function minimizeApplication(')]
        surface = (ROOT / 'DockSurface.qml').read_text()
        handlers = '\n'.join(line.strip() for line in surface.splitlines() if line.strip().startswith(
            ('onActivateWindowRequested:', 'onCloseWindowRequested:', 'onCycleWindowsRequested:', 'onRestoreApplicationRequested:', 'onCloseApplicationRequested:')))
        extra = '''
    id: root
    property var controller: bridge
    QtObject { id: surfaces; property var instances: [view] }
    QtObject { id: bridge; property var appService: apps
METHODS
    }
    Window {
        visible: true; width: 1000; height: 800
        TestCase { id: finder; when: false; visible: true; name: "OwnedInput" }
        DockView {
            id: view; appsManaged: true; autoHide: false; reducedMotion: true; previewsEnabled: false
            applications: apps.items; windowGroups: apps.windowGroups
HANDLERS
        }
    }
    PreviewPrivacy { id: privacy }
    QtObject { id: previewController; property string previewLockState: privacy.state
        function previewTarget(appId, key) { return null; }
    }
    PreviewIntegration { view: view; controller: previewController; mapped: true }
'''.replace('METHODS', methods).replace('HANDLERS', handlers)
        ipc = '''
        function group(): string {
            view.openContext(view.order.indexOf("one"));
            finder.wait(20);
            const button=finder.findChild(view,"context-restore-here");
            const point=button.mapToItem(view,button.width/2,button.height/2);
            finder.mousePress(view,point.x,point.y);
            const pressed=button.pressed;
            finder.mouseRelease(view,point.x,point.y);
            return JSON.stringify({pressed:pressed,closed:view.contextIndex<0});
        }
        function row(key: string): string {
            if (!view.openWindowChooser("one")) return JSON.stringify({opened:false});
            finder.wait(20);
            const button = finder.findChild(view, "window-activate-" + key);
            if (!button) return JSON.stringify({opened:true,found:false});
            const point = button.mapToItem(view, button.width/2, button.height/2);
            finder.mousePress(view, point.x, point.y);
            const pressed = button.pressed;
            finder.mouseRelease(view, point.x, point.y);
            return JSON.stringify({opened:true,found:true,pressed:pressed,closed:!view.windowChooserOpen,
                lockState:privacy.state,transaction:apps._parkingActive ? apps._parkingActive.publicId : 0});
        }
        function cycle(delta: int): bool { return bridge.cycleWindows("one",delta); }
        function exact(app: string, key: string): bool { return bridge.activateWindow(app,key); }
        function windows(): string { return JSON.stringify(apps.windowGroups.one.map(w=>({key:w.key,active:w.active}))); }
        function loseHelper(): bool { apps._parking.running=false; return true; }
'''
        shell = parking.SHELL.replace('import QtQuick', 'import QtQuick\nimport QtTest\nimport "ui"', 1)
        shell = shell.replace('ShellRoot {', 'ShellRoot {' + extra, 1).replace('        function seed(', ipc + '\n        function seed(', 1)
        (root / 'shell.qml').write_text(shell)
        self.call = self.fixture.call
        self.fixture.start(platform='offscreen')
        state = self.fixture.seed()
        self.keys = state['items'][0]['windows']
        for key in self.keys:
            before = self.call('snapshot')['revision']
            self.assertGreater(self.call('park', 'one', key), 0)
            self.fixture.wait_revision(before)

    def test_group_context_uses_production_bridges_and_exact_receipts(self):
        before=self.call('snapshot')['revision']
        result=self.call('group')
        self.assertTrue(result['pressed'] and result['closed'])
        done=self.fixture.wait_revision(before,2)
        self.assertEqual(done['parked'],[])
        self.assertTrue(done['last']['ok'])
        self.assertEqual(json.loads(self.fixture.state.read_text())['clients'][2]['workspace']['name'],'1')

    def test_clicked_non_fifo_parked_row_restores_exact_key_after_receipt(self):
        before = self.call('snapshot')
        windows = self.call('windows')
        data = json.loads(self.fixture.state.read_text())
        data['delay'] = .35
        self.fixture.write_state(data)
        result = self.call('row', self.keys[1])
        self.assertTrue(result['opened'] and result['found'] and result['pressed'] and result['closed'])
        self.assertEqual(result['lockState'], 'unknown')
        self.assertGreater(result['transaction'], 0, 'parked row must enqueue restore, never activate natively')
        queued = self.call('snapshot')
        self.assertEqual(queued['revision'], before['revision'])
        self.assertEqual(queued['parked'], before['parked'])
        self.assertEqual(self.call('windows'), windows, 'submission must not optimistically activate the fixture')
        done = self.fixture.wait_revision(before['revision'])
        self.assertEqual(done['last'], {'transactionId':result['transaction'], 'ok':True,
                                      'status':'restored', 'key':self.keys[1]})
        self.assertEqual([r['key'] for r in done['parked']], [self.keys[0]])
        clients = json.loads(self.fixture.state.read_text())['clients']
        self.assertEqual(clients[1]['workspace']['name'], '1')
        self.assertNotEqual(clients[0]['workspace']['name'], '1')
        self.assertNotIn('PRIVATE TITLE', self.fixture.journal.read_text())

    def test_cycle_routes_parked_target_and_rejects_stale_generation(self):
        data = json.loads(self.fixture.state.read_text())
        data['clients'][1]['stableId'] = '99'
        self.fixture.write_state(data)
        before = self.call('snapshot')['revision']
        self.assertTrue(self.call('cycle', -1))
        self.assertTrue(self.call('snapshot')['parkingBusy'])
        done = self.fixture.wait_revision(before)
        self.assertFalse(done['last']['ok'])
        self.assertEqual(done['last']['key'], self.keys[1])
        self.assertNotEqual(json.loads(self.fixture.state.read_text())['clients'][1]['workspace']['name'], '1')
        self.assertFalse(self.call('exact', 'foreign', self.keys[0]))
        self.assertFalse(self.call('exact', 'one', 'stale-key'))

    def test_unavailable_helper_never_falls_through_to_activation(self):
        self.call('loseHelper')
        before = self.call('windows')
        self.assertFalse(self.call('exact', 'one', self.keys[1]))
        self.assertEqual(self.call('windows'), before)
