import QtQuick

// One adapter under LiveApps, shared by all outputs. No titles or window identities
// escape this projection. backend supplies native events; OverlapSnapshot supplies
// acknowledged read-only geometry. Owned fixtures exercise both boundaries.
QtObject {
    id: root
    required property var backend
    property var consumers: ({})
    readonly property bool active: Object.keys(consumers).length > 0
    property var snapshot: null
    property double sampledAt: 0
    readonly property var monitors: snapshot ? snapshot.monitors : []
    readonly property var windows: snapshot ? snapshot.windows : []
    property int generation: 0
    property bool busy: false
    property bool pending: false
    signal requested(int generation)
    signal canceled()
    function setConsumer(key: string, enabled: bool): void {
        const next = Object.assign({}, consumers);
        if (enabled) next[key] = true;
        else delete next[key];
        consumers = next;
    }
    onActiveChanged: {
        if (active) refresh();
        else {
            generation++;
            refreshTimer.stop();
            deadline.stop();
            expiry.stop();
            pending = false;
            busy = false;
            snapshot = null;
            canceled();
        }
    }
    // One shared 1000 ms cadence, only while mapped opt-in consumers exist.
    // Supported events still request a 50 ms coalesced refresh between ticks.
    function refresh(): void {
        if (!active) return;
        if (busy) { pending = true; return; }
        if (!refreshTimer.running) refreshTimer.start();
    }
    function complete(token: int, ok: bool, data: var): void {
        if (!active || !busy || token !== generation) return;
        deadline.stop();
        busy = false;
        snapshot = ok ? data : null;
        sampledAt = ok ? Date.now() : 0;
        if (ok) expiry.restart();
        else expiry.stop();
        if (pending) { pending = false; refresh(); }
    }
    property Connections events: Connections {
        target: root.backend
        function onRawEvent(event) {
            if (["openwindow", "closewindow", "activewindowv2", "movewindowv2", "fullscreen",
                "workspacev2", "focusedmon", "moveworkspacev2", "activespecial", "activespecialv2",
                "monitoraddedv2", "monitorremoved", "configreloaded", "changefloatingmode",
                "pin", "togglegroup", "moveintogroup", "moveoutofgroup", "minimized"].indexOf(event.name) >= 0)
                root.refresh();
        }
    }
    property Timer cadence: Timer { interval: 1000; repeat: true; running: root.active; onTriggered: root.refresh() }
    property Timer expiry: Timer { interval: 2000; onTriggered: root.snapshot = null }
    property Timer deadline: Timer {
        interval: 750
        onTriggered: {
            root.generation++;
            root.busy = false;
            root.pending = false;
            root.snapshot = null;
            root.canceled();
        }
    }
    property Timer refreshTimer: Timer {
        interval: 50
        onTriggered: {
            if (!root.active || root.busy) return;
            root.busy = true;
            root.generation++;
            root.deadline.start();
            root.requested(root.generation);
        }
    }
    Component.onDestruction: canceled()
    // Use compositor origins with Qt's already-logical, transformed output size.
    // The resting shelf, not popup size, hover expansion or hide animation,
    // determines overlap; otherwise visibility feeds back into its own geometry.
    function shelfFor(outputName: string, width: real, height: real, shelfWidth: real, shelfHeight: real, offset: real): rect {
        const output = monitors.find(m => m.name === outputName);
        if (!output) return Qt.rect(0, 0, 0, 0);
        return Qt.rect(output.x + (width - shelfWidth) / 2,
            output.y + height - offset - shelfHeight, shelfWidth, Math.max(0, shelfHeight - 6));
    }
    function evaluate(outputName: string, rect: rect): var {
        if (!active) {
            // Preserve ordinary fullscreen suppression from the live foreign
            // toplevel flag, without starting geometry requests in default mode.
            const fullscreen = backend.toplevels.values.some(w => {
                const m = w.monitor, data = w.lastIpcObject;
                return m && m.name === outputName && w.wayland && w.wayland.fullscreen
                    && !w.wayland.minimized && data.mapped === true && data.hidden !== true
                    && (data.pinned === true || (w.workspace &&
                        ((m.activeWorkspace && m.activeWorkspace.id === w.workspace.id)
                        || (m.lastIpcObject.specialWorkspace && m.lastIpcObject.specialWorkspace.id !== 0
                            && m.lastIpcObject.specialWorkspace.id === w.workspace.id))));
            });
            return {available:false, overlap:false, fullscreen:fullscreen};
        }
        if (!snapshot || Date.now() - sampledAt > 2000 || Date.now() < sampledAt)
            return {available:false, overlap:false, fullscreen:false};
        const output = monitors.find(m => m.name === outputName);
        if (!output) return {available:false, overlap:false, fullscreen:false};
        let overlap = false, fullscreen = false;
        for (const w of windows) {
            const visible = w.pinned ? monitors.some(m => m.name === w.monitor)
                : w.workspace !== null && monitors.some(m => m.workspace === w.workspace || (m.special !== 0 && m.special === w.workspace));
            if (!w.mapped || w.hidden || !visible) continue;
            if (w.fullscreen && w.monitor === outputName) fullscreen = true;
            // Hyprland client at/size are global logical coordinates. Do not
            // multiply by output scale or clamp negative positions.
            if ([w.x,w.y,w.width,w.height].every(v => typeof v === "number" && isFinite(v))
                && w.width > 0 && w.height > 0 && rect.width > 0 && rect.height > 0
                && w.x < rect.x + rect.width && w.x + w.width > rect.x
                && w.y < rect.y + rect.height && w.y + w.height > rect.y) overlap = true;
        }
        return {available:true, overlap:overlap, fullscreen:fullscreen};
    }
}
