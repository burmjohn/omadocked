import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "DesktopActionLogic.js" as DesktopActions
import "../core/ParkingLogic.js" as Parking

// Loaded only outside test mode. Titles are event-driven, private view metadata.
QtObject {
    id: root
    readonly property NativeOverlap overlapSource: NativeOverlap { backend: Hyprland }
    readonly property OverlapSnapshot overlapSnapshot: OverlapSnapshot {
        source: root.overlapSource
        backend: Hyprland
        socketPath: Hyprland.requestSocketPath
    }
    readonly property var entries: DesktopEntries.applications.values.map(e => ({
        id: e.id, name: e.name, icon: e.icon, startupClass: e.startupClass,
        launchable: e.execString.length > 0,
        // This bounded slice excludes Exec-less D-Bus-only actions.
        actions: DesktopActions.metadata(e.actions, true)
    }))
    readonly property var windows: ToplevelManager.toplevels.values.map(w => ({
        handle: w, appId: w.appId, title: w.title, active: w.activated,
        urgent: Hyprland.toplevels.values.some(h => h.wayland === w && h.urgent)
    }))
    function close(handle): bool {
        // Only request the chosen client's native close protocol; it may refuse.
        if (ToplevelManager.toplevels.values.indexOf(handle) === -1) return false;
        handle.close();
        return true;
    }
    function activate(handle): bool {
        // Membership is read again at dispatch; no stale cached toplevel activation.
        if (ToplevelManager.toplevels.values.indexOf(handle) === -1) return false;
        handle.activate();
        return true;
    }
    function refreshParkingMetadata() {
        Hyprland.refreshToplevels();
    }
    function parkingRecord(handle): var {
        // PID is only one field in the exact QObject/address/full-identity correlation.
        // lastIpcObject is a snapshot; refresh before validating a newly mapped window.
        return Parking.recordAfterRefresh(handle, ToplevelManager.toplevels.values, Hyprland.toplevels.values,
            () => Hyprland.refreshToplevels());
    }
    function parkingIdentity(handle): var {
        return Parking.identity(handle, ToplevelManager.toplevels.values, Hyprland.toplevels.values);
    }
}
