import QtQuick
import QtTest
TestCase {
    id: test
    name: "SettingsSlot"
    visible: true
    when: windowShown
    width: 1800; height: 800
    function makeDock() {
        const c = Qt.createComponent("../../ui/DockView.qml");
        compare(c.status, Component.Ready, c.errorString());
        const apps=[];
        for(let i=0;i<18;++i) apps.push({id:"fixture"+i,name:"Fixture",icon:"",running:true,active:false,windows:["key"+i],windowCount:1});
        const d=createTemporaryObject(c,test,{applications:apps,appsManaged:true,autoHide:true,iconSize:34,zoomSize:140,waveWidth:25,transparency:46});
        d.shelfEntered();
        verify(waitForRendering(d));
        return d;
    }
    function test_left_settings_no_shell() {
        const d=makeDock(); let gestures=[];
        d.shellGestureRequested.connect(function(kind){gestures.push(kind);});
        mouseMove(d,d.rowX+d.slotSize*1.5,d.height-30); wait(200);
        compare(d.hoveredIndex,1);
        mouseClick(d,d.renderedSlots[1].center,d.height-30,Qt.LeftButton);
        compare(gestures.length,0,"Settings left click must not submit a shell command");
        verify(d.settingsOpen,"Settings must open");
        wait(250);
        verify(d.settingsOpen, "opening click must not dismiss Settings");
        const popup = findChild(d, "settings-popup");
        compare(popup.modal, false, "modal overlay would eat outside presses without closing");
        mouseClick(d, 8, 4);
        compare(d.settingsOpen, false, "click outside the settings box closes it");
    }
    function test_appClickClosesSettingsWithoutLaunchDuringSettle() {
        const d = makeDock();
        const launched = [];
        d.activateRequested.connect(function(id) { launched.push(id); });
        d.settingsOpen = true;
        d.popupSettling = true;
        const i = d.order.indexOf("fixture0");
        verify(i > 1);
        mouseClick(d, d.renderedSlots[i].center, d.height-30);
        compare(d.settingsOpen, false, "app click while Settings is open closes it");
        compare(launched.length, 0, "that click must not launch");
    }
    function test_editorOutsideShelf_data() {
        return [{tag:"app", id:"fixture0", button:Qt.LeftButton},
            {tag:"logo", id:"omarchy-menu", button:Qt.LeftButton},
            {tag:"middle", id:"fixture0", button:Qt.MiddleButton}];
    }
    function test_editorOutsideShelf(data) {
        const d = makeDock();
        let actions = 0;
        d.activateRequested.connect(() => ++actions);
        d.newInstanceRequested.connect(() => ++actions);
        d.shellGestureRequested.connect(() => ++actions);
        d.openItemEditor("");
        findChild(d, "editor-name").text = "Unsaved fixture";
        mouseClick(d, d.renderedSlots[d.order.indexOf(data.id)].center, d.rowY + d.baseIconSize / 2, data.button);
        compare(actions, 0, "outside editor gesture must never dispatch");
        compare(d.settingsOpen, false);
        compare(d.editorOpen, false);
        compare(d.dragActive, false);
    }
    function test_editorShelfWheelCannotDispatch() {
        const d = makeDock();
        let actions = 0;
        d.shellGestureRequested.connect(() => ++actions);
        d.openItemEditor("");
        mouseWheel(d, d.renderedSlots[0].center, d.rowY + d.baseIconSize / 2, 0, -120);
        compare(actions, 0, "editor owns outside shelf wheel gestures too");
        verify(d.editorOpen);
    }
    function test_hiddenSettingsKeyboard_data() {
        return [{tag:"menu", key:Qt.Key_Menu, modifiers:Qt.NoModifier},
            {tag:"shift-f10", key:Qt.Key_F10, modifiers:Qt.ShiftModifier}];
    }
    function test_hiddenSettingsKeyboard(data) {
        const d = makeDock();
        d.applications = [];
        d.showAppsButton = false;
        let gestures = 0;
        d.shellGestureRequested.connect(() => ++gestures);
        compare(d.order, ["omarchy-menu"]);
        d.enterKeyboard();
        keyClick(data.key, data.modifiers);
        verify(d.settingsOpen);
        compare(gestures, 0);
        d.settingsOpen = false;
        d.enterKeyboard();
        keyClick(Qt.Key_Return);
        compare(gestures, 1, "Omarchy primary keyboard behavior is preserved");
    }
    function test_statusIndependentGeometry_data() {
        return [{tag:"tall", height:1080}, {tag:"compact", height:600}];
    }
    function test_statusIndependentGeometry(data) {
        const d = makeDock();
        d.availableHeight = data.height;
        d.settingsOpen = true;
        const popup = findChild(d, "settings-popup");
        const geometry = [d.height, popup.height, data.height - d.height + popup.y];
        for (const error of ["Fixture failure", ""]) {
            d.appError = error;
            compare([d.height, popup.height, data.height - d.height + popup.y], geometry);
        }
        for (const pending of [true, false]) {
            d.applications = [{id:"fixture", name:"Fixture", pending:pending}];
            compare([d.height, popup.height, data.height - d.height + popup.y], geometry);
        }
    }
    function test_pendingEditorFreezesDraft() {
        const d = makeDock();
        d.openItemEditor("");
        const editor = findChild(d, "launcher-editor");
        editor.begin({kind:"command", name:"Submitted", program:"fixture", args:["one"]});
        wait(0);
        d.launcherSaveAccepted(41);
        for (const name of ["editor-name", "editor-kind", "editor-program", "argument-0", "editor-terminal", "editor-enabled", "add-argument"]) {
            verify(findChild(editor, name), name);
            compare(findChild(editor, name).enabled, false, name + " must freeze while saving");
        }
        verify(findChild(d, "editor-cancel").enabled);
        d.launcherSaveResult(40, true);
        verify(d.editorOpen);
        d.launcherSaveResult(41, false);
        verify(d.editorOpen);
        verify(findChild(d, "editor-name").enabled);
        compare(findChild(d, "editor-name").text, "Submitted");
        d.launcherSaveAccepted(42);
        d.launcherSaveResult(42, true);
        compare(d.editorOpen, false);
    }
    function test_pendingStatusUsesDisplayName() {
        const d = makeDock();
        d.applications = [{id:"launcher:fixture", name:"Build <docs>", pending:true}];
        compare(d.appStatus, "Opening Build <docs>…");
        compare(findChild(d, "app-status-text").textFormat, Text.PlainText);
        d.applications = [{id:"fixture", pending:true}];
        compare(d.appStatus, "Opening fixture…");
    }
    function test_middle_preserved() {
        const d=makeDock(); let gestures=[];
        d.shellGestureRequested.connect(function(kind){gestures.push(kind);});
        mouseMove(d,d.rowX+d.slotSize*1.5,d.height-30); wait(200);
        mouseClick(d,d.renderedSlots[1].center,d.height-30,Qt.MiddleButton);
        compare(gestures,["middle"]); verify(!d.settingsOpen);
    }
    function test_caption() {
        const d=makeDock();
        mouseMove(d,d.rowX+d.slotSize*1.5,d.height-30);
        tryCompare(d,"tooltipIndex",1,1000);
        compare(findChild(d,"app-tooltip").text,"Settings");
    }
    function test_right_keyboard_accessibility() {
        const d=makeDock(); let gestures=[];
        d.shellGestureRequested.connect(function(kind){gestures.push(kind);});
        mouseMove(d,d.rowX+d.slotSize*1.5,d.height-30); wait(200);
        mouseClick(d,d.renderedSlots[1].center,d.height-30,Qt.RightButton);
        verify(d.settingsOpen); d.settingsOpen=false; wait(250);
        d.enterKeyboard(); d.focusIndex=1; keyClick(Qt.Key_Return);
        verify(d.settingsOpen); d.settingsOpen=false;
        findChild(d,"settings-item").Accessible.pressAction();
        verify(d.settingsOpen); compare(gestures.length,0);
    }
    function boxesOverlap(a, b, d) {
        const p = a.mapToItem(d, 0, 0);
        const q = b.mapToItem(d, 0, 0);
        return p.x < q.x + b.width && p.x + a.width > q.x && p.y < q.y + b.height && p.y + a.height > q.y;
    }
    function test_settingsCheckboxesDoNotOverlap() {
        const d = makeDock();
        d.settingsOpen = true;
        verify(waitForRendering(d));
        const names = findChild(d, "show-app-names");
        const settingsIcon = findChild(d, "show-apps-button");
        const overlap = findChild(d, "intelligent-hide");
        const hiddenWorlds = findChild(d, "show-hidden-workspace-apps");
        const hideVisible = findChild(d, "hide-visible-apps");
        verify(names && settingsIcon && overlap && hiddenWorlds && hideVisible);
        const controls = [names, settingsIcon, overlap, hiddenWorlds, hideVisible];
        for (let i = 0; i < controls.length; ++i)
            for (let j = i + 1; j < controls.length; ++j)
                verify(!boxesOverlap(controls[i], controls[j], d), controls[i].objectName + " vs " + controls[j].objectName);
        d.availableWidth = 360;
        verify(waitForRendering(d));
        wait(30);
        const attention = findChild(d, "attention-hints-setting");
        verify(attention);
        verify(!boxesOverlap(names, settingsIcon, d));
        verify(!boxesOverlap(settingsIcon, overlap, d));
        verify(!boxesOverlap(hiddenWorlds, hideVisible, d), "workspace filters vs each other");
        verify(!boxesOverlap(names, attention, d), "wrapped Show app names vs Attention");
        verify(!boxesOverlap(settingsIcon, attention, d), "wrapped Settings icon vs Attention");
        verify(!boxesOverlap(hiddenWorlds, attention, d), "hidden-workspace toggle vs Attention");
        verify(!boxesOverlap(hideVisible, attention, d), "hide-visible toggle vs Attention");
    }
    function test_workspaceFilterCheckboxesToggle() {
        const d = makeDock();
        d.settingsOpen = true;
        verify(waitForRendering(d));
        const hiddenWorlds = findChild(d, "show-hidden-workspace-apps");
        const hideVisible = findChild(d, "hide-visible-apps");
        compare(d.showHiddenWorkspaceApps, false);
        compare(d.hideVisibleApps, false);
        hiddenWorlds.Accessible.pressAction();
        hideVisible.Accessible.pressAction();
        compare(d.showHiddenWorkspaceApps, true);
        compare(d.hideVisibleApps, true);
        hiddenWorlds.Accessible.pressAction();
        compare(d.showHiddenWorkspaceApps, false);
        compare(d.hideVisibleApps, true);
    }
}
