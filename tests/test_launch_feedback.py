"""Owned receipt-only launch adapter; never starts a real application."""
import json
import time
import test_app_service as base

SHELL = base.SHELL


class LaunchFeedbackTests(base.AppServiceTests):
    # Do not inherit the whole integration suite a second time.
    def setUp(self):
        super().setUp()
        extra = '''
        function rememberLauncher(): bool { probe.savedLauncher = apps._launcher; return true; }
        function oldLauncherGone(): bool { return probe.savedLauncher === null; }
        function token(id: string): int { return apps._pending[id] ? apps._pending[id].token || 0 : 0; }
        function receipt(id: string, token: int, ok: bool): bool { apps._finishLaunch(id, ok, "fixture failure", token); return true; }
        '''
        (self.root / 'shell.qml').write_text(SHELL.replace('target: "app-test"', 'target: "app-test"' + extra)
            .replace('id: probe', 'id: probe\n    property QtObject savedLauncher: null'))

    def test_production_process_receipts_without_app_launch(self):
        self.fake_native_source()
        self.seed_record_path = self.root / 'receipt.json'
        helper = self.root / 'services/launch_app.py'
        helper.write_text('import json,pathlib,sys,time\n'
                          'record=json.loads(sys.argv[2])\n'
                          f'pathlib.Path({str(self.seed_record_path)!r}).write_text(json.dumps(record))\n'
                          'time.sleep(.2)\nsys.exit(0)\n')
        self.start(test_mode='0', extra_env={'QT_QPA_PLATFORM': 'offscreen'})
        self.assertTrue(self.call('save', '{"kind":"command","name":"Receipt only","program":"never-executed","enabled":true}'))
        ident = self.call('snapshot')['launchers'][0]['id']
        self.assertTrue(self.call('activate', ident))
        self.assertTrue(self.call('rememberLauncher'))
        self.assertTrue(next(i for i in self.call('snapshot')['items'] if i['id'] == ident)['pending'])
        self.assertFalse(self.call('activate', ident))
        deadline = time.monotonic() + 3
        while self.call('snapshot')['pendingTimer'] and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertFalse(self.call('snapshot')['pendingTimer'])
        self.assertEqual(json.loads(self.seed_record_path.read_text())['program'], 'never-executed')
        self.assertTrue(self.call('oldLauncherGone'), 'retire native receipt source before reusing its identity')
        helper.write_text('import sys,time\ntime.sleep(.1)\nsys.exit(7)\n')
        self.assertTrue(self.call('activate', ident))
        deadline = time.monotonic() + 3
        while self.call('snapshot')['pendingTimer'] and time.monotonic() < deadline:
            time.sleep(.02)
        self.assertFalse(self.call('snapshot')['pendingTimer'])
        self.assertIn('Launch failed', self.call('snapshot')['error'])

    def test_bounce_preference_persists(self):
        self.start(extra_env={'QT_QPA_PLATFORM': 'offscreen'})
        self.assertTrue(self.call('snapshot')['settings'].get('launchBounce', False))
        self.assertTrue(self.call('configure', '{"launchBounce":false}'))
        self.assertFalse(json.loads(self.config.read_text())['settings']['launchBounce'])
        self.stop()
        self.start(extra_env={'QT_QPA_PLATFORM': 'offscreen'})
        self.assertFalse(self.call('snapshot')['settings']['launchBounce'])
        self.assertFalse(self.call('configure', '{"launchBounce":1}'))

    def test_receipt_generation_rejects_stale_and_duplicate(self):
        self.start(extra_env={'QT_QPA_PLATFORM': 'offscreen'})
        self.seed()
        self.assertTrue(self.call('pin', 'one', 'true'))
        self.seed([])
        self.assertTrue(self.call('activate', 'one'))
        first = self.call('token', 'one')
        self.assertGreater(first, 0)
        self.assertFalse(self.call('activate', 'one'))
        self.call('receipt', 'one', str(first), 'true')
        self.assertTrue(self.call('snapshot')['items'][0]['pending'], 'spawn receipt is not window readiness')
        self.call('receipt', 'one', str(first), 'false')
        self.assertTrue(self.call('snapshot')['items'][0]['pending'], 'duplicate terminal receipt must be ignored')
        self.seed([{'key': 'new', 'appId': 'One'}])
        self.assertFalse(self.call('snapshot')['items'][0]['pending'])
        self.seed([])
        self.assertTrue(self.call('activate', 'one'))
        second = self.call('token', 'one')
        self.assertGreater(second, first)
        self.call('receipt', 'one', str(first), 'false')
        self.assertTrue(self.call('snapshot')['items'][0]['pending'])
        self.call('receipt', 'one', str(second), 'false')
        self.assertFalse(self.call('snapshot')['items'][0]['pending'])
        self.assertFalse(self.call('snapshot')['pendingTimer'])


# Base methods remain helpers, not duplicate test cases.
for _name in dir(base.AppServiceTests):
    if _name.startswith('test_'):
        setattr(LaunchFeedbackTests, _name, None)
