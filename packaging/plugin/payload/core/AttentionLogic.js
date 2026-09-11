.pragma library

const MAX_APPS = 256;
const MAX_WINDOWS_PER_APP = 512;
const MAX_ROWS = 512;
const MAX_BASELINE_ROWS = 1024;
const MAX_SEEN = 1024;
const MAX_ATTENTION_APPS = 256;
const MAX_ATTENTION_IDS = 512;

// Pure attention policy. Contracts carry stable IDs and timing/state flags only;
// notification text is neither accepted nor retained.
function _stableId(value) {
    return typeof value === "string" && value.length > 0 && value.length <= 512
        && value === value.trim() && !/[\x00-\x1f\x7f]/.test(value);
}

function _optionalId(value) {
    return value === "" || _stableId(value);
}

function _idArray(value) {
    if (!Array.isArray(value) || value.length > 512) return false;
    for (let i = 0; i < value.length; ++i) {
        if (!_stableId(value[i]) || value.indexOf(value[i]) !== i) return false;
    }
    return true;
}

function _onlyKeys(value, allowed) {
    const keys = Object.keys(value);
    for (let i = 0; i < keys.length; ++i) {
        if (!Object.prototype.hasOwnProperty.call(allowed, keys[i])) return false;
    }
    return true;
}

function _validNotification(row) {
    if (!row || typeof row !== "object") return false;
    const allowed = {id: true, timestampMs: true, appId: true, pwaId: true, browserId: true};
    const keys = Object.keys(row);
    for (let i = 0; i < keys.length; ++i) {
        if (!Object.prototype.hasOwnProperty.call(allowed, keys[i])) return false;
    }
    return _stableId(row.id) && Number.isInteger(row.timestampMs) && row.timestampMs >= 0
        && _optionalId(row.appId) && _optionalId(row.pwaId) && _optionalId(row.browserId)
        && (row.appId !== "" || row.pwaId !== "" || row.browserId !== "");
}

function _validNotificationApp(app) {
    const allowed = {id: true, notificationIds: true, pwaIds: true, browserIds: true,
        focused: true, launchPending: true, openedAtMs: true, windows: true};
    return !!app && typeof app === "object" && _onlyKeys(app, allowed) && _stableId(app.id)
        && _idArray(app.notificationIds) && _idArray(app.pwaIds) && _idArray(app.browserIds)
        && typeof app.focused === "boolean" && typeof app.launchPending === "boolean"
        && Number.isFinite(app.openedAtMs) && app.openedAtMs >= 0;
}

function _validNativeApp(app) {
    const allowed = {id: true, notificationIds: true, pwaIds: true, browserIds: true,
        focused: true, launchPending: true, openedAtMs: true, windows: true};
    return !!app && typeof app === "object" && _onlyKeys(app, allowed) && _stableId(app.id)
        && typeof app.focused === "boolean" && typeof app.launchPending === "boolean"
        && Array.isArray(app.windows) && app.windows.length <= MAX_WINDOWS_PER_APP;
}

function _validWindow(win) {
    return !!win && typeof win === "object"
        && _onlyKeys(win, {id: true, focused: true, openedAtMs: true}) && _stableId(win.id)
        && typeof win.focused === "boolean" && Number.isFinite(win.openedAtMs) && win.openedAtMs >= 0;
}

function _eligible(app, nowMs) {
    return _validNotificationApp(app) && Number.isFinite(nowMs) && !app.focused
        && !app.launchPending && nowMs >= app.openedAtMs && nowMs - app.openedAtMs > 3000;
}

function nativeUrgency(apps, windowId, nowMs) {
    if (!Array.isArray(apps) || apps.length > MAX_APPS || !_stableId(windowId) || !Number.isFinite(nowMs)) return null;
    let match = null;
    for (let i = 0; i < apps.length; ++i) {
        const app = apps[i];
        if (!_validNativeApp(app)) continue;
        for (let j = 0; j < app.windows.length; ++j) {
            const win = app.windows[j];
            if (!_validWindow(win) || win.id !== windowId) continue;
            if (match) return null; // Duplicate window IDs are ambiguous and fail closed.
            match = {app: app, win: win};
        }
    }
    if (!match || match.app.focused || match.app.launchPending || match.win.focused
            || nowMs < match.win.openedAtMs || nowMs - match.win.openedAtMs <= 3000) return null;
    return {appId: match.app.id, windowId: match.win.id};
}

