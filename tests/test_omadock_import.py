"""P4-05: preview-first Omadock import never writes or executes on preview."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]


def load_importer():
    path = ROOT / "services" / "omadock_import.py"
    spec = importlib.util.spec_from_file_location("omadock_import", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PreviewImportTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="omadocked-import-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.dock = self.root / "dock.json"
        self.dest = self.root / "pins.json"
        self.dest.write_text("untouched\n")
        self.dest.chmod(0o600)
        self.dock.write_text("{}")

    def test_apply_missing_sources_preserves_all_destination_files(self):
        importer = load_importer()
        self.dock.unlink()
        for suffix in ('.lkg', '.import-bak'):
            self.dest.with_name(self.dest.name + suffix).write_text('original' + suffix)
        before = {p.name: p.read_bytes() for p in self.root.iterdir()}
        for sources in ((None, None), (self.dock, None), (None, self.root / 'missing.json')):
            for _ in range(2):
                with self.assertRaisesRegex(ValueError, 'source'):
                    importer.apply(*sources, self.dest)
                self.assertEqual({p.name: p.read_bytes() for p in self.root.iterdir()}, before)

    def test_cli_single_source_and_explicit_missing_source(self):
        import os
        import subprocess
        import sys
        command = [sys.executable, '-B', str(ROOT / 'tools/import_omadock.py'),
                   '--dock', str(self.dock), '--apply', '--dest', str(self.dest)]
        env = dict(os.environ, HOME=str(self.root))
        before = {p.name: p.read_bytes() for p in self.root.iterdir()}
        for _ in range(2):
            result = subprocess.run(command + ['--settings', str(self.root / 'missing')],
                                    env=env, capture_output=True, text=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual({p.name: p.read_bytes() for p in self.root.iterdir()}, before)
        result = subprocess.run(command, env=env, capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout)['applied'])

    def test_reserved_menu_pin_is_filtered_and_rejected_by_validator(self):
        importer = load_importer()
        self.dock.write_text(json.dumps({'pinned': ['omarchy-menu', 'omarchy-menu.desktop', 'signal']}))
        self.assertEqual(importer.preview(self.dock, None)['pins'], ['signal'])
        self.assertTrue(importer.apply(self.dock, None, self.dest)['applied'])
        self.assertEqual(json.loads(self.dest.read_text())['pins'], ['signal'])
        # Execute the actual runtime parser, including its pure JS dependencies.
        import subprocess
        script = r'''
const fs = require('fs'), vm = require('vm'), path = require('path');
function load(file) {
    const context = {};
    const source = fs.readFileSync(file, 'utf8').replace(/^\.pragma.*$/mg, '')
        .replace(/^\.import "([^"]+)" as (\w+)$/mg, (_, relative, name) => {
            context[name] = load(path.resolve(path.dirname(file), relative)); return '';
        });
    vm.createContext(context); vm.runInContext(source, context);
    return new Proxy(context, {get: (_, name) => vm.runInContext(name, context)});
}
const config = load('services/ConfigLogic.js');
const text = fs.readFileSync(0, 'utf8');
console.log(JSON.stringify(config.parse(text)));
'''
        parsed = subprocess.run(['node', '-e', script], input=self.dest.read_text(),
                                cwd=ROOT, capture_output=True, text=True, timeout=3, check=True)
        self.assertEqual(json.loads(parsed.stdout)['error'], '')
        with self.assertRaisesRegex(ValueError, 'pins'):
            importer._validate_destination(importer._config({'pins': ['omarchy-menu']}))

    def test_repeat_apply_refuses_to_replace_original_backup(self):
        importer = load_importer()
        self.assertTrue(importer.apply(self.dock, None, self.dest)['applied'])
        before = {p.name: p.read_bytes() for p in self.root.iterdir()}
        with self.assertRaisesRegex(ValueError, 'backup'):
            importer.apply(self.dock, None, self.dest)
        self.assertEqual({p.name: p.read_bytes() for p in self.root.iterdir()}, before)

    def test_apply_refuses_busy_without_changing_main_or_backups(self):
        from services.config_store import Store
        importer = load_importer()
        backup = self.root / "pins.json.import-bak"
        backup.write_text("previous import backup")
        lkg = self.root / "pins.json.lkg"
        lkg.write_text("previous good backup")
        store = Store(str(self.dest))
        try:
            result = importer.apply(self.dock, None, self.dest)
            self.assertFalse(result["applied"])
            self.assertEqual(result["error"], "busy")
            self.assertEqual(result["outcome"], "no-commit")
            self.assertEqual(self.dest.read_text(), "untouched\n")
            self.assertEqual(backup.read_text(), "previous import backup")
            self.assertEqual(lkg.read_text(), "previous good backup")
        finally:
            store.close()

    def test_cli_preview_is_read_only_and_apply_busy_exits_nonzero(self):
        import subprocess
        import sys
        from services.config_store import Store
        self.dock.write_text('{}')
        settings = self.root / 'omadock.json'
        settings.write_text('{}')
        command = [sys.executable, '-B', str(ROOT / 'tools/import_omadock.py'),
                   '--dock', str(self.dock), '--settings', str(settings), '--dest', str(self.dest)]
        store = Store(str(self.dest))
        try:
            before = {p.name: p.read_bytes() for p in self.root.iterdir()}
            preview = subprocess.run(command, capture_output=True, text=True, cwd=self.root)
            self.assertEqual(preview.returncode, 0, preview.stderr)
            self.assertFalse(json.loads(preview.stdout)['applied'])
            applied = subprocess.run(command + ['--apply'], capture_output=True, text=True, cwd=self.root)
            self.assertEqual(applied.returncode, 3, applied.stderr)
            self.assertEqual(json.loads(applied.stdout)['error'], 'busy')
            self.assertEqual({p.name: p.read_bytes() for p in self.root.iterdir()}, before)
        finally:
            store.close()

    def test_apply_preserves_conflict_receipt(self):
        importer = load_importer()
        original = importer.Store.request
        def raced(store, request):
            self.dest.write_text('external edit')
            return original(store, request)
        with patch.object(importer.Store, 'request', raced):
            result = importer.apply(self.dock, None, self.dest)
        self.assertFalse(result['applied'])
        self.assertEqual(result['error'], 'conflict')
        self.assertEqual(result['outcome'], 'no-commit')
        self.assertEqual(self.dest.read_text(), 'external edit')
        self.assertEqual(Path(result['backup']).read_text(), 'untouched\n')

    def test_apply_does_not_upgrade_failed_main_fsync_to_success(self):
        importer = load_importer()
        original = importer.Store.atomic_write
        def fail_main_sync(store, name, text):
            if name == store.name:
                import os
                fsync = os.fsync
                def fail_directory(fd):
                    if fd == store.directory:
                        raise OSError('injected directory fsync failure')
                    return fsync(fd)
                with patch('os.fsync', fail_directory):
                    return original(store, name, text)
            return original(store, name, text)
        with patch.object(importer.Store, 'atomic_write', fail_main_sync):
            result = importer.apply(self.dock, None, self.dest)
        self.assertFalse(result['applied'])
        self.assertEqual(result['outcome'], 'indeterminate')
        self.assertEqual(result['stage'], 'main-directory-fsync')
        self.assertTrue(result['mainMatchesReplacement'])
        self.assertFalse(result['mainDurable'])
        self.assertEqual(Path(result['backup']).read_text(), 'untouched\n')

    def test_apply_preserves_durable_backup_degraded_receipt(self):
        importer = load_importer()
        original = importer.Store.atomic_write
        def fail_refresh(store, name, text):
            if name == store.name + '.lkg' and text != 'untouched\n':
                raise OSError('injected backup refresh failure')
            return original(store, name, text)
        with patch.object(importer.Store, 'atomic_write', fail_refresh):
            result = importer.apply(self.dock, None, self.dest)
        self.assertTrue(result['applied'])
        self.assertEqual(result['outcome'], 'durable')
        self.assertTrue(result['backupDegraded'])

    def test_apply_refuses_symlink_ancestor_and_hardlinked_destination(self):
        importer = load_importer()
        alias = self.root / 'alias'
        alias.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(OSError):
            importer.apply(self.dock, None, alias / self.dest.name)
        import os
        os.link(self.dest, self.root / 'linked')
        with self.assertRaises(ValueError):
            importer.apply(self.dock, None, self.dest)
        self.assertEqual(self.dest.read_text(), 'untouched\n')
        self.assertFalse((self.root / 'pins.json.import-bak').exists())

    def test_icon_size_bounds_and_unsupported_values(self):
        importer = load_importer()
        settings = self.root / 'omadock.json'
        for value in (28, 72, 0, 'auto', 27, 73, True, 62.0, '62', None):
            with self.subTest(value=value):
                settings.write_text(json.dumps({'iconSize': value}))
                result = importer.preview(None, settings)
                if type(value) is int and 28 <= value <= 72:
                    self.assertEqual(result['settings']['iconSize'], value)
                else:
                    self.assertNotIn('iconSize', result['settings'])
                    self.assertIn('iconSize', result['unsupported'])

    def test_numeric_icon_size_is_explicitly_imported(self):
        settings = self.root / "omadock.json"
        settings.write_text(json.dumps({"iconSize": 62}))
        importer = load_importer()
        self.assertEqual(importer.preview(None, settings)["settings"].get("iconSize"), 62)
        self.assertTrue(importer.apply(None, settings, self.dest)["applied"])
        self.assertEqual(json.loads(self.dest.read_text())["settings"]["iconSize"], 62)

    def test_preview_maps_pins_without_writing_or_executing(self):
        self.dock.write_text(json.dumps({"pinned": ["brave-browser.desktop", "org.telegram.desktop"]}))
        importer = load_importer()
        with patch("subprocess.Popen") as popen, patch("os.execvpe") as execvpe:
            preview = importer.preview(self.dock, None)
        self.assertFalse(preview["applied"])
        self.assertEqual(preview["pins"], ["brave-browser", "org.telegram.desktop"])
        self.assertEqual(self.dest.read_text(), "untouched\n")
        popen.assert_not_called()
        execvpe.assert_not_called()

    def test_preview_maps_settings_and_reports_unsupported_without_writing(self):
        settings = self.root / "omadock.json"
        settings.write_text(json.dumps({
            "autohide": False,
            "intelligentAutohide": True,
            "minimizeMode": "off",
            "opacity": 0.54,
            "hoverEffect": "wave",
            "shape": "pill",
            "iconSize": 0,
            "showAppsButton": False,
            "showMinimizedTiles": True,
            "pinnedFolders": [{"path": "~/Downloads", "name": "Downloads", "icon": "folder-download"}],
            "mystery": "nope",
        }))
        self.dock.write_text("{}\n")
        importer = load_importer()
        preview = importer.preview(self.dock, settings)
        self.assertFalse(preview["applied"])
        mapped = preview["settings"]
        self.assertEqual(mapped["autoHide"], False)
        self.assertEqual(mapped["intelligentHide"], True)
        self.assertEqual(mapped["minimizeMode"], "off")
        self.assertEqual(mapped["transparency"], 46)
        self.assertEqual(mapped["motionMode"], "wave")
        self.assertEqual(mapped["shape"], "round")
        self.assertIn("iconSize", preview["unsupported"])
        self.assertIn("showAppsButton", preview["unsupported"])
        self.assertIn("showMinimizedTiles", preview["unsupported"])
        self.assertIn("mystery", preview["unsupported"])
        self.assertEqual(len(preview["launchers"]), 1)
        self.assertEqual(preview["launchers"][0]["kind"], "folder")
        self.assertEqual(preview["launchers"][0]["name"], "Downloads")
        self.assertTrue(preview["launchers"][0]["target"].startswith("/"))
        self.assertEqual(self.dest.read_text(), "untouched\n")

    def test_apply_backs_up_destination_then_writes_without_executing(self):
        self.dock.write_text(json.dumps({"pinned": ["signal"]}))
        (self.root / "omadock.json").write_text(json.dumps({"minimizeMode": "off", "autohide": True}))
        importer = load_importer()
        with patch("subprocess.Popen") as popen, patch("os.execvpe") as execvpe:
            result = importer.apply(self.dock, self.root / "omadock.json", self.dest)
        self.assertTrue(result["applied"])
        backup = Path(result["backup"])
        self.assertEqual(backup.read_text(), "untouched\n")
        written = json.loads(self.dest.read_text())
        self.assertEqual(written["version"], 2)
        self.assertEqual(written["pins"], ["signal"])
        self.assertEqual(written["settings"]["minimizeMode"], "off")
        popen.assert_not_called()
        execvpe.assert_not_called()

    def test_apply_refuses_symlink_backup_without_touching_referent(self):
        self.dock.write_text(json.dumps({"pinned": ["signal"]}))
        (self.root / "omadock.json").write_text(json.dumps({"minimizeMode": "off"}))
        target = self.root / "unrelated.txt"
        target.write_text("keep me\n")
        target.chmod(0o644)
        backup = self.root / "pins.json.import-bak"
        backup.symlink_to(target)
        importer = load_importer()
        with self.assertRaises(ValueError):
            importer.apply(self.dock, self.root / "omadock.json", self.dest)
        self.assertEqual(target.read_text(), "keep me\n")
        self.assertEqual(oct(target.stat().st_mode)[-3:], "644")
        self.assertEqual(self.dest.read_text(), "untouched\n")
        self.assertTrue(backup.is_symlink())

    def test_apply_rejects_settings_the_destination_parser_would_refuse(self):
        self.dock.write_text("{}")
        (self.root / "omadock.json").write_text(json.dumps({"itemSpacing": 7, "minimizeMode": "off"}))
        importer = load_importer()
        result = importer.apply(self.dock, self.root / "omadock.json", self.dest)
        self.assertTrue(result["applied"])
        self.assertIn("itemSpacing", result["unsupported"])
        written = json.loads(self.dest.read_text())
        self.assertEqual(written["settings"]["itemSpacing"], 4)
        self.assertEqual(written["settings"]["minimizeMode"], "off")

    def test_apply_dedupes_duplicate_folder_paths_before_write(self):
        self.dock.write_text("{}")
        settings = self.root / "omadock.json"
        settings.write_text(json.dumps({
            "pinnedFolders": [
                {"path": "/tmp/omadocked-folder", "name": "A", "icon": "folder"},
                {"path": "/tmp/omadocked-folder", "name": "A2", "icon": "folder"},
            ]
        }))
        importer = load_importer()
        result = importer.apply(self.dock, settings, self.dest)
        self.assertTrue(result["applied"])
        written = json.loads(self.dest.read_text())
        ids = [row["id"] for row in written["launchers"]]
        self.assertEqual(len(ids), 1)
        self.assertEqual(len(set(ids)), 1)

    def test_validate_destination_rejects_duplicate_launcher_ids(self):
        importer = load_importer()
        launcher = {
            "id": importer._launcher_id("/tmp/a"),
            "kind": "folder", "name": "A", "icon": "folder", "desktopId": "",
            "program": "", "args": [], "workingDirectory": "", "terminal": False,
            "target": "/tmp/a", "action": "", "enabled": True,
        }
        config = importer._config({"pins": ["signal"], "settings": {}, "launchers": [launcher, dict(launcher)]})
        with self.assertRaises(ValueError):
            importer._validate_destination(config)
        self.assertEqual(self.dest.read_text(), "untouched\n")

    def test_validate_destination_rejects_control_characters_in_launcher_name(self):
        importer = load_importer()
        launcher = {
            "id": importer._launcher_id("/tmp/a"),
            "kind": "folder", "name": "A\nB", "icon": "folder", "desktopId": "",
            "program": "", "args": [], "workingDirectory": "", "terminal": False,
            "target": "/tmp/a", "action": "", "enabled": True,
        }
        config = importer._config({"pins": ["signal"], "settings": {}, "launchers": [launcher]})
        with self.assertRaises(ValueError):
            importer._validate_destination(config)

    def test_apply_skips_folder_names_the_parser_would_refuse(self):
        self.dock.write_text("{}")
        settings = self.root / "omadock.json"
        settings.write_text(json.dumps({
            "pinnedFolders": [{"path": "/tmp/omadocked-folder", "name": "A\nB", "icon": "folder"}]
        }))
        importer = load_importer()
        result = importer.apply(self.dock, settings, self.dest)
        self.assertTrue(result["applied"])
        written = json.loads(self.dest.read_text())
        self.assertEqual(written["launchers"], [])
