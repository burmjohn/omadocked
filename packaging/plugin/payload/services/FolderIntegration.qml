import QtQuick

// Production bridge shared by the native surface and isolated integration tests.
Item {
    id: root
    required property var view
    required property var controller
    readonly property alias folders: folders
    FolderService { id: folders }
    Binding { target: root.view; property: "folderResult"; value: folders.result }
    Binding { target: root.view; property: "folderBusy"; value: folders.busy }
    Binding { target: root.view; property: "folderGeneration"; value: folders.generation }
    Binding { target: root.view; property: "folderScannedPath"; value: folders._path }
    Connections {
        target: root.view
        function onFolderOpenRequested(id, path) {
            const record = root.view.launcherRecords.find(r => r.id === id && r.kind === "folder" && r.enabled && r.target === path);
            if (record) folders.open(id, path);
        }
        function onFolderCloseRequested() { folders.close(); }
        function onFolderBrowseRequested(path) {
            if (root.view.settingsOpen && !root.view.editorOpen) folders.open("picker", path);
        }
        function onFolderDirectRequested(id, kind) {
            const record = root.view.launcherRecords.find(r => r.id === id && r.kind === "folder" && r.enabled);
            if (record && (kind === "manager" || kind === "terminal")
                && root.controller.folderAction(id, {kind:"folder-action", enabled:true, action:kind, root:record.target, target:record.target, rootIdentity:null})) root.view.releaseInteractions();
        }
        function onFolderActionRequested(id, kind, path, generation) {
            if (id !== folders.launcherId) return;
            const action = folders.action(kind, path, generation);
            if (action && root.controller.folderAction(id, action)) root.view.releaseInteractions();
        }
    }
    Component.onDestruction: folders.close()
}
