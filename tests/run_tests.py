"""Explicit automated backend subsets; default make test is guard-only.

Full here means classified Python + offscreen Qt, NOT product/manual acceptance.
"""
import argparse
import os
from pathlib import Path
import tempfile
import unittest

from backend_requirements import MODULES, EXCLUDED_METHODS, backend_for
import spawn_safety as safety

ROOT = Path(__file__).resolve().parents[1]


def cases(suite):
    for case in suite:
        if isinstance(case, unittest.TestSuite):
            yield from cases(case)
        else:
            yield case


def accepted(result):
    return bool(result.testsRun) and result.wasSuccessful() and not result.skipped


def select(suite, mode):
    selected, excluded = [], []
    for case in cases(suite):
        if case.id().split('.')[-1] in EXCLUDED_METHODS:
            excluded.append(case.id())
            continue
        backend = backend_for(case.id())
        if mode == 'full' or (backend == 'native') == (mode == 'native'):
            selected.append(case)
        else:
            excluded.append(case.id())
    return unittest.TestSuite(selected), excluded


def qml_tests(kind="qml"):
    if kind not in ("qml", "bench", "render"):
        raise safety.UnsafeLaunch("unclassified Qt input")
    with tempfile.TemporaryDirectory(prefix='omadocked-qt-tests-') as directory:
        env = dict(safety.fixture_environment(), QT_QPA_PLATFORM='offscreen')
        argv = ['/usr/lib/qt6/bin/qmltestrunner', '-input', str(ROOT/'tests'/kind), '-o', '-,txt']
        if kind == 'bench':
            argv += ['-iterations', '2000']
        proc = safety.spawn(argv,
                            required='offscreen', env=env, root=Path(directory))
        try:
            return proc.wait(timeout=300) == 0
        finally:
            if proc.poll() is None:
                proc.terminate()
                try:
                    proc.wait(timeout=5)
                except safety.subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=('offscreen', 'native', 'full', 'bench', 'render'))
    args = parser.parse_args()
    if not __debug__ or os.environ.get('PYTHONOPTIMIZE', '') not in ('', '0'):
        raise safety.UnsafeLaunch('optimized Python is not verification')
    if args.mode in ('bench', 'render'):
        return 0 if qml_tests(args.mode) else 1
    if args.mode in ('native', 'full'):
        # Before discovery/imports and before ANY subprocess, not after a subset.
        safety.require_native(dict(os.environ, QT_QPA_PLATFORM='wayland'))
    discovered = {p.stem for p in (ROOT/'tests').glob('test_*.py')}
    if discovered != set(MODULES):
        raise safety.UnsafeLaunch('module inventory changed: classify before running')
    suite = unittest.defaultTestLoader.discover(str(ROOT/'tests'), pattern='test_*.py')
    selected, excluded = select(suite, args.mode)
    print(f'{args.mode}: selected {selected.countTestCases()}; excluded {len(excluded)} (includes separately consented live-read).', flush=True)
    result = unittest.TextTestRunner(verbosity=2, failfast=True).run(selected)
    ok = accepted(result)
    if ok and args.mode in ('offscreen', 'full'):
        ok = qml_tests()
    print(f'{args.mode} automated backend gate: {"PASS" if ok else "NOT ACCEPTED"}; manual/native-product/physical acceptance not claimed.')
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
