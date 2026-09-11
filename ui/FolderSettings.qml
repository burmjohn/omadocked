pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import "../services/FolderLogic.js" as Folders

Column {
    id: root
    objectName: "folder-settings"
    property string homePath: ""
    property string folderColor: "theme"
    property var records: []
    property var result: ({})
    property bool busy: false
    property string scannedPath: ""
    property bool persistenceBusy: false
    property bool selecting: false
    property int selectionGeneration: 0
    property int pendingTransactionId: 0
    property int pendingGeneration: -1
    readonly property bool draftPending: pendingTransactionId > 0 && pendingGeneration === selectionGeneration
    property bool submitting: false
    function saveAccepted(transactionId: int): void {
        if (!submitting || transactionId <= 0) return;
        pendingTransactionId = transactionId;
        pendingGeneration = selectionGeneration;
    }
    function saveResult(transactionId: int, ok: bool): void {
        if (transactionId <= 0 || transactionId !== pendingTransactionId) return;
        const ownsDraft = selecting && pendingGeneration === selectionGeneration;
        pendingTransactionId = 0;
        pendingGeneration = -1;
        if (ok && ownsDraft) { pathField.text = ""; cancelSelection(); }
    }
    property color textColor: "#eef0f6"
    signal presetRequested(string name)
    signal colorRequested(string color)
    signal browseRequested(string path)
    signal browseClosed()
    signal addRequested(string path, string name)
    spacing: 6
    function preset(name: string): void { if (!persistenceBusy && Folders.presets.indexOf(name) >= 0) presetRequested(name); }
    function beginSelection(scan: bool): int {
        ++selectionGeneration;
        selecting = true;
        if (!pathField.text) pathField.text = homePath;
        if (scan) browseRequested(pathField.text);
        return selectionGeneration;
    }
    function cancelSelection(): void {
        ++selectionGeneration;
        selecting = false;
        browseClosed();
    }
    function acceptSelection(revision: int, path: string): bool {
        if (!selecting || revision !== selectionGeneration || busy || persistenceBusy || submitting || pendingTransactionId > 0
            || path !== scannedPath || !result.complete) return false;
        const canonical = Folders.canonicalPath(path, homePath);
        if (!canonical) return false;
        submitting = true;
        addRequested(canonical, canonical.split("/").pop() || "Home");
        submitting = false;
        return true;
    }
    onVisibleChanged: if (!visible && selecting) cancelSelection()
    Text { text:"Folders & Stacks"; color:root.textColor; font.bold:true; textFormat:Text.PlainText }
    Flow {
        width: parent.width; spacing:4
        Repeater {
            model: Folders.presets
            Button {
                required property string modelData
                text: modelData
                checkable:true
                readonly property bool committed: root.records.some(r => r.kind === "folder" && Folders.canonicalPath(r.target, root.homePath) === (modelData === "Home" ? root.homePath : root.homePath + "/" + modelData))
                checked: committed
                enabled: !root.persistenceBusy
                onClicked: {
                    // AbstractButton toggles before clicked, even when storage
                    // rejects. Only durable records own the checkmark.
                    checked = Qt.binding(() => committed);
                    root.preset(modelData);
                }
                Accessible.name: "Toggle folder pin: " + modelData
            }
        }
    }
    ComboBox {
        objectName:"folder-color"; width:parent.width
        model:Folders.colors; currentIndex:Folders.colors.indexOf(root.folderColor)
        enabled:!root.persistenceBusy
        onActivated: root.colorRequested(currentText)
        Accessible.name:"Folder icon color"
    }
    Text {
        width:parent.width; wrapMode:Text.Wrap; color:root.textColor; font.pixelSize:12
        text:"Theme icons are portable. Missing Yaru assets fall back to the theme folder icon. Explicit custom icons are preserved."
        textFormat:Text.PlainText
    }
    Button { text:"Choose a folder…"; enabled:!root.persistenceBusy; onClicked:root.beginSelection(true) }
    Column {
        visible:root.selecting; width:parent.width; spacing:4
        TextField { id:pathField; objectName:"folder-picker-path"; width:parent.width; enabled:!root.draftPending; Accessible.name:"Absolute folder path"; onAccepted:root.browseRequested(text) }
        Flow {
            width: parent.width; spacing:4
            Button { text:"Read folder"; enabled:!root.busy && !root.draftPending; onClicked:root.browseRequested(pathField.text) }
            Button { text:"Up"; enabled:!root.busy && !root.draftPending; onClicked:{ pathField.text = root.scannedPath.replace(/\/+$/, "").replace(/\/[^/]*$/, "") || "/"; root.browseRequested(pathField.text); } }
            Button { text:"Cancel"; onClicked:root.cancelSelection() }
        }
        Text { width:parent.width; wrapMode:Text.Wrap; color:root.textColor; text:root.busy ? "Reading folder…" : root.result.message || "Recent subfolders (or type any absolute path):"; textFormat:Text.PlainText }
        Repeater {
            model:root.selecting ? (root.result.entries || []).filter(e => e.type === "directory") : []
            Button {
                id: directoryButton
                required property var modelData
                width:parent.width; text:modelData.label; enabled:!root.busy && !root.draftPending
                onClicked:{ pathField.text = modelData.path; root.browseRequested(modelData.path); }
                contentItem:Text { text:directoryButton.text; textFormat:Text.PlainText; elide:Text.ElideRight; color:root.textColor }
            }
        }
        Button {
            objectName:"folder-picker-accept"; text:"Add this folder"; width:parent.width
            enabled:!root.busy && !root.persistenceBusy && root.pendingTransactionId === 0 && !!root.result.complete && root.scannedPath === pathField.text
            onClicked:root.acceptSelection(root.selectionGeneration, pathField.text)
            // Return/Enter are not activation keys on every Qt platform theme.
            // Consume them here; Space and pointer/accessibility keep Button's path.
            Keys.onReturnPressed: event => { if (!event.isAutoRepeat) root.acceptSelection(root.selectionGeneration, pathField.text); }
            Keys.onEnterPressed: event => { if (!event.isAutoRepeat) root.acceptSelection(root.selectionGeneration, pathField.text); }
        }
    }
}
