"""Owned offscreen Settings input, production bridges, durable commit/restart/failure."""
import json
import shutil
import unittest
import test_app_service as service

ROOT=service.ROOT

class DelayPreferenceIntegration(unittest.TestCase):
    def setUp(self):
        self.fixture=service.AppServiceTests(); self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        root=self.fixture.root
        shutil.copytree(ROOT/'ui',root/'ui')
        dock=(ROOT/'Dock.qml').read_text()
        self.assertIn('function configureDelays(',dock,'durable delay bridge missing')
        start=dock.index('    function configureDelays(')
        method=dock[start:dock.index('\n',start)]
        properties='\n'.join(l for l in dock.splitlines() if 'readonly property int tooltipDelay:' in l or 'readonly property int revealDelay:' in l)
        surface=(ROOT/'DockSurface.qml').read_text()
        bindings='\n'.join(l for l in surface.splitlines() if l.strip().startswith(('tooltipDelay:', 'revealDelay:', 'onDelaySettingsRequested:')))
        extra='''
 property var root: probe
 property var controller: bridge
 QtObject { id:bridge; property var appService:apps
PROPERTIES
METHOD
 }
 Window { visible:true; width:1200; height:900
  TestCase { id:input; when:false; visible:true; name:"OwnedDelayInput" }
  DockView { id:view; settingsManaged:true; reducedMotion:true; autoHide:false
BINDINGS
  }
 }
'''.replace('PROPERTIES',properties).replace('METHOD',method).replace('BINDINGS',bindings)
        shell=service.SHELL.replace('import QtQuick','import QtQuick\nimport QtTest\nimport "ui"',1)
        shell=shell.replace('    id: probe','    id: probe'+extra,1)
        shell=shell.replace('        function configure(data: string): bool { return apps.configure(JSON.parse(data)); }','''
        function configure(data: string): bool {
            view.settingsOpen=true;
            const slider=input.findChild(view,data);
            if (!slider) return false;
            slider.forceActiveFocus(); input.keyClick(Qt.Key_Right);
            return true;
        }
        function delays(): string { return JSON.stringify({tooltip:view.tooltipDelay,reveal:view.revealDelay}); }
''')
        (root/'shell.qml').write_text(shell)

    def start(self):
        return self.fixture.start(extra_env={'QT_QPA_PLATFORM':'offscreen','QT_QUICK_BACKEND':'software'})

    def test_input_commit_restart_reject_and_preserve(self):
        f=self.fixture
        self.start()
        self.assertEqual(f.call('delays'),{'tooltip':450,'reveal':160})
        self.assertTrue(f.call('configure','tooltip-delay-slider'))
        self.assertTrue(f.call('configure','reveal-delay-slider'))
        self.assertEqual(f.call('delays'),{'tooltip':500,'reveal':170})
        saved=json.loads(f.config.read_text())
        self.assertEqual(saved['settings']['tooltipDelay'],500)
        self.assertEqual(saved['settings']['revealDelay'],170)
        self.assertEqual(saved['settings']['zoomSize'],145)
        self.assertTrue(saved['settings']['showAppNames'])
        f.stop(); self.start()
        self.assertEqual(f.call('delays'),{'tooltip':500,'reveal':170})
        f.config.chmod(0o444)
        self.assertFalse(f.call('configure','tooltip-delay-slider'))
        self.assertEqual(f.call('delays'),{'tooltip':500,'reveal':170})
        self.assertEqual(json.loads(f.config.read_text()),saved)
