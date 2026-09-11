"""P3-09 helper-owned persistence protocol tests."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "services/config_store.py"


class Helper:
    def __init__(self, path):
        self.proc = subprocess.Popen(
            [sys.executable, str(HELPER), str(path)],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1)
        self.ready = self.read()

    def read(self):
        line = self.proc.stdout.readline()
        if not line:
            raise AssertionError(self.proc.stderr.read())
        return json.loads(line)

    def request(self, message):
        self.proc.stdin.write(json.dumps(message, separators=(",", ":")) + "\n")
        self.proc.stdin.flush()
        return self.read()

    def close(self):
        if self.proc.poll() is None:
            self.proc.terminate()
        self.proc.wait(timeout=3)
        self.proc.stdin.close()
        self.proc.stdout.close()
        self.proc.stderr.close()


class ConfigStoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omadocked-store-")
        self.addCleanup(self.temp.cleanup)
        self.path = Path(self.temp.name) / "encoded space # % :" / "pins.json"
        self.helpers = []

    def helper(self):
        helper = Helper(self.path)
        self.helpers.append(helper)
        return helper

    def tearDown(self):
        for helper in reversed(self.helpers):
            helper.close()

    def test_real_competing_helper_is_read_only_until_owner_exits(self):
        first = self.helper()
        self.assertEqual(first.ready, {"type": "ready", "ok": True, "missing": True, "text": "", "backup": ""})
        second = self.helper()
        self.assertEqual(second.ready, {"type": "ready", "ok": False, "error": "busy"})
        self.assertIsNone(first.proc.poll())
        first.close()
        third = self.helper()
        self.assertTrue(third.ready["ok"])

    def test_commit_readback_lkg_and_recovery_are_one_helper_transaction(self):
        helper = self.helper()
        one = '{"version":2,"pins":["one"]}\n'
        two = '{"version":2,"pins":["two"]}\n'
        self.assertEqual(helper.request({"id": 1, "op": "commit", "expected": "", "missing": True,
                                         "replacement": one, "fallback": one}),
                         {"id": 1, "ok": True, "committed": True, "backupDegraded": False, "outcome": "durable"})
        self.assertEqual(self.path.read_text(), one)
        self.assertEqual(Path(str(self.path) + ".lkg").read_text(), one)
        self.assertTrue(helper.request({"id": 2, "op": "commit", "expected": one, "missing": False,
                                        "replacement": two, "fallback": one})["ok"])
        self.assertEqual(self.path.read_text(), two)
        self.assertEqual(Path(str(self.path) + ".lkg").read_text(), two)
        damaged = "{broken"
        self.path.write_text(damaged)
        response = helper.request({"id": 3, "op": "recover", "expected": damaged, "backup": two})
        self.assertTrue(response["ok"], response)
        self.assertEqual(self.path.read_text(), two)
        preserved = list(self.path.parent.glob("pins.json.damaged-*"))
        self.assertEqual(len(preserved), 1)
        self.assertEqual(preserved[0].read_text(), damaged)

    def test_compare_conflict_never_replaces_external_bytes(self):
        helper = self.helper()
        external = '{"version":2,"pins":["external"]}\n'
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(external)
        response = helper.request({"id": 4, "op": "commit", "expected": "", "missing": True,
                                   "replacement": "{}\n", "fallback": "{}\n"})
        self.assertEqual(response, {"id": 4, "ok": False, "error": "conflict", "outcome": "no-commit"})
        self.assertEqual(self.path.read_text(), external)
        self.assertFalse(Path(str(self.path) + ".lkg").exists())

    def test_lock_fd_is_cloexec_and_not_inherited_by_child(self):
        helper = self.helper()
        lock = str(self.path) + ".lock"
        lock_fds = [fd for fd in Path(f"/proc/{helper.proc.pid}/fd").iterdir()
                    if os.readlink(fd) == lock]
        self.assertEqual(len(lock_fds), 1)
        flags = Path(f"/proc/{helper.proc.pid}/fdinfo/{lock_fds[0].name}").read_text()
        flag_value = int(next(line.split()[1] for line in flags.splitlines() if line.startswith("flags:")), 8)
        self.assertTrue(flag_value & os.O_CLOEXEC)
        child = subprocess.run([sys.executable, "-c", "import os; print(' '.join(os.listdir('/proc/self/fd')))"] ,
                               capture_output=True, text=True, close_fds=False)
        self.assertEqual(child.returncode, 0)
        with open(lock, "r+") as stream:
            with self.assertRaises(BlockingIOError):
                fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)

    def test_dot_components_and_unsafe_lock_fail_without_path_or_data_in_error(self):
        bad = Path(self.temp.name) / "x" / ".." / "pins.json"
        result = subprocess.run([sys.executable, str(HELPER), str(bad)], input="", capture_output=True, text=True)
        self.assertEqual(json.loads(result.stdout), {"type": "ready", "ok": False, "error": "unsafe"})
        self.assertNotIn(str(bad), result.stdout + result.stderr)
        self.path.parent.mkdir(parents=True)
        Path(str(self.path) + ".lock").symlink_to(self.path)
        result = subprocess.run([sys.executable, str(HELPER), str(self.path)], input="", capture_output=True, text=True)
        self.assertEqual(json.loads(result.stdout), {"type": "ready", "ok": False, "error": "unsafe"})
        self.assertNotIn(str(self.path), result.stdout + result.stderr)
        public_parent = Path(self.temp.name) / "public-parent"
        public_parent.mkdir(mode=0o700)
        public_parent.chmod(0o777)
        public_path = public_parent / "pins.json"
        result = subprocess.run([sys.executable, str(HELPER), str(public_path)], input="", capture_output=True, text=True)
        self.assertEqual(json.loads(result.stdout), {"type": "ready", "ok": False, "error": "unsafe"})
        self.assertFalse(Path(str(public_path) + ".lock").exists())


if __name__ == "__main__":
    unittest.main()
