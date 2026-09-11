pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

// Two read-only request-socket queries per shared refresh. Native refresh* methods
// have no completion/failure signal, so they cannot certify retained collections.
// Disposable sockets provide actual replies, a bounded buffer, and cancellation;
// NativeOverlap owns the single cadence, deadline and freshness policy.
QtObject {
    id: root
    required property var source
    required property var backend
    required property string socketPath
    property var socket: null
    property int token: -1
    property var monitorData: []
    property Connections requests: Connections {
        target: root.source
        function onRequested(generation) { root.cancel(); root.token = generation; root.query("j/monitors"); }
        function onCanceled() { root.cancel(); }
    }
    function cancel(): void {
        token = -1;
        monitorData = [];
        const old = socket;
        socket = null;
        if (old) { old.connected = false; old.destroy(); }
    }
    function finish(ok: bool, data: var): void {
        const generation = token;
        cancel();
        source.complete(generation, ok, data);
    }
    function query(command: string): void {
        if (!socketPath) { finish(false, null); return; }
        const item = socketFactory.createObject(root, {path:socketPath, command:command, generation:token});
        socket = item;
        item.connected = true;
    }
    function received(item: var, value: var): void {
        if (item !== socket || item.generation !== token) return;
        socket = null;
        item.connected = false;
        item.destroy();
        try {
            if (!Array.isArray(value)) throw new Error("Invalid snapshot");
            if (item.command === "j/monitors") {
                monitorData = value.map(m => {
                    if (typeof m.name !== "string" || !Number.isInteger(m.id)
                        || !Number.isFinite(m.x) || !Number.isFinite(m.y)
                        || !m.activeWorkspace || !Number.isInteger(m.activeWorkspace.id)
                        || !m.specialWorkspace || !Number.isInteger(m.specialWorkspace.id)) throw new Error("Invalid output");
                    return {id:m.id,name:m.name,x:m.x,y:m.y,workspace:m.activeWorkspace.id,special:m.specialWorkspace.id};
                });
                query("j/clients");
            } else {
                const windows = value.map(w => {
                    if (typeof w.address !== "string" || typeof w.pinned !== "boolean"
                        || !Number.isInteger(w.fullscreen) || w.fullscreen < 0 || w.fullscreen > 3
                        || typeof w.mapped !== "boolean" || typeof w.hidden !== "boolean"
                        || !w.workspace || !Number.isInteger(w.workspace.id) || !Number.isInteger(w.monitor)
                        || !Array.isArray(w.at) || !Array.isArray(w.size)
                        || w.at.length !== 2 || w.size.length !== 2
                        || !w.at.concat(w.size).every(Number.isFinite)) throw new Error("Invalid client");
                    const monitor = monitorData.find(m => m.id === w.monitor);
                    const native = backend.toplevels.values.find(h => h.lastIpcObject.address === w.address);
                    return {workspace:w.workspace.id,monitor:monitor ? monitor.name : "",mapped:w.mapped,
                        hidden:w.hidden || !!(native && native.wayland && native.wayland.minimized),pinned:w.pinned === true,
                        fullscreen:w.fullscreen === 2 || w.fullscreen === 3 || !!(native && native.wayland && native.wayland.fullscreen),
                        x:w.at[0],y:w.at[1],width:w.size[0],height:w.size[1]};
                });
                finish(true, {monitors:monitorData,windows:windows});
            }
        } catch (_) { finish(false, null); }
    }
    property Component socketFactory: Component {
        Socket {
            id: channel
            required property string command
            required property int generation
            property string response: ""
            property int validatedBytes: 0
            // QByteArray is exposed as ArrayBuffer by Qt QML. Validate only new
            // bytes before using the collector's UTF-8 text: QString decoding
            // replaces malformed input, which must not create another identity.
            // 0 = partial scalar, 1 = complete, -1 = malformed; never normalize.
            function validateUtf8(buffer: var): int {
                const bytes = new Uint8Array(buffer);
                let i = validatedBytes;
                while (i < bytes.length) {
                    const first = bytes[i];
                    if (first < 0x80) { ++i; continue; }
                    const count = first >= 0xc2 && first <= 0xdf ? 2
                        : first >= 0xe0 && first <= 0xef ? 3
                        : first >= 0xf0 && first <= 0xf4 ? 4 : 0;
                    if (!count) return -1;
                    for (let j = 1; j < count; ++j) {
                        if (i + j >= bytes.length) { validatedBytes = i; return 0; }
                        const next = bytes[i + j];
                        if (next < 0x80 || next > 0xbf) return -1;
                        if (j === 1 && ((first === 0xe0 && next < 0xa0)
                            || (first === 0xed && next > 0x9f)
                            || (first === 0xf0 && next < 0x90)
                            || (first === 0xf4 && next > 0x8f))) return -1;
                    }
                    i += count;
                }
                validatedBytes = i;
                return 1;
            }
            onConnectedChanged: {
                if (connected) { write(command); flush(); }
                else if (root.socket === channel) root.finish(false, null);
            }
            onError: if (root.socket === channel) root.finish(false, null)
            // StdioCollector retains bytes before decoding; SplitParser with an
            // empty marker decodes each read separately and corrupts split UTF-8.
            parser: StdioCollector {
                waitForEnd: false
                onDataChanged: {
                    if (root.socket !== channel) return;
                    if (text.length > 2097152) { root.finish(false, null); return; }
                    const validity = channel.validateUtf8(data);
                    if (validity < 0) { root.finish(false, null); return; }
                    if (!validity) return;
                    channel.response = text;
                    let value;
                    try { value = JSON.parse(channel.response); } catch (_) { return; }
                    root.received(channel, value);
                }
            }
        }
    }
    Component.onDestruction: cancel()
}
