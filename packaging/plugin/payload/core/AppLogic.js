.pragma library

function validId(id) {
    return typeof id === "string" && id.length > 0 && id.length <= 512
        && id !== "menu" && !/[\/\\\x00-\x1f]/.test(id) && id !== "." && id !== "..";
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
    const skip = {www: true, web: true, com: true, org: true, net: true, app: true, default: true};
    const labels = host.split(".").filter(function(label) {
        return label && label.length > 2 && !skip[label];
    });
    if (!labels.length) return null;
    const hits = [];
    for (const id in index.ids) {
        const entry = index.ids[id];
        if (!entry) continue;
        const hay = String(entry.id + " " + entry.name).toLowerCase();
        if (labels.some(function(label) { return hay.indexOf(label.toLowerCase()) >= 0; }))
            hits.push(entry);
    }
    return hits.length === 1 ? hits[0] : null;
}
function matchIndexed(index, appId, overrides) {
    if (overrides && Object.prototype.hasOwnProperty.call(overrides, appId)) return index.ids[overrides[appId]] || null;
    if (index.ids[appId]) return index.ids[appId];
    if (typeof appId === "string" && appId.endsWith(".desktop") && index.ids[appId.slice(0, -8)]) return index.ids[appId.slice(0, -8)];
    if (Object.prototype.hasOwnProperty.call(index.classes, appId)) return index.classes[appId];
    const aliases = {"brave-messages.google.com__web_conversations-Default": "Google Messages",
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
    return pins.concat(stable).filter(id => id !== "menu").map(id => groups[id]);
}
