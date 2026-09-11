import QtQuick
import "../core/AttentionLogic.js" as Attention
import "../core/ParitySettings.js" as Parity

// One event consumer above all surfaces. Only IDs/flags enter the pure policy.
QtObject {
    id: root
    property var apps: []
    property bool enabled: true
    property bool showUrgentHint: true
    property bool urgentOnNotification: true
    property bool urgentSound: false
    property string urgentSoundName: "bell"
    signal soundRequested(string name)
    // Explicit Settings request, sharing the event player's safety and lifetime.
    property var soundPlayer: null
    readonly property string soundSampleStatus: {
        if (!notificationReady) return "unavailable: host DND state required";
        if (dnd) return "unavailable: Do Not Disturb";
        if (!urgentSound) return "off: enable attention sound first";
        if (urgentSoundName === "none" || Parity.soundNames.indexOf(urgentSoundName) < 0)
            return "unavailable: select a sound";
        if (!soundPlayer) return "unavailable: sound player missing";
        if (!enabled || !soundPlayer.allowed) return "unavailable: visible, unlocked dock required";
        if (soundPlayer.busy) return soundPlayer.status === "starting" ? "starting" : "busy";
        if (soundPlayer.status !== "available") return soundPlayer.status;
        if (soundPlayer.cooldown.running) return "cooldown: wait briefly";
        return "ready";
    }
    function sampleSound() {
        // Revalidate on dispatch; a stale enabled button is not authority.
        return soundSampleStatus === "ready" && soundPlayer.play(urgentSoundName);
    }
    function urgentKey(appId) {
        const entry = _state.attention[appId];
        // Keep an indicated-but-cleared key until explicit acknowledgement or
        // removal; the action controller revalidates native urgency, never falls back.
        return entry ? Object.keys(entry.windows).sort()[0] || "" : "";
    }
    property var actionSource: null
    property Connections _actionEvents: Connections {
        target: root.actionSource
        function onUrgentAcknowledged(appId, key) {
            const app = root.apps.find(a => a.id === appId);
            if (!app || !app.windows.some(w => w.id === key)) return;
            // A verified exact-window action must not clear a sibling's urgency.
            root._state = Attention.closeWindow(root._state, key);
        }
    }
    property var hostShell: null
    property var pluginRegistry: null
    readonly property var notificationService: {
        if (!hostShell || !pluginRegistry || typeof hostShell.serviceFor !== "function" || typeof pluginRegistry.resolveEnabledId !== "function")
            return null;
        return hostShell.serviceFor(pluginRegistry.resolveEnabledId("omarchy.notifications"));
    }
    readonly property var popupModel: notificationService ? notificationService.popupModel || null : null
    readonly property bool notificationReady: !!popupModel && typeof popupModel.get === "function" && !!notificationService && typeof notificationService.isRestoredRow === "function" && notificationService.settingsLoaded === true && typeof notificationService.doNotDisturb === "boolean"
    readonly property bool dnd: !notificationReady || notificationService.doNotDisturb
    readonly property string notificationStatus: !notificationReady ? "unavailable" : _state.overflow ? "capacity-reached" : "available"

    property int _generation: 0
    property double _attachedAt: 0
    function baseline() {
        ++_generation;
        _attachedAt = Date.now();
        const rows = [];
        if (popupModel && typeof popupModel.get === "function") {
            for (let i = 0; i < Math.min(popupModel.count, Attention.MAX_BASELINE_ROWS + 1); ++i) {
                const row = popupModel.get(i);
                rows.push({
                    id: String(row.timestamp) + ":" + String(row.originalId),
                    timestampMs: row.timestamp,
                    appId: "baseline",
                    pwaId: "",
                    browserId: ""
                });
            }
        }
        _state = Attention.beginGeneration(Attention.newState(), String(_generation), rows);
    }
    onPopupModelChanged: baseline()
    onNotificationReadyChanged: baseline()
    function inserted(first, last) {
        if (!_started || !notificationReady)
            return;
        const rows = [];
        for (let i = first; i <= Math.min(last, first + Attention.MAX_ROWS); ++i) {
            const row = popupModel.get(i);
            // Only the two public identity roles reach the restored-row predicate.
            const identity = {
                originalId: row.originalId,
                timestamp: row.timestamp
            };
            if (!Number.isInteger(identity.originalId) || identity.originalId < 0 || !Number.isInteger(identity.timestamp) || identity.timestamp < _attachedAt || notificationService.isRestoredRow(identity))
                continue;
            rows.push({
                id: String(identity.timestamp) + ":" + String(identity.originalId),
                timestampMs: identity.timestamp,
                appId: typeof row.app === "string" ? row.app : "",
                pwaId: "",
                browserId: ""
            });
        }
        // Consume disabled/DND events, never queue them for a later enable/unlock.
        const result = Attention.processNotifications(_state, String(_generation), rows, enabled && urgentOnNotification && !dnd ? policyApps : [], {
            enabled: true,
            soundEnabled: urgentSound,
            soundName: urgentSoundName,
            dnd: dnd
        }, Date.now());
        _state = result.state;
        if (result.soundName)
            soundRequested(result.soundName);
    }
    property Connections _popupEvents: Connections {
        target: root.popupModel
        function onRowsInserted(parent, first, last) {
            root.inserted(first, last);
        }
        function onModelReset() {
            root.baseline();
        }
    }
    property var _state: Attention.newState()
    property var _urgent: ({})
    property bool _started: false
    readonly property var policyApps: apps.map(app => ({
                id: app.id,
                notificationIds: Array.from(app.notificationIds),
                pwaIds: Array.from(app.pwaIds),
                browserIds: Array.from(app.browserIds),
                focused: app.focused,
                launchPending: app.launchPending,
                openedAtMs: app.openedAtMs,
                windows: app.windows.map(w => ({
                            id: w.id,
                            focused: w.focused,
                            openedAtMs: w.openedAtMs
                        }))
            }))
    readonly property var hints: enabled && showUrgentHint ? Object.keys(_state.attention).filter(id => Attention.hintVisible(_state, id, true, policyApps)) : []
    function syncNative() {
        const next = Object.create(null);
        let state = _state;
        apps.forEach(app => app.windows.forEach(w => {
                next[w.id] = w.urgent === true;
                if (_started && enabled && w.urgent === true && _urgent[w.id] === false) {
                    const candidate = Attention.nativeUrgency(policyApps, w.id, Date.now());
                    state = Attention.recordNative(state, candidate);
                    const sound = Attention.soundDecision({
                        enabled: urgentSound,
                        soundName: urgentSoundName
                    }, dnd, candidate ? [candidate] : []);
                    if (sound)
                        soundRequested(sound);
                }
            }));
        Object.keys(_urgent).forEach(id => {
            if (!(id in next))
                state = Attention.closeWindow(state, id);
        });
        Object.keys(state.attention).forEach(id => {
            const app = apps.find(a => a.id === id);
            if (!app || app.focused)
                state = Attention.clearFocused(state, id);
        });
        _urgent = next;
        _state = state;
    }
    // Observe the derived projection, not its source before bindings settle.
    onPolicyAppsChanged: syncNative()
    onEnabledChanged: {
        if (!enabled)
            _state = Object.assign({}, _state, {
                attention: Object.create(null)
            });
    }
    Component.onCompleted: {
        baseline();
        syncNative();
        _started = true;
    }
}
