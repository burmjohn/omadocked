import QtQuick

// Fixed geometry avoids disturbing the magnification/hit-test coordinate system.
Rectangle {
    id: root
    property bool attention: false
    property bool presentationEnabled: false
    property bool reducedMotion: false
    property color accent: "#a7c7ff"
    property bool _ready: false
    readonly property bool animating: pulse.running
    implicitWidth: 7
    implicitHeight: 7
    width: implicitWidth
    height: implicitHeight
    visible: attention && presentationEnabled && pulse.running
    color: accent
    border.width: 0
    radius: Math.min(width, height) / 2
    opacity: 1
    onAttentionChanged: {
        pulse.stop();
        opacity = 1;
        if (_ready && attention && presentationEnabled && !reducedMotion)
            pulse.start();
    }
    onPresentationEnabledChanged: if (!presentationEnabled) {
        pulse.stop();
        opacity = 1;
    }
    onReducedMotionChanged: if (reducedMotion) {
        pulse.stop();
        opacity = 1;
    }
    Component.onCompleted: _ready = true
    Component.onDestruction: pulse.stop()
    SequentialAnimation {
        id: pulse
        loops: 3
        NumberAnimation {
            target: root
            property: "opacity"
            from: 1
            to: 0.3
            duration: 180
        }
        NumberAnimation {
            target: root
            property: "opacity"
            from: 0.3
            to: 1
            duration: 180
        }
    }
}
