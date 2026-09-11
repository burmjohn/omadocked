pragma ComponentBehavior: Bound
import QtQuick

// One fan-open cohort: at most four in-memory stills, one shared native lease.
// A revoked cohort never re-arms until a new open. No retry or capture loop.
Item {
    id: cohort
    required property var controller
    required property var fan
    property Component driverComponent
    property bool permitted: false
    property var sessions: []
    property var sources: ({})
    property int cursor: 0
    property int generation: 0
    property bool armed: false
    readonly property string openKey: fan && fan.opened ? fan.appId : ""
    readonly property string membership: JSON.stringify(fan ? fan.windows.map(w => [w.key, !!w.parked]) : [])
    readonly property bool ownsCapture: controller.previewCaptureOwner === cohort
    // These readback Items belong to the mapped view, not the ShellRoot adapter.
    // Their pixels are presented only through the compact fan Images.
    x: -10000 // Outside the surface; grabToImage reads only the owned driver Item.
    enabled: false
    function revoke(): void {
        generation++;
        armed = false;
        sources = ({});
        const old = sessions;
        sessions = [];
        for (const session of old) {
            session.permitted = false; // Synchronous driver + retained-image disposal.
            session.destroy();
        }
        cursor = 0;
        if (ownsCapture) controller.previewCaptureOwner = null;
    }
    function open(): void {
        revoke();
        if (!openKey || !permitted || !driverComponent) return;
        armed = true;
        // Coalesce dependent app, rows, capacity and mapped bindings before attach.
        Qt.callLater(begin);
    }
    function begin(): void {
        if (!armed || !permitted || !openKey || sessions.length) return;
        controller.previewCaptureOwner = cohort;
        const app = openKey;
        const epoch = generation;
        const rows = fan.windows.slice(0, Math.min(4, fan.visibleCount));
        const next = [];
        for (const row of rows) {
            if (row.parked || !controller.previewTarget(app, row.key)) continue;
            const session = still.createObject(cohort, {
                width: Math.min(320, Math.max(1, Math.ceil(fan.cardWidth - 10))), height: 30,
                identitySignature: JSON.stringify([app, row.key, membership]),
                source: Qt.binding(() => cohort.controller.previewTarget(app, row.key)),
                driverComponent: driverComponent, permitted: true, captureEnabled: false
            });
            if (!session) continue;
            session.sourceChanged.connect(function() { if (epoch === cohort.generation) cohort.revoke(); });
            session.settled.connect(function() {
                if (epoch !== cohort.generation || !cohort.armed || !cohort.ownsCapture
                    || cohort.sessions[cohort.cursor] !== session || !session.captureEnabled) return;
                session.captureEnabled = false;
                if (session.hasContent) {
                    const urls = Object.assign({}, cohort.sources);
                    urls[row.key] = session.stillSource;
                    cohort.sources = urls;
                }
                cohort.cursor++;
                Qt.callLater(cohort.advance);
            });
            next.push(session);
        }
        sessions = next;
        advance();
    }
    function advance(): void {
        if (!armed || !permitted || !ownsCapture || cursor >= sessions.length) return;
        sessions[cursor].captureEnabled = true;
    }
    onOpenKeyChanged: open()
    onPermittedChanged: if (!permitted) revoke()
    onMembershipChanged: if (sessions.length) revoke()
    onOwnsCaptureChanged: if (!ownsCapture && sessions.length) revoke()
    onDriverComponentChanged: if (sessions.length) revoke()
    Connections {
        target: cohort.fan
        function onVisibleCountChanged() { if (cohort.sessions.length) cohort.revoke(); }
    }
    Component.onDestruction: revoke()
    Component { id: still; PreviewSession { allowLive: false } }
}
