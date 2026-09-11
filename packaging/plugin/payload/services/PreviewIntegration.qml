pragma ComponentBehavior: Bound
import QtQuick

// Connects the real chooser to one private, disposable capture session.
Item {
    id: integration
    required property var view
    required property var controller
    property bool mapped: false
    property Component driverComponent
    readonly property bool privacyAllowed: mapped && controller.previewLockState === "unlocked"
    readonly property bool eligible: privacyAllowed && view.windowChooserOpen && view.contextIndex >= 0
        && view.previewsEnabled && !view.surfaceSuspended && view.effectiveProgress > 0
    // One selected preview across output surfaces. A newer explicit selection
    // cancels the previous session; relinquishing ownership does not retry it.
    readonly property bool ownsCapture: eligible && controller.previewCaptureOwner === integration
    function updateCaptureOwner(): void {
        if (eligible) controller.previewCaptureOwner = integration;
        else if (controller.previewCaptureOwner === integration) controller.previewCaptureOwner = null;
    }
    onEligibleChanged: updateCaptureOwner()
    Component.onCompleted: updateCaptureOwner()
    Component.onDestruction: {
        if (controller.previewCaptureOwner === integration) controller.previewCaptureOwner = null;
    }
    Connections {
        target: integration.view
        function onWindowSelectionKeyChanged() { integration.updateCaptureOwner(); }
    }
    // Unknown lock authority disables images, not baseline titled window actions.
    Binding { target: integration.view; property: "windowActionsAllowed"; value: integration.mapped && integration.controller.previewLockState !== "locked" }
    Binding { target: integration.view; property: "previewComponent"; value: preview }
    readonly property var fanCapture: fanCapture
    FanPreviewCapture {
        id: fanCapture
        parent: integration.view
        controller: integration.controller
        fan: integration.view.activeWindowFan
        permitted: integration.privacyAllowed && integration.view.previewsEnabled
            && integration.view.fanEligible && !integration.view.surfaceSuspended
            && integration.view.effectiveProgress > 0
        driverComponent: integration.driverComponent
    }
    Binding { target: integration.view; property: "fanPreviewSources"; value: fanCapture.sources }
    Component {
        id: preview
        PreviewSession {
            permitted: integration.ownsCapture
            // Live preference is retained for compatibility; native live is stretch work.
            allowLive: false
            driverComponent: integration.driverComponent
            source: integration.ownsCapture ? integration.controller.previewTarget(integration.view.contextId, integration.view.windowSelectionKey) : null
            identitySignature: integration.view.activeWindowChooser
                ? JSON.stringify([integration.view.contextId, integration.view.windowSelectionKey,
                    integration.view.activeWindowChooser.groupCard.identitySignature]) : ""
        }
    }
}
