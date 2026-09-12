pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Window
import "../core/DockLogic.js" as Logic
import "../core/ParitySettings.js" as Parity
import "../core/GestureLogic.js" as Gestures

// Pure presentation: applications arrive from the shared service; actions are signals only.
FocusScope {
    id: root
    property var appearanceSettings: ({shape:"rounded", itemSpacing:4, backgroundColor:"theme", themeOpacity:false})
    readonly property string backgroundColor: appearanceSettings.backgroundColor || "theme"
    readonly property bool themeOpacity: appearanceSettings.themeOpacity === true
    readonly property int itemSpacing: appearanceSettings.itemSpacing === undefined ? 4 : appearanceSettings.itemSpacing
    property real themeCornerRadius: -1
    property color themeBackground: shelfColor
    signal appearanceSettingsRequested(var patch)
    onAppearanceSettingsRequested: patch => {
        if (!settingsManaged) appearanceSettings = Object.assign({}, appearanceSettings, patch);
    }
    property int transparency: 0
    readonly property int effectiveTransparency: transparencySlider.previewing ? Math.round(transparencySlider.value) : transparency
    signal transparencyRequested(int value)
    onTransparencyRequested: value => { if (!settingsManaged) transparency = value; }
    property int iconSize: 44
    readonly property int resolvedIconSize: Logic.resolveIconSize(iconSize, Screen.devicePixelRatio)
    readonly property int effectiveIconSize: sizeSlider.previewing && iconSize !== 0 ? Math.round(sizeSlider.value) : resolvedIconSize
    property bool showAppsButton: true
    signal showAppsButtonRequested(bool value)
    onShowAppsButtonRequested: value => { if (!settingsManaged) showAppsButton = value; }
    property real availableWidth: 10000
    property real availableHeight: 1080
    // Half-slot wave radii sum to at most radius on the fixed slot grid.
    // Keep the original 1.2-icon reserve as a floor for unchanged default fit.
    readonly property real expansionCapacity: Math.max(1.2, (peakScale - 1) * Math.min(order.length, effectiveWaveWidth / 10))
    // Fit the renderer, not the requested setting, with room for the shelf rim.
    readonly property int baseIconSize: Math.max(1, Math.min(effectiveIconSize,
        Math.floor((width - 24) / (order.length + expansionCapacity + (order.length - 1) * itemSpacing / 44))))
    signal iconSizeRequested(int value)
    onIconSizeRequested: value => { if (!settingsManaged) iconSize = value; }
    property int zoomSize: 145 // percent of base icon size
    property int waveWidth: 25 // tenths of a slot; half-slot steps
    readonly property int effectiveZoomSize: zoomSlider.previewing ? Math.round(zoomSlider.value) : zoomSize
    readonly property int effectiveWaveWidth: waveSlider.previewing ? Math.round(waveSlider.value) : waveWidth
    signal zoomSizeRequested(int value)
    signal waveWidthRequested(int value)
    onZoomSizeRequested: value => { if (!settingsManaged) zoomSize = value; }
    onWaveWidthRequested: value => { if (!settingsManaged) waveWidth = value; }
    readonly property real peakScale: effectiveZoomSize / 100
    property string motionMode: "wave"
    property bool reducedMotion: false
    property bool showAppNames: true
    property bool advancedTooltips: false
    signal advancedTooltipsRequested(bool value)
    onAdvancedTooltipsRequested: value => { if (!settingsManaged) advancedTooltips = value; }
    property bool launchBounce: true
    signal launchBounceRequested(bool value)
    onLaunchBounceRequested: value => { if (!settingsManaged) launchBounce = value; }
    signal showAppNamesRequested(bool value)
    onShowAppNamesRequested: value => { if (!settingsManaged) showAppNames = value; }
    signal delaySettingsRequested(var patch)
    onDelaySettingsRequested: patch => {
        if (!settingsManaged) {
            if (patch.tooltipDelay !== undefined) tooltipDelay = patch.tooltipDelay;
            if (patch.revealDelay !== undefined) revealDelay = patch.revealDelay;
        }
    }
    onShowAppNamesChanged: {
        clearTooltip();
        appTooltip.hideImmediately();
        refreshTooltip();
    }
    onReducedMotionChanged: if (reducedMotion) {
        clearTooltip();
        appTooltip.hideImmediately();
        refreshTooltip();
    }
    property var attentionApps: []
    property bool attentionPresentationEnabled: false
    property bool attentionDnd: true
    property string notificationStatus: "unavailable"
    property string soundStatus: "unavailable: host DND/unlock state required"
    property bool showUrgentHint: true
    property bool urgentOnNotification: true
    property bool urgentSound: false
    property string urgentSoundName: "bell"
    signal attentionSettingsRequested(var patch)
    property string soundSampleStatus: "unavailable: host DND/unlock state required"
    signal soundSampleRequested()
    property bool settingsManaged: false
    signal modeRequested(string value)
    signal reducedMotionRequested(bool value)
    signal autoHideRequested(bool value)
    signal intelligentHideRequested(bool value)
    signal reserveSpaceRequested(bool value)
    onReserveSpaceRequested: value => { if (!settingsManaged) reserveSpace = value; }
    property string minimizeMode: "active"
    signal minimizeModeRequested(string value)
    onModeRequested: value => { if (!settingsManaged) motionMode = value; }
    onReducedMotionRequested: value => { if (!settingsManaged) reducedMotion = value; }
    onAutoHideRequested: value => { if (!settingsManaged) autoHide = value; }
    onIntelligentHideRequested: value => { if (!settingsManaged) intelligentHide = value; }
    onMinimizeModeRequested: value => { if (!settingsManaged) minimizeMode = value; }
    property var availableOutputs: []
    property string monitorMode: "all"
    property bool followActiveOutput: false
    signal followActiveOutputRequested(bool value)
    onFollowActiveOutputRequested: value => { if (!settingsManaged) followActiveOutput = value; }
    property var selectedOutputs: []
    signal monitorsRequested(string mode, var names)
    onMonitorsRequested: (mode, names) => {
        if (!settingsManaged) { monitorMode = mode; selectedOutputs = names.slice(); }
    }
    function toggleOutput(name: string): void {
        const names = monitorMode === "all" ? availableOutputs.slice() : selectedOutputs.slice();
        const index = names.indexOf(name);
        if (index < 0) names.push(name);
        else names.splice(index, 1);
        // Retained disconnected names cannot substitute for an accessible dock.
        if (!Logic.activeOutputs(availableOutputs, "selected", names).length) return;
        monitorsRequested("selected", names);
    }
    property bool settingsOpen: false
    property bool editorOpen: false
    property var launcherRecords: []
    property var desktopEntries: []
    property bool canRecover: false
    property bool persistenceEnabled: false
    property int launcherSaveTransactionId: 0
    readonly property bool launcherSavePending: launcherSaveTransactionId > 0
    signal recoverRequested()
    signal overrideRequested(string appId, string desktopId)
    signal saveLauncherRequested(var record)
    signal removeLauncherRequested(string id)
    signal duplicateLauncherRequested(string id)
    signal newInstanceRequested(string id)
    signal shellGestureRequested(string kind, real delta)
    function openItemEditor(id: string): bool {
        const record = id ? launcherRecords.find(item => item.id === id) : {};
        if (!record) return false;
        launcherSaveTransactionId = 0;
        cancelDrag();
        contextIndex = -1;
        settingsOpen = true;
        editorOpen = true;
        itemEditor.begin(record);
        return true;
    }
    function closeItemEditor(): void {
        editorOpen = false;
        if (settingsOpen) addItem.forceActiveFocus();
    }
    function launcherSaveAccepted(transactionId: int): void {
        if (transactionId > 0 && launcherSaveTransactionId === 0)
            launcherSaveTransactionId = transactionId;
    }
    function launcherSaveResult(transactionId: int, success: bool): void {
        if (transactionId !== launcherSaveTransactionId)
            return;
        launcherSaveTransactionId = 0;
        if (success) closeItemEditor();
    }
    onSettingsOpenChanged: {
        if (settingsOpen) {
            if (popupGestureBusy) beginPopupSettle()
            else popupSettling = false
        } else {
            if (contextIndex < 0) { popupSettling = false; popupSettleTimer.stop() }
            editorOpen = false
            sizeSlider.cancelPreview()
            transparencySlider.cancelPreview()
            zoomSlider.cancelPreview()
            waveSlider.cancelPreview()
            tooltipDelaySlider.cancelPreview()
            revealDelaySlider.cancelPreview()
        }
    }
    onEditorOpenChanged: if (!editorOpen) {
        // The transaction can finish, but no longer owns this disposable draft.
        launcherSaveTransactionId = 0;
    } else {
        sizeSlider.cancelPreview();
        transparencySlider.cancelPreview();
        zoomSlider.cancelPreview();
        waveSlider.cancelPreview();
        tooltipDelaySlider.cancelPreview();
        revealDelaySlider.cancelPreview();
    }
    readonly property bool monitorPickerOpen: settingsOpen
    function closeMonitorPicker(): void { settingsOpen = false; }
    function toggleMonitorPicker(): void {
        cancelDrag();
        contextIndex = -1;
        settingsOpen = !settingsOpen;
    }
    component TuneButton: Button {
        id: control
        property bool chosen: false
        height: 30
        width: 70
        focusPolicy: Qt.StrongFocus
        background: Rectangle {
            radius: 7
            color: Qt.alpha(root.accentColor, control.chosen ? 0.22 : control.hovered ? 0.12 : 0.05)
            border.width: control.activeFocus ? 2 : 1
            border.color: Qt.alpha(root.accentColor, control.activeFocus ? 1 : control.chosen ? 0.5 : 0.12)
        }
        contentItem: Text {
            text: control.text
            color: control.chosen ? root.accentColor : root.textColor
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
        }
        Accessible.name: text
    }
    component AppearanceButton: TuneButton {
        required property var requestPatch
        property int pressWheelGeneration: -1
        onPressed: pressWheelGeneration = settingsScroll.wheelGeneration
        onClicked: if (pressWheelGeneration === settingsScroll.wheelGeneration)
            root.appearanceSettingsRequested(requestPatch)
        Accessible.onPressAction: root.appearanceSettingsRequested(requestPatch)
    }
    component PreviewSlider: Slider {
        id: control
        required property int committedValue
        property bool tracking: false
        readonly property bool previewing: tracking && pressed && root.settingsOpen && !root.editorOpen
        signal commitRequested(int value)
        value: committedValue
        live: true
        function cancelPreview(): void {
            tracking = false;
            value = Qt.binding(() => committedValue);
        }
        onPressedChanged: {
            if (pressed) tracking = true;
            else {
                const commit = tracking && root.settingsOpen && !root.editorOpen && Math.round(value) !== committedValue;
                tracking = false;
                if (commit) commitRequested(Math.round(value));
                value = Qt.binding(() => committedValue);
            }
        }
        onMoved: if (!pressed && root.settingsOpen && !root.editorOpen) {
            commitRequested(Math.round(value));
            value = Qt.binding(() => committedValue);
        }
    }
    property real pointerX: -1
    property real lastPointerX: rowX + slotSize / 2
    onPointerXChanged: {
        if (pointerX >= 0)
            lastPointerX = pointerX;
    }
    property real motionX: lastPointerX
    property real hoverStrength: pointerX >= 0 ? 1 : 0
    Behavior on motionX {
        NumberAnimation {
            duration: root.reducedMotion ? 0 : 100
            easing.type: Easing.OutCubic
        }
    }
    Behavior on hoverStrength {
        NumberAnimation {
            duration: root.reducedMotion ? 0 : 100
            easing.type: Easing.OutCubic
        }
    }
    readonly property var renderedSlots: {
        const scales = [];
        for (let i = 0; i < order.length; ++i)
            scales.push(1 + (Logic.scaleAt(i, motionX, rowX, slotSize, motionMode, reducedMotion, dragActive, peakScale, effectiveWaveWidth / 10) - 1) * hoverStrength);
        return Logic.layout(scales, width / 2, baseIconSize, iconGap);
    }
    function hitIndex(px: real): int {
        for (let i = 0; i < renderedSlots.length; ++i)
            if (px >= renderedSlots[i].left - 2 && px < renderedSlots[i].right + 2)
                return i;
        return -1;
    }
    function insertionAt(px: real): int {
        for (let i = 0; i < renderedSlots.length; ++i)
            if (px < renderedSlots[i].center)
                return Math.max(Logic.chromeIds(showAppsButton).length, i);
        return order.length;
    }
    readonly property int hoveredIndex: pointerX < 0 ? -1 : hitIndex(pointerX)
    property int tooltipIndex: -1
    property bool overCaption: false
    property int tooltipDelay: 450
    readonly property bool tooltipEligible: visible && !surfaceSuspended && !interactionLocked && shelfVisible
    function clearTooltip(): void {
        tooltipTimer.stop();
        tooltipLeaveTimer.stop();
        tooltipIndex = -1;
        overCaption = false;
    }
    function refreshTooltip(): void {
        if (!tooltipEligible || (hoveredIndex >= 0 && !showAppNames && !Logic.isChromeId(order[hoveredIndex]))) { clearTooltip(); return; }
        if (hoveredIndex < 0) {
            tooltipTimer.stop();
            if (overCaption && tooltipIndex >= 0) {
                tooltipLeaveTimer.stop();
                return;
            }
            if (tooltipIndex >= 0) tooltipLeaveTimer.restart();
            else clearTooltip();
        } else {
            tooltipLeaveTimer.stop();
            if (tooltipIndex >= 0) tooltipIndex = hoveredIndex;
            else tooltipTimer.restart();
        }
    }
    onHoveredIndexChanged: { refreshTooltip(); refreshFan(); }
    // Reserve headroom even while closed: opening must not move native hit targets.
    readonly property real fanHeadroom: Math.max(0, Math.min(112, availableHeight - dockHeight))
    readonly property var activeWindowFan: windowFan
    property var fanPreviewSources: ({})
    property string fanApp: ""
    property string fanPendingApp: ""
    property real fanAnchorX: 0
    property real fanAnchorWidth: 0
    readonly property bool fanOpen: fanApp !== ""
    readonly property bool fanEligible: visible && !surfaceSuspended && windowActionsAllowed
        && shelfVisible && !wantsKeyboard && !dragActive && pressedIndex < 0 && fanHeadroom >= 104
    readonly property rect fanRect: fanOpen ? Qt.rect(windowFan.x, windowFan.y, windowFan.width, windowFan.height) : Qt.rect(0,0,0,0)
    readonly property rect fanBridgeRect: fanOpen ? Qt.rect(Math.max(0, Math.min(width - fanAnchorWidth, fanAnchorX - fanAnchorWidth / 2)),
        windowFan.y + windowFan.height, fanAnchorWidth, Math.max(0, height - dockHeight - windowFan.y - windowFan.height + 2)) : Qt.rect(0,0,0,0)
    function canFan(id: string): bool { return fanEligible && canChooseWindows(id) && windowGroups[id].length >= 2; }
    function dismissFan(immediate: bool): void {
        fanDwell.stop(); fanLeave.stop(); fanPendingApp = ""; fanApp = "";
        if (immediate) windowFan.clearImmediately();
    }
    function refreshFan(): void {
        if (!fanEligible) { dismissFan(true); return; }
        const id = order[hoveredIndex] || "";
        if (fanOpen && id === fanApp) { fanLeave.stop(); return; }
        fanDwell.stop(); fanPendingApp = "";
        if (hoveredIndex < 0) { if (fanOpen) fanLeave.restart(); return; }
        fanLeave.stop(); // A close-induced exit cannot cancel a new entry's dwell.
        // Retarget only after a fresh dwell, never replay a previous app's timer.
        if (fanOpen) dismissFan(true);
        if (canFan(id)) { fanPendingApp = id; fanDwell.restart(); }
    }
    onFanEligibleChanged: if (!fanEligible) dismissFan(true)
    Timer {
        id: fanDwell
        interval: 240
        onTriggered: {
            const id = root.fanPendingApp;
            if (!root.canFan(id) || root.order[root.hoveredIndex] !== id) return;
            const slot = root.renderedSlots[root.hoveredIndex];
            root.fanAnchorX = slot.center;
            root.fanAnchorWidth = Math.max(24, slot.right - slot.left + 8);
            root.fanApp = id;
            root.fanPendingApp = "";
            root.clearTooltip(); appTooltip.hideImmediately();
        }
    }
    Timer {
        id: fanLeave
        interval: 200
        onTriggered: if (!windowFan.hovered && !fanBridge.containsMouse
            && !(root.pointerInside && root.order[root.hoveredIndex] === root.fanApp)) root.dismissFan(false)
    }
    WindowFan {
        id: windowFan
        objectName: "window-fan"
        z: 30
        opened: root.fanOpen
        previewSources: root.fanPreviewSources
        appId: root.fanApp
        appName: root.appName(appId)
        windows: root.windowGroups[appId] || []
        iconSource: (root.appMeta[appId] || {}).icon || root.icons[appId] || ""
        reducedMotion: root.reducedMotion
        maximumWidth: Math.max(1, Math.min(520, root.width - 16))
        backgroundColor: root.shelfColor; textColor: root.textColor; accentColor: root.accentColor
        x: Math.max(8, Math.min(root.width - width - 8, root.fanAnchorX - width / 2))
        y: root.height - root.dockHeight - height - 12
        onEntered: fanLeave.stop()
        onExited: if (root.fanOpen) fanLeave.restart()
        onActivateRequested: key => {
            const id = root.fanApp;
            const row = (root.windowGroups[id] || []).find(w => w.key === key);
            if (!root.canFan(id) || !row) return;
            root.dismissFan(true);
            if (row.parked) root.restoreWindowRequested(id, key, "here");
            else root.activateWindowRequested(id, key);
        }
        onMoreRequested: {
            const id = root.fanApp;
            root.dismissFan(true);
            root.openWindowChooser(id);
        }
    }
    MouseArea {
        id: fanBridge
        z: 29
        x: root.fanBridgeRect.x; y: root.fanBridgeRect.y
        width: root.fanBridgeRect.width; height: root.fanBridgeRect.height
        enabled: root.fanOpen; hoverEnabled: true; acceptedButtons: Qt.NoButton
        onEntered: fanLeave.stop()
        onExited: if (root.fanOpen) fanLeave.restart()
    }
    onTooltipEligibleChanged: if (!tooltipEligible) { clearTooltip(); appTooltip.hideImmediately(); }
    Timer {
        id: tooltipTimer
        interval: root.tooltipDelay
        onTriggered: if (root.tooltipEligible && root.hoveredIndex >= 0 && (root.showAppNames || Logic.isChromeId(root.order[root.hoveredIndex])))
            root.tooltipIndex = root.hoveredIndex
    }
    Timer {
        id: tooltipLeaveTimer
        interval: 70
        onTriggered: root.clearTooltip()
    }
    property string selection: ""
    property bool dragActive: false
    property int pressedIndex: -1
    property string pressedId: ""
    property point pressPosition: Qt.point(0, 0)
    property var dragSnapshot: []
    property int insertionIndex: -1
    function cancelDrag(): void {
        if (dragActive) {
            actionLabel = "Reorder canceled";
        }
        pressedId = "";
        pressedIndex = -1;
        insertionIndex = -1;
        dragActive = false;
    }
    // Wheel is selection only; explicit click confirms the stable key.
    property string wheelSelectionApp: ""
    property string wheelSelectionKey: ""
    function clearWheelSelection(): void { wheelSelectionApp = ""; wheelSelectionKey = ""; }
    function selectWheelWindow(id: string, delta: int): void {
        if (!windowActionsAllowed || !canChooseWindows(id) || (delta !== 1 && delta !== -1)) return;
        const rows = windowGroups[id].filter(w => !w.parked);
        if (rows.length < 2) return;
        let index = wheelSelectionApp === id ? rows.findIndex(w => w.key === wheelSelectionKey) : -1;
        if (index < 0) index = rows.findIndex(w => w.active);
        index = index < 0 ? (delta > 0 ? 0 : rows.length - 1) : (index + delta + rows.length) % rows.length;
        wheelSelectionApp = id;
        wheelSelectionKey = rows[index].key;
        actionLabel = "Selected window " + (index + 1) + " of " + rows.length + " — click to focus";
    }
    property var windowGroups: ({})
    property var parkedWindows: []
    signal minimizeRequested(string appId)
    signal restoreWindowRequested(string appId, string key, string mode)
    signal recoverParkedRequested(string mode)
    function parkedFor(id: string): var {
        const rows = Array.isArray(windowGroups[id]) ? windowGroups[id].filter(w => w.parked) : [];
        return rows.sort((a, b) => Number(a.sequence || 0) - Number(b.sequence || 0));
    }
    function canMinimize(id: string): bool {
        return minimizeMode !== "off" && Array.isArray(windowGroups[id]) && windowGroups[id].some(w => !w.parked);
    }
    property var desktopActions: ({})
    signal desktopActionRequested(string appId, string actionId)
    property bool desktopActionsOpen: false
    onVisibleChanged: if (!visible && desktopActionsOpen) contextIndex = -1
    property real desktopActionsHeight: 360
    readonly property DesktopActionChooser activeDesktopActionChooser: desktopActionsLoader.item as DesktopActionChooser
    readonly property string desktopActionSelectionId: activeDesktopActionChooser ? activeDesktopActionChooser.selectionId : ""
    onDesktopActionsChanged: if (desktopActionsOpen && !canChooseDesktopActions(contextId)) contextIndex = -1
    function canChooseDesktopActions(id: string): bool {
        const app = appMeta[id];
        return !!app && !app.canEdit && id.indexOf("launcher:") !== 0 && id.indexOf("unknown:") !== 0 && id.indexOf("window:") !== 0
            && (!app.kind || app.kind === "application") && order.indexOf(id) > 0
            && Array.isArray(desktopActions[id]) && desktopActions[id].length > 0;
    }
    function openDesktopActions(appId: string): bool {
        if (!canChooseDesktopActions(appId) || appMeta[appId].pending || appMeta[appId].enabled === false) return false;
        openContext(order.indexOf(appId));
        desktopActionsHeight = Math.min(360, 92 + 42 * desktopActions[appId].length);
        desktopActionsOpen = true;
        return true;
    }
    signal activateWindowRequested(string appId, string key)
    signal closeWindowRequested(string appId, string key)
    signal closeApplicationRequested(string appId, var keys)
    signal restoreApplicationRequested(string appId, var keys, string mode)
    property var contextWindowKeys: []
    property var contextParkedKeys: []
    property int contextScopeRevision: 0
    component ContextScopeButton: TuneButton {
        required property int scopeAction
        property int pressRevision: -1
        property string pressApp: ""
        onPressed: { pressRevision = root.contextScopeRevision; pressApp = root.contextId; }
        onClicked: {
            if (pressRevision === root.contextScopeRevision && pressApp === root.contextId) root.invokeContext(scopeAction);
            pressRevision = -1;
        }
        Accessible.onPressAction: root.invokeContext(scopeAction)
    }
    signal cycleWindowsRequested(string appId, int delta)
    property bool windowChooserOpen: false
    property bool previewsEnabled: true
    property bool livePreviews: false
    property bool windowActionsAllowed: true // ordinary text actions: unavailable only when unmapped or confirmed locked
    property Component previewComponent
    signal previewsEnabledRequested(bool value)
    signal livePreviewsRequested(bool value)
    onPreviewsEnabledRequested: value => { if (!settingsManaged) previewsEnabled = value; }
    onLivePreviewsRequested: value => { if (!settingsManaged) livePreviews = value; }
    onPreviewsEnabledChanged: if (windowChooserOpen) contextIndex = -1
    onWindowActionsAllowedChanged: if (!windowActionsAllowed && windowChooserOpen) contextIndex = -1
    property real windowChooserHeight: 400
    readonly property WindowChooser activeWindowChooser: windowChooserLoader.item as WindowChooser
    readonly property string windowSelectionKey: activeWindowChooser ? activeWindowChooser.selectionKey : ""
    function canChooseWindows(id: string): bool {
        const app = appMeta[id];
        return !!app && !!app.running && !app.canEdit && id.indexOf("launcher:") !== 0
            && (!app.kind || app.kind === "application") && order.indexOf(id) > 0
            && !!windowGroups[id] && windowGroups[id].length > 0;
    }
    onWindowGroupsChanged: {
        contextScopeRevision++;
        if (fanOpen && !canFan(fanApp)) { dismissFan(true); refreshTooltip(); }
        else if (!fanOpen) refreshFan();
        if (windowChooserOpen && !canChooseWindows(contextId)) contextIndex = -1;
        if (pressedIndex >= 0) cancelDrag();
        if (wheelSelectionKey && !(windowGroups[wheelSelectionApp] || []).some(w => w.key === wheelSelectionKey && !w.parked)) clearWheelSelection();
    }
    onAppMetaChanged: {
        if (fanOpen && !canFan(fanApp)) dismissFan(true);
        if (windowChooserOpen && !canChooseWindows(contextId)) contextIndex = -1;
        if (desktopActionsOpen && !canChooseDesktopActions(contextId)) contextIndex = -1;
    }
    function openWindowChooser(appId: string): bool {
        if (!windowActionsAllowed || !canChooseWindows(appId)) return false;
        openContext(order.indexOf(appId));
        // 98px chrome plus 42px rows/6px gaps. Freeze on open so churn cannot move targets.
        windowChooserHeight = Math.min(480, 92 + (previewsEnabled ? 168 : 0) + 48 * windowGroups[appId].length);
        windowChooserOpen = true;
        return true;
    }
    property bool folderChooserOpen: false
    property string homePath: ""
    property string folderColor: "theme"
    property bool folderPersistenceBusy: false
    property string folderScannedPath: ""
    signal folderPresetRequested(string name)
    signal folderColorRequested(string color)
    signal folderBrowseRequested(string path)
    signal folderAddRequested(string path, string name)
    function folderSaveAccepted(transactionId: int): void { folderSettings.saveAccepted(transactionId); }
    function folderSaveResult(transactionId: int, ok: bool): void { folderSettings.saveResult(transactionId, ok); }
    signal folderDirectRequested(string id, string kind)
    property var folderResult: ({})
    property bool folderBusy: false
    property int folderGeneration: 0
    property string folderRecordSnapshot: ""
    readonly property FolderChooser activeFolderChooser: folderLoader.item as FolderChooser
    signal folderOpenRequested(string id, string path)
    signal folderCloseRequested()
    signal folderActionRequested(string id, string kind, string path, int generation)
    onFolderChooserOpenChanged: if (!folderChooserOpen) folderCloseRequested()
    function openFolder(id: string): bool {
        const record = launcherRecords.find(r => r.id === id && r.kind === "folder" && r.enabled);
        if (!record || !appMeta[id] || appMeta[id].pending) return false;
        if (folderChooserOpen && contextId === id) { contextIndex = -1; return true; }
        openContext(order.indexOf(id));
        folderRecordSnapshot = JSON.stringify(record);
        folderChooserOpen = true;
        folderOpenRequested(id, record.target);
        return true;
    }
    onLauncherRecordsChanged: if (folderChooserOpen && JSON.stringify(launcherRecords.find(r => r.id === contextId)) !== folderRecordSnapshot) contextIndex = -1
    property int contextIndex: -1
    property string contextId: ""
    property int contextActionIndex: 0
    readonly property var contextApp: appMeta[contextId] || null
    readonly property bool editableContext: !!contextApp && !!contextApp.canEdit
    readonly property var contextActions: {
        const actions = [];
        if (contextApp && !contextApp.pending && contextApp.enabled !== false && contextApp.kind !== "separator") actions.push(0);
        if (contextApp && contextApp.canNewInstance && !contextApp.pending && contextApp.enabled !== false) actions.push(3);
        if (editableContext) actions.push(4, 5, 6);
        else if (contextApp && (contextApp.pinned || contextApp.canPin)) actions.push(1);
        actions.push(2);
        if (canChooseWindows(contextId)) { actions.push(7); if (windowActionsAllowed && contextWindowKeys.length) actions.push(14); }
        if (canChooseDesktopActions(contextId) && !contextApp.pending && contextApp.enabled !== false) actions.push(8);
        if (!editableContext && canMinimize(contextId)) actions.push(9);
        if (!editableContext && parkedFor(contextId).length) actions.push(10, 11);
        if (contextApp && contextApp.kind === "folder" && contextApp.enabled !== false && !contextApp.pending) actions.push(12, 13);
        return actions;
    }
    onContextIndexChanged: {
        if (contextIndex >= 0) beginPopupSettle()
        else {
            folderChooserOpen = false
            windowChooserOpen = false
            desktopActionsOpen = false
            contextId = ""
            if (!settingsOpen) { popupSettling = false; popupSettleTimer.stop() }
        }
    }
    function moveContextAction(delta: int): void {
        const index = contextActions.indexOf(contextActionIndex);
        contextActionIndex = contextActions[(index + delta + contextActions.length) % contextActions.length];
    }
    function invokeContext(action: int): void {
        const id = contextId;
        const app = appMeta[id];
        if (!app || order.indexOf(id) < 0) { contextIndex = -1; return; }
        if (contextActions.indexOf(action) < 0) return;
        if (action === 12 || action === 13) {
            folderDirectRequested(id, action === 12 ? "manager" : "terminal");
        } else if (action === 8) {
            openDesktopActions(id);
        } else if (action === 7) {
            openWindowChooser(id);
        } else if (action === 0) {
            if (app.pending) return;
            contextIndex = -1;
            selectId(id);
        } else if (action === 1) {
            if (!app.pinned && !app.canPin) return;
            contextIndex = -1;
            pinRequested(id, !app.pinned);
        } else if (action === 3) {
            contextIndex = -1;
            newInstanceRequested(id);
        } else if (action === 4) {
            openItemEditor(id);
        } else if (action === 5 || action === 6) {
            contextIndex = -1;
            if (action === 5) duplicateLauncherRequested(id);
            else removeLauncherRequested(id);
        } else if (action === 9) {
            contextIndex = -1;
            minimizeRequested(id);
        } else if (action === 10 || action === 11) {
            const keys = contextParkedKeys.slice();
            if (!windowActionsAllowed || !keys.length || keys.some(key => !(windowGroups[id] || []).some(w => w.key === key && w.parked))) return;
            contextIndex = -1;
            restoreApplicationRequested(id, keys, action === 10 ? "here" : "origin");
        } else if (action === 14) {
            const keys = contextWindowKeys.slice();
            if (!windowActionsAllowed || !keys.length || keys.some(key => !(windowGroups[id] || []).some(w => w.key === key))) return;
            contextIndex = -1;
            closeApplicationRequested(id, keys);
        } else contextIndex = -1;
    }
    function openContext(index: int): void {
        if (index < 0 || index >= order.length) return;
        if (order[index] === "omarchy-menu") return;
        if (order[index] === "menu") { toggleMonitorPicker(); return; }
        closeMonitorPicker();
        cancelDrag();
        windowChooserOpen = false;
        desktopActionsOpen = false;
        folderChooserOpen = false;
        contextId = order[index];
        contextScopeRevision++;
        contextWindowKeys = (windowGroups[contextId] || []).map(w => w.key);
        contextParkedKeys = parkedFor(contextId).map(w => w.key);
        contextActionIndex = contextActions[0];
        contextIndex = index;
        forceActiveFocus();
    }
    property bool keyboardActive: false
    readonly property bool wantsKeyboard: keyboardActive || dragActive || contextIndex >= 0 || monitorPickerOpen
    readonly property bool popupGestureBusy: rowInput.pressed || pressedIndex >= 0
    property bool popupSettling: false
    Timer {
        id: popupSettleTimer
        interval: 80
        onTriggered: root.popupSettling = false
    }
    function beginPopupSettle(): void {
        popupSettling = true
        popupSettleTimer.restart()
    }
    onWantsKeyboardChanged: {
        if (wantsKeyboard)
            forceActiveFocus();
        else
            focus = false;
    }
    property int focusIndex: 0
    property string focusId: "omarchy-menu"
    function moveFocus(delta: int): void {
        let next = focusIndex;
        do { next = (next + delta + order.length) % order.length; }
        while (appMeta[order[next]] && appMeta[order[next]].kind === "separator");
        focusIndex = next;
    }
    onFocusIndexChanged: focusId = order[focusIndex] || "omarchy-menu";
    function enterKeyboard(): void {
        surfaceSuspended = false;
        keyboardActive = true;
        forceActiveFocus();
    }
    function releaseKeyboard(): void {
        keyboardActive = false;
        focus = false;
    }
    Keys.onPressed: event => {
        if (!root.wantsKeyboard)
            return;
        if (root.monitorPickerOpen) {
            if (event.key === Qt.Key_Escape) root.closeMonitorPicker();
            event.accepted = event.key === Qt.Key_Escape;
            return;
        }
        if (root.folderChooserOpen && root.activeFolderChooser) {
            root.activeFolderChooser.handleKey(event.key, event.modifiers);
            event.accepted = true;
            return;
        }
        if (root.desktopActionsOpen && root.activeDesktopActionChooser) {
            root.activeDesktopActionChooser.handleKey(event.key, event.modifiers);
            event.accepted = true;
            return;
        }
        if (root.windowChooserOpen && root.activeWindowChooser) {
            root.activeWindowChooser.handleKey(event.key, event.modifiers);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
            root.openContext(root.focusIndex);
            event.accepted = true;
            return;
        }
        if (root.contextIndex >= 0) {
            if (event.key === Qt.Key_Escape) root.contextIndex = -1;
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) root.invokeContext(root.contextActionIndex);
            else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Down || event.key === Qt.Key_Right) root.moveContextAction(1);
            else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_Up || event.key === Qt.Key_Left) root.moveContextAction(-1);
            event.accepted = true;
            return;
        }
        if (event.key === Qt.Key_Right)
            root.moveFocus(1);
        else if (event.key === Qt.Key_Left)
            root.moveFocus(-1);
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
            root.selectIndex(root.focusIndex);
        else if (event.key === Qt.Key_Escape) {
            root.cancelDrag();
            root.releaseKeyboard();
        } else
            return;
        event.accepted = true;
    }
    function selectIndex(index: int): void {
        if (index < 0 || index >= order.length)
            return;
        if (order[index] === "menu") { toggleMonitorPicker(); return; }
        selectId(order[index]);
    }
    function selectId(id: string): void {
        if (id === "omarchy-menu") { shellGestureRequested("left", 0); return; }
        if (id === "menu") { toggleMonitorPicker(); return; }
        const app = appMeta[id];
        if (!app || order.indexOf(id) < 0 || app.pending || app.enabled === false || app.kind === "separator") return;
        if (app.kind === "folder") { openFolder(id); return; }
        if (wheelSelectionApp === id && wheelSelectionKey) {
            const key = wheelSelectionKey;
            clearWheelSelection();
            if (windowActionsAllowed && (windowGroups[id] || []).some(w => w.key === key && !w.parked))
                activateWindowRequested(id, key);
            return;
        }
        clearWheelSelection();
        selection = id;
        actionLabel = appName(id);
        activateRequested(id);
    }
    function scaleAt(index: int): real {
        return Logic.scaleAt(index, pointerX, rowX, slotSize, motionMode, reducedMotion, dragActive, peakScale, effectiveWaveWidth / 10);
    }
    property var applications: []
    property bool appsManaged: false
    property string appError: ""
    readonly property string appStatus: appError || (applications || []).filter(app => app && app.pending).map(app => "Opening " + app.id + "…").join(" · ")
    readonly property int statusHeight: appStatus ? 32 : 0
    signal activateRequested(string id)
    signal pinRequested(string id, bool pinned)
    signal reorderRequested(var ids)
    readonly property var appMeta: {
        const result = Object.create(null);
        for (const app of applications || [])
            if (app && typeof app.id === "string" && app.id && !Logic.isChromeId(app.id)) result[app.id] = app;
        return result;
    }
    property var localOrder: []
    readonly property var order: {
        const ids = [];
        for (const app of applications || [])
            if (app && appMeta[app.id] && ids.indexOf(app.id) < 0) ids.push(app.id);
        if (appsManaged || !localOrder.length) return Logic.itemOrder(ids, showAppsButton);
        const arranged = localOrder.filter(id => ids.indexOf(id) >= 0 && !Logic.isChromeId(id));
        return Logic.itemOrder(arranged.concat(ids.filter(id => arranged.indexOf(id) < 0)), showAppsButton);
    }
    onOrderChanged: {
        // Model churn invalidates a pointer gesture's snapshot, never its target
        // into a different app. Metadata-only updates preserve the gesture.
        if (pressedIndex >= 0 && JSON.stringify(order) !== JSON.stringify(dragSnapshot)) cancelDrag();
        if (selection && order.indexOf(selection) < 0) selection = "";
        if (contextId) contextIndex = order.indexOf(contextId);
        focusIndex = Math.max(0, order.indexOf(focusId));
        // Private metadata/count churn must update the same hovered group.
        // A removed/reordered identity cannot inherit another app's caption.
        if (tooltipIndex < 0 || order[tooltipIndex] !== appTooltip.captionId) clearTooltip();
    }
    function commitDrag(): void {
        if (!dragActive || !pressedId || Logic.isChromeId(pressedId) || JSON.stringify(order) !== JSON.stringify(dragSnapshot)) { cancelDrag(); return; }
        const next = Logic.insertOrder(dragSnapshot, dragSnapshot.indexOf(pressedId), insertionIndex);
        const changed = JSON.stringify(next) !== JSON.stringify(order);
        cancelDrag();
        if (!changed) return;
        if (!appsManaged) localOrder = next;
        actionLabel = appsManaged ? "Reorder requested" : "temporary order";
        reorderRequested(next.slice(Logic.chromeIds(showAppsButton).length));
    }
    property var icons: {
        const result = Object.create(null);
        for (const id of Object.keys(appMeta)) result[id] = appMeta[id].icon || "";
        return result;
    }
    function appName(id: string): string {
        if (id === "omarchy-menu") return "Omarchy";
        if (id === "menu") return "Settings";
        return appMeta[id] ? appMeta[id].name || id : "";
    }
    property color shelfColor: "#20232b"
    property color textColor: "#eef0f6"
    property color accentColor: "#a7c7ff"
    property string actionLabel: ""
    readonly property real iconGap: baseIconSize * itemSpacing / 44
    readonly property real slotSize: baseIconSize + iconGap
    readonly property real rowX: (width - order.length * slotSize) / 2
    readonly property real dockHeight: Math.ceil(baseIconSize * (peakScale + 20 / 44 * (peakScale - 1)) + 26) + statusHeight
    readonly property real maxDockHeight: Math.ceil(72 * (2 + 20 / 44) + 26) + statusHeight
    readonly property real rowY: height - baseIconSize - 24
    // Reserve capacity at the maximum setting, including with popups closed.
    // Extra transparent width is input-masked; sliders never shift popup position.
    readonly property real settingsStageHeight: settingsPopup.height + 16 + maxDockHeight
    // Keep the bottom-anchored layer sized for Settings even while closed so
    // opening the panel does not resize the window or slide the shelf.
    width: Math.min(Math.max(1136, Math.ceil(24 + 72 * (order.length + Math.min(order.length, 5) + (order.length - 1) * 8 / 44))), availableWidth)
    height: Math.max(dockHeight + Math.max(fanHeadroom, advancedTooltips ? Math.max(0, Math.min(180, availableHeight - dockHeight)) : 0),
        settingsStageHeight)
    clip: true

    property bool autoHide: true
    property bool intelligentHide: false
    property bool reserveSpace: false
    // Committed resting art envelope, not popup, status, hide progress or client
    // layout. Hold it even when auto-hidden: reservation cannot feed overlap.
    readonly property int reservedHeight: reserveSpace
        ? Math.ceil(iconSize * (zoomSize / 100 + 20 / 44 * (zoomSize / 100 - 1)) + 26) : 0
    property bool nativeOverlapAvailable: true
    onNativeOverlapAvailableChanged: updateVisibility()
    property bool nativeOverlap: false
    property bool nativeFullscreen: false
    onIntelligentHideChanged: updateVisibility()
    onNativeOverlapChanged: updateVisibility()
    onNativeFullscreenChanged: updateVisibility()
    property bool simulatedFullscreen: false
    property bool simulatedIntelligent: false
    property bool simulatedOverlap: false
    readonly property string simulationLabel: simulatedFullscreen || simulatedIntelligent || simulatedOverlap
        ? "SIMULATED policy: fullscreen=" + simulatedFullscreen + ", overlap=" + simulatedOverlap : ""
    onSimulatedFullscreenChanged: updateVisibility()
    onSimulatedIntelligentChanged: updateVisibility()
    onSimulatedOverlapChanged: updateVisibility()
    property int revealDelay: 160
    property int hideDelay: 350
    property string visibilityState: "shown"
    property bool surfaceSuspended: false
    property bool pointerInside: false
    property bool overTrigger: false
    readonly property bool interactionLocked: wantsKeyboard || fanOpen || settingsOpen
    readonly property bool outputRoutingLocked: interactionLocked || settingsOpen || pointerInside || overTrigger || pressedIndex >= 0
    onInteractionLockedChanged: updateVisibility()
    onOverCaptionChanged: updateVisibility()
    readonly property bool shelfVisible: visibilityState !== "hidden" && visibilityState !== "revealing"
    property real shelfProgress: shelfVisible ? 1 : 0
    readonly property real effectiveProgress: surfaceSuspended ? 0 : reducedMotion ? (shelfVisible ? 1 : 0) : shelfProgress
    readonly property real shelfSlide: (1 - effectiveProgress) * 12
    Behavior on shelfProgress {
        NumberAnimation {
            id: revealAnimation
            duration: root.reducedMotion ? 0 : 140
            easing.type: Easing.OutCubic
        }
    }
    readonly property rect shelfRect: renderedSlots.length ? Qt.rect(renderedSlots[0].left - 12, height - dockHeight + shelfSlide,
        renderedSlots[renderedSlots.length - 1].right - renderedSlots[0].left + 24, dockHeight - 6 - shelfSlide) : Qt.rect(width / 2, height - dockHeight, 0, 0)
    readonly property rect triggerRect: Qt.rect(rowX, height - 6, order.length * slotSize, 6)
    readonly property rect popupRect: settingsOpen ? Qt.rect(settingsPopup.x, settingsPopup.y, settingsPopup.width, settingsPopup.height)
        : contextIndex >= 0 ? Qt.rect(contextCard.x, contextCard.y, contextCard.width, contextCard.height) : Qt.rect(0, 0, 0, 0)
    readonly property var inputRects: {
        const rects = effectiveProgress > 0 ? [shelfRect, triggerRect] : [triggerRect];
        if (effectiveProgress > 0 && appStatus) rects.push(Qt.rect(statusCard.x, statusCard.y, statusCard.width, statusCard.height));
        if (popupRect.width > 0) rects.push(popupRect);
        if (fanOpen) { rects.push(fanRect); rects.push(fanBridgeRect); }
        return rects;
    }
    function updateVisibility(): void {
        if (surfaceSuspended) {
            visibilityState = "hidden";
            return;
        }
        if ((nativeFullscreen || simulatedFullscreen) && !interactionLocked && !pointerInside && !overTrigger) {
            visibilityState = "hidden";
            return;
        }
        // Native snapshot/property churn while the pointer rests on the trigger
        // must not turn the visibility policy's pointer branch into a dwell bypass.
        if (visibilityState === "revealing" && overTrigger && !pointerInside && !interactionLocked) return;
        const shouldHide = autoHide && (!((intelligentHide && nativeOverlapAvailable) || simulatedIntelligent) || nativeOverlap || simulatedOverlap);
        visibilityState = Logic.visibilityPolicy(visibilityState, shouldHide, pointerInside || overTrigger || overCaption, interactionLocked);
    }
    function releaseInteractions(): void {
        dismissFan(true);
        closeMonitorPicker();
        contextIndex = -1;
        cancelDrag();
        releaseKeyboard();
    }
    function resetSurface(): void {
        surfaceSuspended = true;
        releaseInteractions();
        pointerInside = false;
        overTrigger = false;
        pointerX = -1;
        visibilityState = "hidden";
        revealAnimation.complete();
    }
    function shelfEntered(): void {
        surfaceSuspended = false;
        pointerInside = true;
        updateVisibility();
    }
    function shelfExited(): void {
        pointerInside = false;
        updateVisibility();
    }
    function triggerEntered(): void {
        surfaceSuspended = false;
        overTrigger = true;
        if (visibilityState === "hidden")
            visibilityState = "revealing";
        else updateVisibility();
    }
    function triggerExited(): void {
        overTrigger = false;
        if (visibilityState === "revealing")
            visibilityState = "hidden";
        else updateVisibility();
    }
    onAutoHideChanged: {
        if (!autoHide && !settingsManaged)
            surfaceSuspended = false;
        updateVisibility();
    }
    Timer {
        interval: root.revealDelay
        running: root.visibilityState === "revealing"
        onTriggered: root.visibilityState = root.overTrigger ? "shown" : "hidden"
    }
    Timer {
        interval: root.hideDelay
        running: root.visibilityState === "hiding"
        onTriggered: root.visibilityState = "hidden"
    }

    Item {
        id: body
        anchors.fill: parent
        visible: root.effectiveProgress > 0
        opacity: root.effectiveProgress
        transform: Translate {
            y: root.shelfSlide
        }
        Rectangle {
            id: shelf
            objectName: "shelf-background"
            // Reference "none" is quarter-alpha black, not transparent. It
            // bypasses the opacity setting; the explicit slider value is kept.
            opacity: root.backgroundColor === "none" ? 1 : root.themeOpacity ? root.themeBackground.a : 1 - root.effectiveTransparency / 100
            x: root.shelfRect.x
            y: root.rowY - 8
            width: root.shelfRect.width
            height: root.baseIconSize + 20
            radius: root.appearanceSettings.shape === "square" ? 0
                : root.appearanceSettings.shape === "round" ? height / 2
                : root.appearanceSettings.shape === "theme" && root.themeCornerRadius >= 0 ? root.themeCornerRadius : root.baseIconSize * 0.35
            color: root.backgroundColor === "none" ? Qt.rgba(0,0,0,.25)
                : root.backgroundColor === "theme" ? Qt.rgba(root.themeBackground.r, root.themeBackground.g, root.themeBackground.b, 1) : root.backgroundColor
            border.color: Qt.alpha(root.textColor, root.backgroundColor === "none" ? .48 : .18)
            border.width: 1
            Rectangle {
                x: 22
                y: 1
                width: parent.width - 44
                height: 1
                color: Qt.alpha(root.textColor, 0.12)
            }
        }
        Repeater {
            model: root.order
            delegate: Item {
                id: slot
                required property int index
                required property string modelData
                readonly property bool separator: (root.appMeta[modelData] || {}).kind === "separator"
                readonly property var app: root.appMeta[modelData] || {}
                readonly property int windowCount: app.running && !app.canEdit && !Logic.isChromeId(modelData)
                    && modelData.indexOf("launcher:") !== 0 && (!app.kind || app.kind === "application")
                    ? Math.max(0, Math.floor(Number(app.windowCount) || 0)) : 0
                objectName: modelData === "menu" ? "settings-item" : modelData === "omarchy-menu" ? "omarchy-menu-item" : "item-" + modelData
                readonly property var geometry: root.renderedSlots[index] || {left: 0, right: 0, scale: 1}
                x: geometry.left - 2
                y: root.rowY
                width: geometry.right - geometry.left + 4
                height: root.baseIconSize + 12
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 1
                    radius: 10
                    color: Qt.alpha(root.accentColor, root.selection === slot.modelData ? 0.14 : 0)
                    border.width: root.keyboardActive && root.focusIndex === slot.index ? 2 : 0
                    border.color: root.accentColor
                }
                Accessible.role: Accessible.Button
                Accessible.ignored: separator
                Accessible.name: root.appName(modelData) + (windowCount > 1 ? ", " + windowCount + " windows" : "")
                Accessible.onPressAction: root.selectIndex(slot.index)
                AttentionIndicator {
                    objectName: "attention-" + slot.modelData
                    anchors.right: art.right
                    anchors.top: art.top
                    z: 2
                    attention: root.attentionApps.indexOf(slot.modelData) >= 0
                    presentationEnabled: root.attentionPresentationEnabled && !root.surfaceSuspended
                        && root.visibilityState !== "hidden" && root.visibilityState !== "revealing"
                    reducedMotion: root.reducedMotion || root.attentionDnd
                    accent: root.accentColor
                }
                LaunchFeedback {
                    id: launchFeedback
                    objectName: "launch-feedback-" + slot.modelData
                    requestToken: slot.app.launchToken || 0
                    pending: !!slot.app.pending
                    allowed: root.visible && root.launchBounce && !root.reducedMotion && !root.surfaceSuspended
                        && root.shelfVisible && !root.dragActive
                    // Fit within the existing shelf/input envelope, even at peak wave.
                    amplitude: Math.max(0, Math.min(8, root.dockHeight - root.baseIconSize - 24
                        + art.restY - (art.scale - 1) * root.baseIconSize))
                }
                Image {
                    id: art
                    visible: !slot.separator
                    objectName: "art-" + slot.modelData
                    width: root.baseIconSize
                    height: width
                    anchors.horizontalCenter: parent.horizontalCenter
                    readonly property var meta: root.appMeta[slot.modelData] || ({})
                    property string failedCandidate: ""
                    readonly property string candidate: meta.folderIconCandidate || ""
                    source: candidate && candidate !== failedCandidate ? candidate : Logic.isChromeId(slot.modelData) ? root.icons[slot.modelData] || "" : meta.icon || root.icons[slot.modelData] || ""
                    onStatusChanged: if (status === Image.Error && candidate && source.toString() === candidate) {
                        const failed = candidate;
                        Qt.callLater(() => { if (art.candidate === failed) art.failedCandidate = failed; });
                    }
                    layer.enabled: !!meta.folderTint
                    layer.effect: MultiEffect { colorization: 1; colorizationColor: art.meta.folderTint || "white" }
                    // Fixed decode covers 72px × peakScale; never reload per frame.
                    sourceSize: Qt.size(Math.max(108, Math.ceil(72 * root.peakScale)), Math.max(108, Math.ceil(72 * root.peakScale)))
                    fillMode: Image.PreserveAspectFit
                    scale: slot.geometry.scale
                    readonly property real restY: root.motionMode === "wave" ? -(scale - 1) * root.baseIconSize * 20 / 44 : 0
                    y: restY + launchFeedback.offset * launchFeedback.amplitude
                    transformOrigin: Item.Bottom
                }
                Text {
                    objectName: "fallback-" + slot.modelData
                    anchors.centerIn: art
                    visible: !slot.separator && art.status !== Image.Ready
                    text: parent.modelData.substring(0, 1).toUpperCase()
                    color: root.accentColor
                    font.pixelSize: root.baseIconSize * 0.57
                    textFormat: Text.PlainText
                }
                Rectangle {
                    objectName: "separator-" + slot.modelData
                    visible: slot.separator
                    anchors.centerIn: parent
                    width: 1; height: root.baseIconSize * 0.65
                    color: Qt.alpha(root.textColor, 0.35)
                }
                Text {
                    objectName: "wheel-selection-" + slot.modelData
                    visible: root.wheelSelectionApp === slot.modelData && root.wheelSelectionKey !== ""
                    readonly property var rows: (root.windowGroups[slot.modelData] || []).filter(w => !w.parked)
                    text: (rows.findIndex(w => w.key === root.wheelSelectionKey) + 1) + "/" + rows.length
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: -18
                    color: root.accentColor; font.pixelSize: 12; font.bold: true
                    textFormat: Text.PlainText
                    Accessible.name: "Selected window " + text + "; click application to focus"
                }
                Text {
                    objectName: "window-count-" + slot.modelData
                    visible: slot.windowCount > 1
                    text: slot.windowCount > 99 ? "99+" : String(slot.windowCount)
                    width: 24; height: 15
                    x: (parent.width + root.baseIconSize) / 2 - width
                    y: root.baseIconSize - height
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    textFormat: Text.PlainText
                    color: root.textColor; font.pixelSize: 10; font.weight: Font.DemiBold
                    Accessible.ignored: true
                    Rectangle {
                        anchors.fill: parent; z: -1; radius: 6
                        color: Qt.rgba(root.shelfColor.r, root.shelfColor.g, root.shelfColor.b, 0.94)
                        border.color: Qt.alpha(root.textColor, 0.22)
                    }
                }
                WindowIndicators {
                    id: windowIndicators
                    objectName: "running-" + slot.modelData
                    visible: !slot.separator && !!root.appMeta[slot.modelData] && !!root.appMeta[slot.modelData].running
                    app: Object.assign({}, root.appMeta[slot.modelData] || {})
                    windows: root.windowGroups[slot.modelData] || []
                    width: parent.width
                    y: root.baseIconSize + 1
                    foreground: root.textColor; accent: root.accentColor
                }
                Rectangle {
                    objectName: "active-" + slot.modelData
                    visible: !slot.separator && !!root.appMeta[slot.modelData] && !!root.appMeta[slot.modelData].running && !!root.appMeta[slot.modelData].active
                        && !windowIndicators.hasVisibleActive
                    width: 12; height: 2; radius: 1
                    anchors.horizontalCenter: parent.horizontalCenter
                    // Fallback only: an active mark above already conveys focus.
                    y: root.baseIconSize + 9
                    color: root.accentColor
                }
                Text {
                    objectName: "pending-" + slot.modelData
                    visible: !slot.separator && !!root.appMeta[slot.modelData] && !!root.appMeta[slot.modelData].pending
                    text: "…"; color: root.accentColor; font.bold: true; font.pixelSize: 16
                    anchors.right: parent.right; y: -8
                }
            }
        }
        MouseArea {
            id: rowInput
            x: root.shelfRect.x
            y: root.height - root.dockHeight
            objectName: "rowInput"
            width: root.shelfRect.width
            height: root.dockHeight - 6
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onWheel: wheel => {
                root.cancelDrag();
                const delta = wheel.angleDelta.y || wheel.pixelDelta.y;
                const id = root.order[root.hitIndex(x + wheel.x)] || "";
                if (delta && id === "omarchy-menu") root.shellGestureRequested("wheel", delta);
                else if (delta) root.selectWheelWindow(id, delta < 0 ? 1 : -1);
                wheel.accepted = true;
            }
            onPressed: mouse => {
                if (root.settingsOpen && !root.editorOpen) {
                    mouse.accepted = true;
                    return;
                }
                const hit = root.hitIndex(x + mouse.x);
                const item = root.appMeta[root.order[hit]];
                const folderSwitch = root.folderChooserOpen && mouse.button === Qt.LeftButton && item && item.kind === "folder";
                if (root.contextIndex >= 0 && !folderSwitch) { root.contextIndex = -1; root.cancelDrag(); return; }
                if (mouse.button === Qt.RightButton) {
                    if (hit < 0 && Gestures.emptySpaceGesture("right").action === "settings") root.toggleMonitorPicker();
                    else root.openContext(hit);
                    return;
                }
                if (!folderSwitch) root.contextIndex = -1;
                root.pressedIndex = hit;
                root.pressedId = root.order[root.pressedIndex] || "";
                root.pressPosition = Qt.point(mouse.x, mouse.y);
                root.dragSnapshot = root.order.slice();
            }
            onPositionChanged: mouse => {
                root.pointerX = x + mouse.x;
                if (!pressed || !(pressedButtons & Qt.LeftButton) || root.pressedIndex < 0)
                    return;
                if (mouse.x < 0 || mouse.x >= width || mouse.y < 0 || mouse.y >= height) {
                    root.cancelDrag();
                    return;
                }
                const dx = mouse.x - root.pressPosition.x;
                const dy = mouse.y - root.pressPosition.y;
                if (Math.sqrt(dx * dx + dy * dy) >= 8) {
                    if (root.folderChooserOpen) { root.cancelDrag(); return; }
                    if (Logic.isChromeId(root.pressedId)) { root.pressedIndex = -1; return; }
                    root.dragActive = true;
                }
                if (root.dragActive)
                    root.insertionIndex = root.insertionAt(x + mouse.x);
            }
            // This MouseArea owns the icon hit targets; a sibling hover handler
            // behind it does not receive the same enter/leave events.
            onEntered: root.shelfEntered()
            onExited: { root.pointerX = -1; root.shelfExited(); }
            onCanceled: root.cancelDrag()
            onReleased: mouse => {
                if (mouse.button !== Qt.LeftButton && mouse.button !== Qt.MiddleButton) return;
                if (root.settingsOpen && !root.editorOpen && root.pressedIndex < 0) {
                    root.settingsOpen = false;
                    return;
                }
                if (root.pressedIndex < 0)
                    return;
                if (mouse.x < 0 || mouse.x >= width || mouse.y < 0 || mouse.y >= height) {
                    root.cancelDrag();
                    return;
                }
                if (root.dragActive) {
                    root.commitDrag();
                } else {
                    const id = root.pressedId;
                    if (Logic.isChromeId(id)) {
                        if (root.hitIndex(x + mouse.x) === root.pressedIndex) {
                            if (id === "omarchy-menu") {
                                if (mouse.button === Qt.MiddleButton) root.shellGestureRequested("middle", 0);
                                else root.shellGestureRequested("left", 0);
                            } else if (mouse.button === Qt.MiddleButton) root.shellGestureRequested("middle", 0);
                            else root.selectId(id);
                        }
                    } else if (mouse.button === Qt.MiddleButton) {
                        const app = root.appMeta[id];
                        if (app && app.canNewInstance && !app.pending && app.enabled !== false) root.newInstanceRequested(id);
                    } else root.selectId(id);
                }
                root.dragActive = false;
                root.pressedId = "";
                root.pressedIndex = -1;
                root.insertionIndex = -1;
            }
        }
        Rectangle {
            visible: root.dragActive
            x: root.rowX + root.insertionIndex * root.slotSize - 1
            y: root.rowY - 5
            width: 2
            height: root.baseIconSize + 17
            radius: 1
            color: root.accentColor
        }
        Control {
            id: appTooltip
            objectName: "app-tooltip"
            // A disabled Popup.Item still blocks presses inside its overlay bounds.
            // Paint in the existing scene instead: no popup, grab, or input region.
            focus: false
            enabled: false
            // Disabled Controls still intercept hover under desktop styles.
            // Keep this passive caption out of rowInput's hover delivery.
            hoverEnabled: false
            HoverHandler {
                enabled: appTooltip.visible
                onHoveredChanged: {
                    root.overCaption = hovered;
                    if (hovered) tooltipLeaveTimer.stop();
                    else root.refreshTooltip();
                    root.updateVisibility();
                }
            }
            readonly property bool requested: root.tooltipIndex >= 0 && root.tooltipEligible
            readonly property bool opened: requested && opacity === 1
            visible: requested || opacity > 0
            opacity: 0
            onRequestedChanged: {
                tooltipFade.stop();
                if (!root.reducedMotion && root.showAppNames && root.tooltipEligible) {
                    tooltipFade.to = requested ? 1 : 0;
                    tooltipFade.start();
                } else opacity = requested ? 1 : 0;
            }
            function hideImmediately(): void { tooltipFade.stop(); opacity = 0; }
            property real motionOffset: requested ? 0 : (animate ? 3 : 0)
            property real anchorX: root.width / 2
            property string retainedText: ""
            property string captionId: ""
            readonly property bool animate: !root.reducedMotion && root.showAppNames && root.tooltipEligible
            function updateCaption(): void {
                if (root.tooltipIndex < 0) return; // Retain text during exit.
                const id = captionId;
                retainedText = id === "omarchy-menu" ? "Omarchy"
                    : id === "menu" ? "Settings"
                    : root.appName(id) + ((root.appMeta[id] || {}).pending ? " [starting…]" : "");
            }
            Connections {
                target: root
                function onAppMetaChanged() { appTooltip.updateCaption(); }
                function onTooltipIndexChanged() {
                    if (root.tooltipIndex < 0) return;
                    appTooltip.captionId = root.order[root.tooltipIndex] || "";
                    appTooltip.updateCaption();
                    appTooltip.anchorX = root.renderedSlots[root.tooltipIndex].center;
                }
            }
            readonly property string text: retainedText
            readonly property int textFormat: Text.PlainText
            implicitHeight: contentItem.implicitHeight + topPadding + bottomPadding
            width: Math.min(root.width, (hoverList.active ? 298 : captionText.implicitWidth) + leftPadding + rightPadding)
            contentItem: Column {
                Text {
                    id: captionText
                    width: parent.width; height: implicitHeight
                    text: appTooltip.retainedText; textFormat: appTooltip.textFormat
                    elide: Text.ElideRight; maximumLineCount: 1
                    color: root.textColor; font.pixelSize: 13
                }
                Loader {
                    id: hoverList
                    objectName: "window-hover-loader"
                    width: parent.width
                    active: root.advancedTooltips && root.showAppNames && root.windowActionsAllowed
                        && appTooltip.requested && root.tooltipIndex > 0
                        && appTooltip.captionId === root.order[root.tooltipIndex]
                        && root.canChooseWindows(root.order[root.tooltipIndex] || "")
                    sourceComponent: WindowHoverList {
                        app: root.appMeta[root.order[root.tooltipIndex]] || ({})
                        windows: root.windowGroups[root.order[root.tooltipIndex]] || []
                        selectedKey: root.wheelSelectionApp === root.order[root.tooltipIndex] ? root.wheelSelectionKey : ""
                        foreground: root.textColor; accent: root.accentColor
                        maximumHeight: Math.max(0, root.height - root.dockHeight)
                    }
                }
            }
            padding: 8
            leftPadding: 11
            rightPadding: 11
            x: Math.max(0, Math.min(root.width - width, anchorX - width / 2))
            y: Math.max(0, root.height - root.dockHeight - height - 12 + motionOffset)
            Behavior on x { enabled: appTooltip.opened && appTooltip.animate; NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
            background: Rectangle {
                radius: 10
                color: Qt.rgba(root.shelfColor.r, root.shelfColor.g, root.shelfColor.b, 0.97)
                border.color: Qt.alpha(root.textColor, 0.16)
            }
            NumberAnimation {
                id: tooltipFade
                target: appTooltip
                property: "opacity"
                duration: appTooltip.requested ? 120 : 90
                easing.type: Easing.OutCubic
            }
            Behavior on motionOffset {
                enabled: appTooltip.animate
                NumberAnimation { duration: appTooltip.requested ? 120 : 90; easing.type: Easing.OutCubic }
            }
        }
        Rectangle {
            id: statusCard
            objectName: "app-status"
            visible: !!root.appStatus
            x: (root.width - width) / 2; y: root.height - root.dockHeight
            width: Math.min(420, root.width - 16); height: root.statusHeight - 4
            radius: 7; color: Qt.rgba(root.shelfColor.r, root.shelfColor.g, root.shelfColor.b, 1)
            Text {
                objectName: "app-status-text"
                anchors.fill: parent; anchors.margins: 6
                text: root.appStatus; color: root.textColor; font.pixelSize: 12
                textFormat: Text.PlainText; elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            MouseArea {
                anchors.fill: parent; acceptedButtons: Qt.AllButtons; hoverEnabled: true
                onEntered: root.shelfEntered()
                onExited: root.shelfExited()
            }
        }
    }
    MouseArea {
        id: settingsDismiss
        objectName: "settings-dismiss"
        anchors.fill: parent
        visible: root.settingsOpen && !root.editorOpen
        enabled: visible
        z: 40
        onPressed: mouse => { mouse.accepted = true }
        onReleased: mouse => { mouse.accepted = true; root.settingsOpen = false }
    }
    Popup {
        id: settingsPopup
        objectName: "settings-popup"
        parent: root
        popupType: Popup.Item
        x: (root.width - width) / 2
        y: 8
        width: Math.min(1120, root.width - 16)
        height: Math.max(1, Math.min(570, root.availableHeight - root.maxDockHeight - 16))
        padding: 16
        visible: root.settingsOpen
        modal: false
        dim: false
        focus: true
        z: 30
        onAboutToShow: {
            addItem.forceActiveFocus();
            const flick = settingsScroll.contentItem as Flickable;
            if (flick) flick.contentY = 0;
        }
        closePolicy: root.editorOpen ? Popup.NoAutoClose : Popup.CloseOnEscape
        onClosed: { root.settingsOpen = false; if (root.keyboardActive) root.forceActiveFocus(); }
        background: Rectangle {
            color: Qt.rgba(root.shelfColor.r, root.shelfColor.g, root.shelfColor.b, 1)
            radius: 14
            border.color: Qt.alpha(root.accentColor, 0.5)
        }
        contentItem: Item {
            ItemEditor {
                id: itemEditor
                objectName: "launcher-editor"
                anchors.fill: parent
                visible: root.editorOpen
                submissionPending: root.launcherSavePending
                desktopEntries: root.desktopEntries
                textColor: root.textColor
                accentColor: root.accentColor
                errorMessage: root.appError
                onAccepted: record => root.saveLauncherRequested(record)
                onCanceled: root.closeItemEditor()
            }
            ScrollView {
            id: settingsScroll
            objectName: "settings-scroll"
            anchors.fill: parent
            visible: !root.editorOpen
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            property int wheelGeneration: 0
            function flickable() {
                let item = contentItem;
                while (item && item.contentHeight === undefined)
                    item = item.parent;
                if (item && item.contentHeight !== undefined)
                    return item;
                item = settingsContent.parent;
                while (item && item.contentHeight === undefined)
                    item = item.parent;
                return item;
            }
            // Handle wheel input before child controls or nested viewports can
            // consume it. A settings wheel gesture only scrolls; never edits.
            Item {
                parent: settingsScroll
                anchors.fill: parent
                z: 100
            WheelHandler {
                target: null
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    ++settingsScroll.wheelGeneration;
                    tooltipDelaySlider.cancelPreview();
                    revealDelaySlider.cancelPreview();
                    const flick = settingsScroll.flickable();
                    if (flick && flick.contentHeight > flick.height) {
                        const delta = event.pixelDelta.y || event.angleDelta.y / 3;
                        flick.contentY = Math.max(0, Math.min(flick.contentY - delta,
                            flick.contentHeight - flick.height));
                    }
                    event.accepted = true;
                }
            }
            }
            readonly property var focusedItem: Window.activeFocusItem
            onFocusedItemChanged: Qt.callLater(revealFocus)
            onContentHeightChanged: Qt.callLater(revealFocus)
            onHeightChanged: Qt.callLater(revealFocus)
            function revealFocus(): void {
                if (!visible || !root.settingsOpen || !focusedItem) return;
                let ancestor = focusedItem;
                while (ancestor && ancestor !== settingsContent) ancestor = ancestor.parent;
                if (!ancestor) return;
                const flick = flickable();
                if (!flick || flick.contentHeight === undefined) return;
                const point = focusedItem.mapToItem(flick, 0, 0);
                let next = flick.contentY;
                if (point.y < 0) next += point.y;
                else if (point.y + focusedItem.height > flick.height)
                    next += point.y + focusedItem.height - flick.height;
                flick.contentY = Math.max(0, Math.min(next, flick.contentHeight - flick.height));
            }
            Item {
            id: settingsContent
            objectName: "settings-content"
            width: settingsScroll.availableWidth - 12
            readonly property int columns: width >= 1000 ? 3 : width >= 700 ? 2 : 1
            readonly property real columnWidth: (width - (columns - 1) * 20) / columns
            implicitHeight: Math.max(appearance.height, delaySettings.y + delaySettings.height, advancedSettings.y + advancedSettings.height) + 12
            FolderSettings {
                id: folderSettings
                x: settingsContent.columns > 1 ? settingsContent.columnWidth + 20 : 0
                y: settingsContent.columns > 1 ? 40 : appearance.height + 16
                width: settingsContent.columnWidth
                homePath: root.homePath
                folderColor: root.folderColor
                records: root.launcherRecords
                result: root.folderResult
                busy: root.folderBusy
                scannedPath: root.folderScannedPath
                persistenceBusy: root.folderPersistenceBusy
                textColor: root.textColor
                onPresetRequested: name => root.folderPresetRequested(name)
                onColorRequested: color => root.folderColorRequested(color)
                onBrowseRequested: path => root.folderBrowseRequested(path)
                onBrowseClosed: root.folderCloseRequested()
                onAddRequested: (path, name) => root.folderAddRequested(path, name)
            }
            Column {
                id: delaySettings
                x: folderSettings.x; y: folderSettings.y + folderSettings.height + 12
                width: settingsContent.columnWidth; spacing: 4
                // Shape and spacing choices label themselves; keep the normal
                // three-column page inside its existing viewport.
                Row {
                    width: parent.width; spacing: 4
                    Repeater {
                        model: ["rounded", "round", "square", "theme"]
                        delegate: AppearanceButton {
                            required property string modelData
                            objectName: "shape-" + modelData
                            width: (delaySettings.width - 12) / 4; text: modelData
                            chosen: root.appearanceSettings.shape === modelData
                            Accessible.name: "Shelf shape: " + modelData
                            requestPatch: ({shape:modelData})
                        }
                    }
                }
                Row {
                    width: parent.width; spacing: 4
                    Repeater {
                        model: [2,4,8]
                        delegate: AppearanceButton {
                            required property int modelData
                            objectName: "spacing-" + modelData
                            width: (delaySettings.width - 8) / 3
                            text: modelData === 2 ? "Compact" : modelData === 4 ? "Normal" : "Relaxed"
                            chosen: root.itemSpacing === modelData
                            Accessible.name: "Icon spacing: " + modelData
                            requestPatch: ({itemSpacing:modelData})
                        }
                    }
                }
                Row {
                    width: parent.width; spacing: 4
                    ComboBox {
                        id: backgroundPicker; objectName: "background-color"
                        width: (delaySettings.width - 4) * .57; height: 30
                        model: ["theme", "none", "#000000", "#181825", "#1e1e2e", "#0f172a", "#111827", "#062e24", "#1c1917", "#2c0b16", "#1e102d", "#334155"]
                        currentIndex: model.indexOf(root.backgroundColor)
                        displayText: root.backgroundColor === "none" ? "Black 25% (none)" : "Color: " + root.backgroundColor
                        Accessible.name: "Shelf background color; none means 25 percent black"
                        wheelEnabled: false
                        // mapToItem alone does not subscribe to Flickable scrolling.
                        readonly property real roomAbove: Math.max(0, delaySettings.y + parent.y + y - settingsScroll.contentItem.contentY - 4)
                        readonly property real roomBelow: Math.max(0, settingsScroll.height - roomAbove - height - 8)
                        popup.height: Math.min(220, Math.max(roomAbove, roomBelow))
                        popup.y: roomAbove > roomBelow ? -popup.height : height
                        onActivated: index => {
                            const value = model[index];
                            currentIndex = Qt.binding(() => model.indexOf(root.backgroundColor));
                            root.appearanceSettingsRequested({backgroundColor:value});
                        }
                    }
                    AppearanceButton {
                        objectName: "theme-opacity"; width: (delaySettings.width - 4) * .43
                        text: "Theme opacity"; chosen: root.themeOpacity
                        Accessible.name: "Use host theme opacity; retain explicit transparency"
                        requestPatch: ({themeOpacity:!root.themeOpacity})
                    }
                }
                Text { text: "Tooltip delay: " + root.tooltipDelay + " ms"; color: root.textColor; font.pixelSize: 13 }
                PreviewSlider {
                    id: tooltipDelaySlider; objectName: "tooltip-delay-slider"
                    width: parent.width; height: 28; from: 0; to: 5000; stepSize: 50
                    committedValue: root.tooltipDelay; Accessible.name: "Tooltip delay in milliseconds"
                    onCommitRequested: value => root.delaySettingsRequested({tooltipDelay:value})
                }
                Text { text: "Reveal delay: " + root.revealDelay + " ms"; color: root.textColor; font.pixelSize: 13 }
                PreviewSlider {
                    id: revealDelaySlider; objectName: "reveal-delay-slider"
                    width: parent.width; height: 28; from: 0; to: 2000; stepSize: 10
                    committedValue: root.revealDelay; Accessible.name: "Reveal delay in milliseconds"
                    onCommitRequested: value => root.delaySettingsRequested({revealDelay:value})
                }
                TuneButton {
                    objectName: "reserve-space"; width: parent.width
                    text: root.reserveSpace ? "Reserve shelf space: on" : "Reserve shelf space: off"
                    chosen: root.reserveSpace
                    Accessible.name: "Reserve desktop space even while the shelf is hidden"
                    onClicked: root.reserveSpaceRequested(!root.reserveSpace)
                }
                CheckBox {
                    id: followOutputCheck
                    objectName: "follow-active-output"
                    width: parent.width; height: 30
                    text: "Follow active display"
                    checked: root.followActiveOutput
                    wheelEnabled: false
                    property int pressWheelGeneration: -1
                    onPressed: pressWheelGeneration = settingsScroll.wheelGeneration
                    nextCheckState: function() { return checkState; }
                    onClicked: if (pressWheelGeneration === settingsScroll.wheelGeneration)
                        root.followActiveOutputRequested(!root.followActiveOutput)
                    Accessible.onPressAction: root.followActiveOutputRequested(!root.followActiveOutput)
                    contentItem: Text {
                        text: followOutputCheck.text; color: root.textColor
                        leftPadding: 30; verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 13; textFormat: Text.PlainText
                    }
                }
            }
            Text {
                text: "Settings"
                color: root.textColor
                font.pixelSize: 15
                font.bold: true
                textFormat: Text.PlainText
            }
            TuneButton {
                id: addItem
                objectName: "add-item"
                x: parent.width - width - 78; y: 0
                width: 90; text: "Add Item"
                Accessible.name: "Add a custom launcher item"
                onClicked: root.openItemEditor("")
            }
            TuneButton {
                objectName: "close-settings"
                x: parent.width - width; y: 0
                text: "Close"
                onClicked: root.settingsOpen = false
            }
            Item {
                id: appearance
                width: settingsContent.columnWidth
                height: settingsFooter.y + settingsFooter.height
            Text {
                y: 40; text: "Size"; color: root.textColor; font.pixelSize: 13
            }
            Text {
                objectName: "size-value"
                y: 40; anchors.right: parent.right
                text: root.iconSize === 0 ? "Auto (" + root.resolvedIconSize + " px)" : root.effectiveIconSize + " px"; color: root.textColor; font.pixelSize: 13
            }
            PreviewSlider {
                id: sizeSlider
                objectName: "size-slider"
                y: 56; width: parent.width - 72; height: 32
                from: 28; to: 72; stepSize: 2
                snapMode: Slider.SnapAlways
                committedValue: root.iconSize === 0 ? root.resolvedIconSize : root.iconSize
                enabled: root.iconSize !== 0
                Accessible.name: "Icon size"
                onCommitRequested: value => root.iconSizeRequested(value)
            }
            TuneButton {
                objectName: "size-auto"
                y: 56; anchors.right: parent.right
                text: "Auto"
                chosen: root.iconSize === 0
                onClicked: root.iconSizeRequested(root.iconSize === 0 ? root.resolvedIconSize : 0)
            }
            Text {
                y: 96; text: "Transparency"; color: root.textColor; font.pixelSize: 13
            }
            Text {
                objectName: "transparency-value"
                y: 96; anchors.right: parent.right
                text: root.effectiveTransparency + "%" + (root.backgroundColor === "none" ? " (none overrides)" : root.themeOpacity ? " (theme overrides)" : ""); color: root.textColor; font.pixelSize: 13
            }
            PreviewSlider {
                id: transparencySlider
                objectName: "transparency-slider"
                y: 112; width: parent.width; height: 32
                from: 0; to: 100; stepSize: 1
                snapMode: Slider.SnapAlways
                committedValue: root.transparency
                Accessible.name: "Dock background transparency"
                enabled: !root.themeOpacity && root.backgroundColor !== "none"
                onCommitRequested: value => root.transparencyRequested(value)
            }
            Row {
                y: 160; spacing: 8
                TuneButton {
                    objectName: "mode-wave"; text: "Wave"
                    chosen: root.motionMode === "wave"
                    onClicked: root.modeRequested("wave")
                }
                TuneButton {
                    objectName: "mode-zoom"; text: "Zoom"
                    chosen: root.motionMode === "zoom"
                    onClicked: root.modeRequested("zoom")
                }
                TuneButton {
                    objectName: "mode-off"; text: "Off"
                    chosen: root.motionMode === "off"
                    onClicked: root.modeRequested("off")
                }
            }
            Text {
                y: 198; text: "Zoom size"; color: root.textColor; font.pixelSize: 13
            }
            Text {
                objectName: "zoom-size-value"
                y: 198; anchors.right: parent.right
                text: (root.effectiveZoomSize / 100).toFixed(2) + "×"; color: root.textColor; font.pixelSize: 13
            }
            PreviewSlider {
                id: zoomSlider
                objectName: "zoom-size-slider"
                y: 214; width: parent.width; height: 26
                from: 100; to: 200; stepSize: 5
                snapMode: Slider.SnapAlways
                committedValue: root.zoomSize
                enabled: root.motionMode !== "off" && !root.reducedMotion
                Accessible.name: "Zoom size, maximum hovered icon scale"
                onCommitRequested: value => root.zoomSizeRequested(value)
            }
            Text {
                y: 240; text: "Wave width"; color: root.textColor; font.pixelSize: 13
            }
            Text {
                objectName: "wave-width-value"
                y: 240; anchors.right: parent.right
                text: (root.effectiveWaveWidth / 10).toFixed(1) + " icons / side"; color: root.textColor; font.pixelSize: 13
            }
            PreviewSlider {
                id: waveSlider
                objectName: "wave-width-slider"
                y: 256; width: parent.width; height: 26
                from: 10; to: 50; stepSize: 5
                snapMode: Slider.SnapAlways
                committedValue: root.waveWidth
                enabled: root.motionMode === "wave" && !root.reducedMotion
                Accessible.name: "Wave width, neighboring icon distance on each side"
                onCommitRequested: value => root.waveWidthRequested(value)
            }
            Row {
                y: 282; spacing: 8; width: parent.width
                TuneButton {
                    objectName: "reduced-motion"; text: "Reduce motion"; width: (parent.width - 8) / 2
                    chosen: root.reducedMotion
                    onClicked: root.reducedMotionRequested(!root.reducedMotion)
                }
                TuneButton {
                    objectName: "auto-hide"; text: root.autoHide ? "Auto-hide: on" : "Auto-hide: off"; width: (parent.width - 8) / 2
                    chosen: root.autoHide
                    onClicked: root.autoHideRequested(!root.autoHide)
                }
            }
            Row {
                y: 326; spacing: 8; width: parent.width
                TuneButton {
                    objectName: "minimize-active"; text: "Active"; width: (parent.width - 16) / 3
                    chosen: root.minimizeMode === "active"
                    Accessible.name: "Minimize active window"
                    onClicked: root.minimizeModeRequested("active")
                }
                TuneButton {
                    objectName: "minimize-all"; text: "All"; width: (parent.width - 16) / 3
                    chosen: root.minimizeMode === "all"
                    Accessible.name: "Minimize all application windows"
                    onClicked: root.minimizeModeRequested("all")
                }
                TuneButton {
                    objectName: "minimize-off"; text: "Off"; width: (parent.width - 16) / 3
                    chosen: root.minimizeMode === "off"
                    Accessible.name: "Turn click to minimize off"
                    onClicked: root.minimizeModeRequested("off")
                }
            }
            Row {
                y: 364; spacing: 8; width: parent.width
                TuneButton {
                    objectName: "all-displays"; text: "All displays"; width: (parent.width - 8) / 2
                    chosen: root.monitorMode === "all"
                    onClicked: root.monitorsRequested("all", [])
                }
                TuneButton {
                    objectName: "selected-displays"; text: "Selected displays"; width: (parent.width - 8) / 2
                    enabled: root.availableOutputs.length > 0
                    chosen: root.monitorMode === "selected"
                    onClicked: root.monitorsRequested("selected", root.monitorMode === "selected" ? root.selectedOutputs : root.availableOutputs)
                }
            }
            Item {
                id: outputScroll
                y: 402; width: parent.width; height: root.availableOutputs.length * 30
                Column {
                    width: parent.width
                    Repeater {
                        model: root.availableOutputs
                        delegate: CheckBox {
                            id: outputCheck
                            required property string modelData
                            objectName: "output-" + modelData
                            width: parent.width; height: 30
                            text: modelData
                            checked: root.monitorMode === "all" || root.selectedOutputs.indexOf(modelData) >= 0
                            wheelEnabled: false
                            property int pressWheelGeneration: -1
                            onPressed: pressWheelGeneration = settingsScroll.wheelGeneration
                            nextCheckState: function() { return checkState; }
                            onClicked: {
                                if (pressWheelGeneration === settingsScroll.wheelGeneration)
                                    root.toggleOutput(modelData);
                            }
                            Accessible.onPressAction: root.toggleOutput(modelData)
                            contentItem: Text {
                                text: outputCheck.text; color: root.textColor
                                leftPadding: 30; verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 13; textFormat: Text.PlainText
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
            Text {
                id: settingsFooter
                y: outputScroll.y + outputScroll.height + 18; width: parent.width
                objectName: "settings-footer"
                text: (root.persistenceEnabled && root.settingsManaged ? "Pins, launchers and settings are saved.\n" : "Pins are saved; appearance settings are temporary.\n") + (root.appStatus || root.actionLabel)
                color: root.textColor; font.pixelSize: 13
                wrapMode: Text.Wrap; textFormat: Text.PlainText
            }
            }
            Item {
                id: advancedSettings
                x: settingsContent.columns === 3 ? 2 * (settingsContent.columnWidth + 20) : folderSettings.x
                y: (settingsContent.columns === 3 ? 40 : delaySettings.y + delaySettings.height + 16) + 38
                width: settingsContent.columnWidth
                height: overrideControls.y + overrideControls.height
            Flow {
                id: settingsToggles
                objectName: "settings-toggles"
                y: -38
                width: parent.width
                spacing: 8
                CheckBox {
                    id: namesCheck
                    objectName: "show-app-names"
                    implicitWidth: Math.min(settingsToggles.width, contentItem.implicitWidth)
                    height: 30
                    text: "Show app names"
                    checked: root.showAppNames
                    wheelEnabled: false
                    property int pressWheelGeneration: -1
                    onPressed: pressWheelGeneration = settingsScroll.wheelGeneration
                    nextCheckState: function() { return checkState; }
                    onClicked: if (pressWheelGeneration === settingsScroll.wheelGeneration)
                        root.showAppNamesRequested(!root.showAppNames)
                    Accessible.onPressAction: root.showAppNamesRequested(!root.showAppNames)
                    contentItem: Text {
                        text: namesCheck.text; color: root.textColor
                        leftPadding: 30; verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 13; textFormat: Text.PlainText
                    }
                }
                CheckBox {
                    id: appsButtonCheck
                    objectName: "show-apps-button"
                    implicitWidth: Math.min(settingsToggles.width, contentItem.implicitWidth)
                    height: 30
                    text: "Settings icon"
                    checked: root.showAppsButton
                    wheelEnabled: false
                    property int pressWheelGeneration: -1
                    onPressed: pressWheelGeneration = settingsScroll.wheelGeneration
                    nextCheckState: function() { return checkState; }
                    onClicked: if (pressWheelGeneration === settingsScroll.wheelGeneration)
                        root.showAppsButtonRequested(!root.showAppsButton)
                    Accessible.onPressAction: root.showAppsButtonRequested(!root.showAppsButton)
                    contentItem: Text {
                        text: appsButtonCheck.text; color: root.textColor
                        leftPadding: 30; verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 13; textFormat: Text.PlainText
                    }
                }
                CheckBox {
                    id: overlapCheck
                    objectName: "intelligent-hide"
                    implicitWidth: Math.min(settingsToggles.width, contentItem.implicitWidth)
                    height: 30
                    text: "Overlap hide"
                    Accessible.name: "Hide only when windows overlap; shared one-second refresh while mapped"
                    enabled: root.autoHide
                    checked: root.intelligentHide
                    wheelEnabled: false
                    property int pressWheelGeneration: -1
                    onPressed: pressWheelGeneration = settingsScroll.wheelGeneration
                    nextCheckState: function() { return checkState; }
                    onClicked: if (pressWheelGeneration === settingsScroll.wheelGeneration)
                        root.intelligentHideRequested(!root.intelligentHide)
                    Accessible.onPressAction: if (enabled) root.intelligentHideRequested(!root.intelligentHide)
                    contentItem: Text {
                        text: overlapCheck.text; color: root.textColor
                        leftPadding: 30; verticalAlignment: Text.AlignVCenter
                        font.pixelSize: 13; textFormat: Text.PlainText
                    }
                }
            }
            Column {
                id: previewSettings
                y: Math.max(0, settingsToggles.y + settingsToggles.height)
                width: parent.width; spacing: 6

                Row {
                    width: parent.width; spacing: 8
                    TuneButton {
                        objectName: "attention-hints-setting"; width: (parent.width - 8) / 2
                        text: root.showUrgentHint ? "Attention: on" : "Attention: off"
                        chosen: root.showUrgentHint
                        onClicked: root.attentionSettingsRequested({showUrgentHint:!root.showUrgentHint})
                    }
                    TuneButton {
                        objectName: "launch-bounce-setting"; width: (parent.width - 8) / 2
                        text: root.launchBounce ? "Bounce: on" : "Bounce: off"
                        Accessible.name: "Launch bounce"
                        chosen: root.launchBounce
                        onClicked: root.launchBounceRequested(!root.launchBounce)
                    }
                }
                TuneButton {
                    objectName: "notification-attention-setting"; width: parent.width
                    text: root.urgentOnNotification ? "Notification attention: on" : "Notification attention: off"
                    chosen: root.urgentOnNotification
                    onClicked: root.attentionSettingsRequested({urgentOnNotification:!root.urgentOnNotification})
                }
                Text {
                    width: parent.width; wrapMode: Text.Wrap; textFormat: Text.PlainText
                    color: root.textColor; font.pixelSize: 12
                    text: "Notifications: " + root.notificationStatus + ". Exact app matches only.\nSample: " + root.soundSampleStatus
                        + ". Saved sound: " + (root.urgentSound ? root.urgentSoundName : "off") + "."
                }
                Row {
                    width: parent.width; spacing: 8
                    TuneButton {
                        objectName: "urgent-sound-setting"; width: (parent.width - 8) / 2
                        text: root.urgentSound ? "Attention sound: on" : "Attention sound: off"
                        chosen: root.urgentSound
                        enabled: root.urgentSound || root.soundStatus === "available" && root.urgentSoundName !== "none"
                        onClicked: root.attentionSettingsRequested({urgentSound:!root.urgentSound})
                    }
                    TuneButton {
                        objectName: "urgent-sound-sample"; width: (parent.width - 8) / 2
                        text: "Play sample"
                        Accessible.name: "Play sound sample"
                        enabled: root.settingsOpen && root.urgentSound && root.soundSampleStatus === "ready"
                        onClicked: if (enabled) root.soundSampleRequested()
                        Accessible.onPressAction: if (enabled) root.soundSampleRequested()
                        Keys.onReturnPressed: if (enabled) root.soundSampleRequested()
                        Keys.onEnterPressed: if (enabled) root.soundSampleRequested()
                    }
                }
                TuneButton {
                    objectName: "urgent-sound-name"; width: parent.width
                    text: "Sound: " + root.urgentSoundName + " (next)"
                    onClicked: {
                        const name = Parity.soundNames[(Parity.soundNames.indexOf(root.urgentSoundName) + 1) % Parity.soundNames.length];
                        root.attentionSettingsRequested({urgentSoundName:name, urgentSound:name !== "none" && root.urgentSound});
                    }
                }
                Row {
                    width: parent.width; spacing: 8
                    TuneButton {
                        objectName: "previews-enabled"; width: (parent.width - 8) / 2
                        text: root.previewsEnabled ? "Window previews: on" : "Window previews: off"
                        chosen: root.previewsEnabled
                        onClicked: root.previewsEnabledRequested(!root.previewsEnabled)
                    }
                    CheckBox {
                        id: advancedTooltipCheck
                        objectName: "advanced-tooltips-setting"
                        width: (parent.width - 8) / 2; height: 30
                        text: "Hover titles"
                        Accessible.name: "Advanced text tooltips; requires Show app names"
                        checked: root.advancedTooltips
                        wheelEnabled: false
                        property int pressWheelGeneration: -1
                        onPressed: pressWheelGeneration = settingsScroll.wheelGeneration
                        nextCheckState: function() { return checkState; }
                        onClicked: if (pressWheelGeneration === settingsScroll.wheelGeneration)
                            root.advancedTooltipsRequested(!root.advancedTooltips)
                        Accessible.onPressAction: root.advancedTooltipsRequested(!root.advancedTooltips)
                        contentItem: Text {
                            text: advancedTooltipCheck.text; color: root.textColor
                            leftPadding: 30; verticalAlignment: Text.AlignVCenter
                            font.pixelSize: 13; textFormat: Text.PlainText
                        }
                    }
                }
            }
            Column {
                id: parkingRecovery
                y: previewSettings.y + previewSettings.height + 12
                width: parent.width; spacing: 6
                visible: root.parkedWindows.length > 0
                TuneButton {
                    objectName: "recover-parked-here"; width: parent.width
                    text: "Recover parked windows here"
                    Accessible.name: "Recover all parked windows to the current workspace"
                    onClicked: root.recoverParkedRequested("here")
                }
                TuneButton {
                    objectName: "recover-parked-origin"; width: parent.width
                    text: "Recover parked windows to origins"
                    Accessible.name: "Recover all parked windows to recorded origin workspaces"
                    onClicked: root.recoverParkedRequested("origin")
                }
            }
            TuneButton {
                id: recoverConfig
                objectName: "recover-config"
                y: parkingRecovery.y + (parkingRecovery.visible ? parkingRecovery.height + 12 : 0)
                width: parent.width; text: "Restore last known good configuration"
                visible: root.canRecover
                Accessible.name: "Restore last known good configuration"
                onClicked: root.recoverRequested()
            }
            Column {
                id: overrideControls
                y: recoverConfig.y + (recoverConfig.visible ? recoverConfig.height + 12 : 0)
                width: parent.width; spacing: 8
                Text {
                    width: parent.width; text: "Exact app matching override"
                    color: root.textColor; font.pixelSize: 13; textFormat: Text.PlainText
                }
                TextField {
                    id: overrideAppId; objectName: "override-app-id"
                    width: parent.width; placeholderText: "Exact window app ID"
                    Accessible.name: "Exact window application ID"
                }
                TextField {
                    id: overrideDesktopId; objectName: "override-desktop-id"
                    width: parent.width; placeholderText: "Exact desktop entry ID"
                    Accessible.name: "Exact desktop entry ID for matching override"
                }
                TuneButton {
                    objectName: "apply-override"; text: "Apply override"; width: parent.width
                    enabled: !!overrideAppId.text && !!overrideDesktopId.text
                    Accessible.name: "Apply exact application matching override"
                    onClicked: root.overrideRequested(overrideAppId.text, overrideDesktopId.text)
                }
                TuneButton {
                    objectName: "clear-override"; text: "Clear override"; width: parent.width
                    enabled: !!overrideAppId.text
                    Accessible.name: "Remove exact application matching override"
                    onClicked: root.overrideRequested(overrideAppId.text, "")
                }
            }
            }
            }
            }
        }
    }
    Rectangle {
        id: contextCard
        objectName: "context-card"
        visible: root.contextIndex >= 0 && root.effectiveProgress > 0
        x: (root.width - width) / 2; y: 8
        width: Math.min(300, root.width - 16)
        height: root.folderChooserOpen ? 460 : root.desktopActionsOpen ? root.desktopActionsHeight : root.windowChooserOpen ? root.windowChooserHeight : root.editableContext ? 104 + extraActions.height : 166 + extraActions.height
        radius: 12
        color: Qt.rgba(root.shelfColor.r, root.shelfColor.g, root.shelfColor.b, 1)
        border.color: root.accentColor
        z: 10
        // Consume the whole card behind its buttons, including heading/padding.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
        Text {
            x: 12; y: 10; width: parent.width - 24
            text: root.appName(root.contextId)
            color: root.textColor; font.pixelSize: 12
            textFormat: Text.PlainText
            elide: Text.ElideRight
        }
        Loader {
            id: folderLoader
            active: root.folderChooserOpen && root.contextIndex >= 0
            x: 12; y: 42; width: parent.width - 24; height: parent.height - 54
            sourceComponent: FolderChooser {
                result: root.folderResult
                busy: root.folderBusy
                generation: root.folderGeneration
                textColor: root.textColor; accentColor: root.accentColor
                onDismissRequested: root.contextIndex = -1
                onRefreshRequested: {
                    const record = root.launcherRecords.find(r => r.id === root.contextId);
                    if (record && root.folderChooserOpen) root.folderOpenRequested(record.id, record.target);
                }
                onActionRequested: (kind, path, generation) => {
                    if (root.folderChooserOpen && generation === root.folderGeneration)
                        root.folderActionRequested(root.contextId, kind, path, generation);
                }
            }
        }
        Loader {
            id: windowChooserLoader
            active: root.windowChooserOpen && root.contextIndex >= 0
            x: 12; y: 42; width: parent.width - 24; height: parent.height - 54
            sourceComponent: WindowChooser {
                windows: root.windowGroups[root.contextId] || []
                previewsEnabled: root.previewsEnabled
                previewComponent: root.previewComponent
                textColor: root.textColor; accentColor: root.accentColor
                onDismissRequested: root.contextIndex = -1
                onBackRequested: { root.windowChooserOpen = false; root.contextActionIndex = 7; root.forceActiveFocus(); }
                onCycleRequested: delta => {
                    if (root.windowChooserOpen && root.canChooseWindows(root.contextId) && (delta === -1 || delta === 1))
                        root.cycleWindowsRequested(root.contextId, delta);
                }
                onActivateRequested: key => {
                    const id = root.contextId;
                    if (!root.windowChooserOpen || !root.canChooseWindows(id)
                        || !root.windowGroups[id].some(window => window.key === key)) return;
                    root.contextIndex = -1;
                    root.activateWindowRequested(id, key);
                }
                onCloseRequested: key => {
                    const id = root.contextId;
                    if (root.windowChooserOpen && root.canChooseWindows(id)
                        && root.windowGroups[id].some(window => window.key === key)) root.closeWindowRequested(id, key);
                }
            }
        }
        Loader {
            id: desktopActionsLoader
            active: root.desktopActionsOpen && root.contextIndex >= 0
            x: 12; y: 42; width: parent.width - 24; height: parent.height - 54
            sourceComponent: DesktopActionChooser {
                actions: root.desktopActions[root.contextId] || []
                pending: !root.contextApp || !!root.contextApp.pending || root.contextApp.enabled === false
                textColor: root.textColor; accentColor: root.accentColor
                onDismissRequested: root.contextIndex = -1
                onBackRequested: { root.desktopActionsOpen = false; root.contextActionIndex = 8; root.forceActiveFocus(); }
                onActivateRequested: actionId => {
                    const id = root.contextId;
                    if (!root.desktopActionsOpen || !root.canChooseDesktopActions(id) || root.contextApp.pending
                        || root.contextApp.enabled === false || !root.desktopActions[id].some(action => action.id === actionId)) return;
                    root.contextIndex = -1;
                    root.desktopActionRequested(id, actionId);
                }
            }
        }
        Row {
            visible: !root.windowChooserOpen && !root.desktopActionsOpen && !root.folderChooserOpen
            x: 12; y: 50; spacing: 10
            // The disposable chooser replaces this menu while open.
            TuneButton {
                objectName: "context-open"
                width: 110
                text: root.contextApp && root.contextApp.kind === "separator" ? "Separator"
                    : root.contextApp && root.contextApp.enabled === false ? "Disabled"
                    : root.contextApp && root.contextApp.pending ? "Opening…"
                    : root.contextApp && root.contextApp.running ? "Focus" : "Open"
                focusPolicy: Qt.NoFocus
                enabled: root.contextActions.indexOf(0) >= 0
                chosen: root.contextActionIndex === 0
                onClicked: root.invokeContext(0)
            }
            TuneButton {
                objectName: "context-close"
                width: 110; text: "Dismiss Menu"
                focusPolicy: Qt.NoFocus
                chosen: root.contextActionIndex === 2
                Accessible.name: "Close menu"
                onClicked: root.invokeContext(2)
            }
        }
        TuneButton {
            objectName: "context-pin"
            visible: !root.editableContext && !root.windowChooserOpen && !root.desktopActionsOpen && !root.folderChooserOpen
            x: 12; y: 88; width: parent.width - 24
            text: root.contextApp && root.contextApp.pinned ? "Remove from Dock" : "Keep in Dock"
            focusPolicy: Qt.NoFocus
            enabled: !!root.contextApp && (!!root.contextApp.pinned || !!root.contextApp.canPin)
            opacity: enabled ? 1 : 0.5
            chosen: root.contextActionIndex === 1
            onClicked: root.invokeContext(1)
        }
        Item {
            id: extraActions
            visible: !root.windowChooserOpen && !root.desktopActionsOpen && !root.folderChooserOpen
            x: 12; y: root.editableContext ? 88 : 124
            readonly property int newHeight: root.contextApp && root.contextApp.canNewInstance ? 36 : 0
            width: parent.width - 24
            readonly property int windowsHeight: root.canChooseWindows(root.contextId) ? 36 : 0
            readonly property int desktopActionsHeight: root.canChooseDesktopActions(root.contextId) ? 36 : 0
            readonly property int minimizeHeight: !root.editableContext && root.canMinimize(root.contextId) ? 36 : 0
            readonly property int restoreHeight: !root.editableContext && root.parkedFor(root.contextId).length ? 72 : 0
            readonly property int folderHeight: root.contextApp && root.contextApp.kind === "folder" ? 72 : 0
            readonly property int closeHeight: root.canChooseWindows(root.contextId) ? 36 : 0
            height: newHeight + windowsHeight + desktopActionsHeight + minimizeHeight + restoreHeight + folderHeight + closeHeight + (root.editableContext ? 108 : 0)
            ContextScopeButton {
                objectName: "context-close-windows"; scopeAction: 14
                text: root.contextWindowKeys.length === 1 ? "Close Window" : "Close All Windows (" + root.contextWindowKeys.length + ")"
                width: parent.width
                y: extraActions.newHeight + extraActions.windowsHeight + extraActions.desktopActionsHeight + extraActions.minimizeHeight + extraActions.restoreHeight
                visible: extraActions.closeHeight > 0
                enabled: root.contextActions.indexOf(14) >= 0
                focusPolicy: Qt.NoFocus; chosen: root.contextActionIndex === 14
            }
            TuneButton {
                objectName: "context-folder-manager"; text: "Open in File Manager"; width: parent.width
                y: 108; visible: extraActions.folderHeight > 0
                enabled: root.contextActions.indexOf(12) >= 0
                focusPolicy: Qt.NoFocus; chosen: root.contextActionIndex === 12
                onClicked: root.invokeContext(12)
            }
            TuneButton {
                objectName: "context-folder-terminal"; text: "Open in Terminal"; width: parent.width
                y: 144; visible: extraActions.folderHeight > 0
                enabled: root.contextActions.indexOf(13) >= 0
                focusPolicy: Qt.NoFocus; chosen: root.contextActionIndex === 13
                onClicked: root.invokeContext(13)
            }
            TuneButton {
                objectName: "context-desktop-actions"; text: "App actions…"; width: parent.width
                y: extraActions.newHeight + extraActions.windowsHeight
                visible: extraActions.desktopActionsHeight > 0
                enabled: root.contextActions.indexOf(8) >= 0
                opacity: enabled ? 1 : 0.5
                focusPolicy: Qt.NoFocus; chosen: root.contextActionIndex === 8
                onClicked: root.invokeContext(8)
            }
            TuneButton {
                objectName: "context-windows"; text: root.windowActionsAllowed ? "Windows…" : "Windows unavailable (privacy)"; width: parent.width
                enabled: root.windowActionsAllowed
                y: extraActions.newHeight
                visible: extraActions.windowsHeight > 0
                focusPolicy: Qt.NoFocus; chosen: root.contextActionIndex === 7
                onClicked: root.invokeContext(7)
            }
            TuneButton {
                objectName: "context-new-instance"; text: "New Window"; width: parent.width
                visible: !!root.contextApp && !!root.contextApp.canNewInstance
                enabled: root.contextActions.indexOf(3) >= 0
                focusPolicy: Qt.NoFocus; chosen: root.contextActionIndex === 3
                Accessible.name: "Open a new window of " + root.appName(root.contextId)
                onClicked: root.invokeContext(3)
            }
            TuneButton {
                objectName: "context-minimize"; text: root.minimizeMode === "all" ? "Minimize All" : "Minimize Window"; width: parent.width
                y: extraActions.newHeight + extraActions.windowsHeight + extraActions.desktopActionsHeight
                visible: extraActions.minimizeHeight > 0
                focusPolicy: Qt.NoFocus; chosen: root.contextActionIndex === 9
                Accessible.name: text + " for " + root.appName(root.contextId)
                onClicked: root.invokeContext(9)
            }
            ContextScopeButton {
                scopeAction: 10
                objectName: "context-restore-here"; text: "Restore Group Here (" + root.contextParkedKeys.length + ")"; width: parent.width
                y: extraActions.newHeight + extraActions.windowsHeight + extraActions.desktopActionsHeight + extraActions.minimizeHeight
                visible: extraActions.restoreHeight > 0
                focusPolicy: Qt.NoFocus; chosen: root.contextActionIndex === 10
                Accessible.name: text
                enabled: root.windowActionsAllowed && root.contextParkedKeys.length > 0
            }
            ContextScopeButton {
                scopeAction: 11
                objectName: "context-restore-origin"; text: "Restore Group to Origin"; width: parent.width
                y: extraActions.newHeight + extraActions.windowsHeight + extraActions.desktopActionsHeight + extraActions.minimizeHeight + 36
                visible: extraActions.restoreHeight > 0
                focusPolicy: Qt.NoFocus; chosen: root.contextActionIndex === 11
                Accessible.name: text
                enabled: root.windowActionsAllowed && root.contextParkedKeys.length > 0
            }
            TuneButton {
                objectName: "context-edit"; text: "Edit Item"; width: parent.width
                y: extraActions.newHeight
                visible: root.editableContext
                focusPolicy: Qt.NoFocus; chosen: root.contextActionIndex === 4
                Accessible.name: "Edit " + root.appName(root.contextId)
                onClicked: root.invokeContext(4)
            }
            TuneButton {
                objectName: "context-duplicate"; text: "Duplicate Item"; width: parent.width
                y: extraActions.newHeight + 36
                visible: root.editableContext
                focusPolicy: Qt.NoFocus; chosen: root.contextActionIndex === 5
                Accessible.name: "Duplicate " + root.appName(root.contextId)
                onClicked: root.invokeContext(5)
            }
            TuneButton {
                objectName: "context-remove"; text: "Remove Item"; width: parent.width
                y: extraActions.newHeight + 72
                visible: root.editableContext
                focusPolicy: Qt.NoFocus; chosen: root.contextActionIndex === 6
                Accessible.name: "Remove " + root.appName(root.contextId) + " from dock"
                onClicked: root.invokeContext(6)
            }
        }
        Text {
            objectName: "pin-reason"
            visible: !root.editableContext && !root.windowChooserOpen && !root.desktopActionsOpen && !root.folderChooserOpen
            x: 12; y: 124 + extraActions.height; width: parent.width - 24
            text: root.contextApp && !root.contextApp.canPin ? (root.contextApp.pinned ? "Desktop entry unavailable; this pin can be removed." : "Pin unavailable: no matching desktop entry.") : ""
            color: root.textColor; font.pixelSize: 12
            wrapMode: Text.Wrap; textFormat: Text.PlainText
        }
    }
    Rectangle {
        x: root.triggerRect.x
        y: root.triggerRect.y
        width: root.triggerRect.width
        height: root.triggerRect.height
        radius: 3
        color: Qt.alpha(root.accentColor, root.overTrigger ? 0.7 : 0.22)
        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
            onEntered: root.triggerEntered()
            onExited: root.triggerExited()
        }
    }
}
