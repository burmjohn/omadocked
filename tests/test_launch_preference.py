"""Owned offscreen control → production bridges → sole durable writer."""
import json
import shutil
import unittest
import test_app_service as service


class LaunchPreferenceIntegration(unittest.TestCase):
    def setUp(self):
        self.fixture = service.AppServiceTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        f = self.fixture
        shutil.copytree(service.ROOT / 'ui', f.root / 'ui')
        dock = (service.ROOT / 'Dock.qml').read_text()
        members = '\n'.join(line for line in dock.splitlines() if 'readonly property bool launchBounce:' in line or 'function setLaunchBounce(' in line)
        surface = (service.ROOT / 'DockSurface.qml').read_text()
        bindings = '\n'.join(line for line in surface.splitlines() if line.strip().startswith(('launchBounce:', 'onLaunchBounceRequested:')))
        shell = service.SHELL.replace('import QtQuick', 'import QtQuick\nimport QtTest\nimport "ui"', 1)
        shell = shell.replace('    id: probe', '''
    id: probe
    property var root: probe
    property var controller: bridge
    QtObject { id:bridge; property var appService:apps
MEMBERS
    }
    Window { visible:true; width:1200; height:900
        TestCase { id:input; visible:true; when:false; name:"OwnedLaunchPreference" }
        DockView { id:view; width:1200; height:900; settingsManaged:true; reducedMotion:true; autoHide:false
BINDINGS
        }
    }
'''.replace('MEMBERS', members).replace('BINDINGS', bindings))
        shell = shell.replace('function configure(data: string): bool { return apps.configure(JSON.parse(data)); }', '''function configure(data: string): bool {
            view.settingsOpen = true;
            const button = input.findChild(view, "launch-bounce-setting");
            button.forceActiveFocus(); input.keyClick(Qt.Key_Space);
            return true;
        }
        function bounce(): bool { return view.launchBounce; }''')
        (f.root / 'shell.qml').write_text(shell)

    def test_control_durable_restart_and_rejected_write(self):
        f = self.fixture
        env = {'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software'}
        f.start(extra_env=env)
        self.assertTrue(f.call('bounce'))
        self.assertTrue(f.call('configure', 'toggle'))
        self.assertFalse(f.call('bounce'))
        saved = json.loads(f.config.read_text())
        self.assertFalse(saved['settings']['launchBounce'])
        f.stop()
        f.start(extra_env=env)
        self.assertFalse(f.call('bounce'))
        f.config.chmod(0o444)
        self.assertFalse(f.call('configure', 'toggle'))
        self.assertFalse(f.call('bounce'))
        self.assertEqual(json.loads(f.config.read_text()), saved)
