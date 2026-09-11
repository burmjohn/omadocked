"""Owned offscreen control → production bridges → sole durable writer."""
import json
import shutil
import unittest
import test_app_service as service


class AdvancedTooltipPreference(unittest.TestCase):
    def setUp(self):
        self.fixture = service.AppServiceTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        f = self.fixture
        shutil.copytree(service.ROOT / 'ui', f.root / 'ui')
        dock = (service.ROOT / 'Dock.qml').read_text()
        members = '\n'.join(line for line in dock.splitlines() if 'readonly property bool advancedTooltips:' in line or 'function setAdvancedTooltips(' in line)
        surface = (service.ROOT / 'DockSurface.qml').read_text()
        bindings = '\n'.join(line for line in surface.splitlines() if line.strip().startswith(('advancedTooltips:', 'onAdvancedTooltipsRequested:')))
        shell = service.SHELL.replace('import QtQuick', 'import QtQuick\nimport QtTest\nimport "ui"', 1)
        shell = shell.replace('    id: probe', '''
    id: probe
    property var root: probe
    property var controller: bridge
    QtObject { id:bridge; property var appService:apps
MEMBERS
    }
    Window { visible:true; width:1200; height:900
        TestCase { id:input; visible:true; when:false; name:"OwnedAdvancedTooltipPreference" }
        DockView { id:view; width:1200; height:900; settingsManaged:true; reducedMotion:true; autoHide:false
BINDINGS
        }
    }
'''.replace('MEMBERS', members).replace('BINDINGS', bindings))
        shell = shell.replace('function configure(data: string): bool { return apps.configure(JSON.parse(data)); }', '''function configure(data: string): bool {
            view.settingsOpen = true;
            const button = input.findChild(view, "advanced-tooltips-setting");
            if (!button) return false;
            button.forceActiveFocus(); input.keyClick(Qt.Key_Space);
            return true;
        }
        function advanced(): bool { return view.advancedTooltips; }
        function checked(): bool { return input.findChild(view,"advanced-tooltips-setting").checked; }''')
        (f.root / 'shell.qml').write_text(shell)

    def test_control_durable_restart_and_rejected_write(self):
        f = self.fixture
        env = {'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software'}
        f.start(extra_env=env)
        self.assertFalse(f.call('advanced'))
        self.assertTrue(f.call('configure', 'toggle'))
        self.assertTrue(f.call('advanced'))
        saved = json.loads(f.config.read_text())
        self.assertTrue(saved['settings']['advancedTooltips'])
        f.stop()
        f.start(extra_env=env)
        self.assertTrue(f.call('advanced'))
        f.config.chmod(0o444)
        self.assertFalse(f.call('configure', 'toggle'))
        self.assertTrue(f.call('advanced'))
        self.assertEqual(json.loads(f.config.read_text()), saved)
        self.assertTrue(f.call('checked'))
        f.stop(); f.config.chmod(0o600); f.start(extra_env=env)
        self.assertTrue(f.call('advanced'))
        self.assertTrue(f.call('configure', 'toggle'))
        self.assertFalse(f.call('advanced'))
        self.assertFalse(f.call('checked'))
