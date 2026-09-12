import QtQuick
import QtTest

TestCase {
    id: test
    name: "AppView"
    when: windowShown
    visible: true
    width: 2200
    height: 800
    property var dock
    property var second: null
    QtObject { id: shared; property var items: [] }
    SignalSpy { id: activateSpy; signalName: "activateRequested" }
    SignalSpy { id: pinSpy; signalName: "pinRequested" }
    SignalSpy { id: reorderSpy; signalName: "reorderRequested" }
    function app(id, running, pinned) {
        return {id: id, name: "Application " + id, icon: "", running: !!running,
            active: id === "alpha" && !!running, pinned: !!pinned, canPin: true,
            windowCount: running ? 2 : 0, pending: false};
    }
    function makeView() {
        const component = Qt.createComponent("../../ui/DockView.qml");
        compare(component.status, Component.Ready, component.errorString());
        const view = component.createObject(test, {autoHide: false, reducedMotion: true});
        verify(view !== null);
        return view;
    }
    function init() {
        dock = makeView();
        mouseMove(test, 2150, 750);
    }
    function cleanup() {
        activateSpy.target = null; pinSpy.target = null; reorderSpy.target = null;
        if (second) { second.destroy(); second = null; }
        dock.destroy(); dock = null;
    }
    SignalSpy { id: newSpy; signalName: "newInstanceRequested" }
    SignalSpy { id: duplicateSpy; signalName: "duplicateLauncherRequested" }
    SignalSpy { id: removeSpy; signalName: "removeLauncherRequested" }
    SignalSpy { id: recoverSpy; signalName: "recoverRequested" }
    SignalSpy { id: overrideSpy; signalName: "overrideRequested" }
    SignalSpy { id: minimizeModeSpy; signalName: "minimizeModeRequested" }
    SignalSpy { id: minimizeSpy; signalName: "minimizeRequested" }
    SignalSpy { id: restoreSpy; signalName: "restoreApplicationRequested" }
    SignalSpy { id: recoverParkedSpy; signalName: "recoverParkedRequested" }
    function test_tileIndependentParkingAndRecoveryControlsUseExactKeys() {
        const alpha = app("alpha", true, true);
        dock.applications = [alpha];
        dock.windowGroups = {alpha:[{key:"visible-key",title:"Private",active:true,parked:false},
                                    {key:"parked-key",title:"Private parked",active:false,parked:true,sequence:4}]};
        dock.parkedWindows = [{key:"parked-key",state:"parked",sequence:4}];
        minimizeSpy.target=dock; minimizeSpy.clear(); restoreSpy.target=dock; restoreSpy.clear(); recoverParkedSpy.target=dock; recoverParkedSpy.clear();
        dock.openContext(2);
        const minimize=findChild(dock,"context-minimize");
        const here=findChild(dock,"context-restore-here");
        const origin=findChild(dock,"context-restore-origin");
        verify(minimize !== null && minimize.visible); verify(here !== null && here.visible); verify(origin !== null && origin.visible);
        minimize.clicked(); compare(minimizeSpy.signalArguments[0][0],"alpha");
        dock.openContext(2); here.Accessible.pressAction();
        compare(restoreSpy.signalArguments[0][0],"alpha"); compare(JSON.stringify(restoreSpy.signalArguments[0][1]),JSON.stringify(["parked-key"])); compare(restoreSpy.signalArguments[0][2],"here");
        dock.openContext(2); origin.Accessible.pressAction();
        compare(restoreSpy.signalArguments[1][0],"alpha"); compare(JSON.stringify(restoreSpy.signalArguments[1][1]),JSON.stringify(["parked-key"])); compare(restoreSpy.signalArguments[1][2],"origin");
        dock.selectIndex(1);
        const recoverHere=findChild(dock,"recover-parked-here");
        const recoverOrigin=findChild(dock,"recover-parked-origin");
        verify(recoverHere.visible && recoverOrigin.visible);
        recoverHere.clicked(); recoverOrigin.clicked();
        compare(recoverParkedSpy.signalArguments[0][0],"here");
        compare(recoverParkedSpy.signalArguments[1][0],"origin");
        minimizeSpy.target=null;restoreSpy.target=null;recoverParkedSpy.target=null;
    }
    function test_minimizeModeHasThreeExplicitSettingsControls() {
        dock.selectIndex(1);
        minimizeModeSpy.target = dock; minimizeModeSpy.clear();
        const active = findChild(dock, "minimize-active");
        const all = findChild(dock, "minimize-all");
        const off = findChild(dock, "minimize-off");
        verify(active !== null && all !== null && off !== null);
        dock.minimizeMode = "active";
        verify(active.chosen); verify(!all.chosen); verify(!off.chosen);
        all.clicked(); off.clicked(); active.clicked();
        compare(minimizeModeSpy.count, 3);
        compare(minimizeModeSpy.signalArguments[0][0], "all");
        compare(minimizeModeSpy.signalArguments[1][0], "off");
        compare(minimizeModeSpy.signalArguments[2][0], "active");
        verify(active.Accessible.name.length > 0 && all.Accessible.name.length > 0 && off.Accessible.name.length > 0);
        minimizeModeSpy.target = null;
    }
    function test_clearExactOverrideRequiresOnlyExplicitAppId() {
        dock.selectIndex(1);
        const clear = findChild(dock, "clear-override");
        verify(clear !== null, "matching overrides can be removed without editing JSON");
        verify(!clear.enabled);
        overrideSpy.target = dock; overrideSpy.clear();
        findChild(dock, "override-app-id").text = "org.Example.PWA";
        verify(clear.enabled);
        compare(overrideSpy.count, 0);
        clear.clicked();
        compare(overrideSpy.count, 1);
        compare(overrideSpy.signalArguments[0][0], "org.Example.PWA");
        compare(overrideSpy.signalArguments[0][1], "");
        verify(clear.Accessible.name.length > 0);
        overrideSpy.target = null;
    }
    function test_recoveryAndExactOverrideRequireExplicitAction() {
        dock.selectIndex(1);
        const recover = findChild(dock, "recover-config");
        verify(recover !== null, "recovery is available only by explicit request");
        verify(!recover.visible);
        recoverSpy.target = dock; recoverSpy.clear(); overrideSpy.target = dock; overrideSpy.clear();
        dock.canRecover = true; dock.appError = "Invalid configuration; original preserved";
        verify(recover.visible); compare(recoverSpy.count, 0);
        recover.clicked(); compare(recoverSpy.count, 1);
        const appId = findChild(dock, "override-app-id");
        const desktopId = findChild(dock, "override-desktop-id");
        const apply = findChild(dock, "apply-override");
        verify(!apply.enabled);
        appId.text = "org.Example.PWA"; desktopId.text = "exact-case.desktop";
        compare(overrideSpy.count, 0); verify(apply.enabled);
        apply.clicked();
        compare(overrideSpy.signalArguments[0][0], "org.Example.PWA");
        compare(overrideSpy.signalArguments[0][1], "exact-case.desktop");
        verify(appId.Accessible.name.length > 0); verify(desktopId.Accessible.name.length > 0);
        dock.settingsManaged = true;
        verify(findChild(dock, "settings-footer").text.indexOf("temporary") >= 0);
        dock.persistenceEnabled = true;
        verify(findChild(dock, "settings-footer").text.indexOf("temporary") < 0);
        verify(findChild(dock, "settings-footer").text.indexOf("settings are saved") >= 0);
        verify(findChild(dock, "settings-footer").text.indexOf(dock.appError) >= 0);
        recoverSpy.target = null; overrideSpy.target = null;
    }
    function test_separatorAndDisabledLauncherNeverActivate() {
        const separator = {id: "launcher:separator", kind: "separator", name: "Section", canEdit: true, running: true};
        const disabled = {id: "launcher:disabled", kind: "command", name: "Disabled command", canEdit: true, enabled: false};
        dock.applications = [separator, disabled, app("alpha", true, true)];
        activateSpy.target = dock; activateSpy.clear();
        dock.selectIndex(2); dock.selectIndex(3);
        compare(activateSpy.count, 0, "separators and disabled commands cannot launch");
        const line = findChild(dock, "separator-launcher:separator");
        verify(line !== null && line.visible); verify(line.width <= 2);
        verify(!findChild(dock, "art-launcher:separator").visible);
        verify(!findChild(dock, "fallback-launcher:separator").visible);
        verify(!findChild(dock, "running-launcher:separator").visible);
        verify(findChild(dock, "item-launcher:separator").Accessible.ignored);
        dock.enterKeyboard();
        dock.focusIndex = 1;
        keyClick(Qt.Key_Right);
        compare(dock.focusIndex, 3, "stable indices retained, separator skipped");
        keyClick(Qt.Key_Left); compare(dock.focusIndex, 1);
        dock.openContext(2);
        verify(!findChild(dock, "context-open").enabled);
        compare(dock.contextActionIndex, 4, "separator context starts at Edit");
        dock.openContext(3);
        compare(findChild(dock, "context-open").text, "Disabled");
        verify(!findChild(dock, "context-open").enabled);
    }
    function test_newWindowAndCustomContextUseExactIdentity() {
        const alpha = app("alpha", true, true); alpha.canNewInstance = true;
        dock.applications = [alpha];
        newSpy.target = dock; newSpy.clear();
        dock.openContext(2);
        const newWindow = findChild(dock, "context-new-instance");
        verify(newWindow !== null, "New Window is an explicit independent action");
        verify(newWindow.visible); verify(newWindow.enabled);
        mouseClick(newWindow);
        compare(newSpy.count, 1); compare(newSpy.signalArguments[0][0], "alpha");
        compare(dock.contextIndex, -1);
        alpha.canNewInstance = false; dock.applications = [alpha]; dock.openContext(2);
        verify(!newWindow.visible);
        dock.invokeContext(3); compare(newSpy.count, 1, "capabilities rechecked on invoke");
        const custom = app("launcher:fixture", false, true); custom.kind = "command"; custom.canEdit = true;
        dock.launcherRecords = [{id: custom.id, kind: "command", name: "Editable", program: "printf", args: ["literal spaces"]}];
        dock.applications = [custom];
        duplicateSpy.target = dock; duplicateSpy.clear(); removeSpy.target = dock; removeSpy.clear();
        dock.openContext(2);
        verify(!findChild(dock, "context-pin").visible);
        mouseClick(findChild(dock, "context-edit"));
        verify(dock.editorOpen); verify(dock.settingsOpen);
        compare(findChild(dock, "editor-name").text, "Editable");
        compare(findChild(findChild(dock, "launcher-editor"), "argument-0").text, "literal spaces");
        dock.closeMonitorPicker(); dock.openContext(2);
        mouseClick(findChild(dock, "context-duplicate"));
        compare(duplicateSpy.signalArguments[0][0], custom.id);
        compare(dock.launcherRecords.length, 1, "backend owns duplicate identity");
        dock.openContext(2); mouseClick(findChild(dock, "context-remove"));
        compare(removeSpy.signalArguments[0][0], custom.id);
        compare(dock.applications.length, 1, "backend owns removal; no windows are closed");
        custom.canEdit = false; dock.applications = [custom]; dock.openContext(2);
        verify(!findChild(dock, "context-edit").visible);
        dock.invokeContext(5); dock.invokeContext(6);
        compare(duplicateSpy.count, 1); compare(removeSpy.count, 1);
        compare(dock.openItemEditor("launcher:missing"), false);
        newSpy.target = null; duplicateSpy.target = null; removeSpy.target = null;
    }
    function test_metadataPendingAndErrorFeedback() {
        const alpha = app("alpha", false, true);
        alpha.icon = "data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' width='24' height='24'><rect width='24' height='24' fill='red'/></svg>";
        alpha.pending = true;
        dock.icons = {menu: ""}; // Native adapter supplies only fixed-control icons.
        dock.applications = [alpha];
        const art = findChild(dock, "art-alpha");
        compare(decodeURIComponent(art.source.toString()), alpha.icon);
        tryCompare(art, "status", Image.Ready);
        verify(findChild(dock, "pending-alpha").visible);
        verify(findChild(dock, "app-status").visible);
        compare(findChild(dock, "app-status-text").text, "Opening alpha…");
        activateSpy.target = dock; activateSpy.clear();
        dock.selectIndex(2);
        compare(activateSpy.count, 0, "pending launch cannot be requested twice");
        dock.openContext(2);
        verify(!findChild(dock, "context-open").enabled);
        keyClick(Qt.Key_Escape);
        dock.appError = "Pin save failed: read-only directory";
        compare(findChild(dock, "app-status-text").text, dock.appError);
        dock.selectIndex(1);
        const footer = findChild(dock, "settings-footer");
        verify(footer.text.indexOf("Pins are saved") >= 0);
        verify(footer.text.indexOf("temporary") >= 0);
        verify(footer.text.indexOf(dock.appError) >= 0);
        verify(footer.text.indexOf("demo") < 0);
        dock.settingsOpen = false;
        dock.appError = "";
        alpha.pending = false; alpha.running = true; alpha.active = true; alpha.name = "Renamed app";
        dock.applications = [alpha];
        verify(!findChild(dock, "pending-alpha").visible);
        verify(findChild(dock, "running-alpha").visible);
        verify(findChild(dock, "active-alpha").visible);
        dock.tooltipIndex = 2;
        compare(findChild(dock, "app-tooltip").text, "Renamed app");
    }
    function test_managedReorderAndSharedBinding() {
        shared.items = [app("alpha", true, true), app("beta", true, true), app("gamma", false, true)];
        dock.appsManaged = true;
        dock.applications = Qt.binding(function() { return shared.items; });
        second = makeView(); second.x = 1000;
        second.appsManaged = true;
        second.applications = Qt.binding(function() { return shared.items; });
        reorderSpy.target = dock; reorderSpy.clear();
        pinSpy.target = dock; pinSpy.clear();
        const original = dock.order.slice();
        const y = dock.rowY + 22;
        mousePress(dock, dock.renderedSlots[2].center, y);
        mouseMove(dock, dock.renderedSlots[4].right, y);
        verify(dock.dragActive);
        mouseRelease(dock, dock.renderedSlots[4].right, y);
        compare(reorderSpy.count, 1);
        compare(reorderSpy.signalArguments[0][0], ["beta", "gamma", "alpha"]);
        compare(dock.order, original, "managed reorder waits for service, never breaks bindings");
        shared.items = [app("beta", true, true), app("gamma", false, true), app("alpha", true, true)];
        compare(dock.order, ["omarchy-menu", "menu", "beta", "gamma", "alpha"]);
        compare(second.order, dock.order);
        dock.openContext(4);
        mouseClick(findChild(dock, "context-pin"));
        compare(pinSpy.signalArguments[0][0], "alpha");
        compare(pinSpy.signalArguments[0][1], false);
        shared.items = [app("beta", true, true), app("gamma", false, true), app("alpha", true, false)];
        compare(dock.appMeta.alpha.pinned, false);
        compare(second.appMeta.alpha.pinned, false);
        mousePress(dock, dock.renderedSlots[2].center, y);
        mouseMove(dock, dock.renderedSlots[4].right, y);
        keyClick(Qt.Key_Escape);
        mouseRelease(dock, dock.renderedSlots[4].right, y);
        compare(reorderSpy.count, 1, "cancel writes nothing");
        shared.items = [app("alpha", true, false)];
        compare(dock.order, ["omarchy-menu", "menu", "alpha"]);
        compare(second.order, dock.order);
    }
    function test_liveIdentityAndStalePress() {
        failOnWarning(/TypeError/);
        dock.applications = [app("alpha", true, true), app("beta", true, true), app("gamma", false, true)];
        activateSpy.target = dock; activateSpy.clear();
        reorderSpy.target = dock; reorderSpy.clear();
        dock.enterKeyboard(); dock.focusIndex = 3;
        dock.selectIndex(3);
        dock.openContext(3);
        dock.applications = [app("new", true, false), app("alpha", true, true), app("beta", true, true), app("gamma", false, true)];
        compare(dock.contextIndex, 4);
        compare(dock.focusIndex, 4);
        compare(dock.selection, "beta");
        keyClick(Qt.Key_Return);
        compare(activateSpy.signalArguments[1][0], "beta");
        dock.openContext(4);
        dock.applications = [app("alpha", true, true), app("gamma", false, true)];
        compare(dock.contextIndex, -1);
        compare(dock.selection, "");
        compare(dock.focusIndex, 0);
        dock.releaseKeyboard();
        let y = dock.rowY + 22;
        mousePress(dock, dock.renderedSlots[2].center, y);
        mouseMove(dock, dock.renderedSlots[3].right, y);
        verify(dock.dragActive);
        dock.applications = [app("gamma", false, true)];
        verify(!dock.dragActive);
        mouseRelease(dock, dock.renderedSlots[2].center, dock.rowY + 22);
        compare(reorderSpy.count, 0);
        compare(activateSpy.count, 2);
        y = dock.rowY + 22;
        mousePress(dock, dock.renderedSlots[2].center, y);
        dock.applications = [app("replacement", false, true)];
        mouseRelease(dock, dock.renderedSlots[2].center, dock.rowY + 22);
        compare(activateSpy.count, 2, "a stale pressed index cannot activate its replacement");
    }
    function test_contextActionsAndKeyboard() {
        dock.applications = [app("alpha", true, true), app("beta", false, false)];
        activateSpy.target = dock; pinSpy.target = dock;
        activateSpy.clear(); pinSpy.clear();
        dock.openContext(2);
        compare(findChild(dock, "context-open").text, "Focus");
        compare(findChild(dock, "context-pin").text, "Remove from Dock");
        keyClick(Qt.Key_Return);
        compare(activateSpy.count, 1);
        compare(activateSpy.signalArguments[0][0], "alpha");
        compare(dock.contextIndex, -1);
        dock.openContext(3);
        compare(findChild(dock, "context-open").text, "Open");
        compare(findChild(dock, "context-pin").text, "Keep in Dock");
        keyClick(Qt.Key_Tab);
        keyClick(Qt.Key_Return);
        compare(pinSpy.count, 1);
        compare(pinSpy.signalArguments[0][0], "beta");
        compare(pinSpy.signalArguments[0][1], true);
        dock.openContext(2);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Down);
        keyClick(Qt.Key_Return);
        compare(dock.contextIndex, -1);
        compare(activateSpy.count, 1, "Close dismisses the menu, not windows");
        const unavailable = app("unknown", true, false); unavailable.canPin = false;
        dock.applications = [unavailable];
        dock.openContext(2);
        verify(!findChild(dock, "context-pin").enabled);
        verify(findChild(dock, "pin-reason").text.length > 0);
        keyClick(Qt.Key_Tab);
        keyClick(Qt.Key_Return);
        compare(pinSpy.count, 1, "disabled pin is skipped by keyboard");
        dock.openContext(2);
        mouseClick(findChild(dock, "context-open"));
        compare(activateSpy.signalArguments[1][0], "unknown");
        dock.openContext(2);
        mouseClick(dock, dock.renderedSlots[2].center, dock.rowY + 22);
        compare(dock.contextIndex, -1);
        compare(activateSpy.count, 2, "dismissal cannot click through");
    }
    function test_missingDesktopEntryCanStillBeUnpinned() {
        const missing = app("missing", false, true);
        missing.canPin = false;
        dock.applications = [missing];
        pinSpy.target = dock; pinSpy.clear();
        dock.openContext(2);
        const button = findChild(dock, "context-pin");
        compare(button.text, "Remove from Dock");
        verify(button.enabled, "uninstalling an app must not strand its saved pin");
        keyClick(Qt.Key_Tab);
        keyClick(Qt.Key_Return);
        compare(pinSpy.count, 1);
        compare(pinSpy.signalArguments[0][0], "missing");
        compare(pinSpy.signalArguments[0][1], false);
    }
    function test_emptyAndDynamicApplications() {
        failOnWarning(/TypeError/);
        compare(dock.order, ["omarchy-menu", "menu"], "production defaults have no demo apps");
        compare(dock.applications, []);
        verify(isFinite(dock.shelfRect.x) && dock.shelfRect.width > 0);
        dock.applications = [app("alpha", true, true), app("beta", false, true)];
        compare(dock.order, ["omarchy-menu", "menu", "alpha", "beta"]);
        compare(dock.appMeta.alpha.name, "Application alpha");
        verify(findChild(dock, "running-alpha").visible);
        verify(!findChild(dock, "running-beta").visible);
        verify(findChild(dock, "active-alpha").visible);
        verify(!findChild(dock, "running-menu").visible);
        const items = [];
        for (let i = 0; i < 20; ++i) items.push(app("app" + i, true, false));
        dock.applications = items;
        dock.availableWidth = 1920;
        dock.iconSize = 72;
        compare(dock.order.length, 22);
        compare(dock.baseIconSize, 72, "large screens fit real app counts without fixed-width shrinkage");
        verify(dock.width <= 1920);
        verify(dock.renderedSlots[0].left >= 0);
        verify(dock.renderedSlots[21].right <= dock.width);
        dock.applications = [];
        compare(dock.order, ["omarchy-menu", "menu"]);
        verify(isFinite(dock.shelfRect.width));
    }
}
