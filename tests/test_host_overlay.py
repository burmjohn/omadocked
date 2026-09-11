"""Isolated host-shaped overlay lifecycle; never touches the installed shell."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import spawn_safety as safety
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HostOverlayLifecycleTests(unittest.TestCase):
    def test_keep_loaded_overlay_unloads_helper_and_reloads_cleanly(self):
        with tempfile.TemporaryDirectory(prefix="omadocked-host-overlay-") as temp:
            root = Path(temp)
            config = root / "config encoded # % :" / "pins.json"
            receipt = root / "child-fds.json"
            child = root / "child.py"
            child.write_text('import json,os\nfrom pathlib import Path\nfds={}\nfor fd in Path("/proc/self/fd").iterdir():\n try: fds[fd.name]=os.readlink(fd)\n except OSError: pass\nPath(' + repr(str(receipt)) + ').write_text(json.dumps(fds))\n')
            shell = root / "shell.qml"
            shell.write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
  QtObject { id: host; property string marker: "isolated-host" }
  property int persistenceReceiptId: 0
  property int persistenceReceiptCount: 0
  Loader {
    id: overlay
    active: true
    source: ''' + json.dumps((ROOT / "Dock.qml").as_uri()) + '''
    onLoaded: {
      if (item.shell !== undefined) item.shell = host
      if (item.manifest !== undefined) item.manifest = ({id:"fixture.omadocked", keepLoaded:true})
    }
  }
  Connections {
    target: overlay.item
    ignoreUnknownSignals: true
    function onPersistenceCompleted(transactionId, ok, message) {
      persistenceReceiptId = transactionId
      persistenceReceiptCount++
    }
  }
  Process { id: childProbe; command: ["/usr/bin/python3", ''' + json.dumps(str(child)) + '''] }
  IpcHandler {
    target: "host-overlay-test"
    function state(): string { return JSON.stringify({loaded: overlay.status === Loader.Ready, ready: overlay.item ? overlay.item.ready : false, hostInjected: overlay.item ? overlay.item.shell === host && overlay.item.manifest.id === "fixture.omadocked" : false, opened: overlay.item ? overlay.item.opened : null, visible: overlay.item ? JSON.parse(overlay.item.snapshot()).visible : false, legacyPolicy:overlay.item ? overlay.item.legacyPolicy : null, environmentMonitorOverride:overlay.item ? overlay.item.environmentMonitorOverride : null, monitorMode:overlay.item ? overlay.item.monitorMode : "", selectedOutputs:overlay.item ? overlay.item.selectedOutputs : [], receiptId:persistenceReceiptId, receiptCount:persistenceReceiptCount, error: overlay.item ? overlay.item.appError : ""}) }
    function lifecycle(): string {
      const before = overlay.item.opened
      overlay.item.open('{"source":"host-fixture"}')
      const afterOpen = overlay.item.opened
      overlay.item.close()
      return JSON.stringify({before:before, afterOpen:afterOpen, afterClose:overlay.item.opened,
        visible:JSON.parse(overlay.item.snapshot()).visible})
    }
    function child(): bool { childProbe.running = true; return true }
    function save(name: string): int { return overlay.item.saveLauncher(JSON.stringify({kind:"command",name:name,program:"/usr/bin/true",enabled:true})) }
    function monitors(): int { return overlay.item.monitors("selected", '["stored-output"]') }
    function unload(): bool { overlay.active = false; return true }
    function load(): bool { overlay.active = true; return true }
  }
}
''')
            env = {key: value for key, value in safety.fixture_environment().items()
                   if not key.startswith("OMADOCKED_") and key not in ("QS_CONFIG_PATH", "QS_CONFIG_NAME", "QS_MANIFEST")}
            env.update(QT_QPA_PLATFORM="wayland", QS_NO_RELOAD_POPUP="1", OMADOCKED_TEST_MODE="1",
                       OMADOCKED_VISIBLE="0", OMADOCKED_SCREEN="fixture-output", OMADOCKED_CONFIG_PATH=str(config))
            log_path = root / "runtime.log"
            with log_path.open("w+") as log:
                proc = safety.spawn(["quickshell", "-p", str(shell), "--no-color"], required="native", root=root, env=env,
                                        stdout=log, stderr=subprocess.STDOUT)
                try:
                    def call(method, *args):
                        result = safety.ipc(proc, ["quickshell", "ipc", "--pid", str(proc.pid), "call", "--",
                                                 "host-overlay-test", method, *args], capture_output=True, text=True, timeout=3)
                        if method in ("state", "lifecycle", "save", "monitors"):
                            if result.returncode or not result.stdout.strip():
                                return None
                            return json.loads(result.stdout)
                        return result.returncode == 0
                    deadline = time.monotonic() + 8
                    state = None
                    while time.monotonic() < deadline:
                        state = call("state")
                        if state and state.get("ready"):
                            break
                        time.sleep(.05)
                    self.assertEqual(state, {"loaded": True, "ready": True, "hostInjected": True,
                                             "opened": False, "visible": False, "receiptId": 0,
                                             "legacyPolicy": True, "environmentMonitorOverride": False,
                                             "monitorMode": "selected", "selectedOutputs": ["fixture-output"],
                                             "receiptCount": 0, "error": ""}, log_path.read_text())
                    self.assertEqual(call("lifecycle"), {"before": False, "afterOpen": True,
                                                         "afterClose": False, "visible": False})
                    for name in ("first", "second"):
                        transaction_id = call("save", name)
                        self.assertGreater(transaction_id, 0)
                        deadline = time.monotonic() + 3
                        while time.monotonic() < deadline:
                            state = call("state")
                            if state["receiptId"] == transaction_id:
                                break
                            time.sleep(.01)
                        self.assertEqual(state["receiptId"], transaction_id)
                    recovery = safety.ipc(proc, ["quickshell", "ipc", "--pid", str(proc.pid), "call", "--",
                                               "omadocked-recovery", "status"], capture_output=True, text=True, timeout=3)
                    self.assertEqual(recovery.returncode, 0, recovery.stdout + recovery.stderr)
                    self.assertEqual(json.loads(recovery.stdout), {"ready": True, "busy": False, "records": [],
                                                                   "revision": 0, "last": {}})
                    children = Path(f"/proc/{proc.pid}/task/{proc.pid}/children").read_text().split()
                    self.assertEqual(len(children), 1)
                    command = Path(f"/proc/{children[0]}/cmdline").read_bytes().replace(b"\0", b" ")
                    self.assertIn(b"config_store.py", command)
                    self.assertNotIn(b"polkit", command.lower())
                    self.assertNotIn(b"notification", command.lower())
                    os.kill(int(children[0]), 19)  # SIGSTOP: hold the writer before its receipt.
                    monitor_transaction_id = call("monitors")
                    state = call("state")
                    os.kill(int(children[0]), 18)  # SIGCONT: always release the held writer.
                    self.assertGreater(monitor_transaction_id, transaction_id)
                    self.assertTrue(state["legacyPolicy"])
                    self.assertEqual(state["monitorMode"], "selected")
                    self.assertEqual(state["selectedOutputs"], ["fixture-output"])
                    # Allow the matching commit receipt.
                    deadline = time.monotonic() + 3
                    while time.monotonic() < deadline:
                        state = call("state")
                        if state["receiptId"] == monitor_transaction_id:
                            break
                        time.sleep(.01)
                    self.assertEqual(state["receiptId"], monitor_transaction_id)
                    self.assertFalse(state["legacyPolicy"])
                    self.assertEqual(state["monitorMode"], "selected")
                    self.assertEqual(state["selectedOutputs"], ["stored-output"])
                    self.assertTrue(call("child"))
                    deadline = time.monotonic() + 3
                    while not receipt.exists() and time.monotonic() < deadline:
                        time.sleep(.02)
                    self.assertTrue(receipt.exists())
                    self.assertNotIn(str(config) + ".lock", json.loads(receipt.read_text()).values())
                    self.assertTrue(call("unload"))
                    deadline = time.monotonic() + 3
                    while Path(f"/proc/{children[0]}").exists() and time.monotonic() < deadline:
                        time.sleep(.02)
                    self.assertFalse(Path(f"/proc/{children[0]}").exists())
                    with open(str(config) + ".lock", "r+") as stream:
                        fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
                    self.assertTrue(call("load"))
                    deadline = time.monotonic() + 8
                    while time.monotonic() < deadline:
                        state = call("state")
                        if state and state.get("ready"):
                            break
                        time.sleep(.05)
                    self.assertEqual(state, {"loaded": True, "ready": True, "hostInjected": True,
                                             "opened": False, "visible": False, "receiptId": monitor_transaction_id,
                                             "legacyPolicy": True, "environmentMonitorOverride": False,
                                             "monitorMode": "selected", "selectedOutputs": ["fixture-output"],
                                             "receiptCount": 3, "error": ""})
                finally:
                    proc.terminate()
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        proc.kill(); proc.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
