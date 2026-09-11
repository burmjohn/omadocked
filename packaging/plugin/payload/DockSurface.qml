pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "ui"
import "services"
import "core/DockLogic.js" as Logic

// One disposable presentation per physical screen; no shared service readers.
Item {
    id: root
    required property ShellScreen outputScreen
    required property var controller
    readonly property string outputName: outputScreen ? outputScreen.name : ""
    readonly property bool selected: controller.activeOutputs.indexOf(outputName) >= 0
    readonly property bool mapped: controller.surfaceEnabled && selected && outputScreen !== null
    readonly property bool outputRoutingLocked: mapped && view.outputRoutingLocked
    readonly property bool attentionVisible: mapped && panel.backingWindowVisible && !view.surfaceSuspended
        && view.visibilityState !== "hidden" && view.visibilityState !== "revealing"
    OverlapConsumer {
        source: root.controller.overlapSource
        key: root.outputName
        mapped: root.mapped && panel.backingWindowVisible
        enabled: root.controller.intelligentHide
    }
    readonly property var overlapPolicy: {
        const source = controller.overlapSource;
        if (!source || !outputScreen) return {available:false, overlap:false, fullscreen:false};
        const shelf = source.shelfFor(outputName, outputScreen.width, outputScreen.height,
            view.order.length * view.slotSize + 24, view.dockHeight, controller.offset);
        return source.evaluate(outputName, shelf);
    }
    // A grab requested before the compositor accepts the popup-sized surface is
    // cleared immediately. Wait for native geometry, not an arbitrary delay.
    readonly property bool popupReady: mapped && (view.settingsOpen || view.contextIndex >= 0) && panel.backingWindowVisible
        && Logic.nativeSizeMatches(panel.width, panel.height, view.width, view.height)
    onPopupReadyChanged: popupGrab.active = popupReady
    function reconcile(): void {
        if (!mapped) view.resetSurface();
        else {
            view.surfaceSuspended = false;
            view.visibilityState = "shown";
            view.updateVisibility();
        }
    }
    onMappedChanged: reconcile()
    Component.onCompleted: reconcile()
    Component.onDestruction: view.resetSurface()
    Connections {
        target: root.controller
        function onPersistenceCompleted(transactionId, ok, message) {
            view.launcherSaveResult(transactionId, ok);
            view.folderSaveResult(transactionId, ok);
        }
    }
    function enterKeyboard(): void { if (mapped) view.enterKeyboard(); }
    function releaseInteractions(): void { view.releaseInteractions(); }
    function setSettingsOpen(value: bool): bool {
        if (!mapped) return false;
        view.settingsOpen = value;
        return true;
    }
    function openAppContext(id: string): bool {
        const index = view.order.indexOf(id);
        if (!mapped || index < 1) return false;
        view.openContext(index);
        return true;
    }
    function openItemEditor(id: string): bool {
        return mapped && view.openItemEditor(id);
    }
    function openWindowChooser(id: string): bool {
        return mapped && view.openWindowChooser(id);
    }
    function openDesktopActions(id: string): bool {
        return mapped && view.openDesktopActions(id);
    }
    FolderIntegration { view: view; controller: root.controller }
    PreviewIntegration {
        view: view
        controller: root.controller
        mapped: root.mapped && panel.backingWindowVisible
        driverComponent: Component { NativeCapture {} }
    }
    HyprlandFocusGrab {
        id: popupGrab
        windows: [panel]
        onCleared: view.releaseInteractions()
    }
    PanelWindow {
        id: panel
        screen: root.outputScreen
        visible: root.mapped

        anchors.bottom: true
        margins.bottom: root.controller.offset
        implicitWidth: view.width
        implicitHeight: view.height
        color: "transparent"
        // Explicit zone, never Auto (popup height must not reserve the desktop).
        exclusiveZone: root.mapped ? view.reservedHeight : 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "omadocked-prototype"
        WlrLayershell.keyboardFocus: visible && view.wantsKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        mask: Region {
            x: view.triggerRect.x; y: view.triggerRect.y
            width: view.triggerRect.width; height: view.triggerRect.height
            radius: 3
            Region {
                intersection: Intersection.Combine
                x: Math.floor(view.shelfRect.x); y: Math.floor(view.shelfRect.y)
                width: view.effectiveProgress > 0 ? Math.ceil(view.shelfRect.width) : 0
                height: view.effectiveProgress > 0 ? Math.ceil(view.shelfRect.height) : 0
                radius: 22
            }
            Region {
                intersection: Intersection.Combine
                x: Math.floor(view.popupRect.x); y: Math.floor(view.popupRect.y)
                width: Math.ceil(view.popupRect.width); height: Math.ceil(view.popupRect.height)
            }
            Region {
                intersection: Intersection.Combine
                x: Math.floor(view.fanRect.x); y: Math.floor(view.fanRect.y)
                width: Math.ceil(view.fanRect.width); height: Math.ceil(view.fanRect.height)
                radius: 14
            }
            Region {
                intersection: Intersection.Combine
                x: Math.floor(view.fanBridgeRect.x); y: Math.floor(view.fanBridgeRect.y)
                width: Math.ceil(view.fanBridgeRect.width); height: Math.ceil(view.fanBridgeRect.height)
            }
        }
        DockView {
            id: view
            settingsManaged: true
            appsManaged: true
            applications: root.controller.applications
            windowGroups: root.controller.windowGroups
            previewsEnabled: root.controller.previewsEnabled
            attentionApps: root.controller.attentionHints
            attentionPresentationEnabled: root.controller.attentionAllowed && root.mapped && panel.backingWindowVisible
            attentionDnd: root.controller.attentionDnd
            notificationStatus: root.controller.notificationStatus
            soundStatus: root.controller.soundStatus
            showUrgentHint: root.controller.showUrgentHint
            urgentOnNotification: root.controller.urgentOnNotification
            urgentSound: root.controller.urgentSound
            urgentSoundName: root.controller.urgentSoundName
            onAttentionSettingsRequested: patch => root.controller.configureAttention(patch)
            soundSampleStatus: root.controller.soundSampleStatus
            onSoundSampleRequested: root.controller.sampleSound()
            livePreviews: root.controller.livePreviews
            onPreviewsEnabledRequested: value => root.controller.setPreviewsEnabled(value)
            onLivePreviewsRequested: value => root.controller.setLivePreviews(value)
            parkedWindows: root.controller.parkedWindows
            desktopActions: root.controller.desktopActionGroups
            onDesktopActionRequested: (id, actionId) => root.controller.desktopAction(id, actionId)
            onActivateWindowRequested: (id, key) => root.controller.activateWindow(id, key)
            onCloseWindowRequested: (id, key) => root.controller.closeWindow(id, key)
            onCloseApplicationRequested: (id, keys) => root.controller.closeApplication(id, keys)
            onRestoreApplicationRequested: (id, keys, mode) => root.controller.restoreApplication(id, keys, mode)
            onCycleWindowsRequested: (id, delta) => root.controller.cycleWindows(id, delta)
            onMinimizeRequested: id => root.controller.minimizeApplication(id)
            onRestoreWindowRequested: (id, key, mode) => root.controller.restoreWindow(id, key, mode)
            onRecoverParkedRequested: mode => root.controller.recoverParked(mode)
            appError: root.controller.appError
            launcherRecords: root.controller.launcherRecords
            desktopEntries: root.controller.desktopEntries
            canRecover: root.controller.canRecover
            persistenceEnabled: true
            onRecoverRequested: root.controller.recoverConfiguration()
            onOverrideRequested: (appId, desktopId) => root.controller.setOverride(appId, desktopId)
            onSaveLauncherRequested: record => launcherSaveAccepted(root.controller.saveLauncher(JSON.stringify(record)))
            onRemoveLauncherRequested: id => root.controller.removeLauncher(id)
            onDuplicateLauncherRequested: id => root.controller.duplicateLauncher(id)
            onNewInstanceRequested: id => root.controller.newInstance(id)
            onShellGestureRequested: (kind, delta) => root.controller.shellGesture(kind, delta)
            onActivateRequested: id => root.controller.activate(id)
            onPinRequested: (id, pinned) => root.controller.pin(id, pinned)
            onReorderRequested: ids => root.controller.reorderApps(JSON.stringify(ids))
            motionMode: root.controller.motionMode
            reducedMotion: root.controller.reducedMotion
            showAppNames: root.controller.showAppNames
            advancedTooltips: root.controller.advancedTooltips
            onAdvancedTooltipsRequested: value => root.controller.setAdvancedTooltips(value)
            launchBounce: root.controller.launchBounce
            tooltipDelay: root.controller.tooltipDelay
            revealDelay: root.controller.revealDelay
            onDelaySettingsRequested: patch => root.controller.configureDelays(patch)
            onShowAppNamesRequested: value => root.controller.setShowAppNames(value)
            showAppsButton: root.controller.showAppsButton
            onShowAppsButtonRequested: value => root.controller.setShowAppsButton(value)
            onLaunchBounceRequested: value => root.controller.setLaunchBounce(value)
            autoHide: root.controller.autoHide
            intelligentHide: root.controller.intelligentHide
            reserveSpace: root.controller.reserveSpace
            onReserveSpaceRequested: value => root.controller.setReserveSpace(value)
            nativeOverlapAvailable: root.overlapPolicy.available
            nativeOverlap: root.overlapPolicy.overlap
            nativeFullscreen: root.overlapPolicy.fullscreen
            onPointerInsideChanged: if (root.controller.overlapSource) root.controller.overlapSource.refresh()
            onOverTriggerChanged: if (root.controller.overlapSource) root.controller.overlapSource.refresh()
            onIntelligentHideRequested: value => root.controller.setIntelligentHide(value)
            minimizeMode: root.controller.minimizeMode
            zoomSize: root.controller.zoomSize
            waveWidth: root.controller.waveWidth
            onZoomSizeRequested: value => root.controller.setZoomSize(value)
            onWaveWidthRequested: value => root.controller.setWaveWidth(value)
            iconSize: root.controller.iconSize
            transparency: root.controller.transparency
            appearanceSettings: root.controller.appearanceSettings
            themeCornerRadius: root.controller.themeCornerRadius
            themeBackground: root.controller.themeBackground
            onAppearanceSettingsRequested: patch => root.controller.configureAppearance(patch)
            homePath: root.controller.homePath
            folderColor: root.controller.folderColor
            folderPersistenceBusy: root.controller.persistenceBusy
            onFolderPresetRequested: name => root.controller.toggleFolder(name === "Home" ? homePath : homePath + "/" + name, name)
            onFolderColorRequested: color => root.controller.setFolderColor(color)
            onFolderAddRequested: (path, name) => folderSaveAccepted(root.controller.addFolder(path, name))
            availableWidth: root.outputScreen ? root.outputScreen.width : 10000
            availableHeight: root.outputScreen ? Math.max(1, root.outputScreen.height - root.controller.offset) : 1080
            availableOutputs: root.controller.availableOutputs
            monitorMode: root.controller.monitorMode
            followActiveOutput: root.controller.followActiveOutput
            onFollowActiveOutputRequested: value => root.controller.setFollowActiveOutput(value)
            selectedOutputs: root.controller.selectedOutputs
            onModeRequested: value => root.controller.setMode(value)
            onReducedMotionRequested: value => root.controller.setReducedMotion(value)
            onAutoHideRequested: value => root.controller.setAutoHide(value)
            onMinimizeModeRequested: value => root.controller.setMinimizeMode(value)
            onIconSizeRequested: value => root.controller.setIconSize(value)
            onTransparencyRequested: value => root.controller.setTransparency(value)
            onSettingsOpenChanged: {
                if (settingsOpen) root.controller.claimKeyboard(root);
            }
            onMonitorsRequested: (mode, names) => root.controller.monitors(mode, JSON.stringify(names))
            onWantsKeyboardChanged: if (wantsKeyboard) root.controller.claimKeyboard(root)
            icons: root.controller.controlIcons
            shelfColor: root.controller.colors.background
            textColor: root.controller.colors.foreground
            accentColor: root.controller.colors.accent
        }
    }
    function snapshot(): var {
        return {
            name: outputName, selected: selected, visible: panel.visible,
            popupGrabActive: popupGrab.active,
            width: view.width, height: view.height,
            keyboardFocus: panel.visible && view.wantsKeyboard ? "exclusive" : "none",
            view: {
                state: view.visibilityState, order: view.order, selection: view.selection,
                pointerInside: view.pointerInside, overTrigger: view.overTrigger,
                interactionLocked: view.interactionLocked,
                actionLabel: view.actionLabel, keyboardActive: view.keyboardActive,
                focusIndex: view.focusIndex, dragActive: view.dragActive,
                insertionIndex: view.insertionIndex, shelfProgress: view.effectiveProgress,
                inputRects: view.inputRects, renderedSlots: view.renderedSlots,
                monitorPickerOpen: view.monitorPickerOpen, contextIndex: view.contextIndex,
                mode: view.motionMode, reducedMotion: view.reducedMotion, autoHide: view.autoHide, minimizeMode: view.minimizeMode,
                zoomSize: view.zoomSize, waveWidth: view.waveWidth,
                iconSize: view.iconSize, baseIconSize: view.baseIconSize, transparency: view.transparency,
                settingsOpen: view.settingsOpen, editorOpen: view.editorOpen, popupRect: view.popupRect,
                windowChooserOpen: view.windowChooserOpen, windowSelectionKey: view.windowSelectionKey,
                desktopActionsOpen: view.desktopActionsOpen, desktopActionSelectionId: view.desktopActionSelectionId
            }
        };
    }
}
