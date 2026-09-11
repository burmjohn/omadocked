pragma ComponentBehavior: Bound
import QtQuick
import "../core/PreviewLogic.js" as Preview

// One disposable capture generation. No URLs/files enter persistence or IPC.
Item {
    id: session
    property Component driverComponent
    // Typed QObject ownership emits sourceChanged on actual destruction, even
    // after the still's capture driver has gone away.
    property QtObject source: null
    property string identitySignature: ""
    property bool permitted: false
    // Retention permission is independent of the shared native capture lease.
    property bool captureEnabled: true
    property bool attempted: false
    property bool settlementSent: false
    signal settled()
    property bool allowLive: false
    property int generation: 0
    property var captureState: null
    property var retainedImage: null
    property bool freezing: false
    property bool completed: false
    readonly property string status: !captureState ? "unavailable" : captureState.hasStill ? "ready"
        : captureState.terminal ? "unavailable" : "capturing"
    readonly property bool hasContent: status === "ready"
    readonly property url stillSource: retainedImage ? retainedImage.url : ""
    readonly property size stillSize: Qt.size(still.implicitWidth, still.implicitHeight)
    readonly property bool driverActive: driver.active
    readonly property var captureDriver: driver.item
    function invalidate(): void {
        generation++;
        deadline.stop();
        driver.active = false;
        retainedImage = null;
        freezing = false;
        captureState = null;
        settlementSent = false;
    }
    function restart(): void {
        if (!completed) return;
        invalidate();
        attempted = false;
        // Invalidate synchronously; coalesce dependent source/key bindings before
        // attaching a new native source. This is an event task, not a retry timer.
        Qt.callLater(startCapture);
    }
    function startCapture(): void {
        if (attempted || captureState || driver.active || !captureEnabled || !permitted || !visible || !source || !identitySignature || !driverComponent) return;
        attempted = true;
        captureState = Preview.newCapture(identitySignature, {captureToken:"preview", generation:generation,
            maxAttempts:1, allowLive:allowLive});
        const token = generation;
        driver.active = true;
        // Loader attachment can synchronously stop and settle this attempt.
        if (token === generation && captureState && !settlementSent && driver.active) deadline.start();
    }
    function event(type: string): void {
        if (!captureState) return;
        captureState = Preview.reduceCapture(captureState, {type:type, captureToken:"preview",
            generation:generation, identitySignature:identitySignature});
    }
    function failed(): void {
        if (!captureState || (settlementSent && !allowLive)) return;
        const notify = !settlementSent;
        settlementSent = true;
        generation++;
        deadline.stop();
        // Even a stopped live stream must discard its old pixels.
        retainedImage = null;
        captureState = null;
        driver.active = false;
        freezing = false;
        if (notify) settled();
    }
    function frameReady(): void {
        if (!captureDriver || !captureDriver.hasContent || freezing || !captureState || captureState.hasStill) return;
        freezing = true;
        const token = generation;
        const ownedDriver = driver.item;
        const size = Qt.size(Math.max(1, Math.min(320, Math.ceil(width))), Math.max(1, Math.min(240, Math.ceil(height))));
        if (!ownedDriver.grabToImage(function(result) {
            if (token !== session.generation || !session.permitted || !session.visible || !session.captureState) return;
            if (!result || !result.url.toString()) { session.failed(); return; }
            session.retainedImage = result;
            session.event("capture-ready");
            session.deadlineStop();
            // Mark terminal before driver disposal or receipt handlers can reenter.
            session.settlementSent = true;
            if (session.allowLive) {
                session.captureState = Preview.reduceCapture(session.captureState, {type:"popup-visible", visible:true});
                if (driver.item === ownedDriver) ownedDriver.live = session.captureState.live;
            } else driver.active = false;
            session.settled();
        }, size)) failed();
    }
    function deadlineStop(): void { deadline.stop(); }
    onSourceChanged: restart()
    onIdentitySignatureChanged: restart()
    onPermittedChanged: restart()
    onCaptureEnabledChanged: {
        if (!captureEnabled && driver.active) {
            if (hasContent) { deadline.stop(); driver.active = false; }
            else failed();
        } else if (captureEnabled) Qt.callLater(startCapture);
    }
    onAllowLiveChanged: restart()
    onDriverComponentChanged: restart()
    onVisibleChanged: restart()
    Component.onCompleted: { completed = true; restart(); }
    Component.onDestruction: invalidate()
    Timer { id: deadline; interval: 1000; repeat: false; onTriggered: session.failed() }
    Image {
        id: still
        anchors.fill: parent
        source: session.stillSource
        cache: false
        fillMode: Image.PreserveAspectFit
        visible: session.hasContent && !session.allowLive
    }
    Loader {
        id: driver
        anchors.fill: parent
        active: false
        sourceComponent: session.driverComponent
        onLoaded: {
            item.live = false;
            item.paintCursor = false;
            item.constraintSize = Qt.binding(function() { return Qt.size(session.width, session.height); });
            item.captureSource = session.source;
            Qt.callLater(session.frameReady);
        }
    }
    Connections {
        target: driver.item
        function onHasContentChanged() {
            // Native context stop clears content without emitting stopped().
            if (driver.item && !driver.item.hasContent && (session.freezing || session.hasContent))
                session.failed();
            else Qt.callLater(session.frameReady);
        }
        function onStopped() { session.failed(); }
    }
}
