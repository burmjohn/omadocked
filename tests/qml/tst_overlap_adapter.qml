import QtQuick
import QtTest

TestCase {
    id: test
    name: "NativeOverlapAdapter"
    when: windowShown
    QtObject { id: ws; property int id: 1 }
    QtObject { id: otherWs; property int id: 2 }
    QtObject { id: hiddenWs; property int id: 3 }
    QtObject {
        id: left
        property string name: "left"
        property int x: -1280
        property int y: -100
        property var activeWorkspace: ws
        property var lastIpcObject: ({specialWorkspace:{id:0}})
    }
    QtObject {
        id: right
        property string name: "right"
        property int x: 0
        property int y: 0
        property var activeWorkspace: otherWs
        property var lastIpcObject: ({specialWorkspace:{id:0}})
    }
    QtObject { id: nativeWindow; property bool fullscreen: false; property bool minimized: false }
    QtObject {
        id: win
        property var workspace: ws
        property var monitor: left
        property var wayland: nativeWindow
        property var lastIpcObject: ({mapped:true,hidden:false,pinned:false,at:[-800,550],size:[400,100],fullscreen:0})
    }
    QtObject {
        id: backend
        property QtObject monitors: QtObject { property var values: [left,right] }
        property QtObject toplevels: QtObject { property var values: [win] }
        property int refreshes: 0
        signal rawEvent(var event)
        function refreshToplevels() { refreshes++; }
        function refreshMonitors() { refreshes++; }
        function refreshWorkspaces() { refreshes++; }
    }
    function test_default_fullscreen_remains_native_event_driven() {
        const component = Qt.createComponent("../../services/NativeOverlap.qml");
        const model = createTemporaryObject(component, test, {backend:backend});
        nativeWindow.fullscreen = true;
        verify(model.evaluate("left",Qt.rect(0,0,1,1)).fullscreen,
            "Disabling overlap polling must preserve ordinary native fullscreen suppression");
        verify(!model.evaluate("right",Qt.rect(0,0,1,1)).fullscreen);
        model.setConsumer("fixture",true);
        verify(!model.evaluate("left",Qt.rect(0,0,1,1)).fullscreen,
            "Enabled but unavailable snapshot falls back to ordinary visibility");
        model.setConsumer("fixture",false);
        nativeWindow.fullscreen = false;
        compare(backend.refreshes,0,"Default fullscreen uses native signals, no poll requests");
    }
    function test_geometry_and_events() {
        const component = Qt.createComponent("../../services/NativeOverlap.qml");
        compare(component.status, Component.Ready, component.errorString());
        const model = createTemporaryObject(component, test, {backend:backend});
        verify(model);
        // Owned projection fixture: geometry policy stays exact production;
        // real request parsing/ACK/failure is tested by test_overlap_socket.py.
        model.setConsumer("fixture", true);
        model.sampledAt = Date.now();
        model.snapshot = Qt.binding(() => ({
            monitors: backend.monitors.values.map(m => ({name:m.name,x:m.x,y:m.y,
                workspace:m.activeWorkspace.id,special:m.lastIpcObject.specialWorkspace.id})),
            windows: backend.toplevels.values.map(w => ({workspace:w.workspace.id,monitor:w.monitor.name,
                mapped:w.lastIpcObject.mapped,hidden:w.lastIpcObject.hidden || w.wayland.minimized,
                pinned:w.lastIpcObject.pinned,fullscreen:w.wayland.fullscreen || w.lastIpcObject.fullscreen === 2,
                x:w.lastIpcObject.at[0],y:w.lastIpcObject.at[1],width:w.lastIpcObject.size[0],height:w.lastIpcObject.size[1]}))
        }));
        verify(typeof model.shelfFor === "function", "Production logical output geometry");
        compare(model.shelfFor("left", 1280, 720, 500, 80, 10), Qt.rect(-890,530,500,74));
        // ShellScreen dimensions are already logical, including fractional scale
        // and transformed outputs: no second scaling of window coordinates.
        compare(model.shelfFor("left", 853, 480, 400, 70, 0), Qt.rect(-1053.5,310,400,64));
        const shelf = Qt.rect(-900,590,500,80);
        verify(model.evaluate("left", shelf).overlap);
        verify(!model.evaluate("right", Qt.rect(0,600,500,80)).overlap);
        win.workspace = hiddenWs;
        verify(!model.evaluate("left", shelf).overlap);
        win.workspace = ws;
        win.lastIpcObject = {mapped:true,hidden:false,pinned:false,at:[-800,400],size:[400,100],fullscreen:0};
        verify(!model.evaluate("left", shelf).overlap, "lastIpcObject-only notification updates geometry");
        nativeWindow.fullscreen = true;
        verify(model.evaluate("left", shelf).fullscreen);
        verify(!model.evaluate("right", shelf).fullscreen);
        nativeWindow.fullscreen = false;
        win.lastIpcObject = {mapped:true,hidden:false,pinned:false,at:[-800,490],size:[400,100],fullscreen:0};
        verify(!model.evaluate("left", shelf).overlap, "Touching edges are not overlap");
        win.lastIpcObject = {mapped:true,hidden:false,pinned:false,at:[-800,491],size:[400,100],fullscreen:0};
        verify(model.evaluate("left", shelf).overlap);
        nativeWindow.minimized = true;
        verify(!model.evaluate("left", shelf).overlap);
        nativeWindow.minimized = false;
        win.workspace = hiddenWs;
        left.lastIpcObject = {specialWorkspace:{id:3}};
        verify(model.evaluate("left", shelf).overlap, "Visible special workspace counts");
        left.lastIpcObject = {specialWorkspace:{id:0}};
        verify(!model.evaluate("left", shelf).overlap, "Closed special/parked workspace does not count");
        win.lastIpcObject = {mapped:true,hidden:false,pinned:true,at:[-800,550],size:[400,100],fullscreen:0};
        verify(model.evaluate("left", shelf).overlap, "Pinned visible on owning output");
        win.lastIpcObject = {mapped:true,hidden:true,pinned:true,at:[-800,550],size:[400,100],fullscreen:2};
        verify(!model.evaluate("left", shelf).overlap);
        verify(!model.evaluate("left", shelf).fullscreen);
        win.workspace = ws;
        win.lastIpcObject = {mapped:true,hidden:false,at:[-20,600],size:[100,80],fullscreen:1};
        verify(model.evaluate("right", Qt.rect(0,600,500,80)).overlap, "Visible window may straddle outputs");
        verify(!model.evaluate("left", shelf).fullscreen, "Maximized is not fullscreen");
        left.activeWorkspace = hiddenWs;
        verify(!model.evaluate("right", Qt.rect(0,600,500,80)).overlap, "Workspace switch invalidates straddling geometry");
        left.activeWorkspace = ws;
        left.x = -1600;
        compare(model.shelfFor("left", 1280, 720, 500, 80, 10).x, -1210);
        win.monitor = right;
        nativeWindow.fullscreen = true;
        verify(model.evaluate("right", shelf).fullscreen);
        verify(!model.evaluate("left", shelf).fullscreen);
        nativeWindow.fullscreen = false;

        backend.toplevels.values = [];
        verify(!model.evaluate("left", shelf).overlap);
        backend.monitors.values = [];
        verify(!model.evaluate("left", shelf).available);
    }
}
