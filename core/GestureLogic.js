.pragma library

function none(reason) {
    return {action: "none", reason: reason || "", key: "", target: ""};
}

function stableKey(window) {
    return window && typeof window.key === "string" && window.key.length > 0 ? window.key : "";
}

function validUniqueWindows(windows) {
    if (!Array.isArray(windows)) return false;
    const seen = Object.create(null);
    for (const window of windows) {
        const key = stableKey(window);
        if (!key || Object.prototype.hasOwnProperty.call(seen, key)) return false;
        seen[key] = true;
    }
    return true;
}

// Positive wheel deltas select the previous row; negative deltas select next.
function wheelSelection(windows, selectedKey, delta) {
    if (!validUniqueWindows(windows) || !windows.length || typeof delta !== "number"
            || !Number.isFinite(delta) || delta === 0)
        return none("invalid-wheel");
    const keys = windows.map(stableKey);
    const current = keys.indexOf(selectedKey);
    if (current < 0) return {action: "select", reason: "initial", key: keys[0], target: ""};
    const step = delta > 0 ? -1 : 1;
    return {action: "select", reason: "wheel", key: keys[(current + step + keys.length) % keys.length], target: ""};
}

function isVisibleWindow(window) {
    return !!window && window.mapped !== false && window.hidden !== true && window.parked !== true;
}

function appWheelDecision(windows, selectedKey, delta) {
    if (!validUniqueWindows(windows)) return none("invalid-model");
    if (typeof delta !== "number" || !Number.isFinite(delta) || delta === 0)
        return none("invalid-wheel");
    const visible = windows.filter(isVisibleWindow);
    if (visible.length > 1) return wheelSelection(visible, selectedKey, delta);
    if (visible.length === 1)
        return {action: "cycle-app", reason: "singleton", key: stableKey(visible[0]), target: ""};
    if (windows.length)
        return {action: "cycle-app", reason: "all-parked", key: "", target: ""};
    return none("no-windows");
}

function appGesture(button) {
    return button === "middle"
        ? {action: "launch-new-instance", reason: "", key: "", target: ""}
        : none("unsupported-button");
}

function settingsLogoGesture(kind, delta) {
    if (kind === "left") return {action: "quick-menu", reason: "", key: "", target: ""};
    if (kind === "right") return {action: "settings", reason: "", key: "", target: ""};
    if (kind === "middle") return {action: "terminal", reason: "", key: "", target: ""};
    if (kind === "wheel" && typeof delta === "number" && Number.isFinite(delta) && delta !== 0)
        return {action: "workspace", reason: "adjacent-existing", key: "", target: delta < 0 ? "e+1" : "e-1"};
    return none("unsupported-gesture");
}

function emptySpaceGesture(button) {
    return button === "right"
        ? {action: "settings", reason: "", key: "", target: ""}
        : none("unsupported-button");
}

function acceptSelection(windows, key, pressedRevision, currentRevision) {
    if (!Number.isSafeInteger(pressedRevision) || pressedRevision < 0
            || !Number.isSafeInteger(currentRevision) || currentRevision < 0)
        return none("invalid-revision");
    if (pressedRevision !== currentRevision) return none("stale-model");
    if (!validUniqueWindows(windows) || windows.map(stableKey).indexOf(key) < 0)
        return none("missing-key");
    return {action: "activate-window", reason: "", key: key, target: ""};
}

function validRect(rect) {
    return !!rect && [rect.x, rect.y, rect.width, rect.height].every(function(value) {
        return typeof value === "number" && Number.isFinite(value);
    }) && rect.width > 0 && rect.height > 0;
}

function intersectsStrict(a, b) {
    return validRect(a) && validRect(b)
        && a.x < b.x + b.width && a.x + a.width > b.x
        && a.y < b.y + b.height && a.y + a.height > b.y;
}

// Snapshot-only overlap policy: callers decide when compositor data is refreshed.
function hasStrictOverlap(windows, dockRect, selectedOutput, activeWorkspace) {
    if (!Array.isArray(windows) || !validRect(dockRect)) return false;
    return windows.some(function(window) {
        return isVisibleWindow(window)
            && window.output === selectedOutput
            && window.workspace === activeWorkspace
            && intersectsStrict(window, dockRect);
    });
}
