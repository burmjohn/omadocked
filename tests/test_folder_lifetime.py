"""Real scanner descendants: QML destruction, SIGKILL and fork/setup race."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
import test_folder_service as fixtures

ROOT = Path(__file__).resolve().parents[1]


def gone(pid):
    for _ in range(200):
        if not Path(f'/proc/{pid}').exists():
            return True
        time.sleep(.005)
    return False


def marker_pid(marker):
    for _ in range(200):
        if marker.exists() and marker.read_text():
            return int(marker.read_text())
        time.sleep(.005)
    raise AssertionError('worker did not reach injected boundary')


class FolderLifetimeTests(unittest.TestCase):
    def test_loader_destruction_reaps_blocked_worker_repeatedly(self):
        original = fixtures.SHELL
        fixtures.SHELL = original.replace('FolderService { id: folders }',
            'property var folders: disposable.item\nLoader { id:disposable; sourceComponent: FolderService {} }').replace(
            'function state(): string', 'function dispose(): void { disposable.active=false; }\nfunction recreate(): void { disposable.active=true; }\nfunction state(): string')
        f = fixtures.FolderServiceTests('test_real_recent_metadata_and_stale_action')
        try:
            f.setUp()
        finally:
            fixtures.SHELL = original
        pids = []
        try:
            helper = f.root/'services/folder_scan.py'
            marker = f.root/'worker.pid'
            helper.write_text(helper.read_text().replace('root_fd = os.open(path, flags)',
                f'open({str(marker)!r}, "w").write(str(os.getpid()))\n        time.sleep(30)\n        root_fd = os.open(path, flags)'))
            for _ in range(5):
                marker.unlink(missing_ok=True)
                f.call('open', f.folder)
                pid = marker_pid(marker); pids.append(pid)
                f.call('dispose')
                self.assertTrue(gone(pid), f'worker {pid} outlived Loader')
                f.call('recreate')
            print(json.dumps({'loader_cycles':len(pids), 'all_workers_gone':True}))
        finally:
            for pid in pids:
                if Path(f'/proc/{pid}').exists():
                    os.kill(pid, signal.SIGKILL); gone(pid)
            f.tearDown()

    def supervisor_loss(self, setup_race):
        with tempfile.TemporaryDirectory(prefix='folder-death-') as temp:
            root = Path(temp); marker = root/'worker.pid'; resume = root/'resume'
            source = (ROOT/'services/folder_scan.py').read_text()
            if setup_race:
                source = source.replace('        root_fd = os.open(path, flags)',
                    '        time.sleep(30)\n        root_fd = os.open(path, flags)')
                # Pause before *any* child target code (including death setup).
                boundary = '    signal.signal(signal.SIGTERM, signal.SIG_DFL)'
                injection = (f'    open({str(marker)!r}, "w").write(str(os.getpid()))\n'
                    f'    while not os.path.exists({str(resume)!r}): time.sleep(.001)\n')
            else:
                boundary = '        root_fd = os.open(path, flags)'
                injection = f'        open({str(marker)!r}, "w").write(str(os.getpid()))\n        time.sleep(30)\n'
            self.assertIn(boundary, source)
            helper = root/'scan.py'; helper.write_text(source.replace(boundary, injection+boundary, 1))
            proc = subprocess.Popen([sys.executable, str(helper)], stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            pid = None
            try:
                proc.stdin.write(json.dumps({'path':temp,'generation':1,'token':'death','timeoutMs':10000}));proc.stdin.close()
                pid = marker_pid(marker)
                proc.kill();proc.wait(timeout=3)
                resume.touch()
                self.assertTrue(gone(pid), f'worker survives supervisor loss, setup_race={setup_race}')
            finally:
                if proc.poll() is None: proc.kill();proc.wait(timeout=3)
                if pid and Path(f'/proc/{pid}').exists(): os.kill(pid, signal.SIGKILL);gone(pid)
                proc.stdout.close();proc.stderr.close()

    def test_supervisor_sigkill(self): self.supervisor_loss(False)
    def test_supervisor_death_before_child_setup(self): self.supervisor_loss(True)
