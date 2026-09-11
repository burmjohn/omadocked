"""Additional repair contracts. Owned files, fake clients and Lua stub only."""
import importlib.util
import json
import os
from pathlib import Path
import select
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

config = load('remediation_config', ROOT/'services/config_store.py')
parking = load('remediation_parking', ROOT/'services/parking_store.py')

class RepairContracts(unittest.TestCase):
    def test_configuration_operation_timeout_disables_writer(self):
        import test_parking_service as ps
        import time
        fixture=ps.ParkingServiceTests();fixture.setUp()
        self.addCleanup(fixture.doCleanups);self.addCleanup(fixture.tearDown)
        path=fixture.root/'services/config_store.py'
        path.write_text(path.read_text().replace('    def request(self, request):',
            '    def request(self, request):\n        import time\n        time.sleep(60)'))
        fixture.start()
        self.assertTrue(fixture.call('configure','{"minimizeMode":"all"}'))
        deadline=time.monotonic()+5
        while time.monotonic()<deadline:
            state=fixture.call('snapshot')
            if 'disabled' in state['error']: break
            time.sleep(.05)
        self.assertIn('disabled',state['error'])
        self.assertFalse(fixture.call('configure','{"minimizeMode":"off"}'))

    def test_parking_verification_timeout_finishes_request(self):
        import test_parking_service as ps
        fixture=ps.ParkingServiceTests();fixture.setUp()
        self.addCleanup(fixture.doCleanups);self.addCleanup(fixture.tearDown)
        path=fixture.root/'services/parking_store.py'
        path.write_text(path.read_text().replace('        if operation == "status":',
            '        if operation == "status":\n            if request["id"] > 1:\n                import time\n                time.sleep(60)'))
        fixture.start();state=fixture.seed();key=state['items'][0]['windows'][0]
        transaction=fixture.call('park','one',key)
        result=fixture.wait_revision(state['revision'])
        self.assertEqual(result['last']['transactionId'],transaction)
        self.assertFalse(result['last']['ok'])
        self.assertFalse(result['parkingBusy'])

    def test_qml_publishes_committed_save_with_backup_warning(self):
        import test_parking_service as ps
        fixture=ps.ParkingServiceTests();fixture.setUp()
        self.addCleanup(fixture.doCleanups);self.addCleanup(fixture.tearDown)
        path=fixture.root/'services/config_store.py'
        path.write_text(path.read_text().replace('    def atomic_write(self, name, text):',
            '    def atomic_write(self, name, text):\n        self._writes = getattr(self, "_writes", 0) + 1\n        if self._writes == 3: raise OSError("fixture backup")'))
        fixture.start()
        self.assertTrue(fixture.call('configure','{"minimizeMode":"all"}'))
        state=fixture.wait_mode('all')
        self.assertIn('backup',state['error'].lower())
        self.assertTrue(fixture.call('configure','{"minimizeMode":"off"}'))
        self.assertEqual(fixture.wait_mode('off')['error'],'')

    def test_recovery_final_backup_failure_reports_committed_main(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'pins.json'
            store = config.Store(str(path))
            self.addCleanup(store.close)
            store.atomic_write(store.name, '{broken')
            store.atomic_write(store.name+'.lkg', '{}')
            original = store.atomic_write
            def fail_backup(name, text):
                if name.endswith('.lkg'): raise OSError('fixture')
                original(name, text)
            store.atomic_write = fail_backup
            try: result = store.recover(dict(id=1,expected='{broken',backup='{}'))
            except OSError: result = {'ok':False}
            self.assertEqual(path.read_text(), '{}')
            self.assertTrue(result['ok'])
            self.assertTrue(result['backupDegraded'])

    def test_all_config_special_file_reads_are_bounded(self):
        for target, operation in [('main','commit'),('lkg','recover')]:
            with self.subTest(target=target), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp)/'pins.json'
                process = subprocess.Popen([sys.executable,str(ROOT/'services/config_store.py'),str(path)],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
                try:
                    self.assertTrue(json.loads(process.stdout.readline())['ok'])
                    if target == 'lkg': path.write_text('{broken')
                    os.mkfifo(str(path)+('.lkg' if target == 'lkg' else ''))
                    request=dict(id=1,op=operation,expected='{broken' if target=='lkg' else '',missing=target=='main',replacement='{}',fallback='{}',backup='{}')
                    process.stdin.write(json.dumps(request)+'\n');process.stdin.flush()
                    self.assertTrue(select.select([process.stdout],[],[],1)[0])
                    self.assertFalse(json.loads(process.stdout.readline())['ok'])
                finally:
                    process.terminate();process.wait(timeout=3)
                    for stream in (process.stdin,process.stdout,process.stderr):stream.close()

    def test_journal_fifo_startup_is_bounded(self):
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'parking.json';os.mkfifo(path)
            process=subprocess.Popen([sys.executable,str(ROOT/'services/parking_store.py'),str(path)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,env=dict(os.environ,HYPRLAND_INSTANCE_SIGNATURE='fixture'))
            try:
                self.assertTrue(select.select([process.stdout],[],[],1)[0])
                self.assertFalse(json.loads(process.stdout.readline())['ok'])
            finally:
                process.terminate();process.wait(timeout=3)
                process.stdout.close();process.stderr.close()

    def test_missing_recovery_generation_never_matches(self):
        identity=dict(key='k',address='0xaaa',pid=1,**{'class':'A','initialClass':'A','xwayland':False})
        self.assertFalse(parking.client_identity(identity,identity))

    def test_post_dispatch_generation_is_independently_verified(self):
        import test_parking_helper as ph
        fixture = ph.ParkingHelperTests(); fixture.setUp()
        self.addCleanup(fixture.doCleanups); self.addCleanup(fixture.tearDown)
        script = fixture.hyprctl.read_text()
        script = script.replace("    state.write_text(json.dumps(data))", "    data['clients'][0]['stableId']='a2'\n    state.write_text(json.dumps(data))")
        fixture.hyprctl.write_text(script)
        process = fixture.start()
        result = fixture.park(process, 'a', '0xaaa', 101, 'FixtureA', '1')
        self.assertFalse(result['ok']); self.assertEqual(result['status'], 'unverified')
        status = process.request(dict(id=2, op='status'))
        self.assertEqual(status['blocked'], ['a'])
        self.assertEqual(len(status['records']), 1)

    def test_lua_generation_guard_is_inert_for_replacement(self):
        identity=dict(key='k',address='0xaaa',stableId='a1',pid=1,**{'class':'A','initialClass':'A','xwayland':False})
        helper=object.__new__(parking.Parking);helper.executable='/not-executed'
        with patch.object(parking.subprocess,'run') as run:
            helper.move(identity,'1')
        code=run.call_args.args[0][2]
        for generation, expected in [('0xa1',1),('0xa2',0),('nil',0)]:
            stub="local calls=0; hl={get_windows=function() return {{address='0xaaa',stable_id="+generation+"}} end,dsp={window={move=function(_) return {_run=function() calls=calls+1 end} end}},dispatch=function(d) return d._run() end}; "
            result=subprocess.run(['/usr/bin/lua','-'],input=stub+code+'; print(calls)',capture_output=True,text=True,timeout=3)
            self.assertEqual(result.returncode,0,result.stderr)
            self.assertEqual(int(result.stdout),expected)