function _matchingApps(apps, field, id) {
    if (!_stableId(id)) return {status: "none", matches: []};
    let match = "";
    for (let i = 0; i < apps.length; ++i) {
        const app = apps[i];
        if (!_validNotificationApp(app)) continue;
        const exact = field === "appId"
            ? app.id === id || app.notificationIds.indexOf(id) !== -1
            : app[field].indexOf(id) !== -1;
        if (exact) {
            if (match !== "") return {status: "ambiguous", matches: []};
            match = app.id;
        }
    }
    return match === "" ? {status: "none", matches: []} : {status: "unique", matches: [match]};
}

function notificationTargets(apps, notification) {
    if (!Array.isArray(apps) || apps.length > MAX_APPS || !_validNotification(notification)) return [];
    const candidates = [["pwaIds", notification.pwaId], ["appId", notification.appId],
        ["browserIds", notification.browserId]];
    for (let i = 0; i < candidates.length; ++i) {
        if (candidates[i][1] === "") continue;
        const result = _matchingApps(apps, candidates[i][0], candidates[i][1]);
        if (result.status === "ambiguous") return [];
        if (result.status === "unique") return result.matches;
    }
    return [];
}

function newState() {
    return {generation: "", seen: Object.create(null), attention: Object.create(null), overflow: false};
}

function _copySet(source, limit) {
    const result = Object.create(null);
    let copied = 0;
    let overflow = false;
    if (!source || typeof source !== "object") return {value: result, overflow: false};
    for (const key in source) {
        if (!Object.prototype.hasOwnProperty.call(source, key)) {
            overflow = true;
            continue;
        }
        if (!_stableId(key) || source[key] !== true) continue;
        if (copied >= limit) {
            overflow = true;
            break;
        }
        result[key] = true;
        ++copied;
    }
    return {value: result, overflow: overflow};
}

function _copyState(state) {
    const result = newState();
    if (!state || typeof state !== "object") return result;
    if (_stableId(state.generation)) result.generation = state.generation;
    const seen = _copySet(state.seen, MAX_SEEN);
    result.seen = seen.value;
    result.overflow = state.overflow === true || seen.overflow;
    if (state.attention && typeof state.attention === "object") {
        let copiedApps = 0;
        for (const appId in state.attention) {
            if (!Object.prototype.hasOwnProperty.call(state.attention, appId)) {
                result.overflow = true;
                continue;
            }
            if (copiedApps >= MAX_ATTENTION_APPS) {
                result.overflow = true;
                break;
            }
            ++copiedApps;
            const entry = state.attention[appId];
            if (_stableId(appId) && entry && typeof entry === "object") {
                const notifications = _copySet(entry.notifications, MAX_ATTENTION_IDS);
                const windows = _copySet(entry.windows, MAX_ATTENTION_IDS);
                if (notifications.overflow || windows.overflow) result.overflow = true;
                if (Object.keys(notifications.value).length || Object.keys(windows.value).length) {
                    result.attention[appId] = {notifications: notifications.value, windows: windows.value};
                }
            }
        }
    }
    return result;
}

function beginGeneration(state, generation, baselineRows) {
    const result = _copyState(state);
    if (!_stableId(generation) || !Array.isArray(baselineRows)) return result;
    result.generation = generation;
    result.seen = Object.create(null);
    result.overflow = baselineRows.length > MAX_BASELINE_ROWS;
    if (result.overflow) return result;
    for (let i = 0; i < baselineRows.length; ++i) {
        if (_validNotification(baselineRows[i])) result.seen[baselineRows[i].id] = true;
    }
    return result;
}

function _entry(state, appId) {
    if (!state.attention[appId])
        state.attention[appId] = {notifications: Object.create(null), windows: Object.create(null)};
    return state.attention[appId];
}

