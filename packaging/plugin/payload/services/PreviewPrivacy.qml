import QtQuick

// Consume only the supported boolean projection, never authentication services.
QtObject {
    property QtObject hostShell: null
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
