"""Native Gio boundary; only owned temporary receipt scripts may execute."""
import importlib.util
import os
from pathlib import Path
import unittest
import json
import sys
import tempfile
from types import SimpleNamespace
from unittest.mock import patch, Mock

PATH = Path(__file__).resolve().parents[1] / "services" / "launch_app.py"


class LauncherTests(unittest.TestCase):
    def module(self):
        spec = importlib.util.spec_from_file_location("launch_app", PATH)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module

    def test_test_mode_blocks_before_loading_gio(self):
        with patch.dict(os.environ, OMADOCKED_TEST_MODE="1"):
            with self.assertRaisesRegex(RuntimeError, "test mode"):
                self.module().launch("one")

    def test_command_preserves_argv_cwd_and_reports_failure_without_shell(self):
        module = self.module()
        self.assertTrue(hasattr(module, "launch_record"), "Missing typed launcher dispatch")
        with tempfile.TemporaryDirectory(prefix="omadocked-argv-") as temp, patch.dict(os.environ, OMADOCKED_TEST_MODE="0"):
            result = Path(temp) / "result.json"
            values = ["", "a b", "$(touch never)", "'quoted'", "line\nbreak", "--flag=%f"]
            script = "import json,os,sys;open(sys.argv[1],'w').write(json.dumps([os.getcwd(),sys.argv[2:]]))"
            record = {"kind": "command", "enabled": True, "program": sys.executable,
                      "args": ["-c", script, str(result), *values], "workingDirectory": temp}
            module.launch_record(record)
            self.assertEqual(json.loads(result.read_text()), [temp, values])
            with self.assertRaisesRegex(RuntimeError, "exit code 7"):
                module.launch_record(dict(record, args=["-c", "import sys;sys.exit(7)"]))

    def test_terminal_uses_desktop_argv_api_and_testmode_blocks_all_kinds(self):
        module = self.module()
        self.assertTrue(hasattr(module, "command_argv"), "Missing terminal argv policy")
        with patch.object(module.shutil, "which", return_value="/usr/bin/xdg-terminal-exec"):
            self.assertEqual(module.command_argv({"program":"fixture", "args":["a b", "$(no)"], "terminal":True,
                                                 "workingDirectory":"/tmp/a b"}),
                             ["/usr/bin/xdg-terminal-exec", "--dir=/tmp/a b", "--", "fixture", "a b", "$(no)"])
        with patch.dict(os.environ, OMADOCKED_TEST_MODE="1"):
            for kind in ("application", "command", "file", "folder", "link", "action", "separator"):
                with self.assertRaisesRegex(RuntimeError, "test mode"):
                    module.launch_record({"kind":kind, "enabled":True})

    def test_uri_defaults_and_allowlisted_actions(self):
        module = self.module()
        self.assertTrue(hasattr(module, "launch_record"), "Missing typed launcher dispatch")
        app = Mock()
        app.launch_default_for_uri.return_value = True
        with patch.dict(os.environ, OMADOCKED_TEST_MODE="0"), patch.dict("sys.modules", {"gi.repository": SimpleNamespace(Gio=SimpleNamespace(AppInfo=app))}):
            module.launch_record({"kind":"link", "target":"https://example.com/a%20b", "enabled":True})
            app.launch_default_for_uri.assert_called_with("https://example.com/a%20b", None)
            with tempfile.TemporaryDirectory(prefix="omadocked-uri-") as temp:
                target = Path(temp) / "a #%.txt"
                target.touch()
                module.launch_record({"kind":"file", "target":str(target), "enabled":True})
                app.launch_default_for_uri.assert_called_with(target.as_uri(), None)
                module.launch_record({"kind":"folder", "target":temp, "enabled":True})
                app.launch_default_for_uri.assert_called_with(Path(temp).as_uri(), None)
            for uri in ("javascript:bad", "file:///tmp/x", "ftp://host", "https://", "https://a b"):
                with self.assertRaises(ValueError):
                    module.launch_record({"kind":"link", "target":uri, "enabled":True})
            with patch.object(module, "spawn") as spawn:
                for action, argv in (("quick-menu", ["omarchy", "menu", "toggle", "root"]), ("keybindings", ["omarchy", "menu", "keybindings"])):
                    module.launch_record({"kind":"action", "action":action, "enabled":True})
                    spawn.assert_called_with(argv, "")
                with self.assertRaises(ValueError):
                    module.launch_record({"kind":"action", "action":"bad", "enabled":True})

    def test_desktop_action_uses_exact_advertised_gio_action_void_result(self):
        entry = Mock()
        entry.list_actions.return_value = ["New-Window"]
        entry.launch_action.return_value = None
        api = Mock()
        api.new.return_value = entry
        with patch.dict(os.environ, OMADOCKED_TEST_MODE="0"), patch.dict("sys.modules", {"gi.repository": SimpleNamespace(GioUnix=SimpleNamespace(DesktopAppInfo=api))}):
            self.module().launch_record({"kind": "desktop-action", "enabled": True,
                                         "desktopId": "Exact.App", "actionId": "New-Window"})
            api.new.assert_called_once_with("Exact.App.desktop")
            entry.list_actions.assert_called_once_with()
            entry.launch_action.assert_called_once_with("New-Window", None)
            entry.launch.assert_not_called()

    def test_menu_action_dispatches_exact_gio_id_but_menu_app_is_reserved(self):
        entry, api = Mock(), Mock()
        entry.list_actions.return_value = ["menu"]
        entry.launch_action.return_value = None
        api.new.return_value = entry
        record = {"kind": "desktop-action", "enabled": True, "desktopId": "Exact.App", "actionId": "menu"}
        with patch.dict(os.environ, OMADOCKED_TEST_MODE="0"), patch.dict("sys.modules", {"gi.repository": SimpleNamespace(GioUnix=SimpleNamespace(DesktopAppInfo=api))}):
            module = self.module()
            with self.assertRaises(ValueError):
                module.launch_record(dict(record, desktopId="menu"))
            api.new.assert_not_called()
            module.launch_record(record)
            api.new.assert_called_once_with("Exact.App.desktop")
            entry.list_actions.assert_called_once_with()
            entry.launch_action.assert_called_once_with("menu", None)
            entry.launch.assert_not_called()
            entry.launch_action.reset_mock()
            for actions in ([], ["Menu"], ["menu", "menu"]):
                entry.list_actions.return_value = actions
                with self.assertRaisesRegex(ValueError, "advertised"):
                    module.launch_record(record)
            entry.launch_action.assert_not_called()
            entry.launch.assert_not_called()

    def test_desktop_action_rejects_malformed_tokens_before_gio(self):
        api = Mock()
        bad = [None, 1, "", " ", " padded", "trailing ", "../x", "a/b", "a\\b", "a\n", "a\x7f", "a;b", "x" * 513]
        with patch.dict(os.environ, OMADOCKED_TEST_MODE="0"), patch.dict("sys.modules", {"gi.repository": SimpleNamespace(GioUnix=SimpleNamespace(DesktopAppInfo=api))}):
            for field in ("desktopId", "actionId"):
                for token in bad:
                    with self.subTest(field=field, token=token), self.assertRaises(ValueError):
                        self.module().launch_record(dict({"kind": "desktop-action", "enabled": True,
                                                         "desktopId": "Exact.App", "actionId": "New-Window"}, **{field: token}))
            api.new.assert_not_called()

    def test_desktop_action_missing_removed_or_duplicate_fails_closed(self):
        entry, api = Mock(), Mock()
        record = {"kind": "desktop-action", "enabled": True, "desktopId": "Exact.App", "actionId": "New-Window"}
        with patch.dict(os.environ, OMADOCKED_TEST_MODE="0"), patch.dict("sys.modules", {"gi.repository": SimpleNamespace(GioUnix=SimpleNamespace(DesktopAppInfo=api))}):
            for result in (None, TypeError("native NULL")):
                api.new.side_effect = result if isinstance(result, Exception) else None
                api.new.return_value = result
                with self.assertRaisesRegex(RuntimeError, "no longer exists"):
                    self.module().launch_record(record)
            api.new.side_effect = None
            api.new.return_value = entry
            for actions in ([], ["new-window"], ["New-Window", "New-Window"]):
                entry.list_actions.return_value = actions
                with self.assertRaisesRegex(ValueError, "advertised"):
                    self.module().launch_record(record)
            entry.launch_action.assert_not_called()
        with patch.dict(os.environ, OMADOCKED_TEST_MODE="1"), patch.dict("sys.modules", {"gi.repository": None}):
            with self.assertRaisesRegex(RuntimeError, "test mode"):
                self.module().launch_record(record)

    def test_real_gio_rechecks_removed_action_and_void_does_not_prove_exec_success(self):
        import subprocess
        with tempfile.TemporaryDirectory(prefix="omadocked-action-gio-") as temp:
            root = Path(temp)
            applications = root / "applications"
            applications.mkdir()
            desktop = applications / "owned.desktop"
            base = "[Desktop Entry]\nType=Application\nName=Owned fixture\nExec=/usr/bin/true\nActions=Old;\n[Desktop Action Old]\nName=Old\nExec=/nonexistent/omadocked-owned-action\n"
            desktop.write_text(base)
            env = dict(os.environ, OMADOCKED_TEST_MODE="0", XDG_DATA_HOME=temp, XDG_DATA_DIRS=temp)
            result = subprocess.run(["/usr/bin/python3", "-c", "from gi.repository import GioUnix; import json; print(json.dumps(GioUnix.DesktopAppInfo.new('owned.desktop').list_actions()))"], env=env, text=True, capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(json.loads(result.stdout), ["Old"])
            record = {"kind": "desktop-action", "enabled": True, "desktopId": "owned", "actionId": "Old"}
            command = ["/usr/bin/python3", str(PATH), "--record", json.dumps(record)]
            # The advertised action has an invalid executable. Gio returns void;
            # submission cannot honestly claim successful execution or a window.
            result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 0, result.stderr)
            desktop.write_text(base.replace("Actions=Old;", "Actions=New;").replace("Desktop Action Old", "Desktop Action New"))
            result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 1)
            self.assertIn("no longer advertised", result.stderr)
            desktop.unlink()
            result = subprocess.run(command, env=env, text=True, capture_output=True, timeout=3)
            self.assertEqual(result.returncode, 1)
            self.assertIn("no longer exists", result.stderr)

    def test_gio_owns_exec_parsing_and_launch_result(self):
        entry = Mock()
        entry.launch.return_value = True
        api = Mock()
        api.new.return_value = entry
        gio = SimpleNamespace(DesktopAppInfo=api)
        with patch.dict(os.environ, OMADOCKED_TEST_MODE="0"), patch.dict("sys.modules", {"gi.repository": SimpleNamespace(GioUnix=gio)}):
            self.module().launch("example")
            api.new.assert_called_once_with("example.desktop")
            entry.launch.assert_called_once_with([], None)
            entry.launch.return_value = False
            with self.assertRaisesRegex(RuntimeError, "rejected"):
                self.module().launch("example")
            for ident in ("../foo", "", "menu", "x\n"):
                with self.assertRaises(ValueError):
                    self.module().launch(ident)


if __name__ == "__main__":
    unittest.main()
