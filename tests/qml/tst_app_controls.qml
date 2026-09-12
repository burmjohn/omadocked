import QtQuick
import QtTest

TestCase {
    id: test
    name: "AppControls"
    when: windowShown
    visible: true
    width: 1000; height: 800
    property var dock
    SignalSpy { id: groupClose; signalName: "closeApplicationRequested" }
    SignalSpy { id: groupRestore; signalName: "restoreApplicationRequested" }
    SignalSpy { id: exact; signalName: "activateWindowRequested" }
    SignalSpy { id: launch; signalName: "newInstanceRequested" }
    SignalSpy { id: primary; signalName: "activateRequested" }
    function init() {
        const c = Qt.createComponent("../../ui/DockView.qml");
        compare(c.status, Component.Ready, c.errorString());
        dock = c.createObject(test, {autoHide:false, reducedMotion:true, appsManaged:true,
            applications:[{id:"a", name:"A", running:true, canNewInstance:true}, {id:"b", name:"B", running:true}],
            windowGroups:{a:[{key:"a1",title:"One",active:true},{key:"a2",title:"Two"},{key:"a3",title:"Parked",parked:true}],b:[{key:"b1"}]}});
        exact.target=dock; launch.target=dock; primary.target=dock;
        exact.clear(); launch.clear(); primary.clear();
    }
    function cleanup() { exact.target=null; launch.target=null; primary.target=null; dock.destroy(); }
    function point() { return Qt.point(dock.rowX + dock.slotSize * 2.5, dock.rowY + 15); }
    function test_windowMenuWheelSelectsThenEnterConfirms() {
        dock.previewsEnabled=false;
        verify(dock.openWindowChooser("a")); wait(0);
        const chooser=dock.activeWindowChooser;
        const list=findChild(dock,"window-list");
        const p=list.mapToItem(dock,list.width/2,list.height/2);
        mouseWheel(dock,p.x,p.y,0,-120);
        compare(chooser.selectionKey,"a2"); compare(exact.count,0);
        keyClick(Qt.Key_Return);
        compare(exact.count,1); compare(exact.signalArguments[0][1],"a2");
    }
    function test_contextGroupScopeFrozenAndPressReorderCanceled() {
        groupClose.target=dock; groupClose.clear(); groupRestore.target=dock; groupRestore.clear();
        dock.openContext(2);
        let button=findChild(dock,"context-close-windows");
        verify(button !== null, "explicit scoped group close control");
        compare(button.text,"Close All Windows (3)");
        let p=button.mapToItem(dock,button.width/2,button.height/2);
        mousePress(dock,p.x,p.y); verify(button.pressed);
        dock.windowGroups={a:dock.windowGroups.a.slice().reverse(),b:dock.windowGroups.b};
        mouseRelease(dock,p.x,p.y); compare(groupClose.count,0);
        wait(0); p=button.mapToItem(dock,button.width/2,button.height/2);
        mousePress(dock,p.x,p.y); verify(button.pressed);
        compare(button.pressApp,"a"); compare(button.pressRevision,dock.contextScopeRevision);
        mouseRelease(dock,p.x,p.y); compare(groupClose.count,1);
        compare(groupClose.signalArguments[0][0],"a");
        compare(JSON.stringify(groupClose.signalArguments[0][1]),JSON.stringify(["a1","a2","a3"]));
        compare(dock.contextIndex,-1);
        dock.openContext(2);
        button=findChild(dock,"context-restore-here");
        button.Accessible.pressAction();
        compare(groupRestore.count,1); compare(groupRestore.signalArguments[0][0],"a");
        compare(JSON.stringify(groupRestore.signalArguments[0][1]),JSON.stringify(["a3"]));
        compare(groupRestore.signalArguments[0][2],"here");
        groupClose.target=null; groupRestore.target=null;
    }
    function test_middleClickNewInstanceAndStaleReorder() {
        const p=point();
        mousePress(dock,p.x,p.y,Qt.MiddleButton);
        verify(findChild(dock,"rowInput").pressed);
        mouseRelease(dock,p.x,p.y,Qt.MiddleButton);
        compare(launch.count,1); compare(launch.signalArguments[0][0],"a"); compare(primary.count,0);
        mousePress(dock,p.x,p.y,Qt.MiddleButton);
        verify(findChild(dock,"rowInput").pressed);
        dock.applications=dock.applications.slice().reverse();
        mouseRelease(dock,p.x,p.y,Qt.MiddleButton);
        compare(launch.count,1);
    }
    function test_pressWheelReleaseAndWindowReorderCancel() {
        const p=point();
        mousePress(dock,p.x,p.y); verify(findChild(dock,"rowInput").pressed);
        mouseWheel(dock,p.x,p.y,0,-120);
        mouseRelease(dock,p.x,p.y);
        compare(primary.count,0); compare(exact.count,0);
        mousePress(dock,p.x,p.y); verify(findChild(dock,"rowInput").pressed);
        dock.windowGroups={a:dock.windowGroups.a.slice().reverse(),b:dock.windowGroups.b};
        mouseRelease(dock,p.x,p.y);
        compare(primary.count,0); compare(exact.count,0);
        mouseClick(dock,p.x,p.y); compare(exact.count,1); compare(exact.signalArguments[0][1],"a2");
    }
    function test_wheelSelectsWithoutActivationThenClickConfirms() {
        const p=point();
        mouseWheel(dock,p.x,p.y,0,-120);
        compare(exact.count,0); compare(primary.count,0);
        compare(dock.wheelSelectionKey,"a2");
        const mark=findChild(dock,"wheel-selection-a");
        verify(mark !== null && mark.visible); compare(mark.text,"2/2");
        mouseClick(dock,p.x,p.y);
        compare(exact.count,1); compare(exact.signalArguments[0][0],"a"); compare(exact.signalArguments[0][1],"a2");
        compare(primary.count,0);
    }
}
