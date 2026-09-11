import QtQuick
import QtQuick.Controls
import QtTest

TestCase {
    id: test
    name: "WindowFanHover"
    visible: true
    when: windowShown
    width: 1400; height: 800
    Control { id: desktop; anchors.fill: parent; hoverEnabled: true }
    property var dock
    function init() {
        const component = Qt.createComponent("../../ui/DockView.qml");
        compare(component.status, Component.Ready, component.errorString());
        dock = createTemporaryObject(component, desktop, {
            availableWidth: 1000, autoHide: true, iconSize: 34, zoomSize: 140,
            appsManaged: true, applications: [
                {id:"one", name:"Editor", running:true, icon:"", windowCount:2},
                {id:"two", name:"Browser", running:true, icon:"", windowCount:1}],
            windowGroups: {one:[{key:"a", title:"<b>Plain title</b>", active:true},
                                {key:"b", title:"Second", parked:true}],
                           two:[{key:"c", title:"Only"}]}
        });
        verify(dock !== null);
        verify(waitForRendering(dock));
        mouseMove(test, 1300, 700);
    }
    function hover(id) {
        mouseMove(dock, dock.renderedSlots[dock.order.indexOf(id)].center, dock.height - 30);
    }
    SignalSpy { id: activation; signalName: "activateWindowRequested" }
    SignalSpy { id: restore; signalName: "restoreWindowRequested" }

    function cleanup() { activation.target = null; restore.target = null; dock.resetSurface(); mouseMove(test,1300,700); }
    function test_singleton_settings_and_countChanges() {
        hover("two"); wait(550); compare(dock.fanOpen, false);
        compare(findChild(dock,"app-tooltip").requested, true);
        hover("menu"); wait(300); compare(dock.fanOpen, false);
        hover("one"); tryCompare(dock,"fanOpen",true,800);
        dock.windowGroups = {one:[{key:"a", title:"Only"}], two:[{key:"c", title:"Only"}]};
        compare(dock.fanOpen,false);
        tryCompare(findChild(dock,"app-tooltip"),"requested",true,900);
        dock.windowGroups = {one:[{key:"a",title:"One"},{key:"b",title:"Two"}]};
        tryCompare(dock,"fanOpen",true,800);
    }
    function test_switch_leave_reenter_latestDwell() {
        dock.windowGroups = {one:dock.windowGroups.one, two:[{key:"c",title:"C"},{key:"d",title:"D"}]};
        hover("one"); wait(100); hover("two"); wait(100);
        compare(dock.fanOpen,false);
        tryCompare(dock,"fanApp","two",800);
        hover("one"); compare(dock.fanOpen,false);
        tryCompare(dock,"fanApp","one",800);
        mouseMove(test,1300,700); wait(100); verify(dock.fanOpen);
        hover("one"); wait(250); verify(dock.fanOpen);
        mouseMove(test,1300,700); tryCompare(dock,"fanOpen",false,500);
        hover("one"); tryCompare(dock,"fanOpen",true,800);
    }
    function test_staleHeldPress_data() {
        return [{tag:"reorder", rows:[{key:"b",title:"Second"},{key:"a",title:"First"}]},
            {tag:"title", rows:[{key:"a",title:"Changed"},{key:"b",title:"Second"}]},
            {tag:"removal",rows:[{key:"b",title:"Second"},{key:"c",title:"Third"}]}];
    }
    function test_staleHeldPress(data) {
        activation.target = dock; activation.clear();
        hover("one"); tryCompare(dock,"fanOpen",true,800);
        const card = findChild(dock,"fan-window-a");
        const p = card.mapToItem(dock,card.width/2,card.height/2);
        mousePress(dock,p.x,p.y);
        dock.windowGroups = {one:data.rows};
        mouseRelease(dock,p.x,p.y);
        compare(activation.count,0);
    }
    function test_parked_plainTitle_privacy() {
        restore.target = dock; restore.clear();
        hover("one"); tryCompare(dock,"fanOpen",true,800);
        const title = findChild(dock,"fan-title-a");
        compare(title.textFormat,Text.PlainText); compare(title.text,"<b>Plain title</b>");
        const card = findChild(dock,"fan-window-b");
        mouseMove(card,card.width/2,card.height/2);
        mouseClick(card,card.width/2,card.height/2);
        compare(restore.count,1); compare(restore.signalArguments[0][1],"b");
        compare(restore.signalArguments[0][2],"here"); compare(dock.fanOpen,false);
        hover("one"); tryCompare(dock,"fanOpen",true,800);
        dock.windowActionsAllowed = false;
        compare(dock.fanOpen,false); compare(dock.fanRect.width,0);
        compare(findChild(dock,"window-fan").visible,false);
        wait(300); compare(dock.fanOpen,false);
    }
    function test_overflow_clamp_reducedMotion() {
        dock.availableWidth = 320; dock.reducedMotion = true;
        const rows=[]; for (let i=0;i<12;++i) rows.push({key:"w"+i,title:"Window "+i});
        dock.windowGroups = {one:rows};
        hover("one"); tryCompare(dock,"fanOpen",true,800);
        const fan=findChild(dock,"window-fan");
        verify(fan.visibleCount <= 4); verify(fan.overflow);
        verify(dock.fanRect.x >= 0); verify(dock.fanRect.x + dock.fanRect.width <= dock.width);
        verify(dock.fanRect.y >= 0);
        const x=dock.fanRect.x;
        const bridge=dock.fanBridgeRect;
        mouseMove(dock,bridge.x+bridge.width/2,bridge.y+bridge.height/2);
        wait(180); compare(dock.fanRect.x,x,"anchor frozen as wave settles");
        const more=findChild(fan,"fan-more");
        mouseClick(more,more.width/2,more.height/2);
        compare(dock.fanOpen,false); compare(dock.windowChooserOpen,true);
        compare(dock.activeWindowChooser.windows.length,12);
    }
    function test_exitAnimation_retainsGeometry_untilFinished() {
        hover("one"); tryCompare(dock,"fanOpen",true,800);
        const fan = findChild(dock,"window-fan");
        wait(180);
        const w=fan.width;
        mouseMove(test,1300,700);
        tryCompare(dock,"fanOpen",false,500);
        compare(fan.width,w,"exit fade must not collapse the row");
        verify(fan.visible);
        tryCompare(fan,"visible",false,400);
        compare(fan.windows.length,0,"closed fan drops private rows");
    }
    function test_nativeShaped_iconBinding() {
        dock.icons = {menu:""}; // DockSurface supplies only control icons here.
        dock.applications = dock.applications.map(a => Object.assign({},a,{icon:"file:///usr/share/icons/breeze/apps/32/preferences-system.svg"}));
        hover("one"); tryCompare(dock,"fanOpen",true,800);
        const fan=findChild(dock,"window-fan");
        compare(fan.iconSource,dock.applications[0].icon);
    }
    function test_icon_gap_card_exactClick_data() { return [{tag:"default",advanced:false},{tag:"advanced-caption",advanced:true}]; }
    function test_icon_gap_card_exactClick(data) {
        dock.advancedTooltips = data.advanced;
        activation.target = dock; activation.clear();
        const h = dock.height;
        hover("one");
        tryCompare(dock, "fanOpen", true, 900);
        compare(dock.height, h, "hover never resizes bottom-anchored panel");
        compare(dock.wantsKeyboard, false);
        const fan = findChild(dock, "window-fan");
        const bridge = dock.fanBridgeRect;
        mouseMove(dock, bridge.x + bridge.width / 2, bridge.y + bridge.height / 2);
        wait(100);
        verify(dock.fanOpen);
        const card = findChild(fan, "fan-window-a");
        verify(card !== null);
        mouseMove(card, card.width / 2, card.height / 2);
        const point = card.mapToItem(dock, card.width/2, card.height/2);
        for (let i=0; i<20; ++i) {
            mouseMove(dock, point.x + i%2, point.y, 25);
            verify(dock.fanOpen);
            compare(dock.visibilityState, "interacting");
        }
        compare(findChild(dock,"app-tooltip").requested, false);
        mouseClick(card, card.width/2, card.height/2);
        compare(activation.count, 1);
        compare(activation.signalArguments[0][0], "one");
        compare(activation.signalArguments[0][1], "a");
        compare(dock.fanOpen, false);
        compare(dock.windowChooserOpen, false);
    }
}
