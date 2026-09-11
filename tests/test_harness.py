"""Harness control tests: fake subprocesses only, never touch the desktop."""
import contextlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import Mock, patch

TESTS = Path(__file__).resolve().parent


def load_harness(name, optimize=0):
    path = TESTS / (name + ".py")
    module = types.ModuleType("harness_" + name)
    module.__file__ = str(path)
    exec(compile(path.read_text(), str(path), "exec", optimize=optimize), module.__dict__)
    return module


class HarnessTests(unittest.TestCase):
    @contextlib.contextmanager
    def harness(self, name, args=(), wayland=True, optimize=0):
        module = load_harness(name, optimize)
        if hasattr(module, "unchanged_digest"):
            module.unchanged_digest = Mock(return_value="test-only-digest")
        commands = types.SimpleNamespace(
            run=Mock(side_effect=RuntimeError("unexpected command")),
            Popen=Mock(side_effect=RuntimeError("unexpected process")),
            STDOUT=subprocess.STDOUT, TimeoutExpired=subprocess.TimeoutExpired,
        )
        with tempfile.TemporaryDirectory() as directory:
            module.ROOT = Path(directory)
            (module.ROOT / "shell.qml").write_text("// test fixture\n")
            env = {"WAYLAND_DISPLAY": "test-only"} if wayland else {}
            with patch.object(module, "subprocess", commands), patch.object(module.safety, "subprocess", commands), patch.object(module.safety, "require_native"), patch.dict(os.environ, env, clear=True), patch.object(sys, "argv", [name, *args]), contextlib.redirect_stdout(io.StringIO()):
                yield module, commands

    def invoke(self, module):
        return module.main() if hasattr(module, "main") else module.run()

    def seed_evidence(self, module, name):
        evidence = module.ROOT / "evidence"
        evidence.mkdir(exist_ok=True)
        target = evidence / ("native.json" if name == "live" else "smoke.json")
        target.write_text(json.dumps({"passed": True, "stale": True}))
        foundation = evidence / "foundation.json"
        foundation.write_bytes(b"immutable historical fixture\n")
        return target, foundation

    def fake_runtime(self, module, commands):
        runtime = {"alive": True, "visible": False, "clock": 0., "transform": 0}
        state = {"screenCount": 1, "phase": 3, "nonlaunching": True, "testMode": True,
                 "visible": False, "output": "TEST", "fallback": False,
                 "mode": "off", "reducedMotion": True, "autoHide": False, "offset": 96}
        proc = Mock(pid=321)
        proc.poll.side_effect = lambda: None if runtime["alive"] else 0
        def wait(**kwargs):
            runtime["alive"] = False
            return 0
        proc.wait.side_effect = wait
        def start(*args, **kwargs):
            runtime["alive"] = True
            runtime["visible"] = False
            state["visible"] = False
            state["fallback"] = kwargs["env"].get("OMADOCKED_SCREEN") == "OMADOCKED-ABSENT-PROBE"
            return proc
        commands.Popen.side_effect = start
        def run(argv, **kwargs):
            argv = [arg for arg in argv if arg != "--"]
            value = ""
            if argv[:3] == ["hyprctl", "-j", "monitors"]:
                value = json.dumps([{"name": "TEST", "width": 1000, "height": 1000,
                    "scale": 1, "x": 0, "y": 0, "refreshRate": 60, "transform": runtime["transform"]}])
            elif argv[:3] == ["hyprctl", "-j", "layers"]:
                rows = [{"pid": proc.pid, "namespace": "omadocked-prototype", "x": 100,
                         "y": 800, "w": 100, "h": 100}] if runtime["visible"] and runtime["alive"] else []
                value = json.dumps({"TEST": {"levels": {"3": rows}}})
            elif argv[:2] == ["quickshell", "ipc"]:
                method = argv[6]
                if method == "snapshot":
                    value = json.dumps(state)
                elif method in ("show", "hide"):
                    runtime["visible"] = state["visible"] = method == "show"
                elif method == "mode":
                    state["mode"] = argv[7]
            elif argv[0] == "grim":
                Path(argv[-1]).write_bytes(b"unit-test capture placeholder")
            elif argv[:3] != ["omarchy", "plugin", "validate"]:
                raise RuntimeError("unexpected fake argv: " + repr(argv))
            return types.SimpleNamespace(returncode=0, stdout=value, stderr="")
        commands.run.side_effect = run
        module.time = types.SimpleNamespace(monotonic=lambda: runtime["clock"], sleep=lambda _: None)
        return runtime, proc

    def test_failed_attempt_invalidates_previous_success_before_commands(self):
        for name in ("live", "smoke"):
            with self.subTest(name=name), self.harness(name, ["--visible"]) as (module, commands):
                target, foundation = self.seed_evidence(module, name)
                def fail(*args, **kwargs):
                    self.assertFalse(json.loads(target.read_text())["passed"])
                    raise RuntimeError("command failed")
                commands.run.side_effect = fail
                with self.assertRaisesRegex(RuntimeError, "command failed"):
                    self.invoke(module)
                self.assertFalse(json.loads(target.read_text())["passed"])
                self.assertEqual(foundation.read_bytes(), b"immutable historical fixture\n")

    def test_rejected_attempt_also_invalidates_previous_success(self):
        for name, args, wayland, optimization in (
            ("live", [], True, 0), ("smoke", [], False, 0),
            ("live", ["--visible"], True, 1), ("smoke", [], True, 1),
        ):
            with self.subTest(name=name, optimization=optimization), self.harness(name, args, wayland, optimization) as (module, commands):
                target, foundation = self.seed_evidence(module, name)
                with self.assertRaises(RuntimeError):
                    self.invoke(module)
                self.assertFalse(json.loads(target.read_text())["passed"])
                self.assertEqual(foundation.read_bytes(), b"immutable historical fixture\n")
                commands.run.assert_not_called()
                commands.Popen.assert_not_called()

    def test_success_is_published_only_after_cleanup(self):
        for name in ("live", "smoke"):
            with self.subTest(name=name), self.harness(name, ["--visible"]) as (module, commands):
                target, _ = self.seed_evidence(module, name)
                runtime, proc = self.fake_runtime(module, commands)
                def wait(**kwargs):
                    self.assertFalse(json.loads(target.read_text())["passed"], "passed published before cleanup")
                    runtime["alive"] = False
                    return 0
                proc.wait.side_effect = wait
                self.invoke(module)
                self.assertTrue(json.loads(target.read_text())["passed"])
                self.assertFalse(runtime["alive"])

    def test_cleanup_failure_never_publishes_success(self):
        for name in ("live", "smoke"):
            with self.subTest(name=name), self.harness(name, ["--visible"]) as (module, commands):
                target, _ = self.seed_evidence(module, name)
                _, proc = self.fake_runtime(module, commands)
                proc.wait.side_effect = RuntimeError("cleanup failed")
                output = io.StringIO()
                with contextlib.redirect_stdout(output), self.assertRaisesRegex(RuntimeError, "cleanup failed"):
                    self.invoke(module)
                self.assertFalse(json.loads(target.read_text())["passed"])
                self.assertNotIn('"passed": true', output.getvalue())

    def test_capture_help_discloses_composited_background_and_overlap(self):
        with self.harness("live", ["--help"]) as (module, commands):
            output = io.StringIO()
            with contextlib.redirect_stdout(output), self.assertRaises(SystemExit) as caught:
                self.invoke(module)
            self.assertEqual(caught.exception.code, 0)
            help_text = output.getvalue()
            for text in ("--capture-composited-region", "composited", "background", "overlap"):
                self.assertIn(text, help_text)
            commands.run.assert_not_called()
            commands.Popen.assert_not_called()

    def test_capture_requires_opt_in_and_labels_scope(self):
        for flag in (None, "--capture-composited-region", "--capture"):
            args = ["--visible"] + ([flag] if flag else [])
            with self.subTest(flag=flag), self.harness("live", args) as (module, commands):
                self.fake_runtime(module, commands)
                try:
                    self.invoke(module)
                except SystemExit as exc:
                    self.fail(f"Capture opt-in flag rejected: {flag} ({exc})")
                report = json.loads((module.ROOT / "evidence/native.json").read_text())
                captures = [call for call in commands.run.call_args_list if call.args[0][0] == "grim"]
                self.assertEqual(len(captures), 1 if flag else 0)
                for check in report["checks"]:
                    if "screenshot" in check:
                        self.assertEqual(check.get("screenshot_scope"), "cropped composited desktop region; may include background and overlapping windows, not isolated surface pixels")
                    elif not flag:
                        self.assertNotIn("screenshot_scope", check)

    def test_show_gets_fresh_readiness_deadline(self):
        with self.harness("live", ["--visible"]) as (module, commands):
            runtime, _ = self.fake_runtime(module, commands)
            fake_run = commands.run.side_effect
            pending = False
            def delayed_show(argv, **kwargs):
                nonlocal pending
                argv = [arg for arg in argv if arg != "--"]
                result = fake_run(argv, **kwargs)
                if argv[:2] == ["quickshell", "ipc"] and argv[6] == "show":
                    # Configuration/show outlasts the old IPC-startup budget.
                    runtime["clock"] += 20
                    pending = True
                elif argv[:3] == ["hyprctl", "-j", "layers"] and pending:
                    pending = False
                    return types.SimpleNamespace(stdout="{}", returncode=0, stderr="")
                return result
            commands.run.side_effect = delayed_show
            self.invoke(module)
            self.assertTrue(json.loads((module.ROOT / "evidence/native.json").read_text())["passed"])

    def test_smoke_labels_snapshot_only_coverage(self):
        with self.harness("smoke") as (module, commands):
            self.fake_runtime(module, commands)
            self.invoke(module)
            report = json.loads((module.ROOT / "evidence/smoke.json").read_text())
            self.assertIn("hidden/nonlaunching snapshot contract", report["checks"])
            self.assertIn("owned-layer absence at compositor", report["not_tested"])
            self.assertIn("child-process launch tracing", report["not_tested"])

    def test_rotated_or_unknown_transform_rejected_before_launch(self):
        for transform in (1, 2, 3, 4, 5, 6, 7, None):
            with self.subTest(transform=transform), self.harness("live", ["--visible"]) as (module, commands):
                runtime, _ = self.fake_runtime(module, commands)
                runtime["transform"] = transform
                with self.assertRaisesRegex(RuntimeError, "transform.*unsupported"):
                    self.invoke(module)
                commands.Popen.assert_not_called()
                self.assertFalse(json.loads((module.ROOT / "evidence/native.json").read_text())["passed"])

    def test_live_requires_explicit_visible_before_commands(self):
        with self.harness("live") as (module, commands):
            with self.assertRaisesRegex(RuntimeError, "--visible"):
                self.invoke(module)
            commands.run.assert_not_called()
            commands.Popen.assert_not_called()

    def test_wayland_guards_before_commands(self):
        for name in ("live", "smoke"):
            with self.subTest(name=name), self.harness(name, ["--visible"], wayland=False) as (module, commands):
                with self.assertRaisesRegex(RuntimeError, "Wayland"):
                    self.invoke(module)
                commands.run.assert_not_called()
                commands.Popen.assert_not_called()

    def test_native_contract_optimized_execution_rejected_before_activity(self):
        for optimization in (1, 2):
            with self.subTest(optimization=optimization), self.harness("unit/native_contract", optimize=optimization) as (module, commands):
                with patch.object(Path, "open", side_effect=RuntimeError("unexpected file activity")) as file_open:
                    with self.assertRaisesRegex(RuntimeError, "Python optimized execution is unsupported"):
                        self.invoke(module)
                    file_open.assert_not_called()
                commands.run.assert_not_called()
                commands.Popen.assert_not_called()

    def test_optimized_execution_rejected_before_commands(self):
        for name in ("live", "smoke"):
            for optimization in (1, 2):
                with self.subTest(name=name, optimization=optimization), self.harness(name, ["--visible"], optimize=optimization) as (module, commands):
                    with self.assertRaisesRegex(RuntimeError, "optimized"):
                        self.invoke(module)
                    commands.run.assert_not_called()
                    commands.Popen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
