import QtQuick
import QtTest

TestCase {
    id: test
    name: "DailyUseRender"
    when: windowShown
    width: 900
    height: 760
    visible: true
    property var dock
    function initTestCase() {
        const component = Qt.createComponent("../../ui/DockView.qml");
        compare(component.status, Component.Ready, component.errorString());
        dock = component.createObject(test, {autoHide: false, reducedMotion: true, appsManaged: true, settingsManaged: true, persistenceEnabled: true,
                                             availableOutputs: ["Fixture-A", "Fixture-B", "Fixture-C"]});
        verify(dock !== null);
        dock.x = (test.width - dock.width) / 2;
        dock.y = test.height - dock.height;
        dock.desktopEntries = [{id: "fixture-browser", name: "Fixture Browser"}];
        dock.launcherRecords = [{id: "launcher:fixture", kind: "command", name: "Build project", icon: "utilities-terminal",
                                  program: "/usr/bin/make", args: ["test", "MESSAGE=spaces stay together"], workingDirectory: "/tmp",
                                  terminal: true, target: "", desktopId: "", action: "", enabled: true}];
        dock.applications = [{id: "fixture-browser", name: "Fixture Browser", icon: "", running: true, active: true,
                              pinned: true, canPin: true, windowCount: 2, canNewInstance: true},
                             {id: "launcher:fixture", name: "Build project", kind: "command", icon: "", canEdit: true,
                              canDuplicate: true, canRemove: true, pinned: true, running: false}];
        dock.settingsOpen = true;
        dock.x = (test.width - dock.width) / 2;
        dock.y = test.height - dock.height;
    }
    function test_render() {
        verify(waitForRendering(dock));
        grabImage(test).save("evidence/daily-settings-offscreen.png");
        verify(dock.openItemEditor("launcher:fixture"));
        verify(waitForRendering(dock));
        grabImage(test).save("evidence/daily-editor-offscreen.png");
    }
    function cleanupTestCase() { dock.destroy(); }
}
