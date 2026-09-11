import QtQuick
import Quickshell.Wayland

// The installed API starts one frame when a source is attached with live=false.
// PreviewSession owns eligibility, timeout and disposal. constraintSize bounds
// presentation, not transient native buffers; retained readback is bounded there.
Item {
    id: root
    property QtObject captureSource: null
    property alias live: capture.live
    property alias paintCursor: capture.paintCursor
    property size constraintSize: Qt.size(width, height)
    readonly property bool hasContent: capture.hasContent
    readonly property size sourceSize: capture.sourceSize
    signal stopped()
    ScreencopyView {
        id: capture
        anchors.centerIn: parent
        constraintSize: root.constraintSize
        // Do not anchor-fill the native item: its implicit size preserves aspect.
        width: implicitWidth
        height: implicitHeight
        captureSource: root.captureSource
        live: false
        paintCursor: false
        onStopped: root.stopped()
    }
}
