pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// Disposable plain-text presentation; only exact action IDs leave this component.
Item {
    id: chooser
    required property var actions
    property color textColor: "#eef0f6"
    property color accentColor: "#a7c7ff"
    property bool pending: false
    property string selectionId: ""
    property bool backFocused: false
    property int modelRevision: 0
    function revealSelection(): void {
        const index = actions.findIndex(action => action.id === selectionId);
        list.currentIndex = index;
        if (index >= 0) list.positionViewAtIndex(index, ListView.Contain);
    }
    onSelectionIdChanged: revealSelection()
    onActionsChanged: {
        modelRevision++;
        if (selectionId && !actions.some(action => action.id === selectionId)) selectionId = "";
        list.forceLayout();
        revealSelection();
    }
    function handleKey(key: int, modifiers: int): void {
        if (key === Qt.Key_Escape) { dismissRequested(); return; }
        if (key === Qt.Key_Back || key === Qt.Key_Backspace || key === Qt.Key_Left) { backRequested(); return; }
        if (key === Qt.Key_Up || key === Qt.Key_Down) {
            const index = actions.findIndex(action => action.id === selectionId);
            const delta = key === Qt.Key_Down ? 1 : -1;
            selectionId = actions.length ? actions[index < 0 ? (delta > 0 ? 0 : actions.length - 1)
                : (index + delta + actions.length) % actions.length].id : "";
            backFocused = false;
        } else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
            backFocused = !backFocused;
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            if (backFocused) backRequested();
            else if (!pending && actions.some(action => action.id === selectionId)) activateRequested(selectionId);
        }
    }
    signal activateRequested(string actionId)
    signal dismissRequested()
    signal backRequested()
    Component.onCompleted: selectionId = actions.length ? actions[0].id : ""
    component ActionButton: Button {
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
        opacity: enabled ? 1 : 0.5
        Accessible.name: text
    }
    ActionButton {
        objectName: "desktop-actions-back"; text: "Back"; width: chooser.width; height: 32
        Accessible.name: "Back to application menu"
        chosen: chooser.backFocused
        onClicked: chooser.backRequested()
    }
    ListView {
        id: list
        objectName: "desktop-action-list"
        anchors.fill: parent; anchors.topMargin: 44
        clip: true; spacing: 6
        model: chooser.actions
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { }
        delegate: ActionButton {
            id: row
            required property var modelData
            readonly property string actionId: modelData.id
            property string pressedActionId: ""
            property int pressedRevision: -1
            objectName: "desktop-action-" + actionId
            width: list.width - 12; height: 36
            text: modelData.name
            chosen: chooser.selectionId === actionId && !chooser.backFocused
            enabled: !chooser.pending
            Accessible.name: "App action: " + text
            Accessible.onPressAction: if (row.enabled && row.visible && chooser.actions.some(action => action.id === row.actionId)) chooser.activateRequested(row.actionId)
            onPressed: { pressedActionId = actionId; pressedRevision = chooser.modelRevision; }
            onClicked: {
                if (pressedRevision === chooser.modelRevision && pressedActionId === actionId
                    && chooser.actions.some(action => action.id === pressedActionId)) chooser.activateRequested(pressedActionId);
                pressedActionId = "";
            }
        }
        Component.onCompleted: forceLayout()
    }
}
