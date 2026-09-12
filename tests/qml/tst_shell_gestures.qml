import QtQuick
import QtTest

TestCase {
    id: test
    name: "ShellGestures"
    when: windowShown
    visible: true
    width: 1000; height: 800
    property var dock
    SignalSpy { id: action; signalName: "shellGestureRequested" }
    function init() {
        const c=Qt.createComponent("../../ui/DockView.qml");
        compare(c.status,Component.Ready,c.errorString());
        dock=c.createObject(test,{autoHide:false,reducedMotion:true,appsManaged:true});
        action.target=dock; action.clear();
    }
    function cleanup() { action.target=null; dock.destroy(); }
    function logo() { return Qt.point(dock.renderedSlots[0].center,dock.rowY+15); }
    function settings() { return Qt.point(dock.renderedSlots[1].center,dock.rowY+15); }
    function click(p,button) {
        const input=findChild(dock,"rowInput");
        mousePress(dock,p.x,p.y,button); verify(input.pressed);
        mouseRelease(dock,p.x,p.y,button);
    }
    function test_omarchyMenuIsLeftOfSettings() {
        compare(dock.order[0], "omarchy-menu");
        compare(dock.order[1], "menu");
        click(logo(), Qt.LeftButton);
        compare(action.count, 1);
        compare(action.signalArguments[0][0], "left");
        verify(!dock.settingsOpen);
    }
    function test_leftSettingsMiddleTerminal() {
        click(settings(),Qt.LeftButton);
        compare(action.count,0); verify(dock.settingsOpen);
        dock.settingsOpen=false;
        click(logo(),Qt.MiddleButton);
        compare(action.count,1); compare(action.signalArguments[0][0],"middle");
    }
    function test_settingsRemainKeyboardAndRightAccessible() {
        click(settings(),Qt.RightButton); verify(dock.settingsOpen); compare(action.count,0);
        dock.settingsOpen=false;
        dock.selectIndex(1); verify(dock.settingsOpen); compare(action.count,0);
    }
    function test_emptySpaceRightOnly() {
        const p=Qt.point(dock.shelfRect.x+1,dock.rowY+15);
        compare(dock.hitIndex(p.x),-1);
        click(p,Qt.LeftButton); compare(action.count,0); verify(!dock.settingsOpen);
        click(p,Qt.MiddleButton); compare(action.count,0); verify(!dock.settingsOpen);
        click(p,Qt.RightButton); verify(dock.settingsOpen); compare(action.count,0);
    }
    function test_wheelCancelsPressAndIgnoresHorizontal() {
        const p=logo();
        mousePress(dock,p.x,p.y); verify(findChild(dock,"rowInput").pressed);
        mouseWheel(dock,p.x,p.y,0,-120);
        mouseRelease(dock,p.x,p.y);
        compare(action.count,1); compare(action.signalArguments[0][0],"wheel"); compare(action.signalArguments[0][1],-120);
        mouseWheel(dock,p.x,p.y,120,0); compare(action.count,1);
        mouseWheel(dock,p.x,p.y,0,120); compare(action.count,2); compare(action.signalArguments[1][1],120);
    }
    function test_releaseOutsideLogoCancels() {
        const p=logo(); mousePress(dock,p.x,p.y); verify(findChild(dock,"rowInput").pressed);
        mouseRelease(dock,dock.shelfRect.x+1,p.y); compare(action.count,0);
    }
}
