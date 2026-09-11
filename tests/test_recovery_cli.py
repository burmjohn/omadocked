"""Installed enable/disable/remove CLI contracts against an owned HOME and IPC shim.
No live omarchy-shell endpoint is reachable: every bridge request is allowlisted.
These test the CLI, not the real host config mutator or watcher ordering.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class RecoveryCliTests(unittest.TestCase):
    # Discovery never exports; direct CLI execution may opt in explicitly.
    evidence_dir = None

    def test_installed_lifecycle_commands_preserve_external_state(self):
        with tempfile.TemporaryDirectory(prefix='omadocked-recovery-cli-') as directory:
            root = Path(directory)
            home = root / 'home'
            package = home / '.config/omarchy/plugins/burmjohn.omadocked'
            package.mkdir(parents=True)
            (package / 'manifest.json').write_bytes((ROOT / 'manifest.json').read_bytes())
            journal = home / '.local/state/omadocked/parking.json'
            journal.parent.mkdir(parents=True)
            journal.write_text('owned durable sentinel')
            state = root / 'enabled.json'
            state.write_text('true')
            log = root / 'calls.jsonl'
            commands = root / 'bin'
            commands.mkdir()
            shim = commands / 'omarchy-shell'
            shim.write_text('''#!/usr/bin/python3
import json,os,sys
from pathlib import Path
state=Path(os.environ['OWNED_ENABLED']); log=Path(os.environ['OWNED_LOG'])
a=sys.argv[1:]
with log.open('a') as f: f.write(json.dumps(a)+'\\n')
if a==['shell','setPluginEnabled','burmjohn.omadocked','false']:
 state.write_text('false'); print('ok')
elif a==['shell','enablePlugin','burmjohn.omadocked','{}']:
 state.write_text('true'); print('ok')
elif a==['shell','listPlugins']:
 print(json.dumps([{'id':'burmjohn.omadocked','enabled':json.loads(state.read_text())}]))
elif a==['shell','rescanPlugins']: print('ok')
else: sys.exit(98)
''')
            shim.chmod(0o700)
            catalog = commands / 'omarchy-plugin-catalog'
            catalog.write_text('#!/usr/bin/python3\nprint(\'[{"id":"burmjohn.omadocked","kinds":["overlay"]}]\')\n')
            catalog.chmod(0o700)
            env = dict(os.environ, HOME=str(home), PATH=str(commands)+':/usr/bin',
                       OWNED_ENABLED=str(state), OWNED_LOG=str(log))
            results = []
            for command in ('disable', 'enable', 'remove'):
                argv = ['/usr/bin/omarchy-plugin-'+command, 'burmjohn.omadocked']
                if command == 'remove': argv.append('--yes')
                result = subprocess.run(argv, env=env, capture_output=True, text=True, timeout=5)
                self.assertEqual(result.returncode, 0, result.stderr)
                results.append({'command':command,'stdout':result.stdout.replace(str(home),'<owned-home>')})
                self.assertEqual(journal.read_text(), 'owned durable sentinel')
                self.assertEqual(json.loads(state.read_text()), command == 'enable')
            self.assertFalse(package.exists())
            backups = list(package.parent.glob('.burmjohn.omadocked.bak.*'))
            self.assertEqual(len(backups), 1)
            self.assertEqual((backups[0]/'manifest.json').read_bytes(), (ROOT/'manifest.json').read_bytes())
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertEqual(calls, [
                ['shell','setPluginEnabled','burmjohn.omadocked','false'],
                ['shell','enablePlugin','burmjohn.omadocked','{}'],
                ['shell','listPlugins'],
                ['shell','setPluginEnabled','burmjohn.omadocked','false'],
                ['shell','rescanPlugins']])
            out = Path(self.evidence_dir) if self.evidence_dir is not None else root / 'receipts'
            out.mkdir(parents=True, exist_ok=True)
            (out/'installed-cli-results.json').write_text(json.dumps({'results':results,'calls':calls,
                'external_journal_unchanged':True,'nongit_backup_verified':True},indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, add_help=False)
    parser.add_argument('--evidence-dir', type=Path, help='explicit receipt export directory (default: temporary)')
    args, remaining = parser.parse_known_args()
    RecoveryCliTests.evidence_dir = args.evidence_dir
    unittest.main(argv=[__file__, *remaining])
