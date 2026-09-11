import QtQuick
import QtTest

TestCase {
    name: "PreviewPrivacy"

    Component {
        id: legacyHost
        QtObject {
            property var audit: ({lookups: 0})
            function serviceFor(id) {
                audit.lookups++;
                return {locked: false, strandedLock: false, strandedLockResolved: true};
            }
        }
    }
    Component {
        id: projectedHost
        QtObject {
            property var privacyKnown: false
            property var privacyBlocked: true
            property var notificationStateKnown: false
            property var doNotDisturb: true
        }
    }
    function test_projectedPermissionRequiresStrictKnownAndUnblocked() {
        const host = createTemporaryObject(projectedHost, this);
        const gate = gateFor(host);
        compare(gate.state, "unknown");
        host.privacyBlocked = false;
        compare(gate.state, "unknown");
        host.privacyKnown = true;
        compare(gate.state, "unlocked");
        host.privacyBlocked = true;
        compare(gate.state, "locked");
        host.privacyKnown = false;
        compare(gate.state, "unknown");
        host.privacyKnown = "true";
        host.privacyBlocked = false;
        compare(gate.state, "unknown");
        host.privacyKnown = true;
        host.privacyBlocked = 0;
        compare(gate.state, "unknown");
    }
    function test_missingDndReadinessVetoes() {
        const gate = gateFor(null);
        compare(gate.notificationStateKnown, false);
        compare(gate.doNotDisturb, true);
    }
    function test_dndRequiresProjectedHydrationAndStrictBoolean() {
        const host = createTemporaryObject(projectedHost, this);
        const gate = gateFor(host);
        host.doNotDisturb = false;
        compare(gate.notificationStateKnown, false);
        compare(gate.doNotDisturb, true);
        host.notificationStateKnown = true;
        compare(gate.notificationStateKnown, true);
        compare(gate.doNotDisturb, false);
        host.doNotDisturb = true;
        compare(gate.doNotDisturb, true);
        host.doNotDisturb = 0;
        compare(gate.notificationStateKnown, false);
        compare(gate.doNotDisturb, true);
        host.doNotDisturb = false;
        host.notificationStateKnown = false;
        compare(gate.doNotDisturb, true);
    }
    function test_sourceReplacementDisconnectAndLateOldChanges() {
        const oldHost = createTemporaryObject(projectedHost, this, {
            privacyKnown: true, privacyBlocked: false,
            notificationStateKnown: true, doNotDisturb: false
        });
        const gate = gateFor(oldHost);
        compare(gate.state, "unlocked");
        const replacement = createTemporaryObject(projectedHost, this);
        gate.hostShell = replacement;
        compare(gate.state, "unknown");
        compare(gate.doNotDisturb, true);
        oldHost.privacyBlocked = true;
        oldHost.privacyBlocked = false;
        compare(gate.state, "unknown");
        replacement.privacyKnown = true;
        replacement.privacyBlocked = false;
        compare(gate.state, "unlocked");
        gate.hostShell = null;
        compare(gate.state, "unknown");
        compare(gate.notificationStateKnown, false);
        replacement.privacyBlocked = true;
        replacement.privacyBlocked = false;
        compare(gate.state, "unknown");
    }
    function test_initialOwnerDestructionRevokes() {
        const host = projectedHost.createObject(this, {
            privacyKnown: true, privacyBlocked: false,
            notificationStateKnown: true, doNotDisturb: false
        });
        const gate = gateFor(host);
        compare(gate.state, "unlocked");
        host.destroy();
        tryCompare(gate, "hostShell", null);
        compare(gate.state, "unknown");
        compare(gate.notificationStateKnown, false);
        compare(gate.doNotDisturb, true);
    }
    function test_knownUnknownDoesNotConsultLegacyFallback() {
        const host = createTemporaryObject(legacyHost, this);
        const gate = gateFor(host);
        const projected = createTemporaryObject(projectedHost, this);
        gate.hostShell = projected;
        projected.privacyKnown = true;
        projected.privacyBlocked = false;
        compare(gate.state, "unlocked");
        projected.privacyKnown = false;
        compare(gate.state, "unknown");
        gate.hostShell = host;
        compare(gate.state, "unknown");
        compare(host.audit.lookups, 0);
        compare(gate.lockService, undefined);
    }
    function test_adapterOutputsAreReadOnly() {
        const gate = gateFor(null);
        for (const name of ["state", "notificationStateKnown", "doNotDisturb"]) {
            let rejected = false;
            try { gate[name] = name === "state" ? "unlocked" : false; }
            catch (_) { rejected = true; }
            verify(rejected, name + " must reject assignment");
        }
    }
    function gateFor(host) {
        const component = Qt.createComponent("../../services/PreviewPrivacy.qml");
        compare(component.status, Component.Ready, component.errorString());
        return createTemporaryObject(component, this, {hostShell: host});
    }
    function test_missingFacadeCannotUseLegacyAuthenticationLookup() {
        const host = createTemporaryObject(legacyHost, this);
        const gate = gateFor(host);
        compare(gate.state, "unknown");
        compare(host.audit.lookups, 0);
        gate.hostShell = null;
        compare(gate.state, "unknown");
    }
    function test_scopedFacadeWithoutProjectionIsUnsupportedContract() {
        const host = createTemporaryObject(legacyHost, this);
        const gate = gateFor(host);
        compare(gate.hostContract, "unsupported");
        compare(gate.state, "unknown");
        compare(gate.notificationStateKnown, false);
        compare(host.audit.lookups, 0);
    }
}
