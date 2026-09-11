"""Install the frozen user plugin after its matching host package is installed."""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

HERE = Path(__file__).resolve().parent
OLD = HERE.parents[1] / 'evidence/live-integration/candidate-nwh9b5v8'
PID = 1934522
PLUGIN = Path.home() / '.config/omarchy/plugins/burmjohn.omadocked'
CONFIG = Path.home() / '.config/omadocked/pins.json'
JOURNAL = Path.home() / '.local/state/omadocked/parking.json'
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def call(pid, *args):
    p = subprocess.run(['quickshell', 'ipc', '--pid', str(pid), 'call', '--', *args],
                       capture_output=True, text=True, timeout=8)
    p.check_returncode()
    return p.stdout.strip()
def snapshot(pid): return json.loads(call(pid, 'shell', 'call', 'burmjohn.omadocked', 'snapshot', ''))

assert os.geteuid() != 0, 'Run this as your normal user, not with sudo.'
assert sys.argv[1:] in ([], ['--check'])
files = json.loads((HERE / 'files.json').read_text())
assert all(sha(HERE / 'payload' / name) == value for name, value in files.items())
required = json.loads((HERE / 'required-host.json').read_text())
host_ready = all((Path('/usr/share/omarchy') / name).is_file() and
    sha(Path('/usr/share/omarchy') / name) == value for name, value in required.items())
assert b'/usr/share/omarchy/shell' in Path(f'/proc/{PID}/cmdline').read_bytes().split(b'\0'), 'Live host changed; stop for a fresh handoff.'
state = snapshot(PID)
assert state['appsReady'] and not state['appError'] and not state['parkingBusy']
assert state['parkedWindows'] == [], 'Recover parked windows before this migration.'
assert state['minimizeMode'] == 'off'
assert PLUGIN.is_symlink() and PLUGIN.resolve() == OLD / 'plugin'
assert not CONFIG.is_symlink() and not JOURNAL.exists()
if sys.argv[1:]:
    print(json.dumps({'payload_files_verified': len(files), 'source_ready': True,
                      'matching_host_installed': host_ready, 'live_changes': False}))
    raise SystemExit(0)
assert host_ready, 'Install the matching Omarchy host-support package first.'
assert json.loads(subprocess.check_output(['hyprctl', '-j', 'locked']))['locked'] is False
assert call(PID, 'lock', 'isLocked') == 'false'

backup_root = Path.home() / '.local/state/omadocked'
backup_root.mkdir(parents=True, exist_ok=True)
backup = Path(tempfile.mkdtemp(prefix='install-backup-', dir=backup_root))
shutil.copytree(HERE / 'payload', backup / 'new-plugin')
if CONFIG.exists(): shutil.copy2(CONFIG, backup / 'pins.json.before')
subprocess.run(['quickshell', 'kill', '--pid', str(PID)], check=True, timeout=12)
# The source writer has exited. Copy its latest committed state, not an earlier snapshot.
for source, destination in [(OLD / 'pins.json', CONFIG), (OLD / 'parking.json', JOURNAL)]:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.exists():
        shutil.copy2(source, destination)
        destination.chmod(0o600)
        assert sha(source) == sha(destination)
if (OLD / 'pins.json.lkg').exists():
    shutil.copy2(OLD / 'pins.json.lkg', CONFIG.with_name('pins.json.lkg'))
    CONFIG.with_name('pins.json.lkg').chmod(0o600)
PLUGIN.rename(backup / 'previous-plugin-link')
(backup / 'new-plugin').rename(PLUGIN)
assert not PLUGIN.is_symlink() and all(sha(PLUGIN / n) == h for n, h in files.items())
# Use the normal desktop environment and official launcher, not the agent's environment.
p = subprocess.run(['hyprctl', 'dispatch', 'hl.dsp.exec_cmd("omarchy-launch-shell")'],
                   capture_output=True, text=True, timeout=8)
p.check_returncode()
assert p.stdout.strip() == 'ok', p.stdout
expected = {k: state[k] for k in ['iconSize', 'transparency', 'minimizeMode', 'monitorMode', 'selectedOutputs']}
end = time.monotonic() + 30
while time.monotonic() < end:
    rows = subprocess.check_output(['ps', '-C', 'quickshell', '-o', 'pid=,args='], text=True)
    for row in rows.splitlines():
        parts = row.strip().split(maxsplit=1)
        if len(parts) == 2 and parts[1] == 'quickshell -n -p /usr/share/omarchy/shell':
            new_pid = int(parts[0])
            if new_pid == PID: continue
            try: current = snapshot(new_pid)
            except (ValueError, subprocess.SubprocessError): continue
            if current.get('appError'):
                raise SystemExit('Dock reported a startup error; inspect it before proceeding. Backup: ' + str(backup))
            if current.get('appsReady') and current.get('parkingReady') and current.get('visible'):
                assert all(current[k] == v for k, v in expected.items()), 'Settings readback mismatch'
                # A normal host has the system mount namespace, not the old overlay.
                assert os.readlink(f'/proc/{new_pid}/ns/mnt') == os.readlink('/proc/1369/ns/mnt')
                receipt = {'pid': new_pid, 'plugin': str(PLUGIN), 'settings': expected,
                           'backup': str(backup), 'normal_host': True}
                (backup_root / 'installed.json').write_text(json.dumps(receipt, indent=2))
                print(json.dumps(receipt, indent=2))
                raise SystemExit(0)
    time.sleep(0.25)
raise SystemExit('Host readiness not confirmed within 30 seconds. Backup: ' + str(backup))
