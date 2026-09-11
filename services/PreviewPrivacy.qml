import QtQuick

// Consume only the supported boolean projection, never authentication services.
QtObject {
    property QtObject hostShell: null
    // Hosted Omarchy 4.0.3 third-party facades do not project these fields.
    // Fail closed unless the host explicitly implements omadocked-privacy/1.
    readonly property string hostContract: {
        if (!hostShell) return "none";
        const known = hostShell.privacyKnown === true || hostShell.privacyKnown === false;
        const blocked = hostShell.privacyBlocked === true || hostShell.privacyBlocked === false;
        const notify = hostShell.notificationStateKnown === true || hostShell.notificationStateKnown === false;
        return known && blocked && notify ? "omadocked-privacy/1" : "unsupported";
    }
    // notificationStateKnown is the host's readiness-qualified projection:
    // it must include settingsLoaded, not just the provider's DND default.
    readonly property bool notificationStateKnown: hostShell !== null
        && hostShell.notificationStateKnown === true
        && typeof hostShell.doNotDisturb === "boolean"
    readonly property bool doNotDisturb: !notificationStateKnown
        || hostShell.doNotDisturb !== false
    readonly property string state: {
        if (!hostShell || hostShell.privacyKnown !== true) return "unknown";
        if (hostShell.privacyBlocked === true) return "locked";
        return hostShell.privacyBlocked === false ? "unlocked" : "unknown";
    }
}
