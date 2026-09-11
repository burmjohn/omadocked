"""Test-only pre-spawn boundary. No PATH shims or global subprocess patches."""
import os
from pathlib import Path
import shutil
import stat
import sys
import subprocess

ROOT = Path(__file__).resolve().parents[1]
QUICKSHELL = Path('/usr/bin/quickshell')


class UnsafeLaunch(RuntimeError):
    pass


def fixture_environment():
    """Drop inherited test/Quickshell controls BEFORE fixture overrides."""
    return {k: v for k, v in os.environ.items()
            if not k.startswith(('OMADOCKED_', 'QS_', 'FAKE_'))
            and k != 'HYPRLAND_INSTANCE_SIGNATURE'}


def _owned(path, roots):
    value = Path(path)
    if not value.is_absolute() or not any(value.resolve().is_relative_to(r) for r in roots):
        raise UnsafeLaunch(f'fixture path is not owned: {path}')
    return value


def _command(argv, env):
    if not isinstance(argv, (tuple, list)) or not argv:
        raise UnsafeLaunch('explicit argv required')
    argv = list(map(str, argv))
    executable = shutil.which(argv[0], path=env.get('PATH', os.defpath))
    if not executable:
        raise UnsafeLaunch('fixture executable is missing')
    resolved = Path(executable).resolve()
    if resolved == QUICKSHELL.resolve():
        argv[0] = str(QUICKSHELL)
    elif resolved == Path('/usr/lib/qt6/bin/qmltestrunner').resolve() and env.get('QT_QPA_PLATFORM') == 'offscreen':
        argv[0] = '/usr/lib/qt6/bin/qmltestrunner'
    elif resolved == Path('/usr/bin/python3').resolve() and len(argv) > 3:
        wrapper = Path(argv[1])
        if argv[2] != '--' or not wrapper.is_file() or wrapper.read_bytes() != (ROOT/'tools/preview.py').read_bytes():
            raise UnsafeLaunch('only the exact preview wrapper (including owned copies) is allowed')
        qs = shutil.which('quickshell', path=env.get('PATH', os.defpath))
        if not qs or Path(qs).resolve() != QUICKSHELL.resolve():
            raise UnsafeLaunch('preview wrapper must resolve the installed Quickshell, not a shim')
    else:
        raise UnsafeLaunch('unexpected fixture executable (private symlinks must resolve to installed Quickshell)')
    if any(a.split('=')[0] in ('-platform', '--platform', '-platformpluginpath', '-platformtheme') for a in argv):
        raise UnsafeLaunch('Qt command-line platform overrides refused')
    if any(a in ('-d', '--daemonize') for a in argv):
        raise UnsafeLaunch('owned fixtures may not daemonize')
    return argv


def _socket_stat(path):
    return path.stat()


def _wayland_plugin_available():
    return any(Path('/usr/lib/qt6/plugins/platforms').glob('libqwayland*.so'))


def require_native(env, scope='hidden-backend'):
    """Consent is read from the caller, not a fixture's child overrides."""
    if os.environ.get('OMADOCKED_TEST_NATIVE') != '1' or scope not in os.environ.get('OMADOCKED_TEST_NATIVE_SCOPE', '').split(','):
        raise UnsafeLaunch(f'native consent required: OMADOCKED_TEST_NATIVE=1 OMADOCKED_TEST_NATIVE_SCOPE={scope}')
    if env.get('QT_QPA_PLATFORM') != 'wayland':
        raise UnsafeLaunch('native requires wayland without fallback')
    runtime = Path(env.get('XDG_RUNTIME_DIR', ''))
    display = env.get('WAYLAND_DISPLAY', '')
    if not runtime.is_absolute() or not runtime.is_dir() or not display:
        raise UnsafeLaunch('native requires existing absolute runtime and Wayland socket')
    socket = Path(display) if Path(display).is_absolute() else runtime/display
    try:
        metadata = _socket_stat(socket)
    except OSError as error:
        raise UnsafeLaunch('Wayland socket is missing') from error
    if not stat.S_ISSOCK(metadata.st_mode) or metadata.st_uid != os.getuid() or not os.access(socket, os.R_OK | os.W_OK) or not os.access(runtime, os.R_OK | os.W_OK | os.X_OK):
        raise UnsafeLaunch('Wayland socket/runtime is not accessible and user-owned')
    if not _wayland_plugin_available():
        raise UnsafeLaunch('installed Qt6 Wayland platform plugin missing')


