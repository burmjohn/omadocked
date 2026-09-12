pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "ui"
import "services"
import "core/DockLogic.js" as Logic

// Shared native controller. Per-screen interaction belongs to DockSurface.
Item {
    id: root
    // Optional host-loader injection points; standalone preview leaves them null.
    property string omarchyPath: ""
    property var shell: null
    property var manifest: null
    property var barWidgetRegistry: null
    property var pluginRegistry: null
    property var service: null
    readonly property int phase: 3
    readonly property bool testMode: appService.testMode
    readonly property bool nonlaunching: testMode
    readonly property var applications: appService.items
    // Private titles are presentation data, deliberately omitted from snapshots.
    readonly property var windowGroups: appService.windowGroups
    readonly property var desktopActionGroups: appService.desktopActions
    readonly property string appError: appService.error
    readonly property var launcherRecords: appService.launchers
    readonly property var desktopEntries: appService.entries
    readonly property bool canRecover: appService.canRecover
    readonly property bool ready: appService.ready
    readonly property bool persistenceBusy: appService.persistenceBusy
    readonly property bool parkingReady: appService.parkingReady
    readonly property bool parkingBusy: appService.parkingBusy
    readonly property var parkedWindows: appService.parkedWindows
    readonly property var lastParkingReceipt: appService.lastParkingReceipt
    readonly property int parkingRevision: appService.parkingRevision
    signal persistenceCompleted(int transactionId, bool ok, string message)
    signal parkingCompleted(int transactionId, bool ok, string status, string key)
    property int pendingMonitorPolicyTransactionId: 0
    property var pendingMonitorPolicy: null
    Connections {
        target: appService
        function onPersistenceCompleted(transactionId, ok, message) {
            if (transactionId === root.pendingMonitorPolicyTransactionId) {
                root.pendingMonitorPolicyTransactionId = 0;
                root.pendingMonitorPolicy = null;
                if (ok) {
                    root.environmentMonitorOverride = false;
                    root.legacyPolicy = false;
                }
            }
            root.persistenceCompleted(transactionId, ok, message);
        }
        function onParkingCompleted(transactionId, ok, status, key) { root.parkingCompleted(transactionId, ok, status, key); }
    }
    AppService { id: appService }
    ShellGestures { id: shellGestures; enabled: !root.testMode }
    function shellGesture(kind: string, delta: real): bool {
        return shellGestures.perform(kind, delta);
    }
    PreviewPrivacy { id: previewPrivacy; hostShell: root.shell }
    readonly property bool attentionAllowed: surfaceEnabled && (!shell || previewLockState === "unlocked")
    readonly property bool attentionVisible: {
        for (const surface of surfaces.instances)
            if (surface.attentionVisible) return true;
        return false;
    }
    readonly property var attentionHints: attention.hints
    readonly property bool attentionDnd: attention.dnd
    readonly property string notificationStatus: attention.notificationStatus
    readonly property string soundStatus: previewLockState !== "unlocked" || attention.notificationStatus === "unavailable"
        ? "unavailable: host DND/unlock state required" : attentionSound.status
    readonly property bool showUrgentHint: appService.settings.showUrgentHint
    readonly property bool urgentOnNotification: appService.settings.urgentOnNotification
    readonly property bool urgentSound: appService.settings.urgentSound
    readonly property string urgentSoundName: appService.settings.urgentSoundName
    function configureAttention(patch: var): int { return appService.configure(patch); }
    readonly property string soundSampleStatus: attention.soundSampleStatus
    function sampleSound(): bool { return attention.sampleSound(); }
    AttentionService {
        id: attention
        apps: appService.attentionApps
        actionSource: appService
        hostShell: root.shell
        pluginRegistry: root.pluginRegistry
        enabled: root.attentionAllowed
        showUrgentHint: root.showUrgentHint
        urgentOnNotification: root.urgentOnNotification
        urgentSound: root.urgentSound
        urgentSoundName: root.urgentSoundName
        soundPlayer: attentionSound
        onSoundRequested: name => attentionSound.play(name)
    }
    AttentionSound {
        id: attentionSound
        allowed: root.attentionAllowed && root.attentionVisible && root.previewLockState === "unlocked"
            && !attention.dnd && root.urgentSound && !root.testMode
    }
    readonly property string previewLockState: previewPrivacy.state
    readonly property bool previewsEnabled: appService.settings.previewsEnabled
    readonly property bool livePreviews: appService.settings.livePreviews
    property QtObject previewCaptureOwner: null
    function previewTarget(appId: string, key: string): var {
        return previewLockState === "unlocked" && previewsEnabled ? appService.previewTarget(appId, key) : null;
    }
    function setPreviewsEnabled(value: bool): int { return appService.configure({previewsEnabled:value}); }
    function setLivePreviews(value: bool): int { return appService.configure({livePreviews:value}); }
    // Available while this overlay is loaded, including when surfaces are hidden.
    // Unload/disable removes this IPC; recover first or use the retained helper
    // described in docs/recovery.md. Recreation reconnects the durable journal.
    IpcHandler {
        target: "omadocked-recovery"
        function status(): string {
            return JSON.stringify({ready:root.parkingReady, busy:root.parkingBusy,
                records:root.parkedWindows, revision:root.parkingRevision, last:root.lastParkingReceipt});
        }
        function recover(mode: string): int { return root.recoverParked(mode); }
        function restoreFifo(mode: string): int { return root.restoreFifo(mode); }
        function minimizeActive(): int { return root.minimizeActive(); }
    }
    readonly property int screenCount: Quickshell.screens.length
    // Omarchy's enabled keepLoaded overlay Loader injects these after creation;
    // it does not call open() on enable. Require the actual manifest contract,
    // not an arbitrary shell marker. Explicit show/close still owns this instance.
    readonly property bool hostedVisibleOnEnable: !!shell && !!pluginRegistry && !!manifest
        && manifest.id === "burmjohn.omadocked" && manifest.keepLoaded === true
        && Array.isArray(manifest.kinds) && manifest.kinds.indexOf("overlay") >= 0
        && !!manifest.entryPoints && manifest.entryPoints.overlay === "Dock.qml"
    property bool surfaceEnabled: Quickshell.env("OMADOCKED_VISIBLE") === "1"
        || (!testMode && hostedVisibleOnEnable)
    readonly property bool opened: surfaceEnabled
    readonly property string requestedOutput: Quickshell.env("OMADOCKED_SCREEN") || ""
    readonly property string requestedOutputs: Quickshell.env("OMADOCKED_SCREENS") || ""
    readonly property int offset: {
        const raw = Quickshell.env("OMADOCKED_OFFSET");
        const n = Number(raw);
        return raw && isFinite(n) && n >= 0 ? Math.round(n) : 0;
    }
    property bool legacyPolicy: requestedOutput !== "" && requestedOutputs === ""
    property bool environmentMonitorOverride: requestedOutputs !== ""
    readonly property var monitorSettings: environmentMonitorOverride
        ? Logic.initialMonitorPolicy(requestedOutputs)
        : {mode: appService.settings.monitorMode, names: appService.settings.selectedOutputs}
    readonly property string monitorError: monitorSettings.error || ""
    readonly property string monitorMode: legacyPolicy ? "selected" : monitorSettings.mode
    readonly property var selectedOutputs: legacyPolicy ? [requestedOutput] : monitorSettings.names
    readonly property var availableOutputs: {
        const names = [];
        for (const screen of Quickshell.screens) names.push(screen.name);
        return names;
    }
    property var outputPolicy: ({name: "", fallback: true, reason: "no-outputs"})
    readonly property var baseOutputs: legacyPolicy
        ? (outputPolicy.name ? [outputPolicy.name] : [])
        : Logic.activeOutputs(availableOutputs, monitorMode, selectedOutputs)
    readonly property bool followActiveOutput: appService.settings.followActiveOutput
    function setFollowActiveOutput(value: bool): int { return appService.configure({followActiveOutput:value}); }
    readonly property var activeOutputs: outputRouter.activeOutputs
    OutputRouter {
        id: outputRouter
        backend: Hyprland
        availableOutputs: root.availableOutputs
        baseOutputs: root.baseOutputs
        // Explicit preview environment policies retain precedence over storage.
        followActiveOutput: root.followActiveOutput && !root.legacyPolicy && !root.environmentMonitorOverride
        interactionLocked: {
            for (const surface of surfaces.instances)
                if (surface.outputRoutingLocked) return true;
            return false;
        }
    }
    function reconcileOutputs(): void {
        outputPolicy = Logic.resolveOutput(availableOutputs, requestedOutput, outputPolicy.name);
    }
    onAvailableOutputsChanged: reconcileOutputs()
    Component.onCompleted: reconcileOutputs()
    function monitors(mode: string, namesJson: string): int {
        const next = Logic.monitorPolicy(mode, namesJson);
        if (!next || pendingMonitorPolicyTransactionId > 0) return 0;
        const transactionId = appService.configure({monitorMode: next.mode, selectedOutputs: next.names});
        if (transactionId <= 0) return 0;
        pendingMonitorPolicy = next;
        pendingMonitorPolicyTransactionId = transactionId;
        return transactionId;
    }
    readonly property string motionMode: appService.settings.motionMode
    readonly property bool reducedMotion: appService.settings.reducedMotion
    readonly property bool showAppNames: appService.settings.showAppNames
    readonly property bool showAppsButton: appService.settings.showAppsButton !== false
    readonly property bool advancedTooltips: appService.settings.advancedTooltips
    readonly property bool launchBounce: appService.settings.launchBounce
    readonly property int tooltipDelay: appService.settings.tooltipDelay
    readonly property int revealDelay: appService.settings.revealDelay
    readonly property bool autoHide: appService.settings.autoHide
    readonly property bool intelligentHide: appService.settings.intelligentHide
    readonly property bool reserveSpace: appService.settings.reserveSpace
    readonly property var overlapSource: appService.overlapSource
    readonly property string minimizeMode: appService.settings.minimizeMode
    readonly property int zoomSize: appService.settings.zoomSize
    readonly property int waveWidth: appService.settings.waveWidth
    readonly property int iconSize: appService.settings.iconSize
    readonly property int transparency: appService.settings.transparency
    readonly property var appearanceSettings: appService.settings
    function configureAppearance(patch: var): int { return appService.configure(patch); }
    Loader {
        id: hostAppearance
        source: root.shell && root.omarchyPath ? "host/Appearance.qml" : ""
    }
    readonly property real themeCornerRadius: hostAppearance.item ? hostAppearance.item.cornerRadius : -1
    readonly property color themeBackground: hostAppearance.item ? hostAppearance.item.background : colors.background
    readonly property string folderColor: appService.settings.folderColor
    readonly property string homePath: Quickshell.env("HOME")
    function setFolderColor(value: string): int { return appService.configure({folderColor:value}); }
    function toggleFolder(path: string, name: string): int { return appService.toggleFolder(path, name); }
    function addFolder(path: string, name: string): int {
        if (launcherRecords.some(r => r.kind === "folder" && r.target === path)) return 0;
        return appService.saveLauncher({kind:"folder", name:name, target:path, enabled:true});
    }

    readonly property string themePath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/current/theme/colors.toml"
    property string paletteSource: "fallback"
    property var colors: ({background: "#20232b", foreground: "#eef0f6", accent: "#a7c7ff"})
    function loadPalette(raw: string): void {
        const values = {};
        const lines = raw.split("\n");
        for (let i = 0; i < lines.length; ++i) {
            const match = lines[i].match(/^\s*([A-Za-z0-9_]+)\s*=\s*["'](#[0-9A-Fa-f]{6})["']/);
            if (match) values[match[1]] = match[2];
        }
        colors = {
            background: values.background || values.color0 || "#20232b",
            foreground: values.foreground || values.color7 || "#eef0f6",
            accent: values.accent || values.color4 || "#a7c7ff"
        };
        paletteSource = values.background || values.color0 ? "omarchy" : "fallback";
    }
    FileView {
        id: paletteFile
        path: root.themePath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadPalette(text())
        onFileChanged: reload()
        onLoadFailed: root.loadPalette("")
    }
    function themedIcon(candidates: var): string {
        for (let i = 0; i < candidates.length; ++i)
            if (Quickshell.hasThemeIcon(candidates[i]))
                return Quickshell.iconPath(candidates[i], true);
        return Quickshell.iconPath("application-x-executable", true);
    }
    readonly property var controlIcons: ({
        menu: themedIcon(["preferences-system", "configure", "start-here"]),
        "omarchy-menu": themedIcon(["omarchy", "start-here", "application-menu", "open-menu"])
    })
    Variants {
        id: surfaces
        model: Quickshell.screens
        delegate: DockSurface {
            required property var modelData
            outputScreen: modelData
            controller: root
        }
    }
    function show(): void { surfaceEnabled = true; }
    function hide(): void { surfaceEnabled = false; }
    function open(payload: string): void { show(); }
    function close(): void { hide(); }
    function setMode(value: string): bool {
        if (["wave", "zoom", "off"].indexOf(value) < 0) return false;
        return appService.configure({motionMode: value});
    }
    function setReducedMotion(value: bool): bool { return appService.configure({reducedMotion: value}); }
    function setShowAppNames(value: bool): bool { return appService.configure({showAppNames: value}); }
    function setShowAppsButton(value: bool): bool { return appService.configure({showAppsButton: value}); }
    function setAdvancedTooltips(value: bool): bool { return appService.configure({advancedTooltips: value}); }
    function setLaunchBounce(value: bool): bool { return appService.configure({launchBounce: value}); }
    function configureDelays(patch: var): int { return appService.configure(patch); }
    function setAutoHide(value: bool): bool { return appService.configure({autoHide: value}); }
    function setIntelligentHide(value: bool): bool { return appService.configure({intelligentHide: value}); }
    function setReserveSpace(value: bool): bool { return appService.configure({reserveSpace: value}); }
    function setMinimizeMode(value: string): bool {
        if (["active", "all", "off"].indexOf(value) < 0) return false;
        return appService.configure({minimizeMode: value});
    }
    function setIconSize(value: real): bool {
        if (!isFinite(value) || Math.round(value) !== value || (value !== 0 && (value < 28 || value > 72))) return false;
        return appService.configure({iconSize: value});
    }
    function setZoomSize(value: real): bool {
        if (!Number.isInteger(value) || value < 100 || value > 200) return false;
        return appService.configure({zoomSize: value});
    }
    function setWaveWidth(value: real): bool {
        if (!Number.isInteger(value) || value < 10 || value > 50 || value % 5 !== 0) return false;
        return appService.configure({waveWidth: value});
    }
    function setTransparency(value: real): bool {
        if (!isFinite(value) || Math.round(value) !== value || value < 0 || value > 100) return false;
        return appService.configure({transparency: value});
    }
    function representative(): var {
        for (const surface of surfaces.instances)
            if (surface.selected) return surface;
        return surfaces.instances.length ? surfaces.instances[0] : null;
    }
    function keyboard(): void {
        const surface = representative();
        if (!surface || !surface.selected) return;
        show();
        surface.enterKeyboard();
    }
    function claimKeyboard(surface: var): void {
        Logic.claimKeyboard(surfaces.instances, surface);
    }
    function settings(output: string, opened: bool): bool {
        for (const surface of surfaces.instances)
            if (surface.outputName === output) return surface.setSettingsOpen(opened);
        return false;
    }
    function folderAction(id: string, action: var): bool {
        // The bridge already captured a generation-validated value object.
        // Release keyboard ownership before the helper can open another app.
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.folderAction(id, action);
    }
    function activate(id: string): bool {
        // Relinquish all layer keyboard ownership before requesting app focus.
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.activate(id, attention.urgentKey(id));
    }
    function context(output: string, id: string): bool {
        for (const surface of surfaces.instances)
            if (surface.outputName === output) return surface.openAppContext(id);
        return false;
    }
    function windowState(id: string): var {
        const rows = windowGroups[id];
        return Array.isArray(rows) ? rows.map(w => ({key: w.key, active: w.active})) : [];
    }
    function actionState(id: string): var {
        const rows = desktopActionGroups[id];
        return Array.isArray(rows) ? rows.map(a => ({id: a.id, name: a.name})) : [];
    }
    function actionChooser(output: string, id: string): bool {
        for (const surface of surfaces.instances)
            if (surface.outputName === output) return surface.openDesktopActions(id);
        return false;
    }
    function desktopAction(id: string, actionId: string): bool {
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.desktopAction(id, actionId);
    }
    function windowChooser(output: string, id: string): bool {
        for (const surface of surfaces.instances)
            if (surface.outputName === output) return surface.openWindowChooser(id);
        return false;
    }
    function activateWindow(id: string, key: string): bool {
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.activateWindow(id, key);
    }
    function closeWindow(id: string, key: string): bool {
        // Native applications may display a save prompt; relinquish the grab.
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.closeWindow(id, key);
    }
    function cycleWindows(id: string, delta: real): bool {
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.cycleWindows(id, delta);
    }
    function closeApplication(id: string, keys: var): bool {
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.closeApplication(id, keys);
    }
    function restoreApplication(id: string, keys: var, mode: string): int {
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.restoreApplication(id, keys, mode);
    }
    function minimizeActive(): int {
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.minimizeActive();
    }
    function minimizeApplication(id: string): int {
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.minimizeApplication(id);
    }
    function parkWindow(id: string, key: string): int {
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.parkWindow(id, key);
    }
    function restoreWindow(id: string, key: string, mode: string): int {
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.restoreWindow(id, key, mode);
    }
    function restoreFifo(mode: string): int { return appService.restoreFifo(mode); }
    function recoverParked(mode: string): int { return appService.recoverParked(mode); }
    function editor(output: string, id: string): bool {
        for (const surface of surfaces.instances)
            if (surface.outputName === output) return surface.openItemEditor(id);
        return false;
    }
    function newInstance(id: string): bool {
        for (const surface of surfaces.instances) surface.releaseInteractions();
        return appService.newInstance(id);
    }
    function saveLauncher(recordJson: string): int {
        try { return appService.saveLauncher(JSON.parse(recordJson)); }
        catch (_) { return 0; }
    }
    function removeLauncher(id: string): bool { return appService.removeLauncher(id); }
    function duplicateLauncher(id: string): bool { return appService.duplicateLauncher(id); }
    function setOverride(appId: string, desktopId: string): bool { return appService.setOverride(appId, desktopId); }
    function recoverConfiguration(): bool { return appService.recoverConfiguration(); }
    function pin(id: string, pinned: bool): bool { return appService.setPinned(id, pinned); }
    function reorderApps(idsJson: string): bool {
        let ids;
        try { ids = JSON.parse(idsJson); } catch (_) { return false; }
        return appService.reorder(ids);
    }
    function fixtureApps(dataJson: string): bool {
        if (!testMode) return false;
        try {
            const data = JSON.parse(dataJson);
            if (!data || !Array.isArray(data.entries) || !Array.isArray(data.windows)) return false;
            return appService.fixtureSet(data.entries, data.windows);
        } catch (_) { return false; }
    }
    function snapshot(): string {
        const outputs = [];
        for (const surface of surfaces.instances) outputs.push(surface.snapshot());
        const surface = representative();
        const first = surface ? surface.snapshot() : null;
        const visible = outputs.some(function(output) { return output.visible; });
        return JSON.stringify({
            phase: phase, nonlaunching: nonlaunching, testMode: testMode, screenCount: screenCount,
            apps: applications, appsReady: appService.ready, appError: appError,
            launcherRecords: launcherRecords, desktopEntries: desktopEntries, canRecover: canRecover,
            parkingReady: parkingReady, parkingBusy: parkingBusy, parkedWindows: parkedWindows,
            parkingRevision: parkingRevision, lastParkingReceipt: lastParkingReceipt,
            visible: visible, output: first ? first.name : "", requestedOutput: requestedOutput,
            fallback: legacyPolicy ? outputPolicy.fallback : false,
            fallbackReason: legacyPolicy ? outputPolicy.reason : (activeOutputs.length ? monitorMode : "no-selected-outputs"),
            width: first ? first.width : 520, height: first ? first.height : 184, offset: offset,
            mode: motionMode, reducedMotion: reducedMotion, autoHide: autoHide, minimizeMode: minimizeMode,
            iconSize: iconSize, transparency: transparency,
            keyboardFocus: first ? first.keyboardFocus : "none",
            paletteSource: paletteSource, palette: colors, icons: controlIcons,
            view: first ? first.view : null,
            monitorMode: monitorMode, selectedOutputs: selectedOutputs,
            monitorError: monitorError,
            activeOutputs: activeOutputs, outputs: outputs
        });
    }
}
