"""R02/R03 storage outcomes and controller terminal ownership; owned fixtures only."""
import json
import os
from pathlib import Path
import signal
import tempfile
import time
import unittest
from unittest.mock import patch

from test_remediation_contracts import config
import test_parking_service as ps


class StorageOutcomes(unittest.TestCase):
    def test_new_parent_entries_are_synchronized_before_writer_ready(self):
        with tempfile.TemporaryDirectory() as tmp:
            calls = []
            sync = os.fsync
            def observed(fd):
                calls.append(os.readlink('/proc/self/fd/'+str(fd)))
                return sync(fd)
            with patch.object(os, 'fsync', observed):
                store = config.Store(str(Path(tmp)/'new'/'nested'/'pins.json'))
            try:
                self.assertEqual(calls, [tmp, str(Path(tmp)/'new')])
            finally: store.close()

    def test_reload_reconciles_current_main_with_durability_barrier(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/'pins.json'; path.write_text('{"current":1}')
            store = config.Store(str(path))
            try:
                sync = os.fsync
                calls = []
                def observed(fd):
                    calls.append('directory' if fd == store.directory else 'file')
                    return sync(fd)
                with patch.object(os, 'fsync', observed):
                    self.assertEqual(store.ready()['text'], path.read_text())
                self.assertEqual(calls, ['file', 'directory'])
                with patch.object(os, 'fsync', side_effect=OSError('barrier')):
                    with self.assertRaises(OSError): store.ready()
            finally: store.close()

    def test_pre_main_backup_or_preservation_failure_is_no_commit(self):
        for op in ('commit', 'recover'):
            with self.subTest(op=op), tempfile.TemporaryDirectory() as tmp:
                path = Path(tmp)/'pins.json'; path.write_text('{old')
                store = config.Store(str(path))
                try:
                    store.atomic_write(store.name+'.lkg', '{}')
                    with patch.object(store, 'atomic_write', side_effect=OSError('pre-main')):
                        result = store.request(dict(id=1,op=op,expected='{old',backup='{}',replacement='{}',fallback='{}'))
                    self.assertEqual(result['outcome'], 'no-commit')
                    self.assertEqual(path.read_text(), '{old')
                finally: store.close()

    def test_lost_output_never_emits_a_false_no_commit_receipt(self):
        import io
        with tempfile.TemporaryDirectory() as tmp:
            request = dict(id=1,op='commit',expected='',missing=True,replacement='{}',fallback='{}')
            calls = []
            def output(value):
                calls.append(value)
                if len(calls) > 1: raise BrokenPipeError('lost output')
            with patch.object(config, 'emit', output), patch.object(config.sys, 'stdin', io.StringIO(json.dumps(request)+'\n')):
                with self.assertRaises(BrokenPipeError): config.main(['helper', str(Path(tmp)/'pins.json')])
            self.assertEqual(len(calls), 2, 'failed delivery retried as misleading failure receipt')
            self.assertTrue(calls[1]['ok'])

    def test_auxiliary_write_failure_matrix_never_claims_cross_file_atomicity(self):
        for op in ('commit', 'recover'):
            for phase in ('pre-main', 'final-backup'):
                for stage in ('write', 'file-fsync', 'rename', 'directory-fsync', 'readback'):
                    with self.subTest(op=op, phase=phase, stage=stage), tempfile.TemporaryDirectory() as tmp:
                        path = Path(tmp)/'pins.json'; store = config.Store(str(path))
                        try:
                            old, new = '{old', '{}'
                            store.atomic_write(store.name, old); store.atomic_write(store.name+'.lkg', new)
                            atomic, write, sync, replace, read = store.atomic_write, os.write, os.fsync, os.replace, store.read
                            ordinal, selected = 0, False
                            def atomic_fault(name, text):
                                nonlocal ordinal, selected
                                ordinal += 1
                                selected = ordinal == (1 if phase == 'pre-main' else 3)
                                return atomic(name, text)
                            def write_fault(fd, data):
                                if selected and stage == 'write': raise OSError(stage)
                                return write(fd, data)
                            def sync_fault(fd):
                                if selected and ((fd == store.directory and stage == 'directory-fsync') or
                                                 (fd != store.directory and stage == 'file-fsync')): raise OSError(stage)
                                return sync(fd)
                            def rename_fault(*args, **kwargs):
                                if selected and stage == 'rename': raise OSError(stage)
                                return replace(*args, **kwargs)
                            def read_fault(name=None):
                                if selected and stage == 'readback': raise OSError(stage)
                                return read(name)
                            store.atomic_write, store.read = atomic_fault, read_fault
                            with patch.object(os,'write',write_fault), patch.object(os,'fsync',sync_fault), patch.object(os,'replace',rename_fault):
                                result = store.request(dict(id=1,op=op,expected=old,missing=False,replacement=new,fallback=old,backup=new))
                            self.assertEqual(result['outcome'], 'no-commit' if phase == 'pre-main' else 'durable')
                            self.assertEqual(path.read_text(), old if phase == 'pre-main' else new)
                            if phase == 'final-backup': self.assertTrue(result['backupDegraded'])
                        finally: store.close()

    def test_commit_recovery_failure_stages(self):
        for op in ('commit', 'recover'):
            for stage in ('write', 'file-fsync', 'rename', 'directory-fsync', 'readback', 'backup'):
                with self.subTest(op=op, stage=stage), tempfile.TemporaryDirectory() as tmp:
                    path = Path(tmp)/'pins.json'
                    store = config.Store(str(path))
                    try:
                        old, new = '{broken' if op == 'recover' else '{"old":1}', '{"new":1}'
                        store.atomic_write(store.name, old)
                        store.atomic_write(store.name+'.lkg', new if op == 'recover' else old)
                        atomic, write, sync, replace, read = store.atomic_write, os.write, os.fsync, os.replace, store.read
                        target = None
                        main_done = False
                        def atomic_fault(name, text):
                            nonlocal target, main_done
                            target = name
                            if stage == 'backup' and main_done and name.endswith('.lkg'):
                                raise OSError('backup')
                            atomic(name, text)
                            if name == store.name: main_done = True
                        def write_fault(fd, data):
                            if target == store.name and stage == 'write': raise OSError('write')
                            return write(fd, data)
                        def sync_fault(fd):
                            if target == store.name and ((stage == 'file-fsync' and fd != store.directory) or
                                                        (stage == 'directory-fsync' and fd == store.directory)):
                                raise OSError(stage)
                            return sync(fd)
                        def rename_fault(src, dst, **kwargs):
                            if dst == store.name and stage == 'rename': raise OSError('rename')
                            return replace(src, dst, **kwargs)
                        def read_fault(name=None):
                            if target == store.name and stage == 'readback': raise OSError('readback')
                            return read(name)
                        store.atomic_write, store.read = atomic_fault, read_fault
                        with patch.object(os, 'write', write_fault), patch.object(os, 'fsync', sync_fault), patch.object(os, 'replace', rename_fault):
                            try:
                                result = store.request(dict(id=7, op=op, expected=old, missing=False,
                                                            replacement=new, fallback=old, backup=new))
                            except (OSError, UnicodeError, ValueError, TypeError):
                                result = {'id':7, 'ok':False, 'error':'storage'}
                        expected = 'durable' if stage == 'backup' else 'indeterminate' if stage in ('rename','directory-fsync','readback') else 'no-commit'
                        self.assertEqual(result.get('outcome'), expected)
                        self.assertEqual(result['ok'], stage == 'backup')
                        self.assertEqual(path.read_text(), new if stage in ('directory-fsync','readback','backup') else old)
                        if stage == 'directory-fsync':
                            self.assertTrue(result['mainMatchesReplacement'])
                            self.assertFalse(result['mainDurable'])
                        if stage == 'backup': self.assertTrue(result['backupDegraded'])
                        if expected == 'indeterminate':
                            # A helper with unresolved persistence cannot accept another write.
                            again = store.request(dict(id=8, op=op))
                            self.assertEqual(again['outcome'], 'indeterminate')
                    finally:
                        store.close()


class ControllerLifecycle(unittest.TestCase):
    def fixture(self, injected, recovering=False):
        f = ps.ParkingServiceTests(); f.setUp()
        self.addCleanup(f.doCleanups); self.addCleanup(f.tearDown)
        shell = f.root/'shell.qml'
        text = shell.read_text().replace('AppService { id: apps }', '''AppService { id: apps }
    property var receipts: []
    Connections { target: apps; function onPersistenceCompleted(id,ok,message) { receipts.push({id:id,ok:ok,message:message}); } }''')
        text = text.replace('ready:apps.ready,', 'busy:apps.persistenceBusy,owned:apps._leaseOwned,outcome:apps.persistenceOutcome,receipts:receipts,ready:apps.ready,')
        text = text.replace('function configure(data: string): bool', '''function recoverConfig(): bool { return apps.recoverConfiguration(); }
        function late(): bool {
            apps._storeMessage(JSON.stringify({type:"ready",ok:true,text:"{}"}));
            apps._storeMessage(JSON.stringify({id:1,ok:true,outcome:"durable"}));
            apps._lease.exited(0,0); apps._lease.exited(0,0); return true;
        }
        function configure(data: string): bool''')
        shell.write_text(text)
        helper = f.root/'services/config_store.py'
        pidfile = f.root/'owned.pid'
        helper.write_text(helper.read_text().replace('    def request(self, request):',
            '    def request(self, request):\n        Path('+repr(str(pidfile))+').write_text(str(os.getpid()))\n'+injected))
        def cleanup():
            if pidfile.exists():
                try: os.kill(int(pidfile.read_text()), signal.SIGKILL)
                except ProcessLookupError: pass
        self.addCleanup(cleanup)
        if recovering:
            f.config.parent.mkdir(parents=True, exist_ok=True)
            f.config.write_text('{broken')
            Path(str(f.config)+'.lkg').write_text('{"version":2,"pins":[],"launchers":[],"overrides":{},"settings":{"minimizeMode":"all"}}')
        f.start()
        return f, pidfile

    def test_resistant_deadline_terminalizes_once_and_kills_owned_child(self):
        f, pidfile = self.fixture('        import signal,time\n        signal.signal(signal.SIGTERM,signal.SIG_IGN)\n        time.sleep(60)\n')
        self.assertTrue(f.call('configure', '{"minimizeMode":"all"}'))
        deadline = time.monotonic()+5
        while time.monotonic() < deadline:
            state = f.call('snapshot')
            if state['receipts']: break
            time.sleep(.03)
        self.assertFalse(state['busy']); self.assertFalse(state['owned'])
        self.assertEqual(state.get('outcome'), 'indeterminate')
        self.assertEqual(len(state['receipts']), 1); self.assertFalse(state['receipts'][0]['ok'])
        self.assertEqual(state['minimizeMode'], 'active')
        self.assertFalse(f.call('configure', '{"minimizeMode":"off"}'))
        f.call('late'); after = f.call('snapshot')
        self.assertEqual(after['receipts'], state['receipts'])
        self.assertEqual(after['outcome'], 'indeterminate'); self.assertFalse(after['owned'])
        pid = int(pidfile.read_text())
        deadline = time.monotonic()+2
        while time.monotonic() < deadline and Path('/proc/'+str(pid)).exists(): time.sleep(.03)
        self.assertFalse(Path('/proc/'+str(pid)).exists(), 'owned resistant child was not reaped')

    def test_lost_receipt_after_real_commit_is_indeterminate(self):
        f, _ = self.fixture('        result = self.commit(request)\n        os._exit(0)\n')
        self.assertTrue(f.call('configure', '{"minimizeMode":"all"}'))
        deadline = time.monotonic()+4
        while time.monotonic() < deadline:
            state = f.call('snapshot')
            if state['receipts']: break
            time.sleep(.03)
        self.assertEqual(json.loads(f.config.read_text())['settings']['minimizeMode'], 'all')
        self.assertEqual(state['minimizeMode'], 'active')
        self.assertEqual(state.get('outcome'), 'indeterminate')
        self.assertFalse(state['busy']); self.assertFalse(state['owned'])
        self.assertEqual(len(state['receipts']), 1)
        f.call('late'); self.assertEqual(f.call('snapshot')['receipts'], state['receipts'])

    def test_real_late_success_after_deadline_never_publishes(self):
        for recovering in (False, True):
            with self.subTest(recovering=recovering):
                operation = 'recover' if recovering else 'commit'
                injected = ('        import signal,time\n        signal.signal(signal.SIGTERM,signal.SIG_IGN)\n'
                            '        time.sleep(3.2)\n        return self.'+operation+'(request)\n')
                f, pidfile = self.fixture(injected, recovering=recovering)
                self.assertTrue(f.call('recoverConfig') if recovering else f.call('configure', '{"minimizeMode":"all"}'))
                deadline = time.monotonic()+5
                while time.monotonic() < deadline:
                    state = f.call('snapshot')
                    if state['receipts']: break
                    time.sleep(.02)
                self.assertEqual(state.get('outcome'), 'indeterminate')
                self.assertFalse(state['owned']); self.assertFalse(state['busy'])
                time.sleep(.6)  # allow the real late output and bounded escalation
                after = f.call('snapshot')
                self.assertEqual(after['receipts'], state['receipts'])
                self.assertEqual(after['minimizeMode'], 'active')
                self.assertEqual(json.loads(f.config.read_text())['settings']['minimizeMode'], 'all')
                if recovering:
                    self.assertEqual(next(f.config.parent.glob('pins.json.damaged-*')).read_text(), '{broken')
                self.assertFalse(Path('/proc/'+pidfile.read_text()).exists())
                f.stop()
                # A new helper reconciles current bytes, rather than completing the old ID.
                from test_parking_service import ROOT
                (f.root/'services/config_store.py').write_bytes((ROOT/'services/config_store.py').read_bytes())
                restarted = f.start()
                self.assertEqual(restarted['minimizeMode'], 'all')
                self.assertEqual(restarted['receipts'], [])
                f.stop()

    def test_indeterminate_receipt_disables_publication_and_editing(self):
        f, _ = self.fixture('        return {"id":request["id"],"ok":False,"outcome":"indeterminate","mainMatchesReplacement":True,"mainDurable":False}\n')
        self.assertTrue(f.call('configure', '{"minimizeMode":"all"}'))
        deadline = time.monotonic()+4
        while time.monotonic() < deadline:
            state = f.call('snapshot')
            if state['receipts']: break
            time.sleep(.03)
        self.assertFalse(state['owned']); self.assertFalse(state['busy'])
        self.assertEqual(state.get('outcome'), 'indeterminate')
        self.assertIn('unresolved', state['error'].lower())
        self.assertFalse(f.call('configure', '{"minimizeMode":"off"}'))
        self.assertEqual(state['minimizeMode'], 'active')
