pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "../core/PreviewLogic.js" as Preview

// Disposable presentation only. The backend owns membership and close acknowledgement.
Item {
    id: chooser
    required property var windows
    property bool previewsEnabled: true
    property Component previewComponent
    readonly property string previewKey: hasKey(selectionKey) ? selectionKey : ""
    readonly property var groupCard: Preview.buildCards("all", windows.map(w => ({
        key:w.key, appId:"group", title:typeof w.title === "string" ? w.title.slice(0,4096) : "",
        parkedAt:typeof w.sequence === "number" ? w.sequence : 0
    })))[0] || {count:1, titleSummary:"Untitled window"}
    property color textColor: "#eef0f6"
    property color accentColor: "#a7c7ff"
    signal activateRequested(string key)
    signal closeRequested(string key)
    signal dismissRequested()
    signal backRequested()
    signal cycleRequested(int delta)
    property string selectionKey: ""
    property int focusPart: 0 // activation, Close, Back, Previous, Next
    property int modelRevision: 0
    onHeightChanged: if (list && Array.isArray(windows)) { list.forceLayout(); revealSelection(); }
    function revealSelection(): void {
        const index = windows.findIndex(window => window.key === selectionKey);
        list.currentIndex = index;
        if (index >= 0) list.positionViewAtIndex(index, ListView.Contain);
    }
    onWindowsChanged: {
        modelRevision++;
        if (selectionKey && !hasKey(selectionKey)) selectionKey = "";
        list.forceLayout();
        revealSelection();
    }
    onSelectionKeyChanged: revealSelection()
    Component.onCompleted: {
        const active = windows.find(window => window.active);
        selectionKey = active ? active.key : windows.length ? windows[0].key : "";
        revealSelection();
    }
    function handleKey(key: int, modifiers: int): void {
        if (key === Qt.Key_Escape) { dismissRequested(); return; }
        if (key === Qt.Key_Back || key === Qt.Key_Backspace || key === Qt.Key_Left) { backRequested(); return; }
        if (key === Qt.Key_Down || key === Qt.Key_Up) {
            const index = windows.findIndex(window => window.key === selectionKey);
            const delta = key === Qt.Key_Down ? 1 : -1;
            selectionKey = windows.length ? windows[index < 0 ? (delta > 0 ? 0 : windows.length - 1)
                : (index + delta + windows.length) % windows.length].key : "";
            focusPart = 0;
        } else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
            const backwards = key === Qt.Key_Backtab || (modifiers & Qt.ShiftModifier);
            focusPart = (focusPart + (backwards ? 4 : 1)) % 5;
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            if (focusPart === 2) { backRequested(); return; }
            if (focusPart >= 3) { cycleRequested(focusPart === 3 ? -1 : 1); return; }
            if (!hasKey(selectionKey)) return;
            if (focusPart === 1) closeRequested(selectionKey);
            else activateRequested(selectionKey);
        }
    }
    // Wheel selects, never activates. A top-stacked wheel-only surface keeps
    // nested buttons/ListView from scrolling independently of the selection.
    Item {
        anchors.fill: parent
        z: 20
        WheelHandler {
            target: null
            onWheel: event => {
                const delta = event.angleDelta.y || event.pixelDelta.y;
                if (delta) {
                    chooser.modelRevision++; // cancel any held row press
                    chooser.handleKey(delta < 0 ? Qt.Key_Down : Qt.Key_Up, Qt.NoModifier);
                }
                event.accepted = true;
            }
        }
    }
    function hasKey(key: string): bool { return windows.some(window => window.key === key); }
    component WindowButton: Button {
        id: control
        property bool chosen: false
        focusPolicy: Qt.NoFocus
        background: Rectangle {
            radius: 7
            color: Qt.alpha(chooser.accentColor, control.hovered ? 0.16 : 0.05)
            border.width: control.chosen ? 2 : 1
            border.color: Qt.alpha(chooser.accentColor, control.chosen ? 1 : 0.2)
        }
        contentItem: Text {
            text: control.text; textFormat: Text.PlainText; elide: Text.ElideRight
            color: chooser.textColor; font.pixelSize: 13
            verticalAlignment: Text.AlignVCenter
            leftPadding: 10; rightPadding: 10
        }
        Accessible.name: text
    }
    component ExactWindowButton: WindowButton {
        required property string windowKey
        property string pressedKey: ""
        property int pressedRevision: -1
        signal requested(string key)
        onWindowKeyChanged: chooser.modelRevision++
        onPressed: { pressedKey = windowKey; pressedRevision = chooser.modelRevision; }
        onClicked: {
            if (pressedRevision === chooser.modelRevision && pressedKey === windowKey
                    && chooser.hasKey(pressedKey)) requested(pressedKey);
            pressedKey = ""; pressedRevision = -1;
        }
        Accessible.onPressAction: if (chooser.hasKey(windowKey)) requested(windowKey)
    }
    Row {
        spacing: 6
        width: parent.width
        WindowButton {
            objectName: "windows-back"; text: "Back"; width: (chooser.width - 12) / 3; height: 32
            chosen: chooser.focusPart === 2
            Accessible.name: "Back to application actions"
            onClicked: chooser.backRequested()
        }
        WindowButton {
            objectName: "windows-previous"; text: "Previous"; width: (chooser.width - 12) / 3; height: 32
            chosen: chooser.focusPart === 3
            Accessible.name: "Previous window"
            onClicked: chooser.cycleRequested(-1)
        }
        WindowButton {
            objectName: "windows-next"; text: "Next"; width: (chooser.width - 12) / 3; height: 32
            chosen: chooser.focusPart === 4
            Accessible.name: "Next window"
            onClicked: chooser.cycleRequested(1)
        }
    }
    Loader {
        id: previewLoader
        active: chooser.previewsEnabled
        x: 0; y: 44; width: chooser.width; height: 160
        sourceComponent: PreviewCard {
            objectName: "window-preview-card"
            requestedWidth: chooser.width
            requestedHeight: 160
            card: chooser.groupCard
            contentComponent: chooser.previewComponent
        }
    }
    ListView {
        id: list
        objectName: "window-list"
        anchors.fill: parent
        anchors.topMargin: chooser.previewsEnabled ? 212 : 44
        clip: true
        spacing: 6
        model: chooser.windows
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }
        delegate: Item {
            id: row
            required property var modelData
            width: list.width - 12; height: 42
            readonly property string windowKey: modelData.key
            readonly property string title: typeof modelData.title === "string" && modelData.title.trim() ? modelData.title : "Untitled window"
            ExactWindowButton {
                windowKey: row.windowKey
                id: activate
                objectName: "window-activate-" + row.windowKey
                width: parent.width - 76; height: parent.height
                chosen: chooser.selectionKey === row.windowKey && chooser.focusPart === 0
                text: row.title
                // Hover changes selection, not just decoration: do not inherit
                // a platform theme's optional hover-effects default.
                hoverEnabled: true
                Accessible.name: "Activate window: " + row.title + (row.modelData.active ? ", active" : "")
                onHoveredChanged: if (hovered && chooser.hasKey(row.windowKey)) chooser.selectionKey = row.windowKey
                onRequested: key => chooser.activateRequested(key)
                Rectangle {
                    objectName: "window-active-" + row.windowKey
                    width: 3; height: 20; radius: 2
                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                    color: chooser.accentColor; visible: !!row.modelData.active
                }
            }
            ExactWindowButton {
                windowKey: row.windowKey
                objectName: "window-close-" + row.windowKey
                anchors.right: parent.right
                width: 70; height: parent.height; text: "Close"
                chosen: chooser.selectionKey === row.windowKey && chooser.focusPart === 1
                Accessible.name: "Close window: " + row.title
                onRequested: key => chooser.closeRequested(key)
            }
        }
        Component.onCompleted: forceLayout()
    }
}
