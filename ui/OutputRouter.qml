import QtQuick

// Shared routing only; the native backend is injected by Dock. Never moves a
// surface: persistent per-screen delegates consume the settled connector list.
Item {
    id: root
    property var backend: null
    property var availableOutputs: []
    property var baseOutputs: []
    property bool followActiveOutput: false
    readonly property string focusedName: backend && backend.focusedMonitor ? backend.focusedMonitor.name : ""
    property var activeOutputs: []
    property bool interactionLocked: false
    property bool reconcilePending: false
    function schedule(): void {
        if (reconcilePending) return;
        reconcilePending = true;
        Qt.callLater(reconcile);
    }
    function reconcile(): void {
        reconcilePending = false;
        const surviving = activeOutputs.filter(name => availableOutputs.indexOf(name) >= 0);
        let next;
        // Base policy stays live even during interactions; disabling follow
        // restores it immediately. Enabling follow retains connected interacting
        // routes until release. Removed outputs can never retain ownership.
        if (!followActiveOutput) next = baseOutputs.filter(name => availableOutputs.indexOf(name) >= 0);
        else if (interactionLocked && surviving.length) next = surviving;
        else if (availableOutputs.indexOf(focusedName) >= 0) next = [focusedName];
        else next = surviving.length ? surviving.slice(0,1) : availableOutputs.slice().sort().slice(0,1);
        if (JSON.stringify(next) !== JSON.stringify(activeOutputs)) activeOutputs = next.slice();
    }
    onAvailableOutputsChanged: schedule()
    onBaseOutputsChanged: schedule()
    onFollowActiveOutputChanged: schedule()
    onFocusedNameChanged: schedule()
    onInteractionLockedChanged: schedule()
    Component.onCompleted: schedule()
}
