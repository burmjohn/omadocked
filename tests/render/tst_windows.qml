import QtQuick
import QtTest

TestCase {
    id: test
    name: "WindowChooserRender"
    when: windowShown
    width: 640; height: 740
    visible: true
    property var dock
    function initTestCase() {
        const component = Qt.createComponent("../../ui/DockView.qml");
        compare(component.status, Component.Ready, component.errorString());
        dock = component.createObject(test, {autoHide: false, reducedMotion: true, appsManaged: true,
            applications: [{id: "fixture-editor", name: "Fixture Editor", icon: "", running: true,
                            pinned: true, active: true, canPin: true, windowCount: 2}]});
        verify(dock !== null);
        dock.x = Qt.binding(() => (test.width - dock.width) / 2);
        dock.y = Qt.binding(() => test.height - dock.height);
    }
    function test_render() {
        dock.windowGroups = {"fixture-editor": [
            {key: "one", title: "Window management — design notes", active: true},
            {key: "two", title: "tests/qml/tst_window_view.qml", active: false}]};
        verify(dock.openWindowChooser("fixture-editor"));
        verify(waitForRendering(dock));
        grabImage(test).save("evidence/windows-chooser-offscreen.png");
        const many = [];
        for (let i = 0; i < 80; ++i)
            many.push({key: "w" + i, title: "Fixture " + i + " — long window titles stay inside their row ".repeat(8), active: i === 60});
        dock.releaseInteractions();
        dock.availableWidth = 320;
        dock.windowGroups = {"fixture-editor": many};
        verify(dock.openWindowChooser("fixture-editor"));
        verify(waitForRendering(dock));
        grabImage(test).save("evidence/windows-chooser-overflow-offscreen.png");
    }
    function cleanupTestCase() { dock.destroy(); }
}
