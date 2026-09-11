"""External package discovery, hosted parking and removal recovery.
Installed loader/scanner excerpts, owned configuration provider and compositor.
Not live-host acceptance. No full shell, native surfaces or user actions.
"""
import argparse
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
import sys
import sqlite3
from test_parking_helper import ParkingHelperTests

ROOT = Path(__file__).resolve().parents[1]
HOST = Path('/usr/share/omarchy/shell/shell.qml')


def wait_recovery(recovery, tx, timeout=8):
    deadline=time.monotonic()+timeout
    receipt=None
    while time.monotonic()<deadline:
        receipt=recovery()
        if not receipt['busy'] and receipt['last'].get('transactionId')==tx: break
        time.sleep(.04)
    else:
        raise AssertionError(('recovery deadline', tx, receipt))
    assert not receipt['busy'] and receipt['last'].get('transactionId')==tx,receipt
    assert receipt['last']['ok'] and receipt['records']==[],receipt
    return receipt


def run(out=None):
    if out is None:
        with tempfile.TemporaryDirectory(prefix='omadocked-relocation-receipts-') as directory:
            _run(Path(directory))
    else:
        _run(Path(out))


def _run(OUT):
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
        plugin = base / 'external plugins' / 'relocated # dock'
        plugin.mkdir(parents=True)
        hostroot = base / 'new host root'
        hostroot.mkdir()
        for folder in ('services', 'core', 'host'):
            shutil.copytree(ROOT / folder, plugin / folder, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
        shutil.copytree(ROOT / 'ui', plugin / 'ui')
        shutil.copy2(ROOT / 'Dock.qml', plugin / 'Dock.qml')
        for path in [ROOT / 'Dock.qml', ROOT / 'manifest.json', ROOT / 'tests/shared_host.py',
                     ROOT / 'tests/relocation_recovery.py',
                     *[p for folder in ('services','host','core','ui') for p in sorted((ROOT / folder).glob('*'))]]:
            if path.is_file(): provenance['source_sha256'][str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
        # Inert presentation/action boundaries. Actual controller and storage remain intact.
        (plugin / 'DockSurface.qml').write_text('''import QtQuick
Item {
 property var outputScreen; property var controller
 property bool outputRoutingLocked: false; property bool attentionVisible: false
 property bool selected: false
 function snapshot() { return {visible:false, name:"owned", view:null} }
 function releaseInteractions() {}
}''')
        (plugin / 'services/ShellGestures.qml').write_text('import QtQuick\nQtObject { property bool enabled: false; function perform(kind, delta) { return false } }')
        (plugin / 'services/AttentionSound.qml').write_text('import QtQuick\nQtObject { property bool allowed: false; property string status:"inert"; function play(name) { return false } }')
        (hostroot / 'Commons').mkdir()
        (hostroot / 'Commons/qmldir').write_text('singleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\n')
        (hostroot / 'Commons/Style.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property real cornerRadius: 11 }')
        (hostroot / 'Commons/Color.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property QtObject bar: QtObject { property color background: "#223344" } }')
        (hostroot / 'FixtureService.qml').write_text('''import QtQuick
QtObject {
 property var shell; property var manifest; property var pluginRegistry
 property string omarchyPath; property var barWidgetRegistry
 property int serial: 0
 Component.onCompleted: serial = Date.now() % 1000000000
}''')
        shutil.copy2(ROOT / 'manifest.json', plugin / 'manifest.json')
        shutil.copy2('/usr/share/omarchy/shell/Commons/Util.qml', hostroot / 'Commons/Util.qml')
        with (hostroot / 'Commons/qmldir').open('a') as f: f.write('singleton Util 1.0 Util.qml\n')
        registry_text = Path('/usr/share/omarchy/shell/services/PluginRegistry.qml').read_text()
        registry_blocks = (registry_text[registry_text.index('  function isSafeEntryPoint'):registry_text.index('  function barTarget')]
            + registry_text[registry_text.index('  function parseScanOutput'):registry_text.index('  property Process initProcess')]
            + registry_text[registry_text.index('  function rescan()'):registry_text.index('  function ensureUserDir()')])
        (OUT / 'registry-excerpts.qml.txt').write_text(registry_blocks)
        registry_qml = """import QtQuick
import Quickshell.Io
import qs.Commons
QtObject {
 id: registry
 property string pluginsDir: PLUGINS
 property string firstPartyDir: ""
 property var installedPlugins: ({})
 property int registryRevision: 0
 property bool scanning: false
 property bool enabled: true
 signal pluginsChanged()
 signal scanFinished()
 property var shellConfigProvider: function() { return {plugins: enabled ? [{id:"burmjohn.omadocked"}] : []} }
 BLOCKS
}""".replace('PLUGINS', json.dumps(str(plugin.parent))).replace('BLOCKS', registry_blocks)
        (hostroot / 'OwnedRegistry.qml').write_text(registry_qml)
        provenance['registry_sha256'] = hashlib.sha256(registry_text.encode()).hexdigest()
        provenance['registry_excerpts_sha256'] = hashlib.sha256(registry_blocks.encode()).hexdigest()
        validation = subprocess.run(['omarchy','plugin','validate',str(plugin)],capture_output=True,text=True,timeout=10)
        (OUT / 'manifest-validation.log').write_text(validation.stdout + validation.stderr)
        assert validation.returncode == 0, validation
        # Production package references must not fall back to the source checkout.
        package_files = [p for p in plugin.rglob('*') if p.is_file()]
        assert all(str(ROOT).encode() not in p.read_bytes() for p in package_files)
        provenance['package_relative_files'] = sorted(str(p.relative_to(plugin)) for p in package_files)
        # No bundled production images exist; exercise an owned relative SVG
        # alongside the package, without relying on an offscreen system icon theme.
        (plugin / 'fixture-assets').mkdir()
        (plugin / 'fixture-assets/check.svg').write_text('<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8" fill="#223344"/></svg>')
        (plugin / 'AssetProbe.qml').write_text('import QtQuick\nImage { source: Qt.resolvedUrl("fixture-assets/check.svg") }')
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
 property var pluginRegistry: OwnedRegistry {
   onScanFinished: shell.panelEntries = shell.computePanelEntries()
 }

 HOST_SERVICE
 HOST_PANELS
 readonly property var dock: panelLoaders["burmjohn.omadocked"] ? panelLoaders["burmjohn.omadocked"].item : null
 Loader { id: menuAsset; source: shell.dock && shell.dock.manifest ? Util.fileUrl(shell.dock.manifest.__sourceDir + "/AssetProbe.qml") : "" }
 property int receipt: 0
 property bool receiptOk: false
 Connections { target: shell.dock; function onPersistenceCompleted(id, ok, message) { shell.receipt = id; shell.receiptOk = ok } }
 // Two disposable presentation consumers, one actual Dock-owned AppService/writer.
 property bool consumersEnabled: true
 Loader { active: shell.consumersEnabled; sourceComponent: QtObject { property var shared: shell.dock; property int size: shared ? shared.iconSize : -1 } id: consumerA }
 Loader { active: shell.consumersEnabled; sourceComponent: QtObject { property var shared: shell.dock; property int size: shared ? shared.iconSize : -1 } id: consumerB }
 Component.onCompleted: pluginRegistry.rescan()
 IpcHandler {
  target: "shared-host-test"
  function state(): string { return JSON.stringify({loaded:!!shell.dock, ready:shell.dock ? shell.dock.ready:false,
   error:shell.dock ? shell.dock.appError:"", recover:shell.dock ? shell.dock.canRecover:false,
   receipt:shell.receipt, ok:shell.receiptOk, opened:shell.dock ? shell.dock.opened:false,
   size:shell.dock ? shell.dock.iconSize:-1, radius:shell.dock ? shell.dock.themeCornerRadius:-1,
   background:shell.dock ? String(shell.dock.themeBackground):"", assetReady:menuAsset.item ? menuAsset.item.status === Image.Ready:false,
   assetSource:menuAsset.item ? String(menuAsset.item.source):"",
   injected:shell.dock ? shell.dock.shell === shell && shell.dock.manifest.id === "burmjohn.omadocked" && shell.dock.service === null:false,
   two:!!consumerA.item && !!consumerB.item && consumerA.item.shared === consumerB.item.shared,
   a:consumerA.item ? consumerA.item.size:-1, b:consumerB.item ? consumerB.item.size:-1,
   serviceAlive:!!shell.rememberedService, service:!!shell.serviceFor("fixture.service"), serviceSerial:shell.serviceFor("fixture.service") ? shell.serviceFor("fixture.service").serial:0}) }
  function save(size: int): bool { return shell.dock.setIconSize(size) }
  function recover(): bool { return shell.dock.recoverConfiguration() }
  function summon(): bool { return shell.summon("burmjohn.omadocked", "owned") }
  function hide(): bool { return shell.hide("burmjohn.omadocked") }
  function unload(): void { shell.unloadPanels() }
  function disable(): void { shell.pluginRegistry.enabled = false; shell.unloadPanels(); shell.panelEntries = shell.computePanelEntries() }
  function enable(): void { shell.pluginRegistry.enabled = true; shell.pluginRegistry.rescan() }
  function scan(): void { shell.pluginRegistry.rescan() }
  function reload(): void { shell.panelEntries = shell.computePanelEntries() }
  function consumers(value: bool): void { shell.consumersEnabled = value }
  function theme(): void { Style.cornerRadius = 23; Color.bar.background = "#445566" }
  function unloadServices(): void { shell.unloadPluginServices() }
  function loadServices(): void { shell._syncServices() }
 }
}'''.replace('HOST_SERVICE', service).replace('HOST_PANELS', panels)
        (hostroot / 'shell.qml').write_text(shell)
        (OUT / 'fixture-shell.qml.txt').write_text(shell.replace(str(base), '<temporary-root>'))
        config = base / 'config/pins.json'
        fixture = ParkingHelperTests()
        fixture.setUp()
        # Fake compositor executes production Lua checks; only owned clients exist.
        shutil.copy2(ROOT / 'tests/lua_compositor.py', base / 'lua_compositor.py')
        fake_text = fixture.hyprctl.read_text().replace(repr(str(ROOT / 'tests')), repr(str(base)))
        fixture.hyprctl.write_text(fake_text)
        env = {k:v for k,v in safety.fixture_environment().items() if not k.startswith(('OMADOCKED_', 'QS_')) and k not in ('WAYLAND_DISPLAY','DISPLAY','HYPRLAND_INSTANCE_SIGNATURE')}
        env.update(QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software',
                   OMADOCKED_TEST_MODE='1', OMADOCKED_VISIBLE='0', OMADOCKED_CONFIG_PATH=str(config),
                   XDG_STATE_HOME=str(base / 'state'), QS_NO_RELOAD_POPUP='1',
                   HYPRLAND_INSTANCE_SIGNATURE='fixture-session', OMADOCKED_PARKING_JOURNAL=str(fixture.journal),
                   OMADOCKED_HYPRCTL=str(fixture.hyprctl), FAKE_STATE=str(fixture.state),
                   FAKE_LOG=str(fixture.log), FAKE_JOURNAL=str(fixture.journal))
        helper = plugin / 'services/parking_store.py'
        # Other packaged helpers can be exercised without opening any app/file.
        folder = base / 'owned folder'
        folder.mkdir()
        (folder / 'fixture.txt').write_text('owned metadata')
        scan = subprocess.run(['/usr/bin/python3',str(plugin/'services/folder_scan.py')],
            input=json.dumps({'path':str(folder),'generation':1,'token':'relocated','timeoutMs':1000}),
            env=env,cwd=hostroot,capture_output=True,text=True,timeout=5)
        assert scan.returncode == 0,scan
        scan_result = json.loads(scan.stdout)
        assert 'fixture.txt' in scan.stdout,scan_result
        launch = subprocess.run(['/usr/bin/python3',str(plugin/'services/launch_app.py'),'--record',
                                 json.dumps({'enabled':False})],env=env,cwd=hostroot,
                                 capture_output=True,text=True,timeout=5)
        assert launch.returncode != 0,launch
        (OUT/'other-helpers.json').write_text(json.dumps({'folder':scan_result,
            'disabled_launch_exit':launch.returncode,'disabled_launch_stderr':launch.stderr},indent=2)+'\n')
        commands = []
        def direct(requests):
            r = subprocess.run(['/usr/bin/python3',str(helper),str(fixture.journal)],
                input=''.join(json.dumps(x)+'\n' for x in requests),env=env,capture_output=True,text=True,timeout=10)
            rows = [json.loads(x) for x in r.stdout.splitlines()]
            commands.append({'argv':['python3','<relocated>/services/parking_store.py','<private-journal>'],
                             'requests':requests,'exit':r.returncode,'responses':rows})
            assert r.returncode == 0 and rows[0]['ok'], (r,rows)
            return rows
        identity = fixture.identity('owned-key','0xaaa',101,'FixtureA')
        park = {'id':1,'op':'park','window':identity,'origin':{'workspace':'1','monitor':0,'floating':False,'at':[1,2],'size':[300,200]}}
        assert direct([park])[-1]['status']=='parked'
        parked_bytes = fixture.journal.read_bytes()
        states=[]
        owned_children=set()
        def locked(path):
            with open(str(path)+'.lock','r+') as f:
                try: fcntl.flock(f,fcntl.LOCK_EX|fcntl.LOCK_NB)
                except BlockingIOError: return True
                return False
        with (OUT / 'runtime.log').open('w') as log:
            proc = safety.spawn(['quickshell','-p',str(hostroot/'shell.qml'),'--no-color'],required="offscreen",root=base,owned_roots=(fixture.root,),env=env,cwd=hostroot,stdout=log,stderr=subprocess.STDOUT)
            def raw(target,method,*args):
                r=safety.ipc(proc, ['quickshell','ipc','--pid',str(proc.pid),'call','--',target,method,*map(str,args)],env=env,capture_output=True,text=True,timeout=3)
                return r.stdout.strip()
            def call(method,*args):
                value=raw('shared-host-test',method,*args)
                try: return json.loads(value) if value else True
                except ValueError: return None
            def recovery(method='status',*args):
                return json.loads(raw('omadocked-recovery',method,*args))
            def wait(label,predicate):
                deadline=time.monotonic()+12
                while time.monotonic()<deadline:
                    value=call('state')
                    if value and predicate(value):
                        states.append({'step':label,**value}); return value
                    if proc.poll() is not None: break
                    time.sleep(.04)
                raise AssertionError((label,value,(OUT/'runtime.log').read_text()))
            def children():
                return Path(f'/proc/{proc.pid}/task/{proc.pid}/children').read_text().split()
            def gone(pids):
                deadline=time.monotonic()+5
                while any(Path('/proc/'+p).exists() for p in pids) and time.monotonic()<deadline: time.sleep(.02)
                assert not any(Path('/proc/'+p).exists() for p in pids),pids
            def loaded(label):
                wait(label,lambda x:x['ready'] and x['radius']==11 and x['injected'] and x['assetReady'])
                deadline=time.monotonic()+8
                while time.monotonic()<deadline:
                    r=recovery()
                    if r['ready'] and not r['busy']: break
                    time.sleep(.04)
                assert r['ready'] and not r['busy'],r
                pids=children(); owned_children.update(pids)
                assert len(pids)==2,pids
                paths=[Path('/proc/'+p+'/cmdline').read_bytes().split(b'\0') for p in pids]
                assert {Path(os.fsdecode(a[1])).name for a in paths}=={'config_store.py','parking_store.py'},paths
                assert all(os.fsdecode(a[1]).startswith(str(plugin)) for a in paths),paths
                assert locked(config) and locked(fixture.journal)
                return r
            def unloaded(label):
                pids=children(); owned_children.update(pids)
                wait(label,lambda x:not x['loaded'])
                gone(pids)
                assert raw('omadocked-recovery','status')=='Target not found.'
                assert not locked(config) and not locked(fixture.journal)
                assert fixture.journal.read_bytes()==parked_bytes
            try:
                r=loaded('relocated-discovery-created')
                assert r['records']==[{'key':'owned-key','state':'parked','sequence':1}],r
                assert not call('state')['opened']
                call('save',52); wait('relocated-config-save',lambda x:x['size']==52 and x['ok'])
                pids=children()
                call('summon'); wait('summon',lambda x:x['opened'])
                call('hide'); wait('hide-keeps-loaded',lambda x:x['loaded'] and not x['opened'])
                assert children()==pids and recovery()['records']==r['records']
                call('disable'); unloaded('disabled-unloaded')
                call('reload'); wait('disabled-not-recreated',lambda x:not x['loaded'])
                call('enable'); assert loaded('reenabled-recovery')['records']==r['records']
                assert call('state')['size']==52
                call('unload'); unloaded('explicit-unload')
                call('reload'); assert loaded('reload-recovery')['records']==r['records']
                # Host IPC enqueues; completion must be correlated, not assumed.
                tx=recovery('recover','origin'); assert tx>0
                receipt=wait_recovery(recovery, tx)
                assert json.loads(fixture.state.read_text())['clients'][0]['workspace']['name']=='1'
                states.append({'step':'hosted-recovery-acknowledged','receipt':receipt})
                call('unload'); wait('unload-to-repark',lambda x:not x['loaded']); gone(list(owned_children))
                assert direct([park])[-1]['status']=='parked'
                parked_bytes=fixture.journal.read_bytes()
                call('reload'); loaded('repark-reload')
                call('disable'); unloaded('disable-before-remove')
                # Remove only owned package from discovery, retaining independent backup.
                backup=base/'retained recovery copy'
                shutil.copytree(plugin,backup)
                shutil.rmtree(plugin)
                call('enable'); wait('removed-not-discovered',lambda x:not x['loaded'])
                time.sleep(.15)
                assert raw('omadocked-recovery','status')=='Target not found.'
                helper=backup/'services/parking_store.py'
                rows=direct([{'id':10,'op':'status'},{'id':11,'op':'recover','mode':'origin'},{'id':12,'op':'status'}])
                assert rows[1]['keys']==['owned-key'] and rows[2]['status']=='restored' and rows[3]['records']==[],rows
                assert json.loads(fixture.state.read_text())['clients'][0]['workspace']['name']=='1'
                assert json.loads(fixture.state.read_text())['clients'][2]['workspace']['name']=='1'
                states.append({'step':'removed-backup-helper-recovery','responses':rows})
                # Copy back and rediscover; no parked records invented on reload.
                shutil.copytree(backup,plugin); call('scan')
                assert loaded('restored-package-discovery')['records']==[]
            finally:
                if proc.poll() is None: owned_children.update(children()); proc.terminate()
                try: proc.wait(timeout=5)
                except subprocess.TimeoutExpired: proc.kill(); proc.wait(timeout=5)
                gone(list(owned_children))
                assert not locked(config) and not locked(fixture.journal)
                (OUT/'states.json').write_text(json.dumps(states,indent=2)+'\n')
                (OUT/'commands.json').write_text(json.dumps(commands,indent=2)+'\n')
                (OUT/'provenance.json').write_text(json.dumps(provenance,indent=2)+'\n')
                fixture.tearDown(); fixture.doCleanups()
        warnings=[x for x in (OUT/'runtime.log').read_text().splitlines() if 'WARN' in x or 'ERROR' in x]
        assert warnings == ['  WARN: Unable to find hyprland socket. Cannot connect to hyprland.'],warnings
        (OUT/'result.json').write_text(json.dumps({'checkpoints':len(states),'reaped':True,'children_gone':True,'locks_released':True,'warnings':warnings},indent=2)+'\n')
        print('PASS',len(states),'relocation/recovery checkpoints')

if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-dir', type=Path, help='explicit receipt export directory (default: temporary)')
    args=parser.parse_args()
    db=sqlite3.connect('file:/home/jburmeister/.hermes/state.db?mode=ro',uri=True)
    row=db.execute('select id,model,model_config from sessions where id=?',(os.environ['HERMES_SESSION_ID'],)).fetchone()
    runtime={'session':row[0],'model':row[1],'config':json.loads(row[2])}
    assert runtime['model']=='gpt-6-astra' and runtime['config']['reasoning_config']['effort']=='medium'
    if args.evidence_dir is not None:
        args.evidence_dir.mkdir(parents=True,exist_ok=True)
        (args.evidence_dir/'runtime-attestation.json').write_text(json.dumps(runtime,indent=2)+'\n')
    run(args.evidence_dir)
