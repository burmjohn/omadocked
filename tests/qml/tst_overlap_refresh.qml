import QtQuick
import QtTest
import "../../services"
import "../../ui"

TestCase {
    id: test
    name: "OverlapRefresh"
    when: windowShown
    visible: true
    width: 1200; height: 900
    QtObject {
        id: ownedBackend
        signal rawEvent(var event)
        property QtObject monitors: QtObject { property var values: [] }
        property QtObject toplevels: QtObject { property var values: [] }
    }
    Component { id: factory; NativeOverlap { backend: ownedBackend } }
    property var world: ({monitors:[{name:"owned",x:0,y:0,workspace:1,special:0}],windows:[]})
    property int requests: 0
    property var pending: []
    property bool stalled: false
    property bool failed: false
    function attach(model) {
        model.requested.connect(function(generation) {
            requests++;
            if (stalled) pending.push(generation);
            else model.complete(generation, !failed, world);
        });
    }
    function init() { requests=0; pending=[]; stalled=false; failed=false; world={monitors:[{name:"owned",x:0,y:0,workspace:1,special:0}],windows:[]}; }
    Component { id: viewFactory; DockView { reducedMotion:true; revealDelay:400 } }
    function test_refresh_failure_preserves_reveal_dwell_and_locks() {
        world={monitors:world.monitors,windows:[{workspace:1,monitor:"owned",mapped:true,hidden:false,fullscreen:true,x:0,y:600,width:100,height:100}]};
        const m=createTemporaryObject(factory,test); attach(m); m.setConsumer("one",true);
        const v=createTemporaryObject(viewFactory,test,{autoHide:false,intelligentHide:true});
        const r=Qt.rect(0,600,500,80);
        v.nativeOverlapAvailable=Qt.binding(()=>m.evaluate("owned",r).available);
        v.nativeOverlap=Qt.binding(()=>m.evaluate("owned",r).overlap);
        v.nativeFullscreen=Qt.binding(()=>m.evaluate("owned",r).fullscreen);
        tryCompare(v,"visibilityState","hidden");
        v.triggerEntered(); compare(v.visibilityState,"revealing");
        failed=true; m.refresh(); wait(150);
        compare(v.visibilityState,"revealing","Failed snapshot must not end fullscreen edge dwell early");
        tryCompare(v,"visibilityState","shown",500);
        v.triggerExited(); v.settingsOpen=true; failed=false; m.refresh(); wait(150);
        compare(v.visibilityState,"interacting");
        failed=true; m.refresh(); wait(150); compare(v.visibilityState,"interacting");
        v.resetSurface(); compare(v.visibilityState,"hidden");
    }
    function test_surface_consumer_disable_unmap_and_unload() {
        const m=createTemporaryObject(factory,test); attach(m);
        const c=Qt.createComponent("../../services/OverlapConsumer.qml");
        compare(c.status,Component.Ready,c.errorString());
        const consumer=c.createObject(test,{source:m,key:"owned",mapped:false,enabled:true});
        verify(!m.active); consumer.mapped=true; verify(m.active);
        consumer.enabled=false; verify(!m.active);
        consumer.enabled=true; verify(m.active);
        consumer.mapped=false; verify(!m.active);
        consumer.mapped=true; tryVerify(()=>requests>0);
        consumer.destroy(); tryVerify(()=>!m.active);
        const count=requests; wait(1100); compare(requests,count);
    }
    function test_failure_timeout_and_freshness_fallback() {
        const m=createTemporaryObject(factory,test); attach(m); m.setConsumer("one",true);
        const r=Qt.rect(0,600,500,80);
        tryVerify(()=>m.evaluate("owned",r).available);
        stalled=true; m.refresh();
        tryVerify(()=>m.busy);
        for (let i=0;i<20;i++) { m.refresh(); ownedBackend.rawEvent({name:"fullscreen"}); }
        const count=requests;
        wait(100); compare(requests,count,"No duplicate in flight");
        tryVerify(()=>!m.evaluate("owned",r).available,1000);
        verify(!m.busy,"Timed-out refresh must not wedge cadence");
        const stale=pending[0];
        m.complete(stale,true,world);
        verify(!m.evaluate("owned",r).available,"Timed-out generation cannot revive snapshots");
        stalled=false; failed=true; m.refresh();
        wait(150); verify(!m.evaluate("owned",r).available);
        failed=false; m.refresh(); tryVerify(()=>m.evaluate("owned",r).available);
        // Simulate suspended event-loop/wall-clock age, not a changed-signal ACK.
        m.sampledAt=Date.now()-2500;
        verify(!m.evaluate("owned",r).available,"Old snapshot uses ordinary fallback even before expiry timer fires");
    }
    function test_disable_unmap_cancels_pending_generation() {
        const m=createTemporaryObject(factory,test); attach(m);
        m.setConsumer("one",true); m.setConsumer("two",true);
        tryVerify(()=>requests===1);
        m.setConsumer("one",false); verify(m.active);
        stalled=true; m.refresh(); tryVerify(()=>m.busy);
        const stale=pending[0];
        m.setConsumer("two",false);
        verify(!m.active); verify(!m.busy); verify(!m.snapshot);
        const count=requests;
        m.complete(stale,true,world); m.refresh(); ownedBackend.rawEvent({name:"fullscreen"});
        wait(1100); compare(requests,count); verify(!m.snapshot);
        m.setConsumer("one",true); tryVerify(()=>m.busy);
        m.complete(stale,true,world); verify(!m.snapshot,"Old map generation rejected after re-enable");
        m.setConsumer("one",false);
    }
    function test_silent_move_eventual_convergence() {
        const m=createTemporaryObject(factory,test);
        verify(typeof m.setConsumer === "function", "Mapped opt-in consumers must own shared refresh lifetime");
        attach(m);
        m.setConsumer("one",true);
        m.setConsumer("two",true);
        const shelf=Qt.rect(0,600,500,80);
        tryVerify(()=>m.evaluate("owned",shelf).available);
        verify(!m.evaluate("owned",shelf).overlap);
        world={monitors:world.monitors,windows:[{workspace:1,monitor:"owned",mapped:true,hidden:false,pinned:false,fullscreen:false,x:0,y:600,width:100,height:100}]};
        tryVerify(()=>m.evaluate("owned",shelf).overlap,1500);
        world={monitors:world.monitors,windows:[]};
        tryVerify(()=>!m.evaluate("owned",shelf).overlap,1500);
        verify(requests<=4,"One cadence shared by two outputs");
    }
}
