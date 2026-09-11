import QtQuick
import QtTest

TestCase {
    id: test
    name: "ActionView"
    when: windowShown
    visible: true
    width: 1000; height: 800
    property var dock
    SignalSpy { id: actionSpy; signalName: "desktopActionRequested" }
    function app(count) { return {id: "alpha", name: "Alpha", running: true, canPin: true, windowCount: count}; }
    function init() {
        const component = Qt.createComponent("../../ui/DockView.qml");
        compare(component.status, Component.Ready, component.errorString());
        dock = component.createObject(test, {autoHide: false, reducedMotion: true, applications: [app(2)]});
        verify(dock !== null);
        mouseMove(test, 950, 750);
    }
    function cleanup() { actionSpy.target = null; dock.destroy(); dock = null; }
    function actions() { return [{id: "exact-One", name: "<b>Private fixture</b>"}, {id: "two", name: "<b>Private fixture</b>"}]; }
    function test_explicitActionsDispatchExactIdAndReleasePresentation() {
        compare(typeof dock.openDesktopActions, "function");
        dock.desktopActions = {alpha: actions()};
        actionSpy.target = dock; actionSpy.clear();
        dock.applications = [{id: "alpha", name: "Alpha", pinned: true, canPin: true, running: false}];
        dock.openContext(1);
        const context = findChild(dock, "context-desktop-actions");
        verify(context !== null && context.visible);
        compare(context.text, "App actions…");
        mouseClick(context);
        verify(dock.desktopActionsOpen); verify(dock.wantsKeyboard);
        compare(dock.contextIndex, 1);
        compare(dock.desktopActionSelectionId, "exact-One");
        compare(actionSpy.count, 0);
        const row = findChild(dock, "desktop-action-two");
        compare(row.contentItem.textFormat, Text.PlainText);
        compare(row.contentItem.text, "<b>Private fixture</b>");
        verify(row.Accessible.name.indexOf("Private fixture") >= 0);
        mouseClick(row);
        compare(actionSpy.count, 1);
        compare(actionSpy.signalArguments[0][0], "alpha");
        compare(actionSpy.signalArguments[0][1], "two");
        compare(dock.contextIndex, -1); verify(!dock.desktopActionsOpen);
        compare(dock.desktopActionSelectionId, "");
        verify(dock.actionLabel.indexOf("Private fixture") < 0);
        tryVerify(function() { return findChild(dock, "desktop-action-list") === null; });
    }
    function test_keyboardSelectionIsIdBasedAndNeverRetargetsRemoval() {
        dock.desktopActions = {alpha: actions()}; actionSpy.target = dock; actionSpy.clear();
        verify(dock.openDesktopActions("alpha"));
        keyClick(Qt.Key_Down); compare(dock.desktopActionSelectionId, "two");
        dock.desktopActions = {alpha: actions().reverse()};
        compare(dock.desktopActionSelectionId, "two");
        dock.desktopActions = {alpha: [actions()[0]]};
        compare(dock.desktopActionSelectionId, "");
        keyClick(Qt.Key_Return); compare(actionSpy.count, 0);
        keyClick(Qt.Key_Up); compare(dock.desktopActionSelectionId, "exact-One");
        keyClick(Qt.Key_Tab); keyClick(Qt.Key_Return);
        verify(!dock.desktopActionsOpen); compare(dock.contextIndex, 1);
        verify(dock.openDesktopActions("alpha")); keyClick(Qt.Key_Backspace);
        verify(!dock.desktopActionsOpen); compare(dock.contextIndex, 1);
        verify(dock.openDesktopActions("alpha")); keyClick(Qt.Key_Escape);
        compare(dock.contextIndex, -1);
        verify(dock.openDesktopActions("alpha")); keyClick(Qt.Key_Return);
        compare(actionSpy.count, 1); compare(actionSpy.signalArguments[0][1], "exact-One");
    }
    function test_emptyRemovedAndHiddenModelsDestroyChooserWithoutRequests() {
        actionSpy.target = dock; actionSpy.clear();
        dock.desktopActions = {alpha: []}; compare(dock.openDesktopActions("alpha"), false);
        dock.desktopActions = {alpha: actions()}; verify(dock.openDesktopActions("alpha"));
        dock.desktopActions = {alpha: []};
        compare(dock.contextIndex, -1); compare(dock.desktopActionSelectionId, "");
        tryVerify(function() { return findChild(dock, "desktop-action-list") === null; });
        dock.desktopActions = {alpha: actions()}; verify(dock.openDesktopActions("alpha"));
        dock.applications = [];
        compare(dock.contextIndex, -1); compare(dock.desktopActionSelectionId, "");
        dock.applications = [app(2)]; verify(dock.openDesktopActions("alpha"));
        dock.resetSurface();
        compare(dock.contextIndex, -1); compare(dock.desktopActionSelectionId, "");
        dock.desktopActions = {alpha: [{id: "private", name: "Hidden private fixture"}]};
        keyClick(Qt.Key_Return);
        tryVerify(function() { return findChild(dock, "desktop-action-list") === null; });
        compare(actionSpy.count, 0);
        verify(dock.actionLabel.indexOf("private") < 0); verify(dock.appStatus.indexOf("private") < 0);
    }
    function test_pendingAndNonAppEntriesCannotActivateActions() {
        dock.desktopActions = {alpha: actions()}; actionSpy.target = dock; actionSpy.clear();
        verify(dock.openDesktopActions("alpha"));
        dock.applications = [{id: "alpha", name: "Private application name", pending: true}];
        verify(!findChild(dock, "desktop-action-exact-One").enabled);
        keyClick(Qt.Key_Return); compare(actionSpy.count, 0);
        compare(dock.appStatus, "Opening alpha…");
        dock.releaseInteractions(); dock.openContext(1);
        const button = findChild(dock, "context-desktop-actions");
        verify(button.visible); verify(!button.enabled);
        compare(dock.openDesktopActions("alpha"), false);
        for (const entry of [{id: "launcher:x", canEdit: true}, {id: "unknown:x"}, {id: "window:unmatched"}, {id: "separator", kind: "separator"}, {id: "custom", kind: "command"}]) {
            dock.applications = [entry];
            const map = {}; map[entry.id] = actions(); dock.desktopActions = map;
            compare(dock.openDesktopActions(entry.id), false);
            dock.openContext(1); verify(!findChild(dock, "context-desktop-actions").visible);
        }
        compare(dock.openDesktopActions("missing"), false);
        compare(dock.openDesktopActions("menu"), false);
        compare(actionSpy.count, 0);
    }
    function test_largeListScrollsInsideFrozenPopup() {
        const many = [];
        for (let i = 0; i < 300; ++i) many.push({id: "a" + i, name: "Long action fixture ".repeat(40)});
        dock.desktopActions = {alpha: many}; dock.availableWidth = 320;
        verify(dock.openDesktopActions("alpha"));
        const rect = dock.popupRect; verify(rect.height <= 360);
        verify(rect.x >= 0 && rect.x + rect.width <= dock.width);
        const list = findChild(dock, "desktop-action-list");
        verify(list.clip); verify(list.contentHeight > list.height);
        for (let i = 0; i < 80; ++i) keyClick(Qt.Key_Down);
        compare(dock.desktopActionSelectionId, "a80"); verify(list.contentY > 0);
        const row = findChild(dock, "desktop-action-a80"); verify(row !== null && row.chosen);
        compare(row.contentItem.elide, Text.ElideRight);
        const point = row.mapToItem(list, 0, 0);
        verify(point.y >= 0 && point.y + row.height <= list.height);
        dock.desktopActions = {alpha: many.slice(0, 90)};
        compare(dock.popupRect, rect);
        mouseClick(findChild(dock, "desktop-actions-back"));
        verify(!dock.desktopActionsOpen); compare(dock.contextIndex, 1);
        dock.desktopActions = {alpha: actions()}; verify(dock.openDesktopActions("alpha"));
        const smallRect = dock.popupRect; verify(smallRect.height <= 190);
        dock.desktopActions = {alpha: many}; compare(dock.popupRect, smallRect);
    }
    function test_pointerModelChurnCancelsRatherThanRetargets() {
        dock.desktopActions = {alpha: actions()}; actionSpy.target = dock; actionSpy.clear();
        verify(dock.openDesktopActions("alpha"));
        let button = findChild(dock, "desktop-action-exact-One");
        let point = button.mapToItem(dock, button.width / 2, button.height / 2);
        mousePress(dock, point.x, point.y);
        dock.desktopActions = {alpha: [actions()[1]]};
        mouseRelease(dock, point.x, point.y); compare(actionSpy.count, 0);
        dock.desktopActions = {alpha: actions()}; wait(0);
        button = findChild(dock, "desktop-action-exact-One");
        point = button.mapToItem(dock, button.width / 2, button.height / 2);
        mousePress(dock, point.x, point.y);
        dock.desktopActions = {alpha: actions().reverse()};
        mouseRelease(dock, point.x, point.y); compare(actionSpy.count, 0);
        button = findChild(dock, "desktop-action-two");
        point = button.mapToItem(dock, button.width / 2, button.height / 2);
        mousePress(dock, point.x, point.y);
        dock.releaseInteractions();
        mouseRelease(dock, point.x, point.y); keyClick(Qt.Key_Return);
        compare(actionSpy.count, 0);
    }
    function test_accessibleActionUsesExactIdAndHiddenViewDropsPrivateRows() {
        dock.desktopActions = {alpha: actions()}; actionSpy.target = dock; actionSpy.clear();
        verify(dock.openDesktopActions("alpha"));
        findChild(dock, "desktop-action-two").Accessible.pressAction();
        compare(actionSpy.count, 1); compare(actionSpy.signalArguments[0][1], "two");
        verify(dock.openDesktopActions("alpha"));
        dock.visible = false;
        compare(dock.desktopActionsOpen, false);
        compare(dock.desktopActionSelectionId, "");
        tryVerify(function() { return findChild(dock, "desktop-action-list") === null; });
        dock.desktopActions = {alpha: actions().reverse()};
        compare(actionSpy.count, 1);
    }
    function test_countBadgeHasFixedTargetsAndActualAccessibleCount() {
        const badge = findChild(dock, "window-count-alpha");
        verify(badge !== null, "multiple windows have a compact count badge");
        for (const size of [28, 72]) for (const mode of ["wave", "off"]) {
            dock.iconSize = size; dock.motionMode = mode;
            const slot = findChild(dock, "item-alpha");
            const rect = Qt.rect(slot.x, slot.y, slot.width, slot.height);
            const badgeWidth = badge.width;
            for (const count of [0, 1, 2, 99, 100, 1234]) {
                dock.applications = [app(count)];
                compare(badge.visible, count > 1);
                compare(badge.width, badgeWidth);
                compare(Qt.rect(slot.x, slot.y, slot.width, slot.height), rect);
                if (count > 1) {
                    compare(badge.text, count > 99 ? "99+" : String(count));
                    verify(slot.Accessible.name.indexOf(count + " windows") >= 0);
                }
                compare(findChild(dock, "art-alpha").sourceSize.width, 108);
            }
        }
        dock.applications = [{id: "alpha", name: "Alpha", running: false, windowCount: 4},
            {id: "launcher:x", name: "Custom", canEdit: true, running: true, windowCount: 5},
            {id: "sep", kind: "separator", running: true, windowCount: 8}];
        for (const id of ["menu", "alpha", "launcher:x", "sep"])
            verify(!findChild(dock, "window-count-" + id).visible);
    }
}
