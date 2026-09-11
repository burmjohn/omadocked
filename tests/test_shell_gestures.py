"""Actual offscreen input through exact production bridges to owned argv receipts."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import spawn_safety as safety
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ShellGestureIntegration(unittest.TestCase):
    def test_offscreen_receipts_and_nonlaunching_guard(self):
        with tempfile.TemporaryDirectory(prefix="omadocked-gestures-") as td:
            root=Path(td)
            for directory in ('ui','core','services'):
                shutil.copytree(ROOT/directory,root/directory)
            service=root/'services/ShellGestures.qml'
            self.assertTrue(service.exists(), 'production shell gesture dispatcher is missing')
            dock=(ROOT/'Dock.qml').read_text()
            start=dock.index('    function shellGesture(')
            method=dock[start:dock.index('\n    }',start)+6]
            handler=next(l for l in (ROOT/'DockSurface.qml').read_text().splitlines() if 'onShellGestureRequested:' in l)
            shell='''import QtQuick
import QtTest
import Quickshell
import Quickshell.Io
import "ui"
import "services"
ShellRoot {
 id: root
 property var controller: bridge
 QtObject { id: bridge; property bool testMode: false
METHOD
 }
 ShellGestures { id: shellGestures; enabled: !bridge.testMode }
 Window { visible:true; width:1000; height:800
  TestCase { id: input; visible:true; when:false; name:"OwnedGestures" }
  DockView { id:view; autoHide:false; reducedMotion:true; appsManaged:true
HANDLER
  }
 }
 IpcHandler { target:"fixture"
  function ready(): bool { return true; }
  function block(value: bool): void { bridge.testMode=value; }
  function gesture(kind: string, delta: real): bool { return bridge.shellGesture(kind,delta); }
  function click(button: int): string {
   const x=view.renderedSlots[0].center, y=view.rowY+15;
   input.mousePress(view,x,y,button);
   const pressed=input.findChild(view,"rowInput").pressed;
   input.mouseRelease(view,x,y,button);
   return JSON.stringify({pressed:pressed,settings:view.settingsOpen});
  }
  function wheel(delta: int): void { input.mouseWheel(view,view.renderedSlots[0].center,view.rowY+15,0,delta); }
 }
}'''.replace('METHOD',method).replace('HANDLER',handler)
            (root/'shell.qml').write_text(shell)
            bin_dir=root/'bin'; bin_dir.mkdir()
            receipts=root/'receipts.jsonl'
            for name in ('omarchy-menu','omarchy-launch-terminal','hyprctl'):
                path=bin_dir/name
                path.write_text('#!/usr/bin/python3\nimport json,sys,os\nwith open(os.environ["RECEIPTS"],"a") as f: f.write(json.dumps([os.path.basename(sys.argv[0])]+sys.argv[1:])+"\\n")\n')
                path.chmod(0o755)
            env=dict(safety.fixture_environment(),QT_QPA_PLATFORM='offscreen',QT_QUICK_BACKEND='software',QS_NO_RELOAD_POPUP='1',PATH=str(bin_dir)+':'+os.environ['PATH'],RECEIPTS=str(receipts))
            with (root/'runtime.log').open('w+') as log:
                proc=safety.spawn(['quickshell','-p',str(root/'shell.qml'),'--no-color'],required="offscreen",root=root,env=env,stdout=log,stderr=subprocess.STDOUT)
                try:
                    def call(method,*args):
                        result=safety.ipc(proc, ['quickshell','ipc','--pid',str(proc.pid),'call','fixture',method,*map(str,args)],capture_output=True,text=True,timeout=3)
                        if result.returncode: raise RuntimeError(result.stderr)
                        return json.loads(result.stdout) if result.stdout.strip() else None
                    deadline=time.monotonic()+8
                    while True:
                        self.assertIsNone(proc.poll(),(root/'runtime.log').read_text())
                        try:
                            if call('ready'): break
                        except RuntimeError: pass
                        self.assertLess(time.monotonic(),deadline)
                        time.sleep(.03)
                    for button in (1,4): self.assertEqual(call('click',button),{'pressed':True,'settings':False})
                    call('wheel',-120); call('wheel',120)
                    deadline=time.monotonic()+3
                    while not receipts.exists() or len(receipts.read_text().splitlines())<4:
                        self.assertLess(time.monotonic(),deadline); time.sleep(.02)
                    expected=[['omarchy-menu','toggle','root'],['omarchy-launch-terminal'],
                              ['hyprctl','eval','hl.dsp.focus({ workspace = "e+1" })'],
                              ['hyprctl','eval','hl.dsp.focus({ workspace = "e-1" })']]
                    self.assertCountEqual([json.loads(l) for l in receipts.read_text().splitlines()],expected)
                    self.assertEqual(call('click',2),{'pressed':True,'settings':True})
                    for kind,delta in [('wheel',0),('wheel',float('nan')),('bad',0),('right',0)]:
                        self.assertFalse(call('gesture',kind,delta))
                    call('block','true')
                    self.assertFalse(call('gesture','left',0)); self.assertFalse(call('gesture','wheel',120))
                    time.sleep(.08)
                    self.assertEqual(len(receipts.read_text().splitlines()),4)
                finally:
                    proc.terminate()
                    try: proc.wait(timeout=5)
                    except subprocess.TimeoutExpired: proc.kill(); proc.wait(timeout=5)
