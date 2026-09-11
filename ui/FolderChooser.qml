pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// Private names and metadata live only as long as the owning stack Loader.
Item {
    id: chooser
    property var result: ({})
    property bool busy: false
    property int generation: 0
    property color textColor: "#eef0f6"
    property color accentColor: "#a7c7ff"
    readonly property var entries: result.entries || []
    property string selectionPath: ""
    property int revision: 0
    property int focusPart: 0
    signal actionRequested(string kind, string path, int generation)
    signal dismissRequested()
    signal refreshRequested()
    onEntriesChanged: {
        ++revision;
        if (!entries.some(e => e.path === selectionPath)) selectionPath = "";
    }
    onGenerationChanged: { ++revision; selectionPath = ""; }
    function choose(kind: string, path: string): void {
        if (busy) return;
        if (kind === "entry" && !entries.some(e => e.path === path && (e.type === "file" || e.type === "directory"))) return;
        actionRequested(kind, path, generation);
    }
    function handleKey(key: int, modifiers: int): void {
        if (key === Qt.Key_Escape) { dismissRequested(); return; }
        if (key === Qt.Key_Down || key === Qt.Key_Up) {
            if (!entries.length) return;
            const index = entries.findIndex(e => e.path === selectionPath);
            const next = (index + (key === Qt.Key_Down ? 1 : entries.length - 1) + entries.length) % entries.length;
            selectionPath = entries[next].path;
            list.positionViewAtIndex(next, ListView.Contain);
            focusPart = 0;
        } else if (key === Qt.Key_Tab || key === Qt.Key_Backtab) {
            focusPart = (focusPart + (key === Qt.Key_Backtab || (modifiers & Qt.ShiftModifier) ? 4 : 1)) % 5;
        } else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) {
            if (focusPart === 4) dismissRequested();
            else if (focusPart === 3) refreshRequested();
            else choose(focusPart === 0 ? "entry" : focusPart === 1 ? "manager" : "terminal", focusPart === 0 ? selectionPath : "");
        }
    }
    component FolderButton: Button {
        id: button
        focusPolicy: Qt.NoFocus
        property bool chosen: false
        property string iconSource: ""
        background: Rectangle {
            radius: 6; color: Qt.alpha(chooser.accentColor, button.hovered ? 0.18 : 0.06)
            border.color: Qt.alpha(chooser.accentColor, button.chosen ? 1 : 0.25)
            border.width: button.chosen ? 2 : 1
        }
        contentItem: Item {
            Image { x:4; anchors.verticalCenter:parent.verticalCenter; width:24; height:24; source:button.iconSource; sourceSize.width:24; sourceSize.height:24 }
            Text {
                anchors.fill:parent
                text: button.text; textFormat: Text.PlainText; elide: Text.ElideRight
                color: chooser.textColor; font.pixelSize: 12
                verticalAlignment: Text.AlignVCenter; leftPadding: button.iconSource ? 34 : 8; rightPadding: 8
            }
        }
        Accessible.name: text
    }
    Column {
        id: controls
        width: parent.width; spacing: 5
        FolderButton {
            objectName:"folder-manager"; width: parent.width; height:32
            text: chooser.result.remainingLabel ? chooser.result.remainingLabel + " more — Open in File Manager" : "Open in File Manager"
            enabled: !chooser.busy; chosen: chooser.focusPart === 1
            onClicked: chooser.choose("manager", "")
        }
        Row {
            width: parent.width; spacing: 4
            FolderButton { objectName:"folder-terminal"; text:"Terminal"; width:(chooser.width - 8) / 3; height:32; enabled:!chooser.busy; chosen:chooser.focusPart === 2; onClicked:chooser.choose("terminal", "") }
            FolderButton { objectName:"folder-refresh"; text:"Refresh"; width:(chooser.width - 8) / 3; height:32; enabled:!chooser.busy; chosen:chooser.focusPart === 3; onClicked:chooser.refreshRequested() }
            FolderButton { objectName:"folder-close"; text:"Close"; width:(chooser.width - 8) / 3; height:32; chosen:chooser.focusPart === 4; onClicked:chooser.dismissRequested() }
        }
        Text {
            width: parent.width
            visible: text !== ""
            text: chooser.busy ? "Reading folder…" : chooser.result.message || ""
            textFormat: Text.PlainText; wrapMode: Text.Wrap
            color: chooser.textColor; font.pixelSize:12
        }
    }
    ListView {
        id: list
        objectName:"folder-list"
        anchors.fill:parent; anchors.topMargin:controls.height + 8
        clip:true; spacing:4; boundsBehavior:Flickable.StopAtBounds
        model:chooser.entries
        ScrollBar.vertical: ScrollBar { }
        delegate: FolderButton {
            id: row
            required property var modelData
            width:list.width - 12; height:52
            property string pressedPath: ""
            property int pressedRevision: -1
            text: modelData.label + "\n" + (modelData.type === "file" ? modelData.size + " bytes · " : modelData.type + " · ") + modelData.relativeTime
            enabled: !chooser.busy && (modelData.type === "file" || modelData.type === "directory")
            chosen: chooser.focusPart === 0 && chooser.selectionPath === modelData.path
            icon.name: modelData.icon
            iconSource: modelData.iconUrl || ""
            onPressed: { pressedPath = modelData.path; pressedRevision = chooser.revision; }
            onClicked: if (pressedRevision === chooser.revision && pressedPath === modelData.path) chooser.choose("entry", pressedPath)
            Accessible.onPressAction: chooser.choose("entry", modelData.path)
        }
    }
}
