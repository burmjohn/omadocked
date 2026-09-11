"""Delivery-harness regressions; all receipts and CLI state are owned temporary files."""
import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import test_recovery_cli as cli
import relocation_recovery as relocation


class RecoveryHarnessTests(unittest.TestCase):
    def test_matching_success_must_be_idle_and_empty(self):
        for busy, ok, records in [(True, True, []), (False, False, []),
                                   (False, True, [{'key': 'remaining'}])]:
            with self.subTest(busy=busy, ok=ok, records=records):
                receipt = {'busy': busy, 'last': {'transactionId': 2, 'ok': ok}, 'records': records}
                with patch.object(relocation.time, 'monotonic', side_effect=[0, 0, 9]), \
                        patch.object(relocation.time, 'sleep'):
                    with self.assertRaises(AssertionError):
                        relocation.wait_recovery(lambda: receipt, 2)

    def test_expired_before_first_poll_fails_closed(self):
        with patch.object(relocation.time, 'monotonic', side_effect=[0, 9]):
            with self.assertRaisesRegex(AssertionError, 'recovery deadline'):
                relocation.wait_recovery(lambda: self.fail('must not poll after expiry'), 2)

    def test_stale_success_then_matching_terminal_success(self):
        stale = {'busy': False, 'last': {'transactionId': 1, 'ok': True}, 'records': []}
        terminal = {'busy': False, 'last': {'transactionId': 2, 'ok': True}, 'records': []}
        rows = iter([stale, terminal])
        with patch.object(relocation.time, 'monotonic', side_effect=[0, 0, 1]), \
                patch.object(relocation.time, 'sleep'):
            self.assertIs(relocation.wait_recovery(lambda: next(rows), 2), terminal)

    def test_relocation_receipt_lifetime_and_explicit_export(self):
        paths = []
        def emit(out):
            paths.append(out)
            out.mkdir(parents=True, exist_ok=True)
            (out / 'result.json').write_text('owned receipt')
        with tempfile.TemporaryDirectory(prefix='omadocked-output-regression-') as directory:
            export = Path(directory) / 'explicit-export'
            with patch.object(relocation, '_run', side_effect=emit):
                relocation.run()
                relocation.run()
                self.assertNotEqual(paths[0], paths[1])
                self.assertTrue(all(not p.exists() for p in paths))
                relocation.run(export)
                self.assertEqual((export / 'result.json').read_text(), 'owned receipt')

    def test_stale_previous_success_cannot_pass_after_timeout(self):
        stale = {'busy': False, 'last': {'transactionId': 1, 'ok': True}, 'records': []}
        # One real poll, then expiry: this is the original false-pass shape.
        with patch.object(relocation.time, 'monotonic', side_effect=[0, 0, 9]), \
                patch.object(relocation.time, 'sleep'):
            with self.assertRaises(AssertionError):
                relocation.wait_recovery(lambda: stale, 2)

    def test_cli_two_runs_leave_history_unchanged_and_export_is_explicit(self):
        with tempfile.TemporaryDirectory(prefix='omadocked-harness-regression-') as directory:
            root = Path(directory)
            (root / 'manifest.json').write_bytes((cli.ROOT / 'manifest.json').read_bytes())
            historical = root / 'evidence/phase3-relocation-recovery'
            historical.mkdir(parents=True)
            receipt = historical / 'installed-cli-results.json'
            receipt.write_text('historical sentinel\n')
            before = hashlib.sha256(receipt.read_bytes()).hexdigest()
            case = cli.RecoveryCliTests('test_installed_lifecycle_commands_preserve_external_state')
            with patch.object(cli, 'ROOT', root):
                for _ in range(2):
                    case.test_installed_lifecycle_commands_preserve_external_state()
                    self.assertEqual(hashlib.sha256(receipt.read_bytes()).hexdigest(), before)
                export = root / 'fresh-export'
                case.evidence_dir = export
                case.test_installed_lifecycle_commands_preserve_external_state()
                result = json.loads((export / 'installed-cli-results.json').read_text())
                self.assertTrue(result['external_journal_unchanged'])
                self.assertTrue(result['nongit_backup_verified'])
                self.assertEqual([r['command'] for r in result['results']], ['disable', 'enable', 'remove'])
                self.assertEqual(hashlib.sha256(receipt.read_bytes()).hexdigest(), before)


if __name__ == '__main__':
    unittest.main()
