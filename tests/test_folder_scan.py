"""P3-05 bounded folder metadata scanner contract."""
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

MODULE_PATH = Path(__file__).resolve().parents[1] / "services" / "folder_scan.py"


def load_module():
    spec = importlib.util.spec_from_file_location("folder_scan", MODULE_PATH)
    if spec is None or spec.loader is None:
        raise RuntimeError("Unable to load folder scanner")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class FolderScanTests(unittest.TestCase):
    def setUp(self):
        self.scan = load_module().scan_folder

    def test_empty_missing_not_directory_and_unreadable_are_distinct_and_private(self):
        with tempfile.TemporaryDirectory(prefix="omadocked-folder-") as temp:
            root = Path(temp)
            empty = root / "empty folder"
            empty.mkdir()
            ordinary = root / "ordinary.txt"
            ordinary.write_text("private contents")
            locked = root / "locked-secret-name"
            locked.mkdir()
            locked.chmod(0)
            try:
                cases = [
                    (empty, "empty"),
                    (root / "missing-secret-name", "missing"),
                    (ordinary, "not-directory"),
                    (locked, "unreadable"),
                ]
                for path, expected in cases:
                    with self.subTest(expected=expected):
                        result = self.scan(str(path), 7, "request_token")
                        self.assertEqual(result["status"], expected)
                        self.assertEqual(result["generation"], 7)
                        self.assertEqual(result["token"], "request_token")
                        self.assertNotIn(str(path), json.dumps(result.get("error", "")))
                        self.assertNotIn("secret-name", json.dumps(result.get("receipt", {})))
            finally:
                locked.chmod(stat.S_IRWXU)

    def test_returns_newest_sixteen_non_dot_entries_without_following_symlinks(self):
        with tempfile.TemporaryDirectory(prefix="omadocked folder 'quotes' ") as temp:
            root = Path(temp)
            names = [f"item {i:02d} 'q'.txt" for i in range(18)]
            names[3] = "line\nbreak.txt"
            for index, name in enumerate(names):
                path = root / name
                path.write_bytes(("payload-%d" % index).encode())
                stamp = 1_700_000_000_000_000_000 + index * 1_000_000_000
                os.utime(path, ns=(stamp, stamp))
            hidden = root / ".private"
            hidden.write_text("must not appear")
            target = root / "item 17 'q'.txt"
            link = root / "newest symlink"
            link.symlink_to(target)
            os.utime(link, ns=(1_800_000_000_000_000_000, 1_800_000_000_000_000_000),
                     follow_symlinks=False)

            result = self.scan(str(root), 2, "tok-2", max_inspected=64,
                               now_ns=1_800_000_010_000_000_000)
            self.assertEqual(result["status"], "ok")
            self.assertTrue(result["complete"])
            self.assertEqual(result["total"], 19)
            self.assertEqual(result["omitted"], 3)
            self.assertEqual(len(result["entries"]), 16)
            self.assertEqual(result["entries"][0]["name"], "newest symlink")
            self.assertEqual(result["entries"][0]["type"], "symlink")
            self.assertEqual(result["entries"][0]["iconCategory"], "link")
            self.assertIsNone(result["entries"][0]["size"])
            self.assertEqual(result["entries"][0]["path"], str(link))
            self.assertFalse(any(row["name"].startswith(".") for row in result["entries"]))
            self.assertTrue(all("content" not in key.lower() for row in result["entries"] for key in row))
            self.assertTrue(all(set(row) == {"name", "path", "type", "size", "mtimeNs", "relativeTime", "iconCategory"}
                                for row in result["entries"]))

    def test_posix_backslash_filename_is_preserved(self):
        with tempfile.TemporaryDirectory(prefix="omadocked-backslash-") as temp:
            name = "literal\\name.txt"
            (Path(temp) / name).touch()
            result = self.scan(temp, 10, "backslash")
            self.assertEqual(result["entries"][0]["name"], name)
            self.assertEqual(result["entries"][0]["path"], str(Path(temp) / name))

    def test_root_symlink_is_rejected_and_root_swap_fails_closed(self):
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="omadocked-anchor-") as temp:
            parent = Path(temp)
            root = parent / "root"
            root.mkdir()
            (root / "original").touch()
            link = parent / "root-link"
            link.symlink_to(root, target_is_directory=True)
            self.assertEqual(module.scan_folder(str(link), 11, "symlink")["status"], "not-directory")

            actual_scandir = module.os.scandir
            moved = parent / "moved"
            def swap_then_scan(directory):
                root.rename(moved)
                root.mkdir()
                (root / "replacement").touch()
                return actual_scandir(directory)
            with patch.object(module.os, "scandir", side_effect=swap_then_scan):
                result = module.scan_folder(str(root), 12, "swap")
            self.assertEqual(result["status"], "changed")
            self.assertEqual(result["entries"], [])

    def test_success_receipt_identifies_anchored_root_inode(self):
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="omadocked-inode-") as temp:
            result = module.scan_folder(temp, 13, "inode")
            metadata = os.stat(temp, follow_symlinks=False)
            self.assertEqual(result["rootIdentity"], {
                "device": str(metadata.st_dev), "inode": str(metadata.st_ino)})

    def test_process_wrapper_enforces_hard_timeout_and_cancellation(self):
        module = load_module()
        with tempfile.TemporaryDirectory(prefix="omadocked-hard-") as temp:
            actual_scandir = module.os.scandir
            def blocking_scandir(directory):
                time.sleep(2)
                return actual_scandir(directory)
            with patch.object(module.os, "scandir", side_effect=blocking_scandir):
                started = time.monotonic()
                timed = module.scan_folder_hard(temp, 14, "hard-timeout", timeout_seconds=0.05)
                elapsed = time.monotonic() - started
            self.assertEqual(timed["status"], "timeout")
            self.assertLess(elapsed, 0.5)

            cancel_started = time.monotonic()
            with patch.object(module.os, "scandir", side_effect=blocking_scandir):
                cancelled = module.scan_folder_hard(temp, 15, "hard-cancel", timeout_seconds=1,
                    cancelled=lambda: time.monotonic() - cancel_started >= 0.05)
            self.assertEqual(cancelled["status"], "cancelled")
            self.assertLess(time.monotonic() - cancel_started, 0.5)

    def test_inspection_cap_is_honest_and_never_claims_an_exact_remainder(self):
        with tempfile.TemporaryDirectory(prefix="omadocked-large-") as temp:
            for index in range(12):
                (Path(temp) / f"entry-{index}").touch()
            result = self.scan(temp, 3, "large", max_inspected=5)
            self.assertEqual(result["status"], "too-large")
            self.assertFalse(result["complete"])
            self.assertEqual(result["inspected"], 5)
            self.assertEqual(result["observedAtLeast"], 6)
            self.assertNotIn("total", result)
            self.assertNotIn("omitted", result)
            self.assertEqual(result["entries"], [])

    def test_timeout_and_cancellation_are_distinct_bounded_results(self):
        with tempfile.TemporaryDirectory(prefix="omadocked-timeout-") as temp:
            (Path(temp) / "one").touch()
            timed = self.scan(temp, 4, "timed", timeout_seconds=0)
            cancelled = self.scan(temp, 5, "cancelled", cancelled=lambda: True)
            self.assertEqual(timed["status"], "timeout")
            self.assertEqual(cancelled["status"], "cancelled")
            self.assertFalse(timed["complete"])
            self.assertFalse(cancelled["complete"])

    def test_disappearing_entries_are_skipped_and_directory_races_are_classified(self):
        module = load_module()

        class VanishedEntry:
            name = "gone"
            path = "/owned/gone"
            def stat(self, follow_symlinks=False):
                raise FileNotFoundError

        class ScanContext:
            def __enter__(self): return iter([VanishedEntry()])
            def __exit__(self, *args): return False

        with tempfile.TemporaryDirectory(prefix="omadocked-race-") as temp:
            with patch.object(module.os, "scandir", return_value=ScanContext()):
                result = module.scan_folder(temp, 6, "race")
                self.assertEqual(result["status"], "empty")
                self.assertEqual(result["inspected"], 1)
                self.assertEqual(result["total"], 0)
        with patch.object(module.os, "open", side_effect=FileNotFoundError):
            self.assertEqual(module.scan_folder("/owned", 6, "race")["status"], "missing")
        with patch.object(module.os, "open", side_effect=PermissionError):
            self.assertEqual(module.scan_folder("/owned", 6, "race")["status"], "unreadable")

    def test_rejects_non_absolute_paths_and_invalid_request_identity(self):
        for args in [("relative", 0, "ok"), ("/tmp", -1, "ok"), ("/tmp", 1.5, "ok"),
                     ("/tmp", 1, ""), ("/tmp", 1, "bad token"), ("/tmp", 1, "x" * 129)]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                self.scan(*args)

    def test_cli_accepts_one_json_request_and_preserves_literal_path(self):
        with tempfile.TemporaryDirectory(prefix="omadocked cli ' ") as temp:
            name = "literal $(not-shell) ' file"
            (Path(temp) / name).touch()
            request = {"path": temp, "generation": 9, "token": "cli_token", "maxInspected": 8}
            completed = subprocess.run([sys.executable, str(MODULE_PATH)], input=json.dumps(request),
                                       text=True, capture_output=True, timeout=3, check=False)
            self.assertEqual(completed.returncode, 0, completed.stderr)
            result = json.loads(completed.stdout)
            self.assertEqual(result["entries"][0]["name"], name)
            self.assertEqual(result["entries"][0]["path"], str(Path(temp) / name))
            self.assertNotIn("private contents", completed.stdout + completed.stderr)


if __name__ == "__main__":
    unittest.main()
