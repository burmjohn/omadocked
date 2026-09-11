import QtQuick
import QtQuick.Controls
import QtTest
import "../../ui"

TestCase {
    id: test
    name: "FanPreviews"
    when: windowShown
    visible: true
    width: 1400; height: 800
    Control { id: desktop; anchors.fill: parent; hoverEnabled: true }
    property int created: 0
    property int disposed: 0
    property int peak: 0
    property bool secondReady: true
    property bool failOnAttach: false
    property var view
    property var adapter
    QtObject { id: red; property color shade: "#dd2211" }
    QtObject { id: blue; property color shade: "#1144dd" }
    QtObject {
        id: controller
        property string previewLockState: "unlocked"
        property QtObject previewCaptureOwner: null
        property QtObject secondSource: blue
        function previewTarget(app, key) {
            if (app !== "app" && app !== "other") return null;
            return key === "b" ? secondSource : ["a","c","d","e","f"].indexOf(key)>=0 ? red : null;
        }
    }
    Component {
        id: driver
        Rectangle {
            property var captureSource: null
            property bool live: false
            property bool paintCursor: false
            property size constraintSize
            readonly property bool hasContent: !test.failOnAttach && captureSource !== null && (captureSource === red || test.secondReady)
            onCaptureSourceChanged: if (captureSource && test.failOnAttach && test.created === 1) stopped()
            signal stopped()
            color: captureSource ? captureSource.shade : "transparent"
            Component.onCompleted: { test.created++; test.peak=Math.max(test.peak,test.created-test.disposed); }
            Component.onDestruction: test.disposed++
        }
    }
    function makeView() {
        const c=Qt.createComponent("../../ui/DockView.qml");
        compare(c.status,Component.Ready,c.errorString());
        return createTemporaryObject(c,desktop,{availableWidth:1000,autoHide:false,appsManaged:true,
            applications:[{id:"app",name:"Owned",running:true},{id:"other",name:"Other",running:true}],
            windowGroups:{app:[{key:"a",title:"Owned A"},{key:"b",title:"Owned B"}],
                other:[{key:"a",title:"Owned A"},{key:"b",title:"Owned B"}]}});
    }
    function integrate(v) {
        const c=Qt.createComponent("../../services/PreviewIntegration.qml");
        compare(c.status,Component.Ready,c.errorString());
        return createTemporaryObject(c,test,{view:v,controller:controller,mapped:true,driverComponent:driver});
    }
    function init() {
        created=0; disposed=0; peak=0; secondReady=true; failOnAttach=false;
        controller.previewLockState="unlocked"; controller.secondSource=blue;
        view=makeView(); adapter=integrate(view);
        mouseMove(test,1300,700);
    }
    function cleanup() { if (adapter) adapter.mapped=false; view.resetSurface(); mouseMove(test,1300,700); }
    function hover(app) {
        mouseMove(view,view.renderedSlots[view.order.indexOf(app)].center,view.height-30);
        tryCompare(view,"fanApp",app,800);
    }
    function test_syncStopDoesNotSkipAnyCard() {
        failOnAttach=true;
        view.windowGroups={app:["a","b","c","d"].map(key=>({key:key,title:"Owned"}))};
        hover("app"); tryCompare(test,"created",2);
        compare(adapter.fanCapture.cursor,1);
        tryCompare(test,"disposed",4,4000);
        compare(created,4); compare(peak,1);
        compare(adapter.fanCapture.cursor,4);
        verify(adapter.fanCapture.sessions.every(s=>s.attempted));
    }
    function test_duplicateAndNonCurrentReceiptsCannotAdvance() {
        secondReady=false;
        view.windowGroups={app:["a","b","c","d"].map(key=>({key:key,title:"Owned"}))};
        hover("app"); tryCompare(test,"created",2);
        const cohort=adapter.fanCapture;
        const sessions=cohort.sessions.slice();
        compare(cohort.cursor,1);
        const url=sessions[0].stillSource.toString();
        sessions[0].failed(); sessions[0].failed();
        sessions[0].settled(); // Duplicate prior-card receipt.
        sessions[2].settled(); // Future card has not captured yet.
        compare(cohort.cursor,1);
        compare(sessions[0].stillSource.toString(),url);
        compare(Object.keys(cohort.sources).join(","),"a");
        secondReady=true;
        tryCompare(cohort,"cursor",4);
        compare(created,4); compare(disposed,4); compare(peak,1);
        for (const session of sessions) session.settled();
        compare(cohort.cursor,4);
        cohort.revoke();
        for (const session of sessions) session.settled(); // Revoked epoch, before deferred destruction.
        compare(cohort.cursor,0); compare(cohort.sessions.length,0);
        verify(sessions.every(s=>s.retainedImage===null && !s.driverActive));
        wait(100); compare(created,4);
    }
    function test_fourVisibleCardsOnlyAndParkedFallback_data() { return [{tag:"four",parked:false},{tag:"parked",parked:true}]; }
    function test_fourVisibleCardsOnlyAndParkedFallback(data) {
        view.windowGroups={app:["a","b","c","d","e","f"].map(key=>({key:key,title:"Owned",parked:key==="b" && data.parked}))};
        hover("app"); tryCompare(test,"disposed",data.parked?3:4);
        compare(created,data.parked?3:4); compare(peak,1);
        compare(adapter.fanCapture.sessions.length,data.parked?3:4);
        for (const session of adapter.fanCapture.sessions) {
            verify(session.stillSize.width<=96 && session.stillSize.height<=30);
            verify(!session.driverActive);
        }
        verify(view.fanPreviewSources.e === undefined);
        if (data.parked) compare(findChild(view,"fan-preview-b").source.toString(),"");
        wait(150); compare(created,data.parked?3:4);
    }
    function test_unknownAuthorityDoesNotAttachThenAutoRetry() {
        controller.previewLockState="unknown";
        hover("app"); wait(100); compare(created,0);
        controller.previewLockState="unlocked";
        wait(100); compare(created,0);
        view.dismissFan(true); mouseMove(test,1300,700); hover("app");
        tryCompare(test,"disposed",2);
    }
    function test_twoOverlappingFansKeepOnlyNewestCohort() {
        secondReady=false; hover("app"); tryCompare(test,"created",2);
        const second=makeView(); second.y=300;
        const b=integrate(second);
        second.fanApp="app"; // Owned overlapping-output opening; pointer test is separate.
        tryCompare(test,"created",4); compare(peak,1);
        compare(adapter.fanCapture.sessions.length,0);
        compare(Object.keys(view.fanPreviewSources).length,0);
        controller.previewLockState="unknown";
        compare(Object.keys(second.fanPreviewSources).length,0);
        compare(b.fanCapture.sessions.length,0);
        compare(created,disposed);
        second.resetSurface(); b.mapped=false;
    }
    function test_revokeClearsEveryStillAndDriver_data() {
        return ["unknown","locked","unmapped","suspended","disabled","regroup","source","close"].map(tag=>({tag:tag}));
    }
    function test_revokeClearsEveryStillAndDriver(data) {
        secondReady=false; hover("app"); tryCompare(test,"created",2);
        const sessions=adapter.fanCapture.sessions.slice();
        verify(sessions[0].retainedImage !== null);
        verify(sessions[1].driverActive);
        if (data.tag === "unknown" || data.tag === "locked") controller.previewLockState=data.tag;
        else if (data.tag === "unmapped") adapter.mapped=false;
        else if (data.tag === "suspended") view.surfaceSuspended=true;
        else if (data.tag === "disabled") view.previewsEnabled=false;
        else if (data.tag === "regroup") view.windowGroups={app:[{key:"a",title:"A"},{key:"c",title:"C"}]};
        else if (data.tag === "source") controller.secondSource=null;
        else view.dismissFan(false);
        compare(Object.keys(view.fanPreviewSources).length,0);
        compare(adapter.fanCapture.sessions.length,0);
        verify(sessions.every(s=>s.retainedImage===null && !s.driverActive));
        compare(disposed,created);
        secondReady=true; controller.previewLockState="unlocked"; controller.secondSource=blue;
        wait(150); compare(created,2,"No automatic re-arm after revoke");
    }
    function test_cancelInFlightReadbackRejectsLatePixels() {
        secondReady=false; hover("app"); tryCompare(test,"created",2);
        const second=adapter.fanCapture.sessions[1];
        secondReady=true; second.frameReady(); verify(second.freezing);
        view.dismissFan(false);
        compare(second.retainedImage,null); verify(!second.driverActive);
        wait(150); compare(Object.keys(view.fanPreviewSources).length,0); compare(created,2);
    }
    function test_actualSourceDestructionClearsEntireCohort() {
        const owned=Qt.createQmlObject('import QtQuick; QtObject { property color shade:"blue" }',test);
        controller.secondSource=owned;
        hover("app"); tryCompare(test,"disposed",2);
        owned.destroy(); wait(0);
        compare(Object.keys(view.fanPreviewSources).length,0);
        compare(adapter.fanCapture.sessions.length,0);
        wait(100); compare(created,2);
    }
    function test_twoOutputsAndChooserShareOneDriver() {
        secondReady=false; hover("app"); tryCompare(test,"created",2);
        const second=makeView(); second.y=300;
        const b=integrate(second);
        // A different output's explicit chooser supersedes this stalled fan.
        verify(second.openWindowChooser("app"));
        tryCompare(test,"created",3); compare(peak,1);
        compare(Object.keys(view.fanPreviewSources).length,0);
        compare(adapter.fanCapture.sessions.length,0);
        second.resetSurface(); b.mapped=false;
        wait(150); compare(created,3);
    }
    function test_timeoutDoesNotRetryOrDropPreviousStill() {
        secondReady=false; hover("app"); tryCompare(test,"created",2);
        tryCompare(test,"disposed",2,1600);
        compare(Object.keys(view.fanPreviewSources).join(","),"a");
        secondReady=true; wait(1100);
        compare(created,2); compare(Object.keys(view.fanPreviewSources).join(","),"a");
    }
    function test_cardMotionAndTitleRefreshDoNotPulseOrRecapture() {
        hover("app"); tryCompare(test,"disposed",2); wait(180);
        const h=view.height, rect=view.fanRect;
        const bridge=view.fanBridgeRect;
        mouseMove(view,bridge.x+bridge.width/2,bridge.y+bridge.height/2);
        const card=findChild(view,"fan-window-a");
        mouseMove(card,card.width/2,card.height/2);
        for (let i=0;i<12;i++) {
            mouseMove(card,card.width/2+i%2,card.height/2,25);
            verify(view.fanOpen); compare(view.height,h); compare(view.fanRect,rect);
        }
        view.windowGroups={app:[{key:"a",title:"Changed"},{key:"b",title:"B"}]};
        wait(100); compare(created,2); compare(Object.keys(view.fanPreviewSources).length,2);
        mouseMove(view,view.renderedSlots[view.order.indexOf("other")].center,view.height-30);
        compare(view.fanOpen,false); compare(Object.keys(view.fanPreviewSources).length,0);
        mouseMove(view,view.renderedSlots[view.order.indexOf("app")].center,view.height-30);
        wait(100); compare(view.fanOpen,false); compare(created,2);
        tryCompare(view,"fanApp","app",800); tryCompare(test,"disposed",4); compare(peak,1);
    }
    function test_adapterUnloadClearsRetainedMemorySynchronously() {
        hover("app"); tryCompare(test,"disposed",2);
        const cohort=adapter.fanCapture;
        const sessions=cohort.sessions.slice();
        verify(sessions.every(s => s.retainedImage !== null));
        adapter.destroy(); wait(0);
        compare(Object.keys(view.fanPreviewSources).length,0);
        verify(controller.previewCaptureOwner === null);
    }
    function test_distinctBoundedPixelsRemainWhileNextCaptures() {
        secondReady=false;
        hover("app");
        tryCompare(test,"created",2,1500);
        compare(peak,1);
        const first=findChild(view,"fan-preview-a");
        verify(first!==null);
        tryCompare(first,"status",Image.Ready);
        wait(180);
        const p=first.mapToItem(test,first.width/2,first.height/2);
        const whole=grabImage(test);
        compare(whole.red(p.x,p.y),0xdd,"Visible fan paints the retained red still");
        compare(whole.blue(p.x,p.y),0x11);
        const probe=Qt.createQmlObject('import QtQuick; Image { width:96; height:30; y:400; cache:false }',test);
        probe.source=first.source; tryCompare(probe,"status",Image.Ready); wait(50);
        const image=grabImage(probe);
        compare(image.red(first.width/2,first.height/2),0xdd);
        compare(image.blue(first.width/2,first.height/2),0x11);
        compare(disposed,1,"First still retained during second native attempt");
        secondReady=true;
        tryCompare(test,"disposed",2);
        const second=findChild(view,"fan-preview-b");
        tryCompare(second,"status",Image.Ready);
        probe.source=second.source; tryCompare(probe,"status",Image.Ready); wait(50);
        const other=grabImage(probe);
        probe.destroy();
        compare(other.red(second.width/2,second.height/2),0x11);
        compare(other.blue(second.width/2,second.height/2),0xdd);
        const q=second.mapToItem(test,second.width/2,second.height/2);
        const both=grabImage(test);
        compare(both.red(p.x,p.y),0xdd);
        compare(both.blue(p.x,p.y),0x11);
        compare(both.red(q.x,q.y),0x11);
        compare(both.blue(q.x,q.y),0xdd);
        compare(first.status,Image.Ready);
        verify(first.sourceSize.width<=320 && first.sourceSize.height<=240);
        wait(200); compare(created,2);
        view.dismissFan(false);
        compare(first.source.toString(),"");
        compare(second.source.toString(),"");
    }
}
