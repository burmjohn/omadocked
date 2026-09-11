import QtQuick

// One finite, disposable visual acknowledgement of a real pending request.
// Token consumption prevents replay after hide/reduced-motion/preference return.
Item {
    id: root
    visible: false
    enabled: false
    property int requestToken: 0
    property bool pending: false
    property bool allowed: true
    property real amplitude: 8
    property real offset: 0
    property int _consumed: 0
    readonly property bool animating: bounce.running
    function cancel() { bounce.stop(); offset = 0; }
    function reconcile() {
        if (!pending || !allowed) cancel();
        if (requestToken <= 0 || requestToken === _consumed) return;
        _consumed = requestToken;
        cancel();
        if (pending && allowed) bounce.start();
    }
    onRequestTokenChanged: Qt.callLater(reconcile)
    onPendingChanged: { if (!pending) cancel(); Qt.callLater(reconcile); }
    onAllowedChanged: { if (!allowed) cancel(); Qt.callLater(reconcile); }
    Component.onCompleted: reconcile()
    Component.onDestruction: cancel()
    property SequentialAnimation _bounce: SequentialAnimation {
        id: bounce
        loops: 3
        NumberAnimation { target: root; property: "offset"; from: 0; to: -1; duration: 200; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "offset"; from: -1; to: 0; duration: 220; easing.type: Easing.OutBounce }
        PauseAnimation { duration: 140 }
    }
}
