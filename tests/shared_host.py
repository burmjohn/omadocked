"""Owned offscreen integration using verbatim installed host lifecycle excerpts.
Not live-host acceptance. No full shell, native surfaces or user actions.
"""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import spawn_safety as safety
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'evidence/phase3-shared-host'
HOST = Path('/usr/share/omarchy/shell/shell.qml')


def run():
    OUT.mkdir(parents=True, exist_ok=True)
    text = HOST.read_text()
    # Fail visibly if the installed structure changes; never emulate its loader.
    service = text[text.index('  Item {\n    id: serviceHost'):text.index('  // Writes inline settings')]
    panels = text[text.index('  property var openPanelIds:'):text.index('  // ---------------------------------------------------------- plugin loader')]
    assert 'asynchronous: true' in panels and 'item.service = shell.serviceFor' in panels
    (OUT / 'host-excerpts.qml.txt').write_text(service + panels)
    provenance = {'host': str(HOST), 'host_sha256': hashlib.sha256(HOST.read_bytes()).hexdigest(),
                  'excerpts_sha256': hashlib.sha256((service + panels).encode()).hexdigest(),
                  'source_sha256': {}}
    with tempfile.TemporaryDirectory(prefix='omadocked-shared-host-') as tmp:
        base = Path(tmp)
        for folder in ('services', 'core', 'host'):
            shutil.copytree(ROOT / folder, base / folder)
        shutil.copytree(ROOT / 'ui', base / 'ui')
        shutil.copy2(ROOT / 'Dock.qml', base / 'Dock.qml')
        for path in [ROOT / 'Dock.qml', ROOT / 'manifest.json', ROOT / 'tests/shared_host.py',
                     *[p for folder in ('services','host','core','ui') for p in sorted((ROOT / folder).glob('*'))]]:
            if path.is_file(): provenance['source_sha256'][str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
        # Inert presentation/action boundaries. Actual controller and storage remain intact.
        (base / 'DockSurface.qml').write_text('''import QtQuick
Item {
 property var outputScreen; property var controller
 property bool outputRoutingLocked: false; property bool attentionVisible: false
 property bool selected: false
 function snapshot() { return {visible:false, name:"owned", view:null} }
 function releaseInteractions() {}
}''')
        (base / 'services/ShellGestures.qml').write_text('import QtQuick\nQtObject { property bool enabled: false; function perform(kind, delta) { return false } }')
        (base / 'services/AttentionSound.qml').write_text('import QtQuick\nQtObject { property bool allowed: false; property string status:"inert"; function play(name) { return false } }')
        (base / 'Commons').mkdir()
        (base / 'Commons/qmldir').write_text('singleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\n')
        (base / 'Commons/Style.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property real cornerRadius: 11 }')
        (base / 'Commons/Color.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property QtObject bar: QtObject { property color background: "#223344" } }')
        (base / 'FixtureService.qml').write_text('''import QtQuick
QtObject {
 property var shell; property var manifest; property var pluginRegistry
 property string omarchyPath; property var barWidgetRegistry
 property int serial: 0
 Component.onCompleted: serial = Date.now() % 1000000000
}''')
        manifest = json.loads((ROOT / 'manifest.json').read_text())
        manifest['__sourceDir'] = str(base)
        fixtures = {manifest['id']: manifest, 'fixture.service': {'id':'fixture.service', 'kinds':['service'], 'entryPoints':{'service':'FixtureService.qml'}, '__sourceDir':str(base)}}
        shell = '''import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import qs.Commons
ShellRoot {
 id: shell
 property string omarchyPath: "owned-host"
 property var barWidgetRegistry: null
 property var bar: null
 property QtObject rememberedService: null
 property bool pluginReloading: false
 property var pluginRegistry: QtObject {
   property var installedPlugins: FIXTURES
   signal pluginsChanged()
   function isEnabled(id) { return !!installedPlugins[id] }
   function resolveEnabledId(id) { return isEnabled(id) ? id : "" }
   function entryPointUrl(m, kind) { return "file://" + m.__sourceDir + "/" + m.entryPoints[kind] }
 }
 HOST_SERVICE
 HOST_PANELS
 readonly property var dock: panelLoaders["burmjohn.omadocked"] ? panelLoaders["burmjohn.omadocked"].item : null
 property int receipt: 0
 property bool receiptOk: false
 Connections { target: shell.dock; function onPersistenceCompleted(id, ok, message) { shell.receipt = id; shell.receiptOk = ok } }
 // Two disposable presentation consumers, one actual Dock-owned AppService/writer.
 property bool consumersEnabled: true
 Loader { active: shell.consumersEnabled; sourceComponent: QtObject { property var shared: shell.dock; property int size: shared ? shared.iconSize : -1 } id: consumerA }
 Loader { active: shell.consumersEnabled; sourceComponent: QtObject { property var shared: shell.dock; property int size: shared ? shared.iconSize : -1 } id: consumerB }
 Component.onCompleted: { _syncServices(); rememberedService = serviceFor("fixture.service"); panelEntries = computePanelEntries() }
 IpcHandler {
  target: "shared-host-test"
  function state(): string { return JSON.stringify({loaded:!!shell.dock, ready:shell.dock ? shell.dock.ready:false,
   error:shell.dock ? shell.dock.appError:"", recover:shell.dock ? shell.dock.canRecover:false,
   receipt:shell.receipt, ok:shell.receiptOk, opened:shell.dock ? shell.dock.opened:false,
   size:shell.dock ? shell.dock.iconSize:-1, radius:shell.dock ? shell.dock.themeCornerRadius:-1,
   background:shell.dock ? String(shell.dock.themeBackground):"",
   injected:shell.dock ? shell.dock.shell === shell && shell.dock.manifest.id === "burmjohn.omadocked" && shell.dock.service === null:false,
   two:!!consumerA.item && !!consumerB.item && consumerA.item.shared === consumerB.item.shared,
   a:consumerA.item ? consumerA.item.size:-1, b:consumerB.item ? consumerB.item.size:-1,
   serviceAlive:!!shell.rememberedService, service:!!shell.serviceFor("fixture.service"), serviceSerial:shell.serviceFor("fixture.service") ? shell.serviceFor("fixture.service").serial:0}) }
  function save(size: int): bool { return shell.dock.setIconSize(size) }
  function recover(): bool { return shell.dock.recoverConfiguration() }
  function summon(): bool { return shell.summon("burmjohn.omadocked", "owned") }
  function hide(): bool { return shell.hide("burmjohn.omadocked") }
  function unload(): void { shell.unloadPanels() }
  function reload(): void { shell.panelEntries = shell.computePanelEntries() }
  function consumers(value: bool): void { shell.consumersEnabled = value }
  function theme(): void { Style.cornerRadius = 23; Color.bar.background = "#445566" }
  function unloadServices(): void { shell.unloadPluginServices() }
  function loadServices(): void { shell._syncServices() }
 }
}'''.replace('FIXTURES', json.dumps(fixtures)).replace('HOST_SERVICE', service).replace('HOST_PANELS', panels)
        (base / 'shell.qml').write_text(shell)
        (OUT / 'fixture-shell.qml.txt').write_text(shell.replace(str(base), '<temporary-root>'))
        config = base / 'config/pins.json'
        env = {k:v for k,v in safety.fixture_environment().items() if not k.startswith(('OMADOCKED_', 'QS_')) and k not in ('WAYLAND_DISPLAY','DISPLAY','HYPRLAND_INSTANCE_SIGNATURE')}
        env.update(QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software', OMADOCKED_TEST_MODE='1', OMADOCKED_VISIBLE='0', OMADOCKED_CONFIG_PATH=str(config), XDG_STATE_HOME=str(base / 'state'), QS_NO_RELOAD_POPUP='1')
        states = []
        with (OUT / 'runtime.log').open('w') as log:
            proc = safety.spawn(['quickshell','-p',str(base / 'shell.qml'),'--no-color'],required="offscreen",root=base,env=env,stdout=log,stderr=subprocess.STDOUT)
            try:
                def call(method, *args):
                    r = safety.ipc(proc, ['quickshell','ipc','--pid',str(proc.pid),'call','--','shared-host-test',method,*map(str,args)],env=env,capture_output=True,text=True,timeout=3)
                    if r.returncode: return None
                    return json.loads(r.stdout) if r.stdout.strip() else True
                def wait(label, predicate):
                    deadline = time.monotonic()+10
                    while time.monotonic()<deadline:
                        s = call('state')
                        if s and predicate(s):
                            states.append({'step':label, **s}); return s
                        if proc.poll() is not None: break
                        time.sleep(.04)
                    raise AssertionError((label,s,(OUT/'runtime.log').read_text()))
                def children():
                    return Path(f'/proc/{proc.pid}/task/{proc.pid}/children').read_text().split()
                def lock_held():
                    with open(str(config)+'.lock','r+') as f:
                        try: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
                        except BlockingIOError: return True
                        return False
                s=wait('created',lambda s:s['ready'] and s['radius']==11)
                assert s['injected'] and s['two'] and s['service'] and not s['error'], s
                service_serial=s['serviceSerial']
                writer=children(); assert len(writer)==1, writer
                assert b'config_store.py' in Path(f'/proc/{writer[0]}/cmdline').read_bytes()
                assert lock_held()
                shell_fds = []
                for fd in Path(f'/proc/{proc.pid}/fd').iterdir():
                    try: shell_fds.append(os.readlink(fd))
                    except FileNotFoundError: pass
                assert str(config)+'.lock' not in shell_fds
                call('loadServices'); wait('service-sync-idempotent',lambda s:s['serviceSerial']==service_serial and s['serviceAlive'])
                call('summon'); wait('summon',lambda s:s['opened'])
                call('hide'); wait('keepLoaded-close',lambda s:s['loaded'] and not s['opened'])
                assert children()==writer and lock_held()
                call('save',48); wait('durable-save-48',lambda s:s['size']==48 and s['ok'])
                assert json.loads(config.read_text())['settings']['iconSize']==48
                call('save',52); wait('two-consumers-save-52',lambda s:s['a']==52 and s['b']==52 and s['ok'])
                assert json.loads(config.read_text())['settings']['iconSize']==52
                call('consumers','false'); wait('consumers-destroyed',lambda s:not s['two'])
                assert children()==writer and lock_held()
                call('consumers','true'); wait('consumers-recreated',lambda s:s['two'] and s['a']==52)
                call('theme'); wait('theme-update',lambda s:s['radius']==23 and s['background']=='#445566')
                # A competing actual writer must fail closed, not become another consumer writer.
                contender=subprocess.run(['/usr/bin/python3',str(base/'services/config_store.py'),str(config)],input='',capture_output=True,text=True,timeout=3)
                (OUT/'contender.log').write_text(contender.stdout+contender.stderr)
                assert contender.returncode == 3 and json.loads(contender.stdout) == {'type':'ready','ok':False,'error':'busy'}, contender
                assert lock_held()
                call('unload'); wait('overlay-unloaded-service-retained',lambda s:not s['loaded'] and s['serviceSerial']==service_serial)
                deadline=time.monotonic()+5
                while any(Path('/proc/'+p).exists() for p in writer) and time.monotonic()<deadline: time.sleep(.02)
                assert not any(Path('/proc/'+p).exists() for p in writer)
                assert not lock_held()
                call('reload'); wait('overlay-reloaded-durable',lambda s:s['ready'] and s['size']==52 and s['radius']==23)
                assert lock_held() and len(children())==1
                call('unload'); wait('unload-before-corruption',lambda s:not s['loaded'])
                deadline=time.monotonic()+5
                while lock_held() and time.monotonic()<deadline: time.sleep(.02)
                assert not lock_held()
                config.write_text('{broken owned fixture')
                call('reload'); wait('corrupt-recovery-offered',lambda s:s['recover'])
                assert call('recover')
                wait('explicit-recovery',lambda s:s['ready'] and not s['recover'] and s['size']==52)
                assert json.loads(config.read_text())['settings']['iconSize']==52
                damaged = list(config.parent.glob('pins.json.damaged-*'))
                assert len(damaged) == 1 and damaged[0].read_text() == '{broken owned fixture'
                call('unloadServices'); wait('service-unloaded-overlay-retained',lambda s:not s['service'] and not s['serviceAlive'] and s['loaded'])
                call('loadServices'); wait('service-recreated',lambda s:s['service'] and s['serviceSerial']!=service_serial)
            finally:
                remaining_children = children() if proc.poll() is None else []
                proc.terminate()
                try: proc.wait(timeout=5)
                except subprocess.TimeoutExpired: proc.kill(); proc.wait(timeout=5)
                (OUT/'states.json').write_text(json.dumps(states,indent=2)+'\n')
                (OUT/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
        deadline = time.monotonic() + 5
        while any(Path('/proc/'+p).exists() for p in remaining_children) and time.monotonic() < deadline:
            time.sleep(.02)
        assert not any(Path('/proc/'+p).exists() for p in remaining_children), remaining_children
        assert not lock_held()
        warnings = [line for line in (OUT/'runtime.log').read_text().splitlines() if 'WARN' in line or 'ERROR' in line]
        assert warnings == ['  WARN: $HYPRLAND_INSTANCE_SIGNATURE is unset. Cannot connect to hyprland.'], warnings
        (OUT/'result.json').write_text(json.dumps({'checkpoints':len(states), 'owned_pid':proc.pid, 'reaped':True,
            'children_gone':True, 'lock_released':True, 'expected_warnings':warnings}, indent=2)+'\n')
        print(f'PASS: {len(states)} lifecycle checkpoints; exact owned process and children reaped; no full live shell imported')

if __name__ == '__main__':
    run()
