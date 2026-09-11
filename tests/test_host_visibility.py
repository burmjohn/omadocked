"""Offscreen Dock lifecycle; zero screen delegates and owned controllers only."""
import json
import shutil
import test_app_service as base


class HostVisibilityTests(base.AppServiceTests):
    def prepare(self, product_policy=True):
        for name in ('Dock.qml', 'DockSurface.qml'):
            shutil.copy2(base.ROOT/name, self.root/name)
        shutil.copytree(base.ROOT/'ui', self.root/'ui')
        # PanelWindow has no offscreen backend. No native surface type is loaded;
        # the zero-length Variants model must never instantiate this inert double.
        (self.root/'DockSurface.qml').write_text('import QtQuick\nItem { property var outputScreen; property var controller }\n')
        dock=self.root/'Dock.qml'
        source=dock.read_text().replace('Quickshell.screens','[]')
        if product_policy:
            # AppService remains TEST_MODE=1. Only the root visibility policy sees
            # product mode; literal zero delegates prevents even transient mapping.
            source=source.replace('readonly property bool testMode: appService.testMode',
                                  'readonly property bool testMode: false')
        dock.write_text(source)
        (self.root/'shell.qml').write_text('''import QtQuick
import Quickshell
import Quickshell.Io
ShellRoot {
    QtObject { id: host; function serviceFor(id) { return null; } }
    QtObject { id: registry; function resolveEnabledId(id) { return id; } }
    Loader { id: overlay; source: "Dock.qml" }
    IpcHandler {
        target: "app-test"
        function snapshot(): string { return JSON.stringify({ready:overlay.item && overlay.item.ready,
            opened:overlay.item ? overlay.item.opened : false,
            visible:overlay.item ? JSON.parse(overlay.item.snapshot()).visible : false,
            outputs:overlay.item ? overlay.item.availableOutputs : [],
            appearance:overlay.item ? overlay.item.appearanceSettings : {},
            mode:overlay.item ? overlay.item.monitorMode : "",
            selected:overlay.item ? overlay.item.selectedOutputs : []}); }
        function inject(part: string): bool {
            if (part === "shell") overlay.item.shell=host;
            if (part === "manifest") overlay.item.manifest=({id:"burmjohn.omadocked",keepLoaded:true,kinds:["overlay"],entryPoints:{overlay:"Dock.qml"}});
            if (part === "registry") overlay.item.pluginRegistry=registry;
            return true;
        }
        function closeFixture(): bool { overlay.item.close(); return true; }
        function openFixture(): bool { overlay.item.open(""); return true; }
        function reloadFixture(): bool { overlay.active=false; overlay.active=true; return true; }
    }
}''')

    def test_complete_late_host_injection_shows_without_changing_monitor_policy(self):
        self.prepare()
        self.config.parent.mkdir(parents=True)
        saved=json.dumps({'version':2,'pins':[],'launchers':[],'overrides':{},
            'settings':{'monitorMode':'selected','selectedOutputs':['owned-saved-output'],'iconSize':52,'itemSpacing':8}})
        self.config.write_text(saved)
        self.start(extra_env={'OMADOCKED_VISIBLE':'0','OMADOCKED_SCREENS':'','OMADOCKED_SCREEN':''})
        initial=self.call('snapshot'); self.assertFalse(initial['opened'])
        for part in ('shell','manifest'):
            self.call('inject',part); self.assertFalse(self.call('snapshot')['opened'])
        self.call('inject','registry')
        shown=self.call('snapshot'); self.assertTrue(shown['opened'])
        self.assertFalse(shown['visible']); self.assertEqual(shown['outputs'],[])
        self.assertEqual((shown['mode'],shown['selected']),(initial['mode'],initial['selected']))
        self.call('closeFixture'); self.assertFalse(self.call('snapshot')['opened'])
        self.call('openFixture'); self.assertTrue(self.call('snapshot')['opened'])
        self.assertEqual(shown['mode'],'selected')
        self.assertEqual(shown['selected'],['owned-saved-output'])
        self.assertEqual(shown['appearance']['iconSize'],52)
        self.assertEqual(shown['appearance']['itemSpacing'],8)
        self.assertEqual(self.config.read_text(),saved)
        self.stop()
        self.start(extra_env={'OMADOCKED_VISIBLE':'0','OMADOCKED_SCREENS':'','OMADOCKED_SCREEN':''})
        for part in ('manifest','registry','shell'): self.call('inject',part)
        self.assertTrue(self.call('snapshot')['opened'])
        self.assertEqual(self.call('snapshot')['appearance'],shown['appearance'])
        self.assertEqual(self.config.read_text(),saved)

    def test_testmode_never_auto_shows_and_standalone_stays_explicit(self):
        self.prepare(product_policy=False)
        self.start(extra_env={'OMADOCKED_VISIBLE':'0'})
        for part in ('shell','manifest','registry'): self.call('inject',part)
        self.assertFalse(self.call('snapshot')['opened'])
        self.call('openFixture'); self.assertTrue(self.call('snapshot')['opened'])
        self.assertFalse(self.call('snapshot')['visible'])


for _name in dir(base.AppServiceTests):
    if _name.startswith('test_'):
        setattr(HostVisibilityTests,_name,None)
