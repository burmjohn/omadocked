"""Owned native-shaped source QObjects -> real AppService -> two offscreen views.
No user toplevel, capture source, action, title diagnostic or compositor movement.
"""
import json
import shutil
import unittest
import test_app_service as service


class AdvancedTooltipNative(unittest.TestCase):
    def setUp(self):
        self.f = service.AppServiceTests()
        self.f.setUp()
        self.addCleanup(self.f.tearDown)
        f = self.f
        f.fake_native_source()
        source = f.root / 'services/LiveApps.qml'
        text = source.read_text()
        begin = text.index('    property QtObject first: QtObject {')
        end = text.index('    property var fixtureValues: [first]', begin)
        text = text[:begin] + '''    property QtObject first: null
    Component.onCompleted: first = Qt.createQmlObject('import QtQuick; QtObject { property string appId:"One"; property string title:""; property bool activated:true }', root)
''' + text[end:]
        text = text.replace('property var fixtureValues: [first]', 'property var fixtureValues: first ? [first] : []')
        text = text.replace('Hyprland.toplevels.values.some', '[].some')
        source.write_text(text)
        shutil.copytree(service.ROOT / 'ui', f.root / 'ui')
        shell = (f.root / 'shell.qml').read_text().replace('import QtQuick', 'import QtQuick\nimport QtTest\nimport "ui"', 1)
        shell = shell.replace('    id: probe', '''    id: probe
    property bool mappedA: true
    property bool mappedB: true
    property QtObject remembered: null
    QtObject { id:controller; property string previewLockState:"unknown"; property var previewCaptureOwner:null }
    Window { visible:true; width:1200; height:900
        TestCase { id:input; visible:true; when:false; name:"OwnedHoverSource" }
        DockView { id:a; autoHide:false; reducedMotion:true; motionMode:"off"; advancedTooltips:true
            tooltipDelay:0; appsManaged:true; applications:apps.items; windowGroups:apps.windowGroups }
        DockView { id:b; y:450; autoHide:false; reducedMotion:true; motionMode:"off"; advancedTooltips:true
            tooltipDelay:0; appsManaged:true; applications:apps.items; windowGroups:apps.windowGroups }
    }
    PreviewIntegration { view:a; controller:controller; mapped:probe.mappedA }
    PreviewIntegration { view:b; controller:controller; mapped:probe.mappedB }
''')
        shell = shell.replace('target: "app-test"', '''target: "app-test"
        function hover(): bool {
            for (const view of [a,b]) { view.shelfEntered(); view.pointerX=view.renderedSlots[1].center; view.refreshTooltip(); }
            input.wait(30); return true;
        }
        function privateChecks(): string {
            const la=input.findChild(a,"window-hover-loader"), lb=input.findChild(b,"window-hover-loader");
            const text=la.item ? input.findChild(la.item,"hover-title-0") : null;
            return JSON.stringify({a:!!la.item,b:!!lb.item,updated:!!text && text.text.indexOf("PRIVATE fixture title")>=0,
                count:la.item ? la.item.rows.length:0,remembered:probe.remembered!==null,keyboard:a.wantsKeyboard,
                popup:a.popupRect.width,capture:controller.previewCaptureOwner!==null});
        }
        function remember(): bool { probe.remembered=input.findChild(a,"window-hover-loader").item; return probe.remembered!==null; }
        function lock(value: string): bool { controller.previewLockState=value; return true; }
        function unmapA(): bool { probe.mappedA=false; a.resetSurface(); return true; }
        function destroySource(): bool { apps._live.item.first.destroy(); return true; }
''')
        (f.root / 'shell.qml').write_text(shell)

    def test_title_event_lock_unmap_and_actual_source_destruction(self):
        f = self.f
        f.start(test_mode='0', extra_env={'QT_QPA_PLATFORM':'offscreen', 'QT_QUICK_BACKEND':'software'})
        f.call('hover')
        checks = f.call('privateChecks')
        self.assertTrue(checks['a']); self.assertTrue(checks['b'])
        self.assertEqual(checks['count'], 1)
        self.assertFalse(checks['keyboard']); self.assertEqual(checks['popup'], 0)
        self.assertFalse(checks['capture'])
        key = f.call('windowState', 'one')[0]['key']
        self.assertTrue(f.call('nativeTitle'))
        self.assertTrue(f.call('privateChecks')['updated'])
        self.assertEqual(f.call('windowState', 'one')[0]['key'], key)
        self.assertTrue(f.call('remember'))
        f.call('lock', 'locked')
        checks = f.call('privateChecks')
        self.assertFalse(checks['a']); self.assertFalse(checks['b']); self.assertFalse(checks['remembered'])
        f.call('lock', 'unknown'); f.call('hover')
        self.assertTrue(f.call('privateChecks')['a'])
        f.call('unmapA')
        checks = f.call('privateChecks')
        self.assertFalse(checks['a']); self.assertTrue(checks['b'])
        f.call('destroySource')
        self.assertEqual(f.call('windowState', 'one'), [])
        checks = f.call('privateChecks')
        self.assertFalse(checks['a']); self.assertFalse(checks['b'])
        self.assertNotIn('PRIVATE fixture title', (f.root / 'runtime.log').read_text())
        self.assertFalse(f.config.exists())
        self.assertNotIn('PRIVATE fixture title', json.dumps(f.call('snapshot')))
