import QtQuick
import QtTest

TestCase {
    id: test
    name: "AutoHidePointer"
    when: windowShown
    visible: true
    width: 1000
    height: 800
    property var dock
    function init() {
        const component = Qt.createComponent("../../ui/DockView.qml");
        compare(component.status, Component.Ready, component.errorString());
        dock = component.createObject(test, {reducedMotion: true, applications: [
            {id: "one", name: "One", running: true},
            {id: "two", name: "Two", running: true},
            {id: "three", name: "Three", running: true}
        ]});
        verify(waitForRendering(dock));
        mouseMove(test, 900, 700);
    }
    function cleanup() { dock.destroy(); }
    function test_leavingEdgeWithoutEnteringIconsAlsoHides() {
        dock.resetSurface();
        mouseMove(dock, dock.triggerRect.x + dock.triggerRect.width / 2, dock.height - 3);
        tryCompare(dock, "visibilityState", "shown", 500);
        wait(dock.hideDelay + 50);
        compare(dock.visibilityState, "shown", "edge dwell keeps the revealed shelf available");
        mouseMove(test, 900, 700);
        tryCompare(dock, "visibilityState", "hidden", 600);
    }
    function test_mouseAwayHidesWithoutOpeningSettings() {
        dock.resetSurface();
        mouseMove(dock, dock.triggerRect.x + dock.triggerRect.width / 2, dock.height - 3);
        tryCompare(dock, "visibilityState", "shown", 500);
        mouseMove(dock, dock.renderedSlots[3].center, dock.rowY + 20);
        wait(50);
        verify(dock.pointerInside, "actual icon-area hover reaches the visibility owner");
        mouseMove(test, 900, 700);
        tryCompare(dock, "pointerInside", false, 200);
        tryCompare(dock, "visibilityState", "hidden", 600);
        compare(dock.settingsOpen, false);
    }
    function test_settingsOpenKeepsShelfShownWithoutHideBounce() {
        dock.resetSurface();
        dock.autoHide = true;
        dock.shelfEntered();
        tryCompare(dock, "visibilityState", "shown", 500);
        compare(dock.shelfProgress, 1);
        const stageHeight = dock.height;
        dock.settingsOpen = true;
        verify(dock.interactionLocked);
        compare(dock.height, stageHeight, "opening Settings must not resize the layer");
        dock.shelfExited();
        wait(dock.hideDelay + 50);
        compare(dock.visibilityState, "interacting", "settings must not auto-hide the shelf");
        verify(dock.shelfVisible);
        compare(dock.shelfProgress, 1);
        dock.settingsOpen = false;
        tryCompare(dock, "visibilityState", "hiding", 200);
    }
}
