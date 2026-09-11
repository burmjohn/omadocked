"""Pure Python only: process creation is always mocked; never load fixtures."""
import ast
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.find_spec('spawn_safety')
safety = __import__('spawn_safety') if SPEC else None


class SpawnSafetyTests(unittest.TestCase):
    def test_missing_or_contradictory_backend_never_spawns(self):
        self.assertIsNotNone(safety, 'shared pre-spawn guard is missing')
        with tempfile.TemporaryDirectory() as tmp, patch('subprocess.Popen') as popen:
            for backend, platform in [(None, 'offscreen'), ('unknown', 'offscreen'),
                                      ('offscreen', 'wayland'), ('native', 'offscreen'),
                                      ('offscreen', None)]:
                with self.subTest(backend=backend, platform=platform):
                    env = {} if platform is None else {'QT_QPA_PLATFORM': platform}
                    with self.assertRaises(safety.UnsafeLaunch):
                        safety.spawn(['quickshell', '-p', str(Path(tmp)/'shell.qml')],
                                     required=backend, env=env, root=Path(tmp))
            popen.assert_not_called()

    def test_offscreen_private_executable_fake_identity_and_ipc(self):
        with tempfile.TemporaryDirectory() as tmp, patch('subprocess.Popen') as popen, patch('subprocess.run') as run:
            root = Path(tmp)
            private = root/'quickshell'
            private.symlink_to('/usr/bin/quickshell')
            fake = root/'hyprctl'
            fake.write_text('#!/usr/bin/python3\n')
            fake.chmod(0o700)
            env = dict(QT_QPA_PLATFORM='offscreen', PATH=str(root),
                       DISPLAY=':0', WAYLAND_DISPLAY='wayland-1', QT_QPA_PLATFORMTHEME='gtk3',
                       HYPRLAND_INSTANCE_SIGNATURE='fixture-session', OMADOCKED_HYPRCTL=str(fake),
                       FAKE_STATE=str(root/'state.json'), FAKE_LOG=str(root/'argv.jsonl'))
            proc = safety.spawn([str(private), '-p', str(root/'shell.qml')],
                                required='offscreen', env=env, root=root)
            effective = popen.call_args.kwargs['env']
            self.assertEqual(effective['HYPRLAND_INSTANCE_SIGNATURE'], 'fixture-session')
            self.assertEqual(effective['OMADOCKED_HYPRCTL'], str(fake))
            self.assertEqual(effective['FAKE_STATE'], env['FAKE_STATE'])
            self.assertEqual(effective['PATH'], str(root))
            self.assertEqual(effective['QT_QPA_PLATFORMTHEME'], '')
            self.assertEqual(effective['QT_QUICK_BACKEND'], 'software')
            self.assertNotIn('WAYLAND_DISPLAY', effective)
            self.assertNotIn('DISPLAY', effective)
            self.assertTrue(Path(effective['HOME']).is_relative_to(root))
            self.assertEqual(env['QT_QPA_PLATFORMTHEME'], 'gtk3', 'do not mutate caller environment')
            proc.pid = 123
            safety.ipc(proc, ['quickshell', 'ipc', '--pid', '123', 'call', 'fixture', 'state'], timeout=3)
            self.assertEqual(run.call_args.kwargs['env'], effective)
            self.assertEqual(run.call_args.args[0][0], '/usr/bin/quickshell')
            self.assertEqual(run.call_args.kwargs['env']['PATH'], str(root))

    def test_native_opt_in_and_socket_prerequisites(self):
        from types import SimpleNamespace
        import stat
        with tempfile.TemporaryDirectory() as tmp, patch('subprocess.Popen') as popen:
            root = Path(tmp)
            env = dict(QT_QPA_PLATFORM='wayland', XDG_RUNTIME_DIR=tmp, WAYLAND_DISPLAY='wayland-owned')
            argv = ['/usr/bin/quickshell', '-p', str(root/'shell.qml')]
            with patch.dict(os.environ, {}, clear=True):
                with self.assertRaises(safety.UnsafeLaunch):
                    safety.spawn(argv, required='native', env=env, root=root)
            consent = {'OMADOCKED_TEST_NATIVE': '1', 'OMADOCKED_TEST_NATIVE_SCOPE': 'hidden-backend'}
            with patch.dict(os.environ, consent, clear=True):
                for change in ({'WAYLAND_DISPLAY': ''}, {}, {'QT_QPA_PLATFORM': 'wayland;xcb'}):
                    with self.assertRaises(safety.UnsafeLaunch):
                        safety.spawn(argv, required='native', env=dict(env, **change), root=root)
                popen.assert_not_called()
                # No compositor is created/contacted: socket metadata is mocked.
                with patch.object(safety, '_socket_stat', create=True, return_value=SimpleNamespace(st_mode=stat.S_IFSOCK, st_uid=os.getuid())), patch('os.access', return_value=True), patch.object(safety, '_wayland_plugin_available', create=True, return_value=True):
                    proc = safety.spawn(argv, required='native', env=env, root=root)
                    self.assertEqual(proc.test_env['XDG_RUNTIME_DIR'], tmp)
                    self.assertEqual(proc.test_env['WAYLAND_DISPLAY'], 'wayland-owned')
                    absolute = dict(env, WAYLAND_DISPLAY=str(root/'absolute.socket'))
                    safety.spawn(argv, required='native', env=absolute, root=root)
                    with patch.object(safety, '_wayland_plugin_available', return_value=False):
                        with self.assertRaises(safety.UnsafeLaunch):
                            safety.spawn(argv, required='native', env=env, root=root)

    def test_classification_and_all_qt_launch_seams_are_explicit(self):
        spec = importlib.util.find_spec('backend_requirements')
        self.assertIsNotNone(spec, 'explicit audit classification is missing')
        import backend_requirements as backends
        modules = {p.stem for p in (ROOT/'tests').glob('test_*.py')}
        self.assertEqual(modules, set(backends.MODULES))
        self.assertEqual(backends.backend_for('test_preview_native.PreviewNative.test_native_null_source_loader_disposal'), 'native')
        self.assertEqual(backends.backend_for('test_preview_native.PreviewNative.test_preview_preferences_persist_without_private_pixels_or_titles'), 'offscreen')
        with self.assertRaises(safety.UnsafeLaunch):
            backends.backend_for('test_unknown.Fixture.test_new')
        for filename, expected in {
            'test_app_service.py': 1, 'test_parking_service.py': 1, 'test_daily_adapter.py': 1,
            'test_folder_service.py': 1, 'test_folder_transactions.py': 1, 'test_host_overlay.py': 1,
            'test_shell_gestures.py': 1, 'shared_host.py': 1, 'relocation_recovery.py': 1,
        }.items():
            tree = ast.parse((ROOT/'tests'/filename).read_text())
            guarded = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and ast.unparse(n.func) == 'safety.spawn']
            self.assertEqual(len(guarded), expected, filename)
            for call in guarded:
                self.assertTrue({'required', 'root', 'env'} <= {k.arg for k in call.keywords}, filename)
            raw = [n for n in ast.walk(tree) if isinstance(n, ast.Call) and ast.unparse(n.func) in ('subprocess.Popen', 'subprocess.run') and n.args and 'quickshell' in ast.unparse(n.args[0])]
            self.assertEqual(raw, [], filename)

    def test_override_escape_hatches_and_optimized_python_refused(self):
        with tempfile.TemporaryDirectory() as tmp, patch('subprocess.Popen') as popen:
            root = Path(tmp)
            argv = ['/usr/bin/quickshell', '-p', str(root/'shell.qml')]
            for args, extras, changes in [
                (argv + ['-platform', 'wayland'], {}, {}),
                (argv, {'executable': '/usr/bin/quickshell'}, {}),
                (argv, {'shell': True}, {}),
                (argv, {}, {'PYTHONOPTIMIZE': '1'}),
                (argv, {}, {'OMADOCKED_TEST_LIVE_READONLY': '1'}),
                (argv, {}, {'FAKE_STATE': '/not-owned/state'}),
                (argv, {}, {'OMADOCKED_HYPRCTL': '/usr/bin/true', 'HYPRLAND_INSTANCE_SIGNATURE': 'real'}),
            ]:
                with self.subTest(args=args, extras=extras, changes=changes), self.assertRaises(safety.UnsafeLaunch):
                    safety.spawn(args, required='offscreen', root=root,
                                 env=dict(QT_QPA_PLATFORM='offscreen', **changes), **extras)
            popen.assert_not_called()

    def test_owned_data_override_wrapper_and_private_shim(self):
        with tempfile.TemporaryDirectory() as tmp, patch('subprocess.Popen') as popen:
            root = Path(tmp)
            data = root/'fixture-data'
            data.mkdir()
            env = dict(QT_QPA_PLATFORM='offscreen', XDG_DATA_HOME=str(data), PATH='/usr/bin')
            copy = root/'preview.py'
            copy.write_bytes((ROOT/'tools/preview.py').read_bytes())
            proc = safety.spawn(['/usr/bin/python3', str(copy), '--', '-p', str(root/'shell.qml')], required='offscreen', env=env, root=root)
            self.assertEqual(proc.test_env['XDG_DATA_HOME'], str(data))
            shim = root/'quickshell'
            shim.write_text('#!/bin/sh\nexit 0\n')
            shim.chmod(0o700)
            popen.reset_mock()
            for command in ([str(shim), '-p', str(root/'shell.qml')], ['/usr/bin/python3', str(copy), '--', '-p', str(root/'shell.qml')]):
                with self.assertRaises(safety.UnsafeLaunch):
                    safety.spawn(command, required='offscreen', env=dict(env, PATH=str(root)), root=root)
            popen.assert_not_called()

    def test_manual_environment_inheritance_and_literal_mappings(self):
        from types import SimpleNamespace
        import stat
        with tempfile.TemporaryDirectory() as tmp:
            caller = dict(OMADOCKED_TEST_NATIVE='1',
                          OMADOCKED_TEST_NATIVE_SCOPE='monitor_contract',
                          XDG_RUNTIME_DIR=tmp, WAYLAND_DISPLAY='caller.socket',
                          CALLER_ONLY='inherited', QT_QPA_PLATFORMTHEME='caller-theme')
            custom = dict(XDG_RUNTIME_DIR=tmp, WAYLAND_DISPLAY='custom.socket',
                          CUSTOM_ONLY='literal', QT_QPA_PLATFORMTHEME='custom-theme')
            for kind in ('run', 'Popen'):
                for name, kwargs in [('omitted', {}), ('none', {'env': None}),
                                     ('custom', {'env': custom})]:
                    with self.subTest(kind=kind, env=name), patch.dict(os.environ, caller, clear=True), patch.object(safety, '_socket_stat', return_value=SimpleNamespace(st_mode=stat.S_IFSOCK, st_uid=os.getuid())) as metadata, patch.object(safety, '_wayland_plugin_available', return_value=True) as plugin, patch('os.access', return_value=True), patch('subprocess.run') as run, patch('subprocess.Popen') as popen:
                        original = dict(custom if name == 'custom' else os.environ)
                        seam = run if kind == 'run' else popen
                        other = popen if kind == 'run' else run
                        result = safety.manual_process(kind, 'monitor_contract', ['never-executed'], cwd=tmp, **kwargs)
                        self.assertIs(result, seam.return_value)
                        seam.assert_called_once_with(['never-executed'], cwd=tmp,
                                                    env=dict(original, QT_QPA_PLATFORM='wayland', QT_QPA_PLATFORMTHEME=''))
                        other.assert_not_called()
                        metadata.assert_called_once_with(Path(tmp)/original['WAYLAND_DISPLAY'])
                        plugin.assert_called_once_with()
                        self.assertEqual(custom if name == 'custom' else dict(os.environ), original)
                        self.assertIsNot(seam.call_args.kwargs['env'], custom)

    def test_manual_environment_refusals_precede_process_creation(self):
        from types import SimpleNamespace
        import stat
        with tempfile.TemporaryDirectory() as tmp:
            valid = dict(XDG_RUNTIME_DIR=tmp, WAYLAND_DISPLAY='mock.socket')
            consent = dict(OMADOCKED_TEST_NATIVE='1', OMADOCKED_TEST_NATIVE_SCOPE='monitor_contract')
            for kind in ('run', 'Popen'):
                for form in ('omitted', 'none', 'empty', 'custom'):
                    for fault in ('no-consent', 'wrong-scope', 'child-only-consent',
                                  'missing-display', 'missing-socket', 'missing-plugin',
                                  'contradictory-platform', 'empty-literal'):
                        with self.subTest(kind=kind, env=form, fault=fault):
                            caller = dict(valid, **consent)
                            child = dict(valid)
                            if fault == 'no-consent':
                                caller.pop('OMADOCKED_TEST_NATIVE')
                            elif fault == 'wrong-scope':
                                caller['OMADOCKED_TEST_NATIVE_SCOPE'] = 'hidden-backend'
                            elif fault == 'child-only-consent':
                                caller = dict(valid)
                                child.update(consent)
                            elif fault == 'missing-display':
                                caller.pop('WAYLAND_DISPLAY')
                                child.pop('WAYLAND_DISPLAY')
                            elif fault == 'contradictory-platform':
                                caller['QT_QPA_PLATFORM'] = child['QT_QPA_PLATFORM'] = 'offscreen'
                            elif fault == 'empty-literal' and form != 'empty':
                                continue
                            kwargs = {} if form == 'omitted' else {'env': None if form == 'none' else {} if form == 'empty' else child}
                            # Inherited forms cannot have child-only consent: no consent still refuses.
                            with patch.dict(os.environ, caller, clear=True), patch.object(safety, '_socket_stat', return_value=SimpleNamespace(st_mode=stat.S_IFSOCK, st_uid=os.getuid()), side_effect=FileNotFoundError() if fault == 'missing-socket' else None), patch.object(safety, '_wayland_plugin_available', return_value=fault != 'missing-plugin'), patch('os.access', return_value=True), patch('subprocess.run') as run, patch('subprocess.Popen') as popen:
                                with self.assertRaises(safety.UnsafeLaunch):
                                    safety.manual_process(kind, 'monitor_contract', ['never-executed'], **kwargs)
                                run.assert_not_called()
                                popen.assert_not_called()

    def test_manual_launches_require_separate_scope(self):
        self.assertTrue(hasattr(safety, 'manual_process'), 'manual launch boundary missing')
        with patch('subprocess.Popen') as popen, patch('subprocess.run') as run, patch.dict(os.environ, {'OMADOCKED_TEST_NATIVE': '1', 'OMADOCKED_TEST_NATIVE_SCOPE': 'hidden-backend'}, clear=True):
            for kind in ('run', 'Popen'):
                with self.assertRaises(safety.UnsafeLaunch):
                    safety.manual_process(kind, 'live', ['/usr/bin/quickshell'])
            popen.assert_not_called()
            run.assert_not_called()

    def test_runner_never_calls_skipped_native_full_acceptance(self):
        self.assertIsNotNone(importlib.util.find_spec('run_tests'), 'split backend runner missing')
        import run_tests
        result = unittest.TestResult()
        result.testsRun = 1
        result.addSkip(unittest.FunctionTestCase(lambda: None), 'native unavailable')
        self.assertFalse(run_tests.accepted(result))
        self.assertFalse(run_tests.accepted(unittest.TestResult()))
        clean = unittest.TestResult()
        clean.testsRun = 1
        self.assertTrue(run_tests.accepted(clean))
        makefile = (ROOT/'Makefile').read_text()
        self.assertIn('test: test-safety', makefile)
        self.assertIn('test-full:', makefile)
        self.assertNotIn('test:\n\t$(PYTHON) -m unittest discover', makefile)

    def test_qt_runner_is_offscreen_and_full_preflight_precedes_discovery(self):
        import run_tests
        with patch('subprocess.Popen') as popen:
            popen.return_value.wait.return_value = 0
            popen.return_value.poll.return_value = 0
            self.assertTrue(run_tests.qml_tests())
            self.assertEqual(popen.call_args.args[0][0], '/usr/lib/qt6/bin/qmltestrunner')
            self.assertEqual(popen.call_args.kwargs['env']['QT_QPA_PLATFORM'], 'offscreen')
            self.assertNotIn('WAYLAND_DISPLAY', popen.call_args.kwargs['env'])
            self.assertTrue(run_tests.qml_tests('bench'))
            self.assertEqual(popen.call_args.args[0][-2:], ['-iterations', '2000'])
            self.assertTrue(run_tests.qml_tests('render'))
            with self.assertRaises(safety.UnsafeLaunch):
                run_tests.qml_tests('../outside')
        with patch('sys.argv', ['run_tests.py', 'full']), patch.dict(os.environ, {}, clear=True), patch.object(unittest.defaultTestLoader, 'discover') as discover, patch('subprocess.Popen') as popen:
            with self.assertRaises(safety.UnsafeLaunch):
                run_tests.main()
            discover.assert_not_called()
            popen.assert_not_called()

    def test_every_discovered_process_path_has_static_coverage(self):
        import json
        inventory = ROOT/'tests/nonqt_spawn_inventory.json'
        self.assertTrue(inventory.exists(), 'audited non-Qt exception inventory missing')
        expected = json.loads(inventory.read_text())
        actual = {}
        for path in sorted((ROOT/'tests').rglob('*.py')):
            if path.name in ('spawn_safety.py', 'test_spawn_safety.py'):
                continue
            tree = ast.parse(path.read_text())
            for node in ast.walk(tree):
                if isinstance(node, ast.ImportFrom):
                    self.assertNotEqual(node.module, 'subprocess', str(path))
                if not isinstance(node, ast.Call):
                    continue
                func = ast.unparse(node.func)
                self.assertNotIn(func, ('os.system', 'os.execv', 'os.execvp', 'os.execvpe', 'os.posix_spawn'), str(path))
                if func in ('subprocess.run', 'subprocess.Popen', 'subprocess.check_call', 'subprocess.check_output'):
                    actual.setdefault(str(path.relative_to(ROOT)), []).append(ast.unparse(node))
                if func == 'safety.manual_process':
                    self.assertEqual(ast.literal_eval(node.args[1]), path.stem)
                if func == 'safety.spawn':
                    self.assertTrue({'required', 'env', 'root'} <= {k.arg for k in node.keywords}, str(path))
                if func == 'safety.ipc':
                    self.assertIn(ast.unparse(node.args[0]), ('proc', 'self.proc', 'self.f.proc'))
        self.assertEqual({p: sorted(v) for p, v in actual.items()}, expected)
        for path in [ROOT/'tests/live.py', ROOT/'tests/smoke.py', *sorted((ROOT/'tests/unit').glob('*_contract.py'))]:
            tree = ast.parse(path.read_text())
            entry = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in ('run', 'main'))
            statements = [ast.unparse(n) for n in entry.body]
            guard = f'safety.manual_native({path.stem!r})'
            self.assertIn(guard, statements)
            if path.stem in ('live', 'smoke'):
                invalidation = next(i for i, text in enumerate(statements) if 'write_text' in text and 'attempt not completed' in text)
                self.assertLess(invalidation, statements.index(guard), 'consent rejection must invalidate old success')
            if path.stem != 'running_app_contract':
                optimized = next(i for i, text in enumerate(statements) if 'not __debug__' in text)
                self.assertLess(optimized, statements.index(guard), 'retain original optimized-Python preflight')

    def test_inherited_controls_are_removed_before_owned_overrides(self):
        with patch.dict(os.environ, {'QS_CONFIG_PATH': '/live', 'OMADOCKED_VISIBLE': '1', 'FAKE_STATE': '/unowned', 'HYPRLAND_INSTANCE_SIGNATURE': 'real'}, clear=True):
            self.assertEqual(safety.fixture_environment(), {})

    def test_selection_is_explicit_and_unknown_cases_fail(self):
        import run_tests
        from unittest.mock import Mock
        ids = ['test_app_service.AppServiceTests.test_configuration',
               'test_preview_native.PreviewTests.test_native_null_source_loader_disposal',
               'test_app_service.AppServiceTests.test_readonly_live_source_no_actions']
        suite = []
        for value in ids:
            case = unittest.FunctionTestCase(lambda: None)
            case.id = lambda value=value: value
            suite.append(case)
        selected, excluded = run_tests.select(suite, 'offscreen')
        self.assertEqual(selected.countTestCases(), 1)
        self.assertEqual(excluded, ids[1:])
        with self.assertRaises(safety.UnsafeLaunch):
            run_tests.select([Mock(id=lambda: 'new_module.Tests.test_new')], 'full')


if __name__ == '__main__':
    unittest.main()