def manual_process(kind, scope, argv, **kwargs):
    """Manual CLI/app/capture runners have their own consent, never hidden consent."""
    supplied_env = kwargs.pop('env', None)
    # Match subprocess inheritance for None/omitted, not explicit empty mappings.
    env = dict(os.environ if supplied_env is None else supplied_env)
    env.setdefault('QT_QPA_PLATFORM', 'wayland')
    require_native(env, scope)
    if sys.flags.optimize or env.get('PYTHONOPTIMIZE', '') not in ('', '0'):
        raise UnsafeLaunch('optimized Python is not verification')
    if kind not in ('run', 'Popen') or kwargs.get('shell') or 'executable' in kwargs:
        raise UnsafeLaunch('unsupported manual spawn')
    env['QT_QPA_PLATFORMTHEME'] = ''
    return getattr(subprocess, kind)(argv, env=env, **kwargs)


def manual_native(scope):
    """Separate opt-in for manual runners; existing action flags still apply."""
    require_native(dict(os.environ, QT_QPA_PLATFORM='wayland'), scope)


def spawn(argv, *, required=None, env, root, owned_roots=(), **kwargs):
    if sys.flags.optimize or env.get('PYTHONOPTIMIZE', '') not in ('', '0') or os.environ.get('PYTHONOPTIMIZE', '') not in ('', '0'):
        raise UnsafeLaunch('optimized Python is not verification')
    if env.get('OMADOCKED_TEST_LIVE_READONLY') == '1':
        raise UnsafeLaunch('live-read is outside the automated backend gate')
    if required not in ('offscreen', 'native'):
        raise UnsafeLaunch('missing/unknown backend requirement')
    platform = 'wayland' if required == 'native' else 'offscreen'
    if env.get('QT_QPA_PLATFORM') != platform:
        raise UnsafeLaunch('backend requirement contradicts effective QT_QPA_PLATFORM')
    if required == 'native':
        require_native(env)
    if kwargs.get('shell') or 'executable' in kwargs:
        raise UnsafeLaunch('shell/executable overrides bypass argv validation')
    env = dict(env)
    root = Path(root).resolve()
    roots = (root, *(Path(p).resolve() for p in owned_roots))
    for key in ('DISPLAY', 'QS_CONFIG_PATH', 'QS_CONFIG_NAME', 'QS_MANIFEST'):
        env.pop(key, None)
    if required == 'offscreen':
        env.pop('WAYLAND_DISPLAY', None)
    fake = env.get('OMADOCKED_HYPRCTL')
    if fake:
        fake = _owned(fake, roots)
        if not fake.is_file() or not os.access(fake, os.X_OK) or not env.get('HYPRLAND_INSTANCE_SIGNATURE'):
            raise UnsafeLaunch('owned fake compositor executable and identity required')
    else:
        env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
    for key, value in env.items():
        if key.startswith('FAKE_') or key in ('OMADOCKED_PARKING_JOURNAL',):
            _owned(value, roots)
    env.update(QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software', QML_XHR_ALLOW_FILE_READ='1')
    for key, name in [('HOME', 'home'), ('XDG_CONFIG_HOME', 'config'), ('XDG_DATA_HOME', 'data'),
                      ('XDG_STATE_HOME', 'state'), ('XDG_CACHE_HOME', 'cache'), ('XDG_RUNTIME_DIR', 'runtime')]:
        if key == 'XDG_RUNTIME_DIR' and required == 'native':
            continue
        existing = Path(env.get(key, ''))
        directory = existing if existing.is_absolute() and any(existing.resolve().is_relative_to(r) for r in roots) else root/'.test-environment'/name
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        env[key] = str(directory)
    argv = _command(argv, env)
    proc = subprocess.Popen(argv, env=env, **kwargs)
    proc.test_env = env
    return proc


def ipc(proc, argv, **kwargs):
    """Use the owned child's exact runtime and the installed CLI, not its PATH."""
    argv = list(map(str, argv))
    if not hasattr(proc, 'test_env') or argv[1:3] != ['ipc', '--pid'] or argv[3] != str(proc.pid):
        raise UnsafeLaunch('IPC requires the exact guarded child PID')
    kwargs.pop('env', None)
    if kwargs.get('shell') or 'executable' in kwargs:
        raise UnsafeLaunch('IPC executable override refused')
    argv[0] = str(QUICKSHELL)
    return subprocess.run(argv, env=dict(proc.test_env), **kwargs)
