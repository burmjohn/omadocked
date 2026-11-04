.pragma library

function validId(id) {
    return typeof id === "string" && id.length > 0 && id.length <= 512
        && id !== "menu" && id !== "omarchy-menu" && !/[\/\\\x00-\x1f]/.test(id) && id !== "." && id !== "..";
}

function parsePins(text) {
    try {
        const config = JSON.parse(text);
        if (!config || config.version !== 1) throw new Error("Unsupported pins version");
        if (!Array.isArray(config.pins) || config.pins.length > 256
            || config.pins.some((id, i) => !validId(id) || config.pins.indexOf(id) !== i))
            throw new Error("Invalid pins list");
        return {pins: config.pins, error: ""};
    } catch (e) { return {pins: [], error: "Pins are read-only: " + e.message}; }
}

// Indices are scoped to one build: desktop-entry updates cannot leave stale matches.
function indexEntries(entries) {
    const ids = Object.create(null), classes = Object.create(null);
    entries.forEach(e => {
        ids[e.id] = Object.prototype.hasOwnProperty.call(ids, e.id) ? null : e;
        if (e.startupClass) classes[e.startupClass] = Object.prototype.hasOwnProperty.call(classes, e.startupClass) ? null : e;
    });
    return {ids: ids, classes: classes};
}
function hostFromClass(appId) {
    if (typeof appId !== "string") return "";
    const match = /^(?:brave|chrome|chromium|vivaldi|microsoft-edge)-(.+?)(?:__|$)/.exec(appId);
    return match ? match[1].replace(/_/g, ".") : "";
}
function domainMatch(index, appId) {
    const host = hostFromClass(appId);
    if (!host) return null;
    // Explicit known PWA metadata only. Generic domain labels/display names
    // cannot establish membership (music.youtube.com is not org.gnome.Music).
    const known = {"music.youtube.com": "YouTube Music",
                   "messages.google.com": "Google Messages",
                   "web.whatsapp.com": "WhatsApp"};
    return Object.prototype.hasOwnProperty.call(known, host) ? index.ids[known[host]] || null : null;
}
function matchIndexed(index, appId, overrides) {
    if (overrides && Object.prototype.hasOwnProperty.call(overrides, appId)) return index.ids[overrides[appId]] || null;
    // A present null is ambiguous, not absent: do not fall through to aliases.
    if (Object.prototype.hasOwnProperty.call(index.ids, appId)) return index.ids[appId];
    if (typeof appId === "string" && appId.endsWith(".desktop")
        && Object.prototype.hasOwnProperty.call(index.ids, appId.slice(0, -8))) return index.ids[appId.slice(0, -8)];
    if (Object.prototype.hasOwnProperty.call(index.classes, appId)) return index.classes[appId];
    // Known desktop/window metadata mismatches only; never case-fold launch IDs.
    // T3's reverse-DNS helper entry is NoDisplay; use its visible t3code launcher.
    // ChatGPT's XWayland class differs in case and has no StartupWMClass entry.
    const aliases = {"Chatgpt": "chatgpt", "com.t3tools.T3Code": "t3code",
                     "brave-messages.google.com__web_conversations-Default": "Google Messages",
                     "brave-web.whatsapp.com__-Default": "WhatsApp"};
    if (Object.prototype.hasOwnProperty.call(aliases, appId) && index.ids[aliases[appId]])
        return index.ids[aliases[appId]];
    return domainMatch(index, appId);
}
// Exact overrides, IDs, desktop suffix, unambiguous StartupWMClass, explicit aliases.
function match(entries, appId, overrides) { return matchIndexed(indexEntries(entries), appId, overrides); }

