pragma ComponentBehavior: Bound
import QtQuick

// Passive opening, deliberate card input. Never a Popup/Control or keyboard grab.
// Fixed hit geometry surrounds animated art; model revisions invalidate held presses.
Item {
    id: fan
    required property var windows
    property string appId: ""
    property var previewSources: ({})
    property string iconSource: ""
    property string appName: ""
    property bool opened: false
    property bool reducedMotion: false
    property real maximumWidth: 520
    property color backgroundColor: "#20232b"
    property color textColor: "#eef0f6"
    property color accentColor: "#a7c7ff"
    property int revision: 0
    property var renderedWindows: [] // Only retained for the 160ms noninteractive exit.
    property string renderedIcon: ""
    readonly property bool hovered: hover.hovered
    HoverHandler { id: hover; enabled: fan.opened }
    onWindowsChanged: { revision++; if (windows.length) renderedWindows = windows; }
    onIconSourceChanged: if (iconSource) renderedIcon = iconSource
    onAppIdChanged: revision++
    readonly property int capacity: Math.max(1, Math.min(4, Math.floor((maximumWidth - 16) / 112)))
    readonly property int visibleCount: Math.min(renderedWindows.length, capacity)
    readonly property bool overflow: renderedWindows.length > visibleCount
    readonly property real cardWidth: Math.min(106, Math.max(36, (maximumWidth - 16 - (overflow ? 54 : 0) - visibleCount * 6) / Math.max(1, visibleCount)))
    width: 16 + visibleCount * (cardWidth + 6) - 6 + (overflow ? 54 : 0)
    height: 92
    visible: opened || art.opacity > 0
    enabled: opened
    signal entered()
    signal exited()
    signal activateRequested(string key)
    signal moreRequested()
    function activate(key: string, pressRevision: int): void {
        if (opened && pressRevision === revision && windows.some(w => w.key === key)) activateRequested(key);
    }
    function clearImmediately(): void {
        fade.stop(); art.opacity = 0; art.scale = 0.97; lift.y = 6;
        renderedWindows = []; renderedIcon = "";
    }
    onOpenedChanged: {
        fade.stop();
        if (opened) { renderedWindows = windows; renderedIcon = iconSource; }
        if (reducedMotion) {
            art.opacity = opened ? 1 : 0;
            art.scale = 1; lift.y = 0;
            if (!opened) clearImmediately();
        }
        else fade.start();
    }
    onReducedMotionChanged: if (reducedMotion) {
        fade.stop(); art.opacity = opened ? 1 : 0;
        art.scale = 1; lift.y = 0;
        if (!opened) clearImmediately();
    }
    ParallelAnimation {
        id: fade
        NumberAnimation { target: art; property: "opacity"; to: fan.opened ? 1 : 0; duration: 160; easing.type: Easing.OutCubic }
        NumberAnimation { target: art; property: "scale"; to: fan.opened ? 1 : 0.97; duration: 160; easing.type: Easing.OutCubic }
        NumberAnimation { target: lift; property: "y"; to: fan.opened ? 0 : 6; duration: 160; easing.type: Easing.OutCubic }
        onFinished: if (!fan.opened) fan.clearImmediately()
    }
    Item {
        id: art
        anchors.fill: parent
        opacity: 0
        // Scenegraph properties only; no frame callbacks or idle timers.
        scale: 0.97
        transform: Translate { id: lift; y: 6 }
        Rectangle {
            anchors.fill: parent
            radius: 14
            color: Qt.rgba(fan.backgroundColor.r, fan.backgroundColor.g, fan.backgroundColor.b, 0.98)
            border.color: Qt.alpha(fan.textColor, .18)
        }
    }
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: fan.entered()
        onExited: fan.exited()
    }
    Row {
        x: 8; y: 7; spacing: 6
        opacity: art.opacity
        Repeater {
            model: fan.visibleCount
            delegate: Item {
                id: card
                required property int index
                readonly property var record: fan.renderedWindows[index] || ({})
                readonly property string windowKey: record.key || ""
                readonly property string title: typeof record.title === "string" && record.title.length ? record.title.slice(0,4096) : "Untitled window"
                objectName: "fan-window-" + windowKey
                width: fan.cardWidth; height: 78
                Accessible.role: Accessible.Button
                Accessible.name: title + (record.parked ? ", parked — restore" : record.active ? ", active" : "")
                Accessible.onPressAction: fan.activate(windowKey, fan.revision)
                Item {
                    anchors.fill: parent
                    scale: art.scale
                    transform: Translate { y: lift.y }
                Rectangle {
                    anchors.fill: parent; radius: 9
                    color: Qt.alpha(fan.accentColor, input.containsMouse ? .18 : card.record.active ? .09 : 0)
                    border.color: Qt.alpha(fan.accentColor, input.containsMouse ? .4 : 0)
                }
                Image {
                    id: icon
                    visible: thumbnail.status !== Image.Ready
                    y: 5; anchors.horizontalCenter: parent.horizontalCenter
                    width: 30; height: 30
                    source: fan.renderedIcon
                    fillMode: Image.PreserveAspectFit
                    sourceSize.width: 48; sourceSize.height: 48
                }
                Text {
                    visible: thumbnail.status !== Image.Ready && icon.status !== Image.Ready
                    y: 4; anchors.horizontalCenter: parent.horizontalCenter
                    text: "▣"; color: fan.accentColor; font.pixelSize: 28
                }
                Image {
                    id: thumbnail
                    objectName: "fan-preview-" + card.windowKey
                    y: 5; x: 5; width: parent.width - 10; height: 30
                    source: fan.opened ? (fan.previewSources[card.windowKey] || "") : ""
                    cache: false
                    visible: status === Image.Ready
                    fillMode: Image.PreserveAspectFit
                }
                Text {
                    objectName: "fan-title-" + card.windowKey
                    x: 5; y: 41; width: parent.width - 10
                    text: card.title; textFormat: Text.PlainText
                    elide: Text.ElideRight; maximumLineCount: 1
                    horizontalAlignment: Text.AlignHCenter
                    color: fan.textColor; font.pixelSize: 12
                }
                Text {
                    x: 5; y: 59; width: parent.width - 10
                    text: card.record.parked ? "Parked" : card.record.active ? "Active" : "Window"
                    textFormat: Text.PlainText; elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    color: Qt.alpha(fan.textColor, .62); font.pixelSize: 10
                }
                }
                MouseArea {
                    id: input
                    anchors.fill: parent; hoverEnabled: true
                    property string pressKey: ""
                    property int pressRevision: -1
                    onEntered: fan.entered()
                    onExited: fan.exited()
                    onPressed: { pressKey = card.windowKey; pressRevision = fan.revision; }
                    onClicked: if (pressKey === card.windowKey) fan.activate(pressKey, pressRevision)
                    onCanceled: { pressKey = ""; pressRevision = -1; }
                }
            }
        }
        Item {
            objectName: "fan-more"
            visible: fan.overflow
            width: visible ? 48 : 0; height: 78
            Accessible.role: Accessible.Button
            Accessible.name: "Show all " + fan.windows.length + " windows"
            Accessible.onPressAction: if (fan.opened) fan.moreRequested()
            Rectangle { anchors.fill: parent; radius: 9; color: Qt.alpha(fan.accentColor, moreInput.containsMouse ? .18 : .06) }
            Text { anchors.centerIn: parent; text: "•••\nMore"; textFormat: Text.PlainText; horizontalAlignment: Text.AlignHCenter; color: fan.textColor; font.pixelSize: 12 }
            MouseArea {
                id: moreInput
                anchors.fill: parent; hoverEnabled: true
                property int pressRevision: -1
                onEntered: fan.entered()
                onExited: fan.exited()
                onPressed: pressRevision = fan.revision
                onClicked: if (fan.opened && pressRevision === fan.revision) fan.moreRequested()
            }
        }
    }
}
