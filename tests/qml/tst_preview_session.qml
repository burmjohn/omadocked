import QtQuick
import QtTest

TestCase {
    id: test
    name: "PreviewSession"
    when: windowShown
    visible: true
    width: 400; height: 300
    property int created: 0
    property int disposed: 0
    property bool stopOnAttach: false
    function cleanup() { stopOnAttach=false; }
    SignalSpy { id: settlements; signalName: "settled" }
    QtObject { id: ownedSource }
    // Owned synthetic pixels, not a simulated successful native capture.
    Component {
        id: ownedDriver
        Rectangle {
            property var captureSource: null
            property bool live: false
            property bool paintCursor: false
            property size constraintSize
            readonly property bool hasContent: captureSource !== null
            signal stopped()
            color: "#22cc66"
            Component.onCompleted: test.created++
            Component.onDestruction: test.disposed++
        }
    }
    function makeSession() {
        const component = Qt.createComponent("../../services/PreviewSession.qml");
        compare(component.status, Component.Ready, component.errorString());
        return createTemporaryObject(component, test, {width:280, height:160,
            driverComponent:ownedDriver, source:ownedSource, identitySignature:"owned-a", permitted:true});
    }
    Component {
        id: stalledDriver
        Item {
            property var captureSource: null
            property bool live: false
            property bool paintCursor: false
            property size constraintSize
            property bool hasContent: false
            onCaptureSourceChanged: if (captureSource && test.stopOnAttach) stopped()
            signal stopped()
            Component.onCompleted: test.created++
            Component.onDestruction: test.disposed++
        }
    }
    function test_syncStopSettlesOnceWithoutRearmingDeadline() {
        created=0; disposed=0; stopOnAttach=true;
        const component=Qt.createComponent("../../services/PreviewSession.qml");
        const session=createTemporaryObject(component,test,{width:96,height:30,driverComponent:stalledDriver,
            source:ownedSource,identitySignature:"sync-stop",permitted:true});
        settlements.target=session; settlements.clear();
        tryCompare(test,"disposed",1);
        compare(settlements.count,1);
        wait(1150);
        compare(settlements.count,1);
        compare(created,1); compare(disposed,1);
    }
    function test_successThenLateFailureSettlesOncePerGeneration() {
        created=0; disposed=0;
        const session=makeSession();
        settlements.target=session; settlements.clear();
        tryCompare(session,"status","ready");
        compare(settlements.count,1);
        const url=session.stillSource.toString();
        session.failed(); // Same entry point as stopped and deadline delivery.
        session.failed();
        wait(1150);
        compare(settlements.count,1);
        compare(session.stillSource.toString(),url);
        session.source=null;
        compare(session.retainedImage,null);
        session.source=ownedSource;
        session.identitySignature="replacement";
        tryCompare(session,"status","ready");
        compare(settlements.count,2);
        compare(created,2); compare(disposed,2);
        session.permitted=false;
        compare(session.retainedImage,null);
    }
    function test_liveStopAfterSuccessDisposesWithoutSecondSettlement() {
        const session=makeSession(); session.allowLive=true;
        settlements.target=session; settlements.clear();
        tryCompare(session,"status","ready");
        compare(settlements.count,1);
        session.captureDriver.stopped();
        compare(session.retainedImage,null); verify(!session.driverActive);
        compare(settlements.count,1);
    }
    function test_captureOwnershipReleaseRetainsStillUntilPermissionRevoked() {
        created=0; disposed=0;
        const session=makeSession();
        tryCompare(session,"status","ready");
        verify(session.hasOwnProperty("captureEnabled"), "Capture lease must be separate from retention permission");
        session.captureEnabled=false;
        compare(session.status,"ready");
        verify(session.retainedImage !== null);
        const image=grabImage(session);
        compare(image.green(40,40),0xcc);
        session.captureEnabled=true;
        wait(100); compare(created,1,"Lease changes cannot retry a consumed attempt");
        session.permitted=false;
        compare(session.retainedImage,null);
        compare(session.stillSource.toString(),"");
    }
    function test_stalledCaptureHasSingleDeadlineAndNoRetry() {
        created=0; disposed=0;
        const component=Qt.createComponent("../../services/PreviewSession.qml");
        const session=createTemporaryObject(component,test,{width:280,height:160,driverComponent:stalledDriver,
            source:ownedSource,identitySignature:"stalled",permitted:true});
        tryCompare(session,"driverActive",true);
        compare(session.status,"capturing");
        tryCompare(session,"status","unavailable",2000);
        tryCompare(test,"disposed",1);
        compare(created,1);
        wait(1100);
        compare(created,1);
        verify(!session.driverActive);
        compare(session.stillSource.toString(),"");
    }
    function test_liveStopsOnSourceLossAndNeverRestartsHidden() {
        created=0; disposed=0;
        const session=makeSession();
        session.allowLive=true;
        tryCompare(session,"status","ready");
        verify(session.driverActive);
        verify(session.captureState.live);
        const before=created;
        session.source=null;
        compare(session.status,"unavailable");
        compare(session.stillSource.toString(),"");
        tryCompare(test,"disposed",before);
        session.visible=false;
        session.source=ownedSource;
        wait(100);
        compare(created,before);
    }
    function test_sameTurnSourceAndIdentityChangesCoalesceCapture() {
        created=0; disposed=0;
        const session=makeSession();
        tryCompare(session,"status","ready");
        const other=Qt.createQmlObject('import QtQuick; QtObject {}',test);
        session.source=other;
        session.identitySignature="new-generation";
        session.source=ownedSource;
        tryCompare(session,"status","ready");
        compare(created,2,"One new capture after dependent bindings settle, not three");
        other.destroy();
    }
    function test_ownedRepeatedLifecycleBalancesDriverObjects() {
        created=0; disposed=0;
        for (let i=0; i<20; ++i) {
            const session=makeSession();
            tryCompare(session,"status","ready");
            session.permitted=false;
            compare(session.stillSource.toString(),"");
            session.destroy();
            tryCompare(test,"disposed",i+1);
        }
        compare(created,20);
    }
    function test_destroyDuringReadbackDoesNotRetainOrResurrectDriver() {
        created=0; disposed=0;
        const session=makeSession();
        session.startCapture();
        session.frameReady();
        verify(session.freezing);
        verify(!session.hasContent);
        session.destroy();
        wait(150);
        compare(disposed,created);
    }
    function test_actualSourceDestructionClearsStill() {
        const source=Qt.createQmlObject('import QtQuick; QtObject {}',test);
        const component=Qt.createComponent("../../services/PreviewSession.qml");
        const session=createTemporaryObject(component,test,{width:280,height:160,
            driverComponent:ownedDriver,source:source,identitySignature:"destroyed",permitted:true});
        tryCompare(session,"status","ready"); source.destroy();
        tryCompare(session,"status","unavailable");
        compare(session.stillSource.toString(),""); verify(!session.driverActive);
    }
    function test_actualSourceDestructionDuringReadback() {
        const source=Qt.createQmlObject('import QtQuick; QtObject {}',test);
        const component=Qt.createComponent("../../services/PreviewSession.qml");
        const session=createTemporaryObject(component,test,{width:280,height:160,
            driverComponent:ownedDriver,source:source,identitySignature:"destroyed",permitted:true});
        session.startCapture(); session.frameReady(); verify(session.freezing);
        source.destroy(); wait(150);
        compare(session.status,"unavailable"); compare(session.stillSource.toString(),"");
    }
    function test_contentLossWithoutStoppedDropsLivePixels() {
        const session=makeSession(); session.allowLive=true;
        tryCompare(session,"status","ready");
        const before=created;
        session.captureDriver.captureSource=null;
        compare(session.status,"unavailable");
        compare(session.stillSource.toString(),"");
        verify(!session.driverActive);
        wait(100); compare(created,before);
    }
    function test_contentLossRejectsInFlightReadback() {
        const session=makeSession();
        session.startCapture(); session.frameReady(); verify(session.freezing);
        session.captureDriver.captureSource=null;
        wait(150);
        compare(session.status,"unavailable"); compare(session.stillSource.toString(),"");
        verify(!session.driverActive);
    }
    function test_stoppedLiveStreamDropsPixelsWithoutRetry() {
        const session=makeSession();
        session.allowLive=true;
        tryCompare(session,"status","ready");
        const before=created;
        session.captureDriver.stopped();
        compare(session.stillSource.toString(),"");
        verify(!session.driverActive);
        wait(100);
        compare(created,before);
    }
    function test_generationChangeDropsAnInFlightOwnedReadback() {
        const session=makeSession();
        const first=session.generation;
        session.identitySignature="replacement";
        verify(session.generation>first);
        session.permitted=false;
        wait(150);
        compare(session.stillSource.toString(),"");
        verify(!session.driverActive);
        compare(session.captureState,null);
    }
    function test_oversizedOwnedReadbackRetainsAtMost320By240() {
        const session=makeSession();
        session.width=1280; session.height=960;
        tryCompare(session,"status","ready");
        compare(session.stillSize,Qt.size(320,240));
        verify(!session.driverActive);
        const image=grabImage(session);
        compare(image.red(40,40),0x22);
        compare(image.green(40,40),0xcc);
        compare(image.blue(40,40),0x66);
        session.visible=false;
        compare(session.stillSource.toString(),"");
    }
    function test_ownedStillIsScaledAndNativeDriverDisposed() {
        created = 0; disposed = 0;
        const session = makeSession();
        verify(session);
        tryCompare(session, "status", "ready");
        verify(session.stillSource.toString().length > 0);
        compare(session.stillSize, Qt.size(280,160));
        tryCompare(test, "disposed", 1);
        compare(created, 1);
        const image=grabImage(session); // Owned offscreen fixture pixels only.
        compare(image.red(40,40),0x22);
        compare(image.green(40,40),0xcc);
        compare(image.blue(40,40),0x66);
        session.permitted = false;
        compare(session.stillSource.toString(), "");
        compare(session.status, "unavailable");
        wait(100);
        compare(created, 1);
    }
}
