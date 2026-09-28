"""Owned offscreen controls, exact production bridges and durable writer."""
import json
import shutil
import unittest
import test_app_service as service


class AppearancePreferences(unittest.TestCase):
    def test_host_adapter_uses_installed_token_names_reactively(self):
        f = self.fixture
        adapter = service.ROOT / 'host/Appearance.qml'
        self.assertTrue(adapter.exists(), 'host token adapter must exist')
        (f.root / 'host').mkdir()
        shutil.copy2(adapter, f.root / 'host/Appearance.qml')
        (f.root / 'Commons').mkdir()
        (f.root / 'Commons/qmldir').write_text('singleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\n')
        (f.root / 'Commons/Style.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property int cornerRadius: 13 }\n')
        (f.root / 'Commons/Color.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property QtObject bar: QtObject { property color background: "#80402010" } }\n')
        shell = service.SHELL.replace('import QtQuick', 'import QtQuick\nimport qs.Commons', 1)
        shell = shell.replace('    id: probe', '    id: probe\n    Loader { id: theme; source: "host/Appearance.qml" }')
        shell = shell.replace('function configure(data: string): bool { return apps.configure(JSON.parse(data)); }', '''function tokens(): string { return JSON.stringify({radius:theme.item.cornerRadius, alpha:theme.item.background.a}); }
        function themeChange(): bool { Style.cornerRadius = 0; Color.bar.background = Qt.rgba(.2,.3,.4,.25); return true; }''')
        (f.root / 'shell.qml').write_text(shell)
        f.start(extra_env={'QT_QPA_PLATFORM':'offscreen', 'QT_QUICK_BACKEND':'software'})
        self.assertEqual(f.call('tokens')['radius'], 13)
        self.assertAlmostEqual(f.call('tokens')['alpha'], 128 / 255, places=3)
        self.assertTrue(f.call('themeChange'))
        self.assertEqual(f.call('tokens')['radius'], 0)
        self.assertAlmostEqual(f.call('tokens')['alpha'], .25, places=3)

    def setUp(self):
        self.fixture = service.AppServiceTests()
        self.fixture.setUp()
        self.addCleanup(self.fixture.tearDown)
        f = self.fixture
        shutil.copytree(service.ROOT / 'ui', f.root / 'ui')
        dock = (service.ROOT / 'Dock.qml').read_text()
        members = '\n'.join(line for line in dock.splitlines() if 'readonly property var appearanceSettings:' in line or 'function configureAppearance(' in line)
        surface = (service.ROOT / 'DockSurface.qml').read_text()
        bindings = '\n'.join(line for line in surface.splitlines() if line.strip().startswith(('appearanceSettings:', 'onAppearanceSettingsRequested:')))
        shell = service.SHELL.replace('import QtQuick', 'import QtQuick\nimport QtTest\nimport "ui"', 1)
        shell = shell.replace('    id: probe', '''
    id: probe
    property var root: probe
    property var controller: bridge
    QtObject { id:bridge; property var appService:apps
MEMBERS
    }
    Window { visible:true; width:1200; height:900
        TestCase { id:input; visible:true; when:false; name:"OwnedAppearance" }
        DockView { id:view; width:1200; height:900; settingsManaged:true; reducedMotion:true; autoHide:false
BINDINGS
        }
    }
'''.replace('MEMBERS', members).replace('BINDINGS', bindings))
        shell = shell.replace('function configure(data: string): bool { return apps.configure(JSON.parse(data)); }', '''function configure(data: string): bool {
            view.settingsOpen = true; input.wait(30);
            const content = input.findChild(view, "settings-popup").contentItem;
            if (data.startsWith("{")) {
                const patch = JSON.parse(data), key = Object.keys(patch)[0];
                if (!view.badgeSettingsOpen) {
                    const expand = input.findChild(content, "badge-settings");
                    expand.forceActiveFocus(); input.keyClick(Qt.Key_Space);
                }
                if (key === "badgePosition") {
                    const choice = input.findChild(content, "badge-" + patch[key]);
                    if (!choice) return false;
                    choice.forceActiveFocus(); input.keyClick(Qt.Key_Space);
                    return true;
                }
                const name = key === "badgeBackgroundColor" ? "badge-background-color"
                    : key === "badgeTextColor" ? "badge-text-color" : "";
                const field = name ? input.findChild(content, name) : null;
                if (!field) return false;
                field.forceActiveFocus(); field.text = patch[key];
                const valid = field.acceptableInput;
                input.keyClick(Qt.Key_Return);
                return valid;
            }
            const button = input.findChild(content, data);
            if (!button) return false;
            button.forceActiveFocus();
            if (data === "background-color") { input.keyClick(Qt.Key_Space); input.keyClick(Qt.Key_Down); input.keyClick(Qt.Key_Return); }
            else input.keyClick(Qt.Key_Space);
            return true;
        }
        function appearance(): string { return JSON.stringify(view.appearanceSettings || {}); }
        function controlState(): string {
            const content = input.findChild(view, "settings-popup").contentItem;
            return JSON.stringify({color:input.findChild(content,"background-color").currentIndex,
                opacity:input.findChild(content,"theme-opacity").chosen,
                square:input.findChild(content,"shape-square").chosen,
                relaxed:input.findChild(content,"spacing-8").chosen});
        }''')
        (f.root / 'shell.qml').write_text(shell)

    def test_background_control_restart_and_rejection(self):
        f = self.fixture
        env = {'QT_QPA_PLATFORM':'offscreen', 'QT_QUICK_BACKEND':'software'}
        f.start(extra_env=env)
        for expected in ['none', '#000000', '#181825']:
            self.assertTrue(f.call('configure', 'background-color'))
            self.assertEqual(f.call('appearance')['backgroundColor'], expected)
        self.assertTrue(f.call('configure', 'theme-opacity'))
        self.assertTrue(f.call('appearance')['themeOpacity'])
        saved = json.loads(f.config.read_text())
        self.assertEqual(saved['settings']['transparency'], 0)
        f.stop(); f.start(extra_env=env)
        self.assertEqual(f.call('appearance')['backgroundColor'], '#181825')
        self.assertTrue(f.call('appearance')['themeOpacity'])
        f.config.chmod(0o444)
        self.assertFalse(f.call('configure', 'background-color'))
        self.assertEqual(f.call('appearance')['backgroundColor'], '#181825')
        # The first rejection leaves the writer fail-closed; this second UI
        # activation is synchronously refused, not a new durable transaction.
        f.call('configure', 'theme-opacity')
        self.assertTrue(f.call('snapshot')['error'])
        self.assertTrue(f.call('appearance')['themeOpacity'])
        self.assertEqual(json.loads(f.config.read_text()), saved)
        self.assertEqual(f.call('controlState')['color'], 3)
        self.assertTrue(f.call('controlState')['opacity'])

    def test_spacing_control_restart_and_rejection(self):
        f = self.fixture
        env = {'QT_QPA_PLATFORM':'offscreen', 'QT_QUICK_BACKEND':'software'}
        f.start(extra_env=env)
        for value in [2, 4, 8]:
            self.assertTrue(f.call('configure', 'spacing-' + str(value)))
            self.assertEqual(f.call('appearance')['itemSpacing'], value)
            self.assertEqual(json.loads(f.config.read_text())['settings']['itemSpacing'], value)
        saved = json.loads(f.config.read_text())
        f.stop(); f.start(extra_env=env)
        self.assertEqual(f.call('appearance')['itemSpacing'], 8)
        f.config.chmod(0o444)
        self.assertFalse(f.call('configure', 'spacing-2'))
        self.assertEqual(f.call('appearance')['itemSpacing'], 8)
        self.assertEqual(json.loads(f.config.read_text()), saved)
        self.assertTrue(f.call('controlState')['relaxed'])

    def test_badge_controls_persist_restart_and_reject_invalid_values(self):
        f = self.fixture
        env = {'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software',
               'XDG_RUNTIME_DIR': str(f.root)}
        f.start(test_mode='0', extra_env=env)
        for patch in ({'badgePosition': 'top-left'}, {'badgeBackgroundColor': '#112233'},
                      {'badgeTextColor': '#eeaa44'}):
            self.assertTrue(f.call('configure', json.dumps(patch)))
        self.assertTrue(f.config.exists(), f.call('snapshot'))
        saved = json.loads(f.config.read_text())
        self.assertEqual(saved['settings']['badgePosition'], 'top-left')
        self.assertEqual(saved['settings']['badgeBackgroundColor'], '#112233')
        self.assertEqual(saved['settings']['badgeTextColor'], '#eeaa44')
        f.stop(); f.start(test_mode='0', extra_env=env)
        self.assertEqual(f.call('appearance')['badgePosition'], 'top-left')
        self.assertEqual(f.call('appearance')['badgeBackgroundColor'], '#112233')
        self.assertEqual(f.call('appearance')['badgeTextColor'], '#eeaa44')
        self.assertFalse(f.call('configure', json.dumps({'badgeTextColor': 'red'})))
        self.assertEqual(json.loads(f.config.read_text()), saved)
        f.config.chmod(0o444)
        self.assertFalse(f.call('configure', json.dumps({'badgePosition': 'bottom-left'})))
        self.assertEqual(f.call('appearance')['badgePosition'], 'top-left')
        self.assertEqual(json.loads(f.config.read_text()), saved)

    def test_shape_control_restart_and_rejection(self):
        f = self.fixture
        env = {'QT_QPA_PLATFORM': 'offscreen', 'QT_QUICK_BACKEND': 'software'}
        f.start(extra_env=env)
        for shape in ['round', 'theme', 'rounded']:
            self.assertTrue(f.call('configure', 'shape-' + shape))
            self.assertEqual(f.call('appearance')['shape'], shape)
        self.assertTrue(f.call('configure', 'shape-square'), 'production shape control must exist and commit')
        self.assertEqual(f.call('appearance')['shape'], 'square')
        saved = json.loads(f.config.read_text())
        self.assertEqual(saved['settings']['shape'], 'square')
        self.assertEqual(saved['settings']['iconSize'], 44)
        self.assertEqual(saved['settings']['transparency'], 0)
        f.stop(); f.start(extra_env=env)
        self.assertEqual(f.call('appearance')['shape'], 'square')
        f.config.chmod(0o444)
        self.assertFalse(f.call('configure', 'shape-round'))
        self.assertEqual(f.call('appearance')['shape'], 'square')
        self.assertEqual(json.loads(f.config.read_text()), saved)
        self.assertTrue(f.call('controlState')['square'])