function recordNative(state, candidate) {
    const result = _copyState(state);
    if (!candidate || !_stableId(candidate.appId) || !_stableId(candidate.windowId)) return result;
    if (!result.attention[candidate.appId] && Object.keys(result.attention).length >= MAX_ATTENTION_APPS) {
        result.overflow = true;
        return result;
    }
    const entry = _entry(result, candidate.appId);
    if (!entry.windows[candidate.windowId] && Object.keys(entry.windows).length >= MAX_ATTENTION_IDS) {
        result.overflow = true;
        return result;
    }
    entry.windows[candidate.windowId] = true;
    return result;
}

function _findUniqueApp(apps, appId) {
    let found = null;
    for (let i = 0; i < apps.length; ++i) {
        if (_validNotificationApp(apps[i]) && apps[i].id === appId) {
            if (found) return null;
            found = apps[i];
        }
    }
    return found;
}

function soundDecision(settings, dnd, eligibleMatches) {
    if (!settings || settings.enabled !== true || dnd !== false || !Array.isArray(eligibleMatches)
            || eligibleMatches.length === 0 || !_stableId(settings.soundName)
            || settings.soundName === "none") return "";
    return settings.soundName;
}

function processNotifications(state, generation, rows, apps, policy, nowMs) {
    const resultState = _copyState(state);
    const matches = [];
    const overflow = resultState.overflow || Array.isArray(rows) && rows.length > MAX_ROWS
        || Array.isArray(apps) && apps.length > MAX_APPS;
    if (overflow) resultState.overflow = true;
    if (!_stableId(generation) || generation !== resultState.generation || !Array.isArray(rows)
            || !Array.isArray(apps) || overflow || !policy || policy.enabled !== true || !Number.isFinite(nowMs))
        return {state: resultState, matches: matches, soundName: "", overflow: overflow};

    for (let i = 0; i < rows.length; ++i) {
        const notification = rows[i];
        if (!_validNotification(notification) || resultState.seen[notification.id]) continue;
        if (Object.keys(resultState.seen).length >= MAX_SEEN) {
            resultState.overflow = true;
            return {state: resultState, matches: [], soundName: "", overflow: true};
        }
        resultState.seen[notification.id] = true;
        const targets = notificationTargets(apps, notification);
        if (targets.length !== 1) continue;
        const app = _findUniqueApp(apps, targets[0]);
        if (!_eligible(app, nowMs)) continue;
        if (!resultState.attention[app.id] && Object.keys(resultState.attention).length >= MAX_ATTENTION_APPS) {
            resultState.overflow = true;
            return {state: resultState, matches: [], soundName: "", overflow: true};
        }
        const entry = _entry(resultState, app.id);
        if (!entry.notifications[notification.id] && Object.keys(entry.notifications).length >= MAX_ATTENTION_IDS) {
            resultState.overflow = true;
            return {state: resultState, matches: [], soundName: "", overflow: true};
        }
        entry.notifications[notification.id] = true;
        matches.push({notificationId: notification.id, appId: app.id});
    }
    const soundName = soundDecision({enabled: policy.soundEnabled, soundName: policy.soundName},
                                    policy.dnd, matches);
    return {state: resultState, matches: matches, soundName: soundName, overflow: false};
}

function _dropEmpty(state, appId) {
    const entry = state.attention[appId];
    if (entry && !Object.keys(entry.notifications).length && !Object.keys(entry.windows).length)
        delete state.attention[appId];
}

function closeWindow(state, windowId) {
    const result = _copyState(state);
    if (!_stableId(windowId)) return result;
    Object.keys(result.attention).forEach(appId => {
        delete result.attention[appId].windows[windowId];
        _dropEmpty(result, appId);
    });
    return result;
}

function clearFocused(state, appId) {
    const result = _copyState(state);
    if (_stableId(appId)) delete result.attention[appId];
    return result;
}

function closeApp(state, appId) {
    return clearFocused(state, appId);
}

function hintVisible(state, appId, showUrgentHint, apps) {
    if (showUrgentHint !== true || !_stableId(appId) || !Array.isArray(apps) || apps.length > MAX_APPS) return false;
    const safe = _copyState(state);
    const entry = safe.attention[appId];
    if (!entry || (!Object.keys(entry.notifications).length && !Object.keys(entry.windows).length)) return false;
    let app = null;
    for (let i = 0; i < apps.length; ++i) {
        if (apps[i] && apps[i].id === appId) {
            if (app) return false;
            app = apps[i];
        }
    }
    return !!app && app.focused === false;
}
