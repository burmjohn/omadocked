"""Folder picker -> verbatim surface/controller bridges -> real durable writer."""
import json
import os
import signal
import subprocess
from pathlib import Path
import time
import unittest
import spawn_safety as safety
import test_folder_service as f

ROOT=Path(__file__).resolve().parents[1]

class FolderTransactions(unittest.TestCase):
    def setUp(self):
        surface=(ROOT/'DockSurface.qml').read_text()
        dock=(ROOT/'Dock.qml').read_text()
        methods=dock[dock.index('    function toggleFolder('):dock.index('\n\n    readonly property string themePath')]
        handlers='\n'.join(line.strip().replace('root.controller.', 'controller.') for line in surface.splitlines()
            if line.strip().startswith(('onFolderAddRequested:', 'onFolderPresetRequested:')))
        completion=surface[surface.index('        function onPersistenceCompleted('):surface.index('\n    }\n    function enterKeyboard')]
        original=f.SHELL
        f.SHELL=original.replace('import QtQuick', 'import QtQuick\nimport QtTest', 1).replace('ShellRoot {', '''ShellRoot {
            QtObject { id:controller; property var launcherRecords: apps.launchers
'''+methods.replace('appService.', 'apps.')+''' }
            TestCase { id:finder; when:false; name:"Finder" }
            property var picker: finder.findChild(view,"folder-settings")
            Connections { target:apps
'''+completion+''' }
''').replace('DockView { id:view;', 'DockView { id:view; homePath:"/tmp"; folderPersistenceBusy:apps.persistenceBusy; folderResult:folders.result; folderBusy:folders.busy; folderScannedPath:folders._path; '+handlers+'\n').replace('function state(): string', '''function begin(): void { view.settingsOpen=true; picker.beginSelection(false); }
        function draft(path:string): void { finder.findChild(picker,"folder-picker-path").text=path; view.folderBrowseRequested(path); }
        function accept(): bool { return picker.acceptSelection(picker.selectionGeneration, view.folderScannedPath); }
        function clickPreset(): void { const b=picker.children[1].children[0]; b.forceActiveFocus(); finder.wait(20); finder.mouseClick(b,30,b.height/2); }
        function presetState(): bool { return picker.children[1].children[0].checked; }
        function clickAdd(): void { const b=finder.findChild(picker,"folder-picker-accept"); b.forceActiveFocus(); finder.keyClick(Qt.Key_Return); }
        function cancel(): void { picker.cancelSelection(); }
        function fakeCompletion(tx:int): void { view.folderSaveResult(tx,true); }
        function transactionState(): string { return JSON.stringify({selecting:picker.selecting,editable:finder.findChild(picker,"folder-picker-path").enabled,path:finder.findChild(picker,"folder-picker-path").text,tx:picker.pendingTransactionId || 0,records:apps.launchers.length,busy:apps.persistenceBusy,error:apps.error}); }
        function state(): string''')
        f.SHELL=f.SHELL.replace('DockView { id:view;', 'Window { visible:true; width:800; height:800; DockView { id:view;').replace('autoHide:false }', 'autoHide:false } }')
        self.fixture=f.FolderServiceTests('test_real_ui_to_launcher_receipt')
        try:self.fixture.setUp()
        finally:f.SHELL=original
        self.call=self.fixture.call
    def tearDown(self): self.fixture.tearDown()
    def settled(self):
        for _ in range(100):
            s=self.call('transactionState')
            if not s['busy']: return s
            time.sleep(.01)
        self.fail('writer busy')
    def scan_settled(self):
        for _ in range(100):
            if not self.call('integrated')['busy']: return
            time.sleep(.01)
        self.fail('scan busy')
    def begin(self):
        self.call('begin');self.call('draft',self.fixture.folder);self.scan_settled()
    def test_real_writer_conflict_preserves_draft(self):
        self.call('save',self.fixture.folder);self.settled()
        other=self.fixture.root/'other';other.mkdir()
        self.call('begin');self.call('draft',other);self.scan_settled()
        disk=self.fixture.root/'pins.json';disk.write_text('{external-conflict')
        self.assertTrue(self.call('accept'))
        s=self.settled();self.assertTrue(s['selecting']);self.assertEqual(s['path'],str(other))
        self.assertEqual(s['records'],1);self.assertIn('externally',s['error']);self.assertEqual(disk.read_text(),'{external-conflict')
        self.call('cancel');self.call('begin');self.assertEqual(self.call('transactionState')['path'],str(other))
    def writer_pid(self):
        # Inspect only direct children of the exact owned Quickshell process.
        children=Path(f'/proc/{self.fixture.proc.pid}/task/{self.fixture.proc.pid}/children').read_text().split()
        found=[int(p) for p in children if b'config_store.py' in Path(f'/proc/{p}/cmdline').read_bytes()]
        self.assertEqual(len(found),1)
        return found[0]
    def test_pending_duplicate_unrelated_completion_cancel_reopen(self):
        self.begin();pid=self.writer_pid();os.kill(pid,signal.SIGSTOP)
        try:
            self.call('clickAdd')
            s=self.call('transactionState');self.assertTrue(s['busy']);self.assertGreater(s['tx'],0)
            self.assertFalse(s['editable'])
            self.assertFalse(self.call('accept'))
            self.call('fakeCompletion',s['tx']+100);self.assertTrue(self.call('transactionState')['selecting'])
            self.call('cancel');self.call('begin')
            self.assertEqual(self.call('transactionState')['path'],str(self.fixture.folder))
        finally: os.kill(pid,signal.SIGCONT)
        s=self.settled();self.assertTrue(s['selecting']);self.assertEqual(s['records'],1);self.assertEqual(s['tx'],0)
    def test_writer_dies_pending_then_sync_rejection(self):
        self.begin();pid=self.writer_pid();os.kill(pid,signal.SIGSTOP)
        try:
            self.assertTrue(self.call('accept'));self.assertGreater(self.call('transactionState')['tx'],0)
        finally: os.kill(pid,signal.SIGKILL)
        s=self.settled();self.assertTrue(s['selecting']);self.assertEqual(s['tx'],0);self.assertEqual(s['records'],0)
        self.assertTrue(self.call('accept'))  # emitted, but no accepted transaction
        self.assertEqual(self.call('transactionState')['tx'],0)
        self.assertEqual(self.call('transactionState')['path'],str(self.fixture.folder))
    def test_real_preset_click_conflict_and_restart(self):
        self.call('begin');self.call('clickPreset');s=self.settled()
        self.assertEqual(s['records'],1);self.assertTrue(self.call('presetState'))
        disk=self.fixture.root/'pins.json';saved=disk.read_text();disk.write_text('{external-conflict')
        self.call('clickPreset');s=self.settled()
        self.assertEqual(s['records'],1);self.assertTrue(self.call('presetState'));self.assertIn('externally',s['error'])
        self.assertEqual(disk.read_text(),'{external-conflict')
        # Restore only this owned fixture, then actually restart its QML/writer.
        proc=self.fixture.proc
        env=dict(part.split('=',1) for part in Path(f'/proc/{proc.pid}/environ').read_text().split('\0') if '=' in part)
        proc.terminate();proc.wait(timeout=3);disk.write_text(saved)
        self.fixture.proc=safety.spawn(proc.args,required="offscreen",root=self.fixture.root,env=env,stdout=self.fixture.log,stderr=subprocess.STDOUT)
        for _ in range(100):
            if self.call('state',check=False) is not None and self.call('integrated')['ready']: break
            time.sleep(.02)
        self.call('begin');self.assertTrue(self.call('presetState'));self.assertEqual(self.settled()['records'],1)
    def test_durable_success_and_duplicate_add(self):
        self.begin();self.assertTrue(self.call('accept'));s=self.settled()
        self.assertFalse(s['selecting']);self.assertEqual(s['records'],1)
        self.assertEqual(json.loads((self.fixture.root/'pins.json').read_text())['launchers'][0]['target'],str(self.fixture.folder))
        self.begin();self.assertTrue(self.call('accept'));s=self.settled()
        self.assertTrue(s['selecting']);self.assertEqual(s['records'],1)
        self.assertFalse((self.fixture.root/'receipt.json').exists())