function build(entries, windows, pins, previous, overrides) {
    const index = indexEntries(entries);
    const groups = Object.create(null);
    function add(id, entry, pinned) {
        if (!groups[id]) groups[id] = {id: id, name: entry ? entry.name : id.replace(/^window:/, ""),
            icon: entry ? entry.icon || "" : "", running: false, active: false, pinned: pinned,
            canPin: !!(entry && entry.launchable), windowCount: 0, pending: false,
            kind: "application", canNewInstance: !!(entry && entry.launchable),
            canEdit: false, canDuplicate: false, canRemove: false,
            pinReason: entry && entry.launchable ? "" : "No launchable desktop entry", windows: []};
        return groups[id];
    }
    pins.forEach(id => add(id, index.ids[id], true));
    windows.forEach(w => {
        const entry = matchIndexed(index, w.appId, overrides);
        const id = entry ? entry.id : "window:" + (w.appId || w.key);
        const item = add(id, entry, pins.indexOf(id) !== -1);
        item.running = true;
        item.active = item.active || !!w.active;
        item.windowCount++;
        item.windows.push(w.key);
    });
    const rest = Object.keys(groups).filter(id => pins.indexOf(id) === -1).sort();
    const stable = previous.filter(id => rest.indexOf(id) !== -1);
    rest.forEach(id => { if (stable.indexOf(id) === -1) stable.push(id); });
    return pins.concat(stable).filter(id => id !== "menu" && id !== "omarchy-menu").map(id => groups[id]);
}

// Synthetic shelf divider for unpinned apps that are not on any displayed workspace.
const HIDDEN_WORKSPACES_ID = "hidden-workspaces";

function hiddenWorkspacesSeparator() {
    return {id: HIDDEN_WORKSPACES_ID, name: "Other workspaces", icon: "", running: false, active: false,
        pinned: false, canPin: false, windowCount: 0, pending: false, kind: "separator",
        canNewInstance: false, canEdit: false, canDuplicate: false, canRemove: false,
        pinReason: "", windows: []};
}

// Same visibility rule as overlap: mapped, not hidden, on a monitor's active
// workspace or shown special workspace. Pinned clients count if their output exists.
function windowOnScreen(window, monitors) {
    if (!window || window.mapped !== true || window.hidden === true) return false;
    const outputs = monitors || [];
    if (window.pinned === true)
        return outputs.some(m => m && m.name === window.monitor);
    if (window.workspace === null || window.workspace === undefined) return false;
    return outputs.some(m => m && (m.workspace === window.workspace
        || (m.special !== 0 && m.special === window.workspace)));
}

function markScreenPresence(item, windows) {
    const members = (item && item.windows || []).map(key => (windows || []).find(w => w.key === key)).filter(Boolean);
    let visible = false, hidden = false, unknown = false;
    members.forEach(w => {
        if (w.viewable === true) visible = true;
        else if (w.viewable === false) hidden = true;
        else unknown = true;
    });
    const next = item || {};
    next.onScreen = visible;
    next.offScreen = !visible && !unknown && hidden;
    return next;
}

function isRunningApplication(item) {
    return !!(item && item.running && !item.pinned && !item.canEdit
        && (!item.kind || item.kind === "application")
        && item.id !== HIDDEN_WORKSPACES_ID
        && !(typeof item.id === "string" && item.id.indexOf("launcher:") === 0));
}

function shelfItems(items, options) {
    const showHidden = !!(options && options.showHiddenWorkspaceApps === true);
    const hideVisible = !!(options && options.hideVisibleApps === true);
    const list = items || [];
    const kept = [];
    const hidden = [];
    for (let i = 0; i < list.length; ++i) {
        const item = list[i];
        if (!item || item.id === HIDDEN_WORKSPACES_ID) continue;
        if (!isRunningApplication(item) || (!showHidden && !hideVisible)) {
            kept.push(item);
            continue;
        }
        if (item.onScreen === true) {
            if (!hideVisible) kept.push(item);
        } else if (item.offScreen === true) {
            if (showHidden) hidden.push(item);
            else kept.push(item);
        } else kept.push(item);
    }
    if (showHidden && hidden.length)
        return kept.concat([hiddenWorkspacesSeparator()], hidden);
    return kept;
}
