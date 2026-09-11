import QtQuick
import Quickshell
import Quickshell.Io
import "../core/AppLogic.js" as Apps
import "../core/WindowLogic.js" as Windows
import "ConfigLogic.js" as Config
import "LauncherLogic.js" as Launchers
import "DesktopActionLogic.js" as DesktopActions
import "FolderLogic.js" as Folders

// Instantiate once above all per-output views. Test mode never creates a live source.
QtObject {
    id: root
    readonly property bool testMode: Quickshell.env("OMADOCKED_TEST_MODE") === "1"
    readonly property string configPath: Quickshell.env("OMADOCKED_CONFIG_PATH") || (testMode ? "" :
        (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omadocked/pins.json")
    readonly property bool _pathAllowed: !configPath || (configPath.startsWith("/") && !configPath.split("/").some(p => p === "." || p === "..")
        && (!testMode || configPath.startsWith("/tmp/") || configPath.startsWith("/var/tmp/")))
    readonly property var items: _items
    // Private view data: never add titles/groups to IPC, persistence or logs.
    readonly property var windowGroups: _windowGroups
    property var _windowGroups: Object.create(null)
    readonly property var desktopActions: _desktopActions
    property var _desktopActions: Object.create(null)
    readonly property bool ready: _ready
    readonly property string error: _leaseError || _storageError || _actionError || _storageWarning
    property string _storageWarning: ""
    readonly property var settings: _config.settings
    readonly property var overlapSource: _live.item ? _live.item.overlapSource : null
    readonly property var launchers: _config.launchers
    readonly property var overrides: _config.overrides
    readonly property var entries: _entries.map(e => ({id: e.id, name: e.name}))
    readonly property bool canRecover: _canRecover
    readonly property bool persistenceBusy: _storeActive !== null
    readonly property bool parkingReady: _parkingReady
    readonly property bool parkingBusy: _parkingActive !== null || _parkingQueue.length > 0
    readonly property var parkedWindows: _parkedWindows
    readonly property var lastParkingReceipt: _lastParkingReceipt
    property int persistenceRevision: 0
    property int parkingRevision: 0
    property bool lastPersistenceOk: true
    signal persistenceCompleted(int transactionId, bool ok, string message)
    signal parkingCompleted(int transactionId, bool ok, string status, string key)
    signal urgentAcknowledged(string appId, string key)
    property var _urgentFocus: ({})
    property bool _canRecover: false
    property string _backupText: ""
    property var _config: Config.defaults()
    property var _items: []
    property var attentionApps: []
    property bool _ready: false
    property string _storageError: ""
    property string _actionError: ""
    property var _pins: []
    property var _entries: []
    property var _windows: []
    property var _focusOrder: []
    property string _diskText: ""
    property bool _diskMissing: true
    property int _storeSerial: 0
    property int _serial: 0
    readonly property string _windowSession: Date.now().toString(36) + "-" + Math.random().toString(36).slice(2) + "-"
    property var _storeActive: null
    readonly property string parkingJournalPath: Quickshell.env("OMADOCKED_PARKING_DISABLED") === "1" ? "" : (Quickshell.env("OMADOCKED_PARKING_JOURNAL") || (testMode ? "" :
        (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omadocked/parking.json")
        )
    readonly property bool _parkingPathAllowed: !parkingJournalPath || (parkingJournalPath.startsWith("/")
        && !parkingJournalPath.split("/").some(p => p === "." || p === "..")
        && (!testMode || parkingJournalPath.startsWith("/tmp/") || parkingJournalPath.startsWith("/var/tmp/")))
    property bool _parkingReady: false
    property bool _startupRecoveryRequired: false
    property var _parkedWindows: []
    property var _parkedIdentities: ({})
    property var _lastParkingReceipt: ({})
    property int _parkingSerial: 0
    property var _parkingQueue: []
    property var _parkingActive: null
    property var _parkingResult: null
    property Loader _live: Loader {
        active: !root.testMode
        source: "LiveApps.qml"
        onLoaded: root._schedule()
        onStatusChanged: if (status === Loader.Error) root._actionError = "Native application source failed to load"
    }
    property Connections _events: Connections {
        target: root._live.item
        function onEntriesChanged() { root._schedule(); }
        function onWindowsChanged() { root._schedule(); }
    }
    property Process _parking: Process {
        command: ["/usr/bin/python3", Launchers.localPath(Qt.resolvedUrl("parking_store.py").toString()), root.parkingJournalPath]
        stdinEnabled: true
        stdout: SplitParser { onRead: line => root._parkingMessage(String(line)) }
        onExited: {
            root._parkingLost("helper-stopped");
            root._actionError = "Window parking helper stopped; parking and recovery disabled";
        }
    }
    property Timer _parkingDeadline: Timer {
        interval: 3000
        onTriggered: {
            root._parkingLost("helper-timeout");
            root._parking.running = false;
            root._actionError = "Window parking helper startup failed; parking and recovery disabled";
        }
    }
    property Timer _parkingMetadataRetry: Timer {
        interval: 80
        repeat: false
        onTriggered: root._retryParkingMetadata()
    }
    function _parkingMessage(line) {
        let message;
        try { message = JSON.parse(line); }
        catch (_) { _actionError = "Window parking helper protocol failed"; _parking.running = false; return; }
        if (message.type === "ready") {
            _parkingDeadline.stop();
            if (!message.ok) { _actionError = "Window parking helper unavailable: " + message.error; return; }
            _parkingActive = {id: ++_parkingSerial, op: "startup-status", publicId: 0};
            _parkingDeadline.restart();
            _parking.write(JSON.stringify({id:_parkingActive.id, op:"status"}) + "\n");
            return;
        }
        if (!_parkingActive || message.id !== _parkingActive.id) return;
        _parkingDeadline.stop();
        if (_parkingActive.op === "startup-status") {
            _applyParkingStatus(message);
            _parkingActive = null;
            _parkingReady = message.ok === true;
            _pumpParking();
            return;
        }
        if (_parkingActive.op === "status-after-operation") {
            const active = _parkingActive.original;
            const result = _parkingResult;
            if (message.ok) _applyParkingStatus(message);
            _parkingActive = null;
            _parkingResult = null;
            _finishParking(active, message.ok ? result : {ok:false, status:"status-unverified", key:result.key});
            return;
        }
        _parkingResult = message;
        _parkingActive = {id: ++_parkingSerial, op:"status-after-operation", publicId:0, original:_parkingActive};
        _parkingDeadline.restart();
        _parking.write(JSON.stringify({id:_parkingActive.id, op:"status"}) + "\n");
    }
    function _parkingLost(status) {
        _parkingReady = false;
        _parkingDeadline.stop();
        _parkingMetadataRetry.stop();
        const active = _parkingActive && (_parkingActive.original || _parkingActive);
        const queued = _parkingQueue.slice();
        _parkingQueue = [];
        _parkingActive = null;
        _parkingResult = null;
        queued.forEach(request => _finishParking(request, {ok:false, status:status}));
        if (active && active.publicId > 0) _finishParking(active, {ok:false, status:status});
    }
    function _rebindLiveKeys() {
        const used = [];
        _windows = _windows.map(w => {
            let identity = w.identity || null;
            if (!testMode && _live.item && w.handle) {
                try { identity = _live.item.parkingIdentity(w.handle); } catch (_) { identity = null; }
            }
            const key = _assignWindowKey(w.key, identity, used);
            used.push(key);
            return Object.assign({}, w, {key: key});
        });
    }
    function _assignWindowKey(previousKey, identity, used) {
        if (previousKey && used.indexOf(previousKey) === -1 && identity
            && _parkedIdentities[previousKey] && _identitiesMatch(_parkedIdentities[previousKey], identity))
            return previousKey;
        const rebound = _rebindParkedKey(identity, used);
        if (rebound) return rebound;
        if (previousKey && used.indexOf(previousKey) === -1) return previousKey;
        return _windowSession + String(++_serial);
    }
    function _applyParkingStatus(message) {
        const identities = Object.create(null);
        _parkedWindows = Array.isArray(message.records) ? message.records.map(r => {
            const key = String(r.key);
            if (r.identity && typeof r.identity === "object") identities[key] = r.identity;
            return {key:key, state:String(r.state), sequence:Number(r.sequence)};
        }) : [];
        _parkedIdentities = identities;
        _startupRecoveryRequired = message.recoveryRequired === true;
        _rebindLiveKeys();
        _schedule();
    }
    function _identitiesMatch(a, b) {
        if (!a || !b) return false;
        if (a.address !== b.address || a.pid !== b.pid || a.class !== b.class
            || a.initialClass !== b.initialClass || a.xwayland !== b.xwayland) return false;
        if (typeof a.stableId === "string" && typeof b.stableId === "string" && a.stableId !== b.stableId)
            return false;
        return true;
    }
    function _rebindParkedKey(identity, used) {
        if (!identity) return "";
        const keys = Object.keys(_parkedIdentities);
        for (let i = 0; i < keys.length; i++) {
            const key = keys[i];
            if (used.indexOf(key) !== -1) continue;
            if (_identitiesMatch(_parkedIdentities[key], identity)) return key;
        }
        return "";
    }
    function _finishParking(active, result) {
        const receipt = {transactionId:active.publicId, ok:result.ok === true, status:String(result.status || "error")};
        if (typeof result.key === "string") receipt.key = result.key;
        _lastParkingReceipt = receipt;
        parkingRevision++;
        parkingCompleted(receipt.transactionId, receipt.ok, receipt.status, receipt.key || "");
        _actionError = receipt.ok ? "" : "Window operation failed: " + receipt.status;
        _parkingActive = null;
        _refresh();
        // Only a matching restore + status read-back can acknowledge parking.
        const request = active.request;
        if (request && request.urgent === true && receipt.ok && receipt.status === "restored"
            && receipt.key === request.key && !_parkedWindows.some(r => r.key === request.key)
            && _windowTarget(request.appId, request.key))
            urgentAcknowledged(request.appId, request.key);
        if (active.group) {
            active.group.remaining--;
            active.group.failed = active.group.failed || !receipt.ok;
            if (active.group.remaining === 0) {
                if (active.group.failed) _actionError = "Some group windows could not be restored; review remaining recovery records";
                else activateWindow(active.group.appId, active.group.focusKey);
            }
        } else if (receipt.ok && receipt.status === "restored" && request && request.appId && request.key) {
            activateWindow(request.appId, request.key);
        }
        _pumpParking();
    }
    function _enqueueParking(request, group): int {
        if (!_parkingReady || !_parking.running) return 0;
        const publicId = ++_parkingSerial;
        const next = _parkingQueue.slice();
        next.push({id:publicId, publicId:publicId, op:request.op, group:group || null, request:Object.assign({}, request, {id:publicId})});
        _parkingQueue = next;
        _pumpParking();
        return publicId;
    }
    function _pumpParking() {
        if (!_parkingReady || _parkingActive || !_parkingQueue.length) return;
        const next = _parkingQueue.slice();
        _parkingActive = next.shift();
        _parkingQueue = next;
        const request = _parkingActive.request;
        if (request.op === "park" && request.awaitMetadata) {
            const pending = _parkingTarget(request.appId, request.key);
            if (pending) {
                request.window = pending.identity;
                request.origin = pending.origin;
                delete request.awaitMetadata;
            } else {
                try { if (_live.item) _live.item.refreshParkingMetadata(); } catch (_) {}
                _parkingMetadataRetry.restart();
                return;
            }
        }
        const target = request.appId ? _windowTarget(request.appId, request.key) : null;
        if (request.appId && (!target || (request.urgent === true && target.urgent !== true))) {
            _finishParking(_parkingActive, {ok:false, status:"membership-changed", key:request.key});
            return;
        }
        _parkingDeadline.restart();
        _parking.write(JSON.stringify(request) + "\n");
    }
    function _retryParkingMetadata() {
        const active = _parkingActive;
        if (!active || !active.request || !active.request.awaitMetadata) return;
        const request = active.request;
        const pending = _parkingTarget(request.appId, request.key);
        if (pending) {
            request.window = pending.identity;
            request.origin = pending.origin;
            delete request.awaitMetadata;
            const member = _windowTarget(request.appId, request.key);
            if (!member) {
                _finishParking(active, {ok:false, status:"membership-changed", key:request.key});
                return;
            }
            _parkingDeadline.restart();
            _parking.write(JSON.stringify(request) + "\n");
            return;
        }
        _finishParking(active, {ok:false, status:"identity-mismatch", key:request.key});
    }
    function _schedule() { Qt.callLater(_refresh); }
    function _sync() {
        if (testMode || !_live.item) return;
        _entries = _live.item.entries;
        const used = [];
        _windows = _live.item.windows.map(w => {
            const previous = _windows.filter(p => p.handle === w.handle)[0];
            let identity = null;
            try { identity = _live.item.parkingIdentity(w.handle); } catch (_) {}
            const key = _assignWindowKey(previous ? previous.key : "", identity, used);
            used.push(key);
            return {key: key, handle: w.handle, appId: w.appId, title: w.title, active: w.active,
                urgent:w.urgent === true, openedAtMs:previous ? previous.openedAtMs : Date.now()};
        });
    }
    property var _pending: Object.create(null)
    property int _launchTimeout: 10000
    property int _launchSerial: 0
    property Process _launcher: null
    // Each native signal source owns its request identity for its whole lifetime.
    // Never relabel a reused Process's late exit with a replacement request token.
    property Component _launcherFactory: Component {
        Process {
            id: launcher
            required property string requestId
            required property int requestToken
            required property var requestRecord
            command: ["/usr/bin/python3", Launchers.localPath(Qt.resolvedUrl("launch_app.py").toString()), "--record", JSON.stringify(requestRecord)]
            stderr: StdioCollector { id: launchErrors }
            onExited: (exitCode, exitStatus) => {
                if (root._launcher === launcher) root._launcher = null;
                root._finishLaunch(requestId, exitCode === 0 && exitStatus === 0,
                    launchErrors.text.trim() || "launcher process failed", requestToken);
                launcher.destroy();
            }
        }
    }
    property Timer _pendingTimer: Timer {
        onTriggered: {
            const now = Date.now();
            Object.keys(root._pending).forEach(id => {
                if (root._pending[id].deadline <= now) {
                    const application = root._pending[id].kind === "application";
                    delete root._pending[id];
                    root._actionError = application ? "Launch requested but no new matching window appeared: " + id : "Launcher timed out: " + id;
                    if (root._launcher && root._launcher.requestId === id && root._launcher.running)
                        root._launcher.running = false;
                }
            });
            root._refresh();
        }
    }
    function _armPending() {
        _pendingTimer.stop();
        const deadlines = Object.keys(_pending).map(id => _pending[id].deadline);
        if (deadlines.length) {
            _pendingTimer.interval = Math.max(1, Math.min.apply(null, deadlines) - Date.now());
            _pendingTimer.start();
        }
    }
    // This long-lived helper is the sole flock owner and the sole process that
    // reads, compares, replaces, backs up or recovers persistent bytes.
    property string persistenceOutcome: "idle"
    property bool _leaseDead: false
    property bool _leaseOwned: false
    property bool _leaseResolved: false
    property string _leaseError: ""
    property Process _lease: Process {
        command: ["/usr/bin/python3", Launchers.localPath(Qt.resolvedUrl("config_store.py").toString()), root.configPath]
        stdinEnabled: true
        stdout: SplitParser { onRead: line => root._storeMessage(String(line)) }
        onExited: (exitCode, exitStatus) => {
            root._storeLost(root._leaseResolved ? "Configuration writer helper stopped" : "Configuration writer helper unavailable");
        }
    }
    // Process.signal targets this Process's own child, not an unverified PID.
    // Logical terminalization is independent of exit; escalation is best effort
    // for userspace resistance, not a bound on uninterruptible kernel IO.
    property Timer _leaseKillDeadline: Timer {
        interval: 500
        onTriggered: if (root._lease.running) root._lease.signal(9)
    }
    function _stopStore() {
        if (_lease.running) {
            _lease.signal(15);
            _leaseKillDeadline.restart();
        }
    }
    function _storeLost(reason) {
        if (_leaseDead) return;
        _leaseDead = true;
        _leaseDeadline.stop();
        const active = _storeActive;
        _storeActive = null;
        _leaseOwned = false;
        _canRecover = false;
        if (active) persistenceOutcome = "indeterminate";
        _leaseError = reason + (active ? "; persistence outcome unresolved; reload to reconcile" : "")
            + "; editing and recovery disabled";
        if (!_leaseResolved) _resolveLease(_leaseError);
        if (active) {
            persistenceRevision++;
            lastPersistenceOk = false;
            persistenceCompleted(active.id, false, _leaseError);
        }
    }
    property Timer _leaseDeadline: Timer {
        interval: 3000
        onTriggered: {
            root._storeLost(root._leaseResolved ? "Configuration writer helper timeout" : "Configuration writer helper startup failed");
            root._stopStore();
        }
    }
    function _resolveLease(message) {
        if (_leaseResolved) return;
        _leaseResolved = true;
        _leaseDeadline.stop();
        _leaseError = message;
        _finishStartup();
    }
    function _storeMessage(line) {
        if (_leaseDead) return;
        let message;
        try { message = JSON.parse(line); }
        catch (e) { _storeLost("Configuration writer helper protocol failed"); _stopStore(); return; }
        if (!message || typeof message !== "object") {
            _storeLost("Configuration writer helper protocol failed"); _stopStore(); return;
        }
        if (message.type === "ready" && !_leaseResolved) {
            _leaseOwned = message.ok === true;
            if (_leaseOwned) {
                _diskText = typeof message.text === "string" ? message.text : "";
                _diskMissing = message.missing === true;
                _backupText = typeof message.backup === "string" ? message.backup : "";
                _loadText(_diskText, _diskMissing);
                _resolveLease("");
            } else {
                _leaseDead = true;
                _resolveLease(message.error === "busy"
                    ? "Configuration writer is active in another instance; editing and recovery disabled"
                    : "Configuration writer helper rejected storage or reconciliation; editing and recovery disabled");
                _stopStore();
            }
            return;
        }
        if (!_storeActive || message.id !== _storeActive.id) return;
        // Missing/contradictory outcomes are lost trustworthy receipts, not proof
        // of failure before rename. Do not publish possibly nondurable bytes.
        if (!((message.ok === true && message.outcome === "durable")
              || (message.ok === false && message.outcome === "no-commit"))) {
            _storeLost("Configuration persistence outcome unresolved");
            _stopStore();
            return;
        }
        persistenceOutcome = message.outcome;
        _leaseDeadline.stop();
        const active = _storeActive;
        _storeActive = null;
        if (!message.ok) {
            _storageError = message.error === "conflict"
                ? "Pins changed externally or became unreadable; reload before editing"
                : (active.recovering ? "Configuration recovery failed" : "Configuration save failed");
            _checkRecovery();
            persistenceRevision++;
            lastPersistenceOk = false;
            persistenceCompleted(active.id, false, _storageError);
            return;
        }
        _diskText = active.recovering ? _backupText : active.text;
        _diskMissing = false;
        // A degraded backup receipt must not claim the new backup was verified.
        _backupText = message.backupDegraded ? "" : _diskText;
        _storageWarning = message.backupDegraded ? "Configuration saved; backup refresh failed" : "";
        _storageError = "";
        if (active.recovering) _loadText(_diskText, false);
        else {
            _config = active.config;
            _pins = _config.pins;
            _actionError = "";
            _refresh(active.order);
        }
        _checkRecovery();
        persistenceRevision++;
        lastPersistenceOk = true;
        persistenceCompleted(active.id, true, _storageWarning);
    }
    function _sendStore(active) {
        persistenceOutcome = "pending";
        _storeActive = active;
        _leaseDeadline.restart();
        const request = {id: active.id, op: active.recovering ? "recover" : "commit",
            expected: _diskText, missing: _diskMissing};
        if (active.recovering) request.backup = _backupText;
        else {
            request.replacement = active.text;
            request.fallback = active.fallback;
        }
        _lease.write(JSON.stringify(request) + "\n");
    }
    function _finishStartup() {
        _checkRecovery();
        _ready = true;
        _refresh();
    }
    Component.onCompleted: {
        if (!parkingJournalPath) _parkingReady = true;
        else if (!_parkingPathAllowed) _actionError = "Parking journal path must be an absolute temporary path in test mode";
        else { _parkingDeadline.start(); _parking.running = true; }
        if (!_pathAllowed) {
            _storageError = testMode ? "Test mode requires an absolute temporary configuration path" : "Pins path must be absolute";
            _finishStartup();
        } else if (!configPath) _finishStartup();
        else {
            _leaseDeadline.start();
            _lease.running = true;
        }
    }
    function _loadText(text, missing) {
        if (missing) { _diskText = ""; _diskMissing = true; return; }
        _diskText = text;
        _diskMissing = false;
        const parsed = Config.parse(text);
        if (parsed.error) { _storageError = parsed.error; return; }
        _storageError = "";
        _config = parsed.config;
        _pins = _config.pins;
    }
    function _refresh(order) {
        _sync();
        const focused = _windows.find(w => w.active);
        const recent = _focusOrder.filter(key => _windows.some(w => w.key === key) && (!focused || key !== focused.key));
        _focusOrder = focused ? [focused.key].concat(recent) : recent;
        const apps = Apps.build(_entries, _windows, _pins, Array.isArray(order) ? order : _items.map(i => i.id), overrides);
        const actions = Object.create(null);
        const entryIndex = Apps.indexEntries(_entries);
        apps.forEach(item => {
            const entry = entryIndex.ids[item.id]; // Duplicate IDs are null, never first-match wins.
            if (DesktopActions.validAppId(item.id) && !item.id.startsWith("launcher:") && entry)
                actions[item.id] = DesktopActions.metadata(entry.actions);
        });
        if (JSON.stringify(actions) !== JSON.stringify(_desktopActions)) _desktopActions = actions;
        const groups = Windows.groups(apps, _windows, _parkedWindows);
        if (JSON.stringify(groups) !== JSON.stringify(_windowGroups)) _windowGroups = groups;
        Object.keys(_pending).forEach(id => {
            const p = _pending[id];
            const app = apps.find(i => i.id === p.desktopId);
            if (p.kind === "application" && app && app.windows.some(key => p.windows.indexOf(key) === -1)) delete _pending[id];
        });
        const attention = apps.filter(i => i.windows.length > 0).map(i => {
            const members = _windows.filter(w => i.windows.indexOf(w.key) !== -1);
            // Exact identifiers/names only. Ambiguous aliases fail closed in AttentionLogic.
            const aliases = [i.id, i.name].concat(members.map(w => w.appId));
            return {id:i.id, notificationIds:aliases.filter((v, n) => typeof v === "string" && v && aliases.indexOf(v) === n),
                pwaIds:[], browserIds:[], focused:!!i.active, launchPending:!!_pending[i.id],
                openedAtMs:Math.min.apply(null, members.map(w => w.openedAtMs || Date.now())),
                windows:members.map(w => ({id:w.key, focused:!!w.active, openedAtMs:w.openedAtMs || Date.now(), urgent:w.urgent === true}))};
        });
        if (JSON.stringify(attention) !== JSON.stringify(attentionApps)) attentionApps = attention;
        const next = apps.filter(i => i.pinned).concat(launchers.map(Launchers.item), apps.filter(i => !i.pinned));
        const resolved = next.map(i => {
            i.pending = !!_pending[i.id];
            i.launchToken = _pending[i.id] ? _pending[i.id].token : 0;
            if (i.kind === "folder" && !i.icon) {
                const mode = settings.folderColor;
                i.icon = ["symbolic", "white", "black"].indexOf(mode) >= 0 ? "folder-symbolic" : "folder";
                i.folderTint = mode === "white" || mode === "black" ? mode : "";
                i.folderIconCandidate = mode.startsWith("Yaru-") ? "file:///usr/share/icons/" + mode + "/48x48/places/folder.svg" : "";
            }
            if (i.icon.startsWith("/")) i.icon = "file://" + i.icon.split("/").map(encodeURIComponent).join("/");
            else if (!i.icon.startsWith("image://") && !i.icon.startsWith("file://"))
                i.icon = Quickshell.iconPath(i.icon || "application-x-executable", true)
                    || Quickshell.iconPath("application-x-executable");
            return i;
        });
        if (JSON.stringify(resolved) !== JSON.stringify(_items)) _items = resolved;
        _armPending();
        Object.keys(_urgentFocus).forEach(id => {
            const key = _urgentFocus[id];
            const app = apps.find(a => a.id === id);
            const target = app && app.windows.indexOf(key) >= 0 && _windows.find(w => w.key === key);
            if (!target || target.active) {
                delete _urgentFocus[id];
                if (target && !_parkedWindows.some(r => r.key === key)) urgentAcknowledged(id, key);
            }
        });
    }
    function fixtureSet(entries, windows): bool {
        if (!testMode) return false;
        // JSON round trip strips executable fixture properties and QObject references.
        _entries = JSON.parse(JSON.stringify(entries));
        const previous = new Map(_windows.map(w => [w.fixtureKey, w]));
        const used = [];
        _windows = JSON.parse(JSON.stringify(windows)).map(w => {
            const old = previous.get(w.key);
            const key = _assignWindowKey(old ? old.key : "", w.identity, used);
            used.push(key);
            return {fixtureKey: w.key, key: key, appId: w.appId, title: w.title, active: !!w.active,
                identity: w.identity, origin: w.origin};
        });
        _refresh();
        return true;
    }
    function _persist(pins): bool { return _commit(Object.assign({}, _config, {pins: pins})); }
    function _future(text): bool {
        try { return JSON.parse(text).version > 2; } catch (e) { return false; }
    }
    function _checkRecovery() {
        _canRecover = false;
        if (!configPath || !_pathAllowed || !_leaseOwned || !_storageError || _future(_diskText)
            || !Config.parse(_diskText).error) return;
        _canRecover = !!_backupText && !Config.parse(_backupText).error;
    }
    function recoverConfiguration(): bool {
        if (!ready || !configPath || !_pathAllowed || !_leaseOwned || !_storageError
            || !_canRecover || _storeActive) return false;
        _sendStore({id: ++_storeSerial, recovering: true});
        return true;
    }
    function configure(patch): int {
        try { return _commit(Object.assign({}, _config, {settings: Config.settings(patch, settings)})); }
        catch (e) { _actionError = e.message; return false; }
    }
    function saveLauncher(record): int {
        try {
            if (!Config.object(record)) throw new Error("Invalid launcher record");
            const existing = launchers.findIndex(r => r.id === record.id);
            if (record.id && existing === -1) throw new Error("Launcher no longer exists");
            let id = record.id;
            if (!id) do { id = Launchers.uuid(); } while (launchers.some(r => r.id === id));
            const value = Launchers.normalize(Object.assign({}, record, {id: id}));
            const next = launchers.slice();
            if (existing === -1) next.push(value); else next[existing] = value;
            return _commit(Object.assign({}, _config, {launchers: next}));
        } catch (e) { _actionError = e.message; return false; }
    }
    function setOverride(appId, desktopId): bool {
        if (!Config.validAppId(appId) || typeof desktopId !== "string"
            || (desktopId && !_entries.some(e => e.id === desktopId))) {
            _actionError = "Invalid application override or missing desktop entry";
            return false;
        }
        const next = Object.assign(Object.create(null), overrides);
        if (desktopId) next[appId] = desktopId; else delete next[appId];
        return _commit(Object.assign({}, _config, {overrides: next}));
    }
    function _completeImmediatePersistence(transactionId, ok, message) {
        persistenceRevision++;
        lastPersistenceOk = ok;
        persistenceCompleted(transactionId, ok, message);
    }
    function _commit(config, recovering, order): int {
        if (!ready || _storageError || (configPath && (!_leaseOwned || !_lease.running || _storeActive))) return 0;
        const text = JSON.stringify(config) + "\n";
        const validated = Config.parse(text);
        if (validated.error) { _actionError = "Pin change rejected: " + validated.error; return 0; }
        const transactionId = ++_storeSerial;
        if (JSON.stringify(validated.config) === JSON.stringify(_config)) {
            _actionError = "";
            _refresh(order);
            Qt.callLater(() => root._completeImmediatePersistence(transactionId, true, ""));
            return transactionId;
        }
        if (!configPath) {
            _config = validated.config;
            _pins = _config.pins;
            _actionError = "";
            _refresh(order);
            Qt.callLater(() => root._completeImmediatePersistence(transactionId, true, ""));
            return transactionId;
        }
        _sendStore({id: transactionId, recovering: false, text: text,
            fallback: _diskText || JSON.stringify(_config) + "\n",
            config: validated.config, order: order});
        return transactionId;
    }
    function setPinned(id, value): bool {
        const item = _items.filter(i => i.id === id)[0];
        if (!item || item.canEdit || (value && !item.canPin)) { _actionError = "No launchable desktop entry for pin"; return false; }
        if (_storageError) return false;
        if (item.pinned === value) return true;
        return _persist(value ? _pins.concat([id]) : _pins.filter(p => p !== id));
    }
    function reorder(ids): bool {
        const current = _items.map(i => i.id);
        if (!Array.isArray(ids) || ids.length !== current.length
            || ids.some((id, i) => current.indexOf(id) === -1 || ids.indexOf(id) !== i)) {
            _actionError = "Reorder requires every current app ID exactly once";
            return false;
        }
        const pins = ids.filter(id => _pins.indexOf(id) !== -1);
        const orderedLaunchers = ids.filter(id => launchers.some(r => r.id === id)).map(id => launchers.find(r => r.id === id));
        // Ordering is stable within each group; cross-group drops snap back.
        return _commit(Object.assign({}, _config, {pins: pins, launchers: orderedLaunchers}), false, ids);
    }
    // True means an activation/launch request was accepted, not compositor acknowledgement.
    function duplicateLauncher(id): bool {
        const record = launchers.find(r => r.id === id);
        if (!record) { _actionError = "Launcher no longer exists"; return false; }
        return saveLauncher(Object.assign({}, record, {id: "", name: record.name + " (copy)"}));
    }
    function removeLauncher(id): bool {
        if (!launchers.some(r => r.id === id)) { _actionError = "Launcher no longer exists"; return false; }
        return _commit(Object.assign({}, _config, {launchers: launchers.filter(r => r.id !== id)}));
    }
    function toggleFolder(path, name): int {
        const canonical = Folders.canonicalPath(path, Quickshell.env("HOME"));
        if (!canonical || typeof name !== "string" || !name) return 0;
        const existing = launchers.filter(r => r.kind === "folder" && Folders.canonicalPath(r.target, Quickshell.env("HOME")) === canonical);
        if (existing.length) return _commit(Object.assign({}, _config, {launchers:launchers.filter(r => existing.indexOf(r) < 0)}));
        return saveLauncher({kind:"folder", name:name, target:canonical, icon:"", enabled:true});
    }
    function folderAction(id, action): bool {
        const record = launchers.find(r => r.id === id && r.kind === "folder" && r.enabled);
        if (!ready || !record || !action || action.kind !== "folder-action"
            || action.root !== record.target || ["entry", "manager", "terminal"].indexOf(action.action) < 0) return false;
        return _requestLaunch(id, action);
    }
    function activate(id, urgentKey): bool {
        // Freeze the indicated native target before refreshing membership. A stale
        // urgent click must not turn into an ordinary click on a different window.
        const previousItem = _items.find(i => i.id === id && !i.canEdit);
        const urgent = previousItem && _windows.filter(w => previousItem.windows.indexOf(w.key) >= 0 && w.urgent === true)
            .sort((a, b) => a.key < b.key ? -1 : a.key > b.key ? 1 : 0)[0];
        _refresh();
        const item = _items.filter(i => i.id === id)[0];
        if (!ready || !item) { _actionError = "Application is no longer available"; return false; }
        const freshUrgent = !item.canEdit && !urgentKey && !urgent && _windows.filter(w => item.windows.indexOf(w.key) >= 0 && w.urgent === true)
            .sort((a, b) => a.key < b.key ? -1 : a.key > b.key ? 1 : 0)[0];
        if (urgentKey || urgent || freshUrgent) {
            const target = _windowTarget(id, urgentKey || (urgent || freshUrgent).key);
            if (!target || target.urgent !== true) {
                _actionError = "Urgent window is no longer available";
                return false;
            }
            if (_parkedWindows.some(r => r.key === target.key))
                return restoreWindow(id, target.key, "here", true) > 0;
            // Request acceptance is not focus acknowledgement. Observe this exact
            // stable key; never cycle/minimize or substitute another member.
            if (!activateWindow(id, target.key)) return false;
            _urgentFocus[id] = target.key;
            _refresh();
            return true;
        }
        if (item.canEdit) return _requestLaunch(id, launchers.find(r => r.id === id));
        if (item.running) {
            const matches = _windows.filter(w => item.windows.indexOf(w.key) !== -1);
            const visible = matches.filter(w => !_parkedWindows.some(r => r.key === w.key));
            const target = matches.filter(w => w.active)[0] || visible[0] || matches[0];
            if (_parking.running && _parkingReady) {
                const parked = _parkedWindows.filter(r => item.windows.indexOf(r.key) !== -1);
                if (parked.length === matches.length && parked.length) {
                    parked.sort((a, b) => a.sequence - b.sequence);
                    return restoreWindow(id, parked[0].key, "here") > 0;
                }
                if (target && target.active) {
                    if (settings.minimizeMode === "off") return matches.length > 1 ? cycleWindows(id, 1) : true;
                    return minimizeApplication(id) > 0;
                }
            }
            if (target && _parkedWindows.some(r => r.key === target.key))
                return restoreWindow(id, target.key, "here") > 0;
            const accepted = !!target && (testMode || _live.item.activate(target.handle));
            _actionError = accepted ? "" : "Window disappeared before activation";
            return accepted;
        }
        if (!item.canPin || !item.pinned || item.pending) {
            _actionError = item.pending ? "Launch already pending" : item.pinReason;
            return false;
        }
        return _requestLaunch(id, {kind: "application", desktopId: id, enabled: true});
    }
    // Explicit IPC always targets one current focused window, independent of click policy.
    function minimizeActive(): int {
        _refresh();
        const target = _windows.find(w => w.active && !_parkedWindows.some(r => r.key === w.key));
        const app = target && _items.find(i => !i.canEdit && i.windows.indexOf(target.key) >= 0);
        return app ? parkWindow(app.id, target.key) : 0;
    }
    function minimizeApplication(appId): int {
        _refresh();
        const item = _items.find(i => i.id === appId && !i.canEdit);
        if (!item || settings.minimizeMode === "off") return 0;
        const candidates = _windows.filter(w => item.windows.indexOf(w.key) !== -1
            && !_parkedWindows.some(r => r.key === w.key));
        const recentKey = _focusOrder.find(key => candidates.some(w => w.key === key));
        const preferred = candidates.find(w => w.active) || candidates.find(w => w.key === recentKey) || candidates[0];
        const chosen = settings.minimizeMode === "all" ? candidates : preferred ? [preferred] : [];
        let first = 0;
        for (const window of chosen) {
            const transaction = parkWindow(appId, window.key);
            if (!first) first = transaction;
        }
        return first;
    }
    // Rebuild membership immediately before every exact-window action.
    function _windowTarget(appId, key) {
        _refresh();
        if (!ready || typeof appId !== "string" || typeof key !== "string") return null;
        const item = _items.find(i => i.id === appId && !i.canEdit);
        if (!item || item.windows.indexOf(key) === -1) return null;
        return _windows.find(w => w.key === key) || null;
    }
    // Read-only binding-safe resolver. Never expose native handles in public rows.
    // In particular, do not call _refresh here: it replaces _windows and would
    // create a binding loop in the event-driven capture source binding.
    function previewTarget(appId, key) {
        if (testMode || !ready || !_live.item || typeof appId !== "string" || typeof key !== "string") return null;
        const item = _items.find(i => i.id === appId && !i.canEdit);
        if (!item || item.windows.indexOf(key) < 0 || _parkedWindows.some(w => w.key === key)) return null;
        const target = _windows.find(w => w.key === key);
        if (!target || !target.handle) return null;
        const current = _live.item.windows.find(w => w.handle === target.handle && w.appId === target.appId);
        return current ? current.handle : null;
    }
    function _parkingTarget(appId, key) {
        const target = _windowTarget(appId, key);
        if (!target) return null;
        let data = null;
        if (testMode) data = target.identity && target.origin ? {identity:target.identity, origin:target.origin} : null;
        else {
            try { data = _live.item ? _live.item.parkingRecord(target.handle) : null; }
            catch (_) { data = null; }
        }
        if (!data || !data.identity || !data.origin) return null;
        data.identity = Object.assign({}, data.identity, {key:key});
        return data;
    }
    function parkWindow(appId, key): int {
        if (_startupRecoveryRequired) { _actionError = "Recover parked windows before parking another window"; return 0; }
        const target = _parkingTarget(appId, key);
        if (target) return _enqueueParking({op:"park", window:target.identity, origin:target.origin});
        if (testMode || !_live.item || !_windowTarget(appId, key)) {
            _actionError = "Window identity changed before parking";
            return 0;
        }
        try { _live.item.refreshParkingMetadata(); } catch (_) {}
        return _enqueueParking({op:"park", appId:appId, key:key, awaitMetadata:true});
    }
    function restoreWindow(appId, key, mode, urgent): int {
        if (mode !== "here" && mode !== "origin") return 0;
        const target = _windowTarget(appId, key);
        if (!target || (urgent === true && target.urgent !== true) || !_parkedWindows.some(r => r.key === key)) return 0;
        if (!testMode) {
            let identity = null;
            try { identity = _live.item ? _live.item.parkingIdentity(target.handle) : null; } catch (_) {}
            if (!identity) return 0;
        }
        return _enqueueParking({op:"restore", appId:appId, key:key, mode:mode, urgent:urgent === true});
    }
    function _groupKeys(appId, keys) {
        if (!Array.isArray(keys) || !keys.length || keys.some((key, i) => typeof key !== "string" || keys.indexOf(key) !== i)) return [];
        return keys.every(key => !!_windowTarget(appId, key)) ? keys.slice() : [];
    }
    // Frozen keys only: never use global recovery as an app-group operation.
    // Each window retains its existing receipt. Focus once, only after all read-backs.
    function restoreApplication(appId, keys, mode): int {
        const scope = _groupKeys(appId, keys);
        if (!scope.length || (mode !== "here" && mode !== "origin") || !_parkingReady || !_parking.running
            || scope.some(key => !_parkedWindows.some(r => r.key === key))) return 0;
        const group = {appId:appId, focusKey:scope[0], remaining:scope.length, failed:false};
        let first = 0;
        for (const key of scope) {
            const transaction = _enqueueParking({op:"restore", appId:appId, key:key, mode:mode}, group);
            if (!first) first = transaction;
        }
        return first;
    }
    function restoreFifo(mode): int {
        if (mode !== "here" && mode !== "origin") return 0;
        return _enqueueParking({op:"restore-fifo", mode:mode});
    }
    function recoverParked(mode): int {
        if (mode !== "here" && mode !== "origin") return 0;
        return _enqueueParking({op:"recover", mode:mode});
    }
    function activateWindow(appId, key): bool {
        const target = _windowTarget(appId, key);
        let accepted = false;
        if (target) {
            if (_parkedWindows.some(window => window.key === key)) {
                // Submission only. The helper validates identity and publishes a
                // restore receipt after read-back; never fall through to activation.
                return restoreWindow(appId, key, "here") > 0;
            }
            if (testMode) {
                _windows = _windows.map(w => Object.assign({}, w, {active: w.key === key}));
                _refresh();
                accepted = true;
            } else {
                try { accepted = !!_live.item && _live.item.activate(target.handle); }
                catch (e) { accepted = false; }
            }
        }
        _actionError = accepted ? "" : "Window is no longer available for activation";
        return accepted;
    }
    // Accepted means a protocol request, not client acknowledgement or exit.
    function cycleWindows(appId, delta): bool {
        _refresh();
        const rows = typeof appId === "string" && Object.prototype.hasOwnProperty.call(_windowGroups, appId) ? _windowGroups[appId] : [];
        const key = Windows.cycleKey(rows, delta);
        if (!key) { _actionError = "No window available or invalid cycle direction"; return false; }
        return activateWindow(appId, key);
    }
    // Accepted means a protocol request, not client acknowledgement or exit.
    function closeWindow(appId, key): bool {
        const target = _windowTarget(appId, key);
        let accepted = false;
        if (target) {
            if (testMode) {
                _windows = _windows.filter(w => w.key !== key);
                _refresh();
                accepted = true;
            } else {
                try { accepted = !!_live.item && _live.item.close(target.handle); }
                catch (e) { accepted = false; }
            }
        }
        _actionError = accepted ? "" : "Window is no longer available for closing";
        return accepted;
    }
    function closeApplication(appId, keys): bool {
        const scope = _groupKeys(appId, keys);
        if (!scope.length) return false;
        let accepted = true;
        for (const key of scope) {
            // A request can synchronously change another member; recheck each.
            if (!closeWindow(appId, key)) accepted = false;
        }
        return accepted;
    }
    // Request submission only: desktop actions need not create a window.
    function desktopAction(appId, actionId): bool {
        _refresh();
        const item = _items.find(i => i.id === appId && !i.canEdit);
        const rows = _desktopActions[appId] || [];
        if (!ready || !item || !DesktopActions.validAppId(appId) || !DesktopActions.validId(actionId)
            || !rows.some(a => a.id === actionId)) {
            _actionError = "Desktop action is no longer available";
            return false;
        }
        return _requestLaunch(appId, {kind: "desktop-action", desktopId: appId, actionId: actionId, enabled: true});
    }
    function newInstance(id): bool {
        _refresh();
        const item = _items.find(i => i.id === id);
        if (!ready || !item || !item.canNewInstance) { _actionError = "No launchable desktop entry for new instance"; return false; }
        return _requestLaunch(id, {kind: "application", desktopId: id, enabled: true});
    }
    function _requestLaunch(id, record): bool {
        if (!record || !record.enabled || record.kind === "separator") { _actionError = "Launcher is disabled or not activatable"; return false; }
        if (_pending[id]) { _actionError = "Launch already pending"; return false; }
        if (record.kind === "application" && !_entries.some(e => e.id === record.desktopId && e.launchable)) {
            _actionError = "No launchable desktop entry"; return false;
        }
        if (!testMode && _launcher && _launcher.running) { _actionError = "Launcher is busy; try again"; return false; }
        const index = Apps.indexEntries(_entries);
        const members = record.kind === "application" ? _windows.filter(w => {
            const e = Apps.matchIndexed(index, w.appId, overrides);
            return e && e.id === record.desktopId;
        }).map(w => w.key) : [];
        _pending[id] = {deadline: Date.now() + _launchTimeout, kind: record.kind, token: ++_launchSerial, receipted: false,
            desktopId: record.desktopId || "", windows: members};
        _actionError = "";
        if (!testMode) {
            // Failed-start sources may not emit exited; the pending deadline still
            // bounds feedback, and the next request retires that inert source.
            if (_launcher) _launcher.destroy();
            _launcher = _launcherFactory.createObject(root, {requestId:id,
                requestToken:_pending[id].token, requestRecord:record});
            _launcher.running = true;
        }
        _refresh();
        return true;
    }
    function _finishLaunch(id, success, message, token) {
        const p = _pending[id];
        if (!p || p.token !== token || p.receipted) return;
        p.receipted = true;
        if (!success || p.kind !== "application") delete _pending[id];
        if (!success) _actionError = "Launch failed: " + message;
        _refresh();
    }
}
