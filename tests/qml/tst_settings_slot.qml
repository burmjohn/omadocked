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
        verify(names && settingsIcon && overlap);
        verify(!boxesOverlap(names, settingsIcon, d), "Show app names vs Settings icon");
        verify(!boxesOverlap(names, overlap, d), "Show app names vs Overlap hide");
        verify(!boxesOverlap(settingsIcon, overlap, d), "Settings icon vs Overlap hide");
        d.availableWidth = 360;
        verify(waitForRendering(d));
        wait(30);
        const attention = findChild(d, "attention-hints-setting");
        verify(attention);
        verify(!boxesOverlap(names, settingsIcon, d));
        verify(!boxesOverlap(settingsIcon, overlap, d));
        verify(!boxesOverlap(names, attention, d), "wrapped Show app names vs Attention");
        verify(!boxesOverlap(settingsIcon, attention, d), "wrapped Settings icon vs Attention");
    }
}
