import QtQuick
import QtTest

TestCase {
    id: test
    name: "WindowView"
    when: windowShown
    visible: true
    width: 1000; height: 800
    property var dock
    SignalSpy { id: activateSpy; signalName: "activateWindowRequested" }
    SignalSpy { id: closeSpy; signalName: "closeWindowRequested" }
    SignalSpy { id: cycleSpy; signalName: "cycleWindowsRequested" }
    function windows() {
        return [{key: "one", title: "Private fixture one", active: false},
                {key: "two", title: "Private fixture two", active: true}];
    }
    function init() {
        const component = Qt.createComponent("../../ui/DockView.qml");
        compare(component.status, Component.Ready, component.errorString());
        dock = component.createObject(test, {autoHide: false, reducedMotion: true,
            applications: [{id: "alpha", name: "Alpha", running: true, canPin: true}]});
        verify(dock !== null);
        mouseMove(test, 950, 750);
    }
    function cleanup() {
        activateSpy.target = null; closeSpy.target = null; cycleSpy.target = null;
        dock.destroy(); dock = null;
    }
    function test_removedAndReorderedPointerGestureCannotRetarget() {
        activateSpy.target = dock; activateSpy.clear(); closeSpy.target = dock; closeSpy.clear();
        dock.windowGroups = {alpha: windows()};
        verify(dock.openWindowChooser("alpha"));
        let button = findChild(dock, "window-close-one");
        let point = button.mapToItem(dock, button.width / 2, button.height / 2);
        mousePress(dock, point.x, point.y);
        verify(button.pressed, "Owned pointer press actually reached row control");
        dock.windowGroups = {alpha: [windows()[1]]};
        mouseRelease(dock, point.x, point.y);
        compare(closeSpy.count, 0, "removed pressed row must not close replacement");
        dock.windowGroups = {alpha: windows()};
        wait(0);
        button = findChild(dock, "window-activate-one");
        point = button.mapToItem(dock, button.width / 2, button.height / 2);
        mousePress(dock, point.x, point.y);
        verify(button.pressed, "Owned pointer press actually reached row control");
        dock.windowGroups = {alpha: windows().reverse()};
        mouseRelease(dock, point.x, point.y);
        compare(activateSpy.count, 0, "reordered gesture is canceled, never neighbor activation");
        dock.releaseInteractions();
        keyClick(Qt.Key_Return); keyClick(Qt.Key_Delete);
        compare(activateSpy.count, 0); compare(closeSpy.count, 0);
    }
    function test_inPlaceReorderDuringPressCancelsRelease_data() {
        return [{tag:"activate",action:"activate"},{tag:"close",action:"close"}];
    }
    function test_inPlaceReorderDuringPressCancelsRelease(data) {
        activateSpy.target = dock; activateSpy.clear(); closeSpy.target = dock; closeSpy.clear();
        dock.windowGroups = {alpha: windows()};
        verify(dock.openWindowChooser("alpha"));
        const chooser = dock.activeWindowChooser;
        const button = findChild(dock, "window-" + data.action + "-one");
        const point = button.mapToItem(dock, button.width / 2, button.height / 2);
        mousePress(dock, point.x, point.y);
        verify(button.pressed);
        // Simulate a retained delegate receiving the reordered model role.
        chooser.windows.reverse();
        button.parent.modelData = chooser.windows[0];
        verify(button.pressed);
        mouseRelease(dock, point.x, point.y);
        compare(activateSpy.count, 0);
        compare(closeSpy.count, 0);
        mouseClick(dock, point.x, point.y);
        compare(data.action === "activate" ? activateSpy.count : closeSpy.count, 1);
    }
    function test_accessibleActionsRevalidateWithoutPointerPress() {
        activateSpy.target = dock; activateSpy.clear(); closeSpy.target = dock; closeSpy.clear();
        dock.windowGroups = {alpha: windows()};
        verify(dock.openWindowChooser("alpha"));
        const close = findChild(dock, "window-close-one");
        close.Accessible.pressAction();
        compare(closeSpy.count, 1); compare(closeSpy.signalArguments[0][1], "one");
        close.parent.modelData = {key:"stale", title:"Owned stale role"};
        close.Accessible.pressAction();
        compare(closeSpy.count, 1);
        const activate = findChild(dock, "window-activate-two");
        activate.Accessible.pressAction();
        compare(activateSpy.count, 1); compare(activateSpy.signalArguments[0][1], "two");
    }
    function test_boundedScrollingBackAndExplicitCycle() {
        const many = [];
        for (let i = 0; i < 80; ++i) many.push({key: "w" + i, title: "Long private fixture ".repeat(30), active: false});
        dock.availableWidth = 320;
        dock.windowGroups = {alpha: many};
        cycleSpy.target = dock; cycleSpy.clear();
        verify(dock.openWindowChooser("alpha"));
        const back = findChild(dock, "windows-back");
        verify(back !== null, "chooser has explicit Back navigation");
        const rect = dock.popupRect;
        verify(dock.height <= dock.settingsStageHeight); verify(rect.x >= 0 && rect.x + rect.width <= dock.width);
        const list = findChild(dock, "window-list");
        verify(list.clip); verify(list.contentHeight > list.height);
        for (let j = 0; j < 60; ++j) keyClick(Qt.Key_Down);
        compare(dock.windowSelectionKey, "w60");
        verify(list.contentY > 0);
        const row = findChild(dock, "window-activate-w60");
        verify(row !== null); verify(row.chosen);
        compare(row.contentItem.elide, Text.ElideRight);
        const point = row.mapToItem(list, 0, 0);
        verify(point.y >= 0 && point.y + row.height <= list.height);
        dock.windowGroups = {alpha: many.slice(0, 65)};
        compare(dock.popupRect, rect, "membership churn does not resize native popup");
        mouseClick(findChild(dock, "windows-previous"));
        mouseClick(findChild(dock, "windows-next"));
        compare(cycleSpy.count, 2);
        compare(cycleSpy.signalArguments[0][0], "alpha"); compare(cycleSpy.signalArguments[0][1], -1);
        compare(cycleSpy.signalArguments[1][0], "alpha"); compare(cycleSpy.signalArguments[1][1], 1);
        mouseClick(back);
        compare(dock.windowChooserOpen, false); compare(dock.contextIndex, 2);
        verify(dock.openWindowChooser("alpha"));
        keyClick(Qt.Key_Backspace);
        compare(dock.windowChooserOpen, false); compare(dock.contextIndex, 2);
        verify(dock.openWindowChooser("alpha"));
        keyClick(Qt.Key_Tab); keyClick(Qt.Key_Tab); keyClick(Qt.Key_Return);
        compare(dock.windowChooserOpen, false, "Tab reaches Back after explicit Close");
    }
    function test_smallChooserFitsItsRowsAndStaysNearShelf() {
        dock.windowGroups = {alpha: windows()};
        verify(dock.openWindowChooser("alpha"));
        const rect = dock.popupRect;
        verify(rect.height <= 368, "Two windows fit with one bounded 168px preview region");
        verify(rect.y >= 0 && rect.y + rect.height <= dock.shelfRect.y,
               "Window chooser sits above the shelf input region");
        dock.windowGroups = {alpha: [windows()[1]]};
        compare(dock.popupRect, rect, "An open chooser does not jump when a window disappears");
        const many = [];
        for (let i = 0; i < 40; ++i) many.push({key: "w" + i, title: "Fixture", active: false});
        dock.windowGroups = {alpha: many};
        compare(dock.popupRect, rect, "Growth uses scrolling, not moving hit targets");
        verify(findChild(dock, "window-list").contentHeight > findChild(dock, "window-list").height);
    }
    function test_emptyOrDestroyedAppDismissesWithoutPrivateResidue() {
        dock.windowGroups = {alpha: windows()};
        verify(dock.openWindowChooser("alpha"));
        dock.windowGroups = {alpha: []};
        compare(dock.contextIndex, -1);
        verify(!dock.windowChooserOpen);
        dock.windowGroups = {alpha: windows()};
        tryVerify(function() { return findChild(dock, "window-list") === null; });
        verify(dock.openWindowChooser("alpha"));
        dock.applications = [];
        compare(dock.contextIndex, -1);
        verify(!dock.windowChooserOpen);
        compare(dock.windowSelectionKey, "");
        dock.applications = [{id: "alpha", name: "Alpha", running: true}];
        dock.openContext(2);
        dock.windowGroups = {alpha: [{key: "secret", title: "Hidden private update", active: false}]};
        tryVerify(function() { return findChild(dock, "window-list") === null; });
        verify(dock.actionLabel.indexOf("Hidden private") < 0);
        verify(dock.appStatus.indexOf("Hidden private") < 0);
        verify(dock.openWindowChooser("alpha"));
        dock.applications = [{id: "alpha", name: "Alpha", running: false}];
        compare(dock.contextIndex, -1);
    }
    function test_keyboardSelectionSurvivesChurnWithoutHiddenActions() {
        dock.windowGroups = {alpha: windows()};
        activateSpy.target = dock; activateSpy.clear(); closeSpy.target = dock; closeSpy.clear();
        verify(dock.openWindowChooser("alpha"));
        compare(dock.windowSelectionKey, "two", "active window starts selected");
        keyClick(Qt.Key_Up); compare(dock.windowSelectionKey, "one");
        dock.windowGroups = {alpha: [{key: "two", title: "Changed private", active: true}, {key: "one", title: "Renamed", active: false}]};
        compare(dock.windowSelectionKey, "one");
        keyClick(Qt.Key_Delete); compare(closeSpy.count, 0);
        keyClick(Qt.Key_Menu); verify(dock.windowChooserOpen, "menu key cannot reach hidden context controls");
        keyClick(Qt.Key_Tab); keyClick(Qt.Key_Return);
        compare(closeSpy.count, 1); compare(closeSpy.signalArguments[0][1], "one");
        compare(activateSpy.count, 0);
        dock.windowGroups = {alpha: [{key: "two", title: "Remaining", active: true}]};
        compare(dock.windowSelectionKey, "", "removal clears selection, never silently retargets Close");
        keyClick(Qt.Key_Return); compare(closeSpy.count, 1); compare(activateSpy.count, 0);
        keyClick(Qt.Key_Down); compare(dock.windowSelectionKey, "two");
        keyClick(Qt.Key_Return);
        compare(activateSpy.count, 1); compare(activateSpy.signalArguments[0][1], "two");
        compare(dock.contextIndex, -1);
    }
    function test_exactRowActionsAndPrivatePlainText() {
        dock.windowGroups = {alpha: [{key: "one", title: "<b>Private fixture</b>", active: true},
                                    {key: "two", title: "", active: false}]};
        activateSpy.target = dock; activateSpy.clear(); closeSpy.target = dock; closeSpy.clear();
        verify(dock.openWindowChooser("alpha"));
        const row = findChild(dock, "window-activate-one");
        verify(row !== null, "explicit chooser has individually targeted rows");
        compare(row.contentItem.textFormat, Text.PlainText);
        verify(row.contentItem.text.indexOf("<b>Private fixture</b>") >= 0);
        verify(findChild(dock, "window-activate-two").contentItem.text.indexOf("Untitled window") >= 0);
        verify(findChild(dock, "window-active-one").visible);
        verify(row.Accessible.name.indexOf("Private fixture") >= 0);
        const close = findChild(dock, "window-close-one");
        verify(close.Accessible.name.indexOf("Close window") >= 0);
        mouseClick(close);
        compare(closeSpy.count, 1); compare(closeSpy.signalArguments[0][0], "alpha"); compare(closeSpy.signalArguments[0][1], "one");
        verify(dock.windowChooserOpen, "Presentation emits a request; the root controller owns native focus release");
        verify(findChild(dock, "window-activate-one") !== null);
        compare(activateSpy.count, 0);
        mouseClick(row);
        compare(activateSpy.count, 1); compare(activateSpy.signalArguments[0][0], "alpha"); compare(activateSpy.signalArguments[0][1], "one");
        compare(dock.contextIndex, -1);
        verify(dock.actionLabel.indexOf("Private fixture") < 0);
        verify(findChild(dock, "window-activate-one") === null, "hidden chooser releases private delegates");
    }
    function test_explicitChooserPreservesContextLifetime() {
        compare(typeof dock.openWindowChooser, "function");
        dock.windowGroups = {alpha: windows()};
        compare(dock.windowChooserOpen, false);
        compare(dock.windowSelectionKey, "");
        dock.openContext(2);
        const action = findChild(dock, "context-windows");
        verify(action !== null && action.visible);
        compare(action.text, "Windows…");
        mouseClick(action);
        verify(dock.windowChooserOpen);
        compare(dock.contextIndex, 2);
        verify(dock.wantsKeyboard);
        compare(dock.order[0], "omarchy-menu");
        keyClick(Qt.Key_Escape);
        compare(dock.windowChooserOpen, false);
        compare(dock.contextIndex, -1);
        compare(dock.windowSelectionKey, "");
        compare(dock.openWindowChooser("missing"), false);
        dock.applications = [{id: "launcher:x", name: "Custom", running: true, kind: "application", canEdit: true}];
        dock.windowGroups = {"launcher:x": windows()};
        compare(dock.openWindowChooser("launcher:x"), false);
    }
}
