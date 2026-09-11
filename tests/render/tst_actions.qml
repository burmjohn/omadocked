import QtQuick
import QtTest

TestCase {
    id: test
    name: "DesktopActionsRender"
    when: windowShown
    width: 640; height: 520
    visible: true
    property var dock
    function initTestCase() {
        const component = Qt.createComponent("../../ui/DockView.qml");
        compare(component.status, Component.Ready, component.errorString());
        dock = component.createObject(test, {autoHide: false, reducedMotion: true, appsManaged: true,
            applications: [
                {id: "fixture-browser", name: "Browser", icon: "", running: true, pinned: true, active: true, canPin: true, windowCount: 3},
                {id: "fixture-editor", name: "Editor", icon: "", running: true, pinned: true, canPin: true, windowCount: 1},
                {id: "fixture-terminal", name: "Terminal", icon: "", running: true, pinned: true, canPin: true, windowCount: 120}]});
        verify(dock !== null);
        dock.x = Qt.binding(() => (test.width - dock.width) / 2);
        dock.y = Qt.binding(() => test.height - dock.height);
    }
    function test_render() {
        dock.desktopActions = {"fixture-browser": [
            {id: "new-window", name: "New Window"},
            {id: "new-private-window", name: "New Private Window"}]};
        verify(dock.openDesktopActions("fixture-browser"));
        verify(waitForRendering(dock));
        grabImage(test).save("evidence/actions-chooser-offscreen.png");
        dock.releaseInteractions();
        dock.availableWidth = 320;
        const many = [];
        for (let i = 0; i < 40; ++i) many.push({id: "action-" + i, name: "Fixture action " + i + " — bounded long label ".repeat(8)});
        dock.desktopActions = {"fixture-browser": many};
        verify(dock.openDesktopActions("fixture-browser"));
        verify(waitForRendering(dock));
        grabImage(test).save("evidence/actions-overflow-offscreen.png");
    }
    function cleanupTestCase() { dock.destroy(); }
}
