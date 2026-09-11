"""Real folder launch receipts in an isolated PATH; never user applications."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]

class FolderActionTests(unittest.TestCase):
    def test_exact_argv_terminal_cwd_and_replaced_root_rejection(self):
        with tempfile.TemporaryDirectory(prefix="omadocked-folder-action-") as temporary:
            root = Path(temporary)
            folder = root / "folder ; $(touch BAD) '"
            folder.mkdir()
            child = folder / "file ' ; $(touch BAD).txt"
            child.write_text("fixture")
            receipt = root / "receipt.json"
            for command in ("xdg-open", "xdg-terminal-exec"):
                program = root / command
                program.write_text("#!/usr/bin/python3\nimport json,os,sys\nfrom pathlib import Path\nPath(os.environ['RECEIPT']).write_text(json.dumps({'argv':sys.argv[1:],'cwd':os.getcwd()}))\n")
                program.chmod(0o700)
            stat = folder.stat()
            record = {"kind":"folder-action", "enabled":True, "action":"entry", "root":str(folder), "target":str(child), "rootIdentity":{"device":str(stat.st_dev), "inode":str(stat.st_ino)}}
            env = dict(os.environ, PATH=str(root), RECEIPT=str(receipt), OMADOCKED_TEST_MODE="0")
            def run(value):
                return subprocess.run(["/usr/bin/python3", str(ROOT / "services/launch_app.py"), "--record", json.dumps(value)], env=env, capture_output=True, text=True, timeout=4)
            result = run(record)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(receipt.read_text())["argv"], [str(child)])
            result = run(dict(record, action="terminal", target=str(folder)))
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(receipt.read_text()), {"argv":["--dir=" + str(folder)], "cwd":str(folder)})
            receipt.unlink()
            folder.rename(root / "old")
            folder.mkdir()
            child.write_text("replacement")
            self.assertNotEqual(run(record).returncode, 0)
            self.assertFalse(receipt.exists())
            self.assertFalse((root / "BAD").exists())

    def test_scan_cli_sigterm_reaps_blocked_worker(self):
        with tempfile.TemporaryDirectory(prefix="omadocked-folder-cancel-") as temporary:
            root = Path(temporary)
            # Inject a blocking filesystem probe into only this owned scanner copy.
            source = (ROOT / "services/folder_scan.py").read_text()
            source = source.replace("root_fd = os.open(path, flags)", "time.sleep(30)\n        root_fd = os.open(path, flags)")
            helper = root / "scan.py"
            helper.write_text(source)
            proc = subprocess.Popen(["/usr/bin/python3", str(helper)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            try:
                proc.stdin.write(json.dumps({"path":str(root), "generation":1, "token":"owned", "timeoutMs":10000}))
                proc.stdin.close()
                child = None
                for _ in range(100):
                    children = Path(f"/proc/{proc.pid}/task/{proc.pid}/children").read_text().split()
                    if children:
                        child = int(children[0])
                        break
                    time.sleep(.01)
                self.assertIsNotNone(child)
                proc.terminate()
                proc.wait(timeout=2)
                for _ in range(100):
                    if not Path(f"/proc/{child}").exists():
                        break
                    time.sleep(.01)
                self.assertFalse(Path(f"/proc/{child}").exists(), "scanner worker survived cancellation")
            finally:
                if proc.poll() is None:
                    proc.kill()
                    proc.wait()
                if child and Path(f"/proc/{child}").exists():
                    os.kill(child, signal.SIGKILL)
                proc.stdout.close()
                proc.stderr.close()

if __name__ == "__main__":
    unittest.main()
