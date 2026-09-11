import QtQuick
import QtTest
import "../../ui"
import "../../core/DockLogic.js" as Logic

TestCase {
    id: test
    name: "ScreenFocus"
    visible: true
    when: windowShown
    width: 1400; height: 800
    property var fixtures: [
        {id: "one", name: "One", running: true},
        {id: "two", name: "Two", running: true},
        {id: "three", name: "Three", running: true}
    ]
    DockView { id: first; applications: test.fixtures; availableOutputs: ["one", "two"]; autoHide: false }
    DockView { id: second; applications: test.fixtures; x: 700; availableOutputs: ["one", "two"]; autoHide: false }
    Connections {
        target: first
        function onWantsKeyboardChanged() {
            if (first.wantsKeyboard && typeof Logic.claimKeyboard === "function") Logic.claimKeyboard([first, second], first);
        }
    }
    Connections {
        target: second
        function onWantsKeyboardChanged() {
            if (second.wantsKeyboard && typeof Logic.claimKeyboard === "function") Logic.claimKeyboard([first, second], second);
        }
    }
    function test_onlyLatestSurfaceOwnsTransientKeyboard() {
        verify(typeof Logic.claimKeyboard === "function", "single keyboard owner policy exists");
        verify(first.visible && second.visible);
        wait(30); // Static children are already rendered at windowShown; allow layout polish.
        compare(first.wantsKeyboard, false); compare(second.wantsKeyboard, false);
        mouseClick(first, first.rowX + first.slotSize / 2, first.rowY + first.baseIconSize / 2, Qt.RightButton);
        compare(first.monitorPickerOpen, true);
        second.openContext(1);
        compare(first.monitorPickerOpen, false);
        compare(first.wantsKeyboard, false);
        compare(second.wantsKeyboard, true);
        first.enterKeyboard();
        compare(second.contextIndex, -1);
        compare(second.wantsKeyboard, false);
        compare(first.keyboardActive, true);
        verify(first.activeFocus, "new owner must retain actual Qt keyboard focus");
        first.releaseInteractions();
        const original = first.order.slice();
        const dragX = first.rowX + first.slotSize * 1.5;
        const dragY = first.rowY + first.baseIconSize / 2;
        mousePress(first, dragX, dragY);
        mouseMove(first, dragX + first.slotSize * 2, dragY);
        compare(first.dragActive, true);
        second.toggleMonitorPicker();
        compare(first.dragActive, false);
        compare(first.order, original);
        compare(first.wantsKeyboard, false);
        mouseRelease(first, dragX + first.slotSize * 2, dragY);
        second.resetSurface();
        compare(second.monitorPickerOpen, false);
        compare(second.wantsKeyboard, false);
        compare(first.selection, "");
    }
}
