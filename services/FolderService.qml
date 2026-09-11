import QtQuick
import Quickshell.Io
import Quickshell
import "FolderLogic.js" as Folders
import "LauncherLogic.js" as Launchers

// Disposable private chooser state. No scans on construction, imports or saves.
QtObject {
    id: root
    property bool opened: false
    property string launcherId: ""
    property int generation: 0
    property var result: ({})
    readonly property bool busy: opened && (_pending !== null || _active !== null)
    property var _pending: null
    property var _active: null
    property string _path: ""
    readonly property string _session: Date.now().toString(36) + "-" + Math.random().toString(36).slice(2)
    function open(id: string, path: string): bool {
        close();
        if (!id || !Folders.absolutePath(path)) return false;
        launcherId = id;
        _path = path;
        opened = true;
        _pending = Folders.request(path, generation, _session + "-" + generation);
        _pump();
        return true;
    }
    function close(): void {
        ++generation;
        opened = false;
        launcherId = "";
        _path = "";
        result = ({});
        _pending = null;
        // The CLI handles SIGTERM and reaps its worker before exiting. Do not
        // start the replacement until onExited; rapid switches coalesce.
        if (_process.running) _process.running = false;
    }
    function _pump(): void {
        if (_active || !_pending || !opened) return;
        _active = _pending;
        _pending = null;
        _process.running = true;
        _process.write(JSON.stringify(_active));
        _process.stdinEnabled = false;
    }
    function _finish(code: int, status: int, text: string): void {
        const expected = _active;
        _active = null;
        if (opened && expected && expected.generation === generation) {
            try {
                if (code !== 0 || status !== 0 || text.length > 1048576) throw new Error("scan failed");
                const normalized = Folders.normalize(JSON.parse(text), expected);
                normalized.entries = normalized.entries.map(e => Object.assign({}, e, {iconUrl:Quickshell.iconPath(e.icon, true) || Quickshell.iconPath("text-x-generic")}));
                result = normalized;
            } catch (_) {
                result = {status:"unreadable", complete:false, entries:[], message:"Folder scan failed. Try again."};
            }
        }
        _process.stdinEnabled = true;
        _pump();
    }
    function action(kind: string, path: string, revision: int): var {
        if (!opened || revision !== generation || busy) return null;
        if (["entry", "manager", "terminal"].indexOf(kind) < 0) return null;
        if (kind === "entry" && (!result.complete || !result.entries.some(e => e.path === path && (e.type === "file" || e.type === "directory")))) return null;
        return {kind:"folder-action", enabled:true, action:kind, root:_path,
            target:kind === "entry" ? path : _path,
            rootIdentity:result.rootIdentity || null};
    }
    property Process _process: Process {
        command: ["/usr/bin/python3", Launchers.localPath(Qt.resolvedUrl("folder_scan.py").toString())]
        stdinEnabled: true
        stdout: StdioCollector { id: output }
        onExited: (code, status) => root._finish(code, status, output.text)
    }
    Component.onDestruction: close()
}
