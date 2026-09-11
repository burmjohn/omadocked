import Quickshell
import Quickshell.Io

ShellRoot {
    Dock {
        id: dock
    }
    IpcHandler {
        target: "omadocked-prototype"
        function snapshot(): string {
            return dock.snapshot();
        }
        function show(): void {
            dock.show();
        }
        function hide(): void {
            dock.hide();
        }
        function monitors(mode: string, namesJson: string): bool {
            return dock.monitors(mode, namesJson);
        }
        function mode(value: string): bool {
            return dock.setMode(value);
        }
        function reducedMotion(value: bool): bool {
            return dock.setReducedMotion(value);
        }
        function autohide(value: bool): bool {
            return dock.setAutoHide(value);
        }
        function minimizeMode(value: string): bool { return dock.setMinimizeMode(value); }
        function iconSize(value: real): bool {
            return dock.setIconSize(value);
        }
        function transparency(value: real): bool {
            return dock.setTransparency(value);
        }
        function settings(output: string, opened: bool): bool {
            return dock.settings(output, opened);
        }
        function keyboard(): void {
            dock.keyboard();
        }
        function activate(id: string): bool { return dock.activate(id); }
        function desktopActions(id: string): string { return JSON.stringify(dock.actionState(id)); }
        function actionChooser(output: string, id: string): bool { return dock.actionChooser(output, id); }
        function desktopAction(id: string, actionId: string): bool { return dock.desktopAction(id, actionId); }
        function windows(id: string): string { return JSON.stringify(dock.windowState(id)); }
        function windowChooser(output: string, id: string): bool { return dock.windowChooser(output, id); }
        function activateWindow(id: string, key: string): bool { return dock.activateWindow(id, key); }
        function closeWindow(id: string, key: string): bool { return dock.closeWindow(id, key); }
        function cycleWindows(id: string, delta: real): bool { return dock.cycleWindows(id, delta); }
        function minimizeApplication(id: string): int { return dock.minimizeApplication(id); }
        function parkWindow(id: string, key: string): int { return dock.parkWindow(id, key); }
        function restoreWindow(id: string, key: string, mode: string): int { return dock.restoreWindow(id, key, mode); }
        function restoreFifo(mode: string): int { return dock.restoreFifo(mode); }
        function recoverParked(mode: string): int { return dock.recoverParked(mode); }
        function context(output: string, id: string): bool { return dock.context(output, id); }
        function editor(output: string, id: string): bool { return dock.editor(output, id); }
        function newInstance(id: string): bool { return dock.newInstance(id); }
        function saveLauncher(recordJson: string): bool { return dock.saveLauncher(recordJson); }
        function removeLauncher(id: string): bool { return dock.removeLauncher(id); }
        function duplicateLauncher(id: string): bool { return dock.duplicateLauncher(id); }
        function setOverride(appId: string, desktopId: string): bool { return dock.setOverride(appId, desktopId); }
        function recoverConfiguration(): bool { return dock.recoverConfiguration(); }
        function pin(id: string, pinned: bool): bool { return dock.pin(id, pinned); }
        function reorderApps(idsJson: string): bool { return dock.reorderApps(idsJson); }
        function fixtureApps(dataJson: string): bool { return dock.fixtureApps(dataJson); }
        function quit(): void {
            Qt.quit();
        }
    }
}
