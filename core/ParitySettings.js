.pragma library

const soundNames = ["bell", "message-new-instant", "complete", "dialog-information",
    "dialog-warning", "phone-incoming-call", "alarm-clock-elapsed", "none"];
const folderColors = ["theme", "symbolic", "white", "black", "Yaru-sage", "Yaru-olive",
    "Yaru-blue", "Yaru-purple", "Yaru-magenta", "Yaru-red", "Yaru-yellow",
    "Yaru-wartybrown", "Yaru-prussiangreen", "Yaru-dark"];
const booleanKeys = ["showMinimizedTiles", "showAppsButton", "showTooltips", "advancedTooltips",
    "launchBounce", "showUrgentHint", "urgentOnNotification", "urgentSound"];
const dangerousKeys = ["__proto__", "prototype", "constructor"];
const MAX_INPUT_BYTES = 64 * 1024;
const MAX_DEPTH = 32;
const MAX_NODES = 4096;

function own(object, key) {
    return Object.prototype.hasOwnProperty.call(object, key);
}

function isObject(value) {
    return !!value && typeof value === "object" && !Array.isArray(value);
}

function finiteNumber(value) {
    return typeof value === "number" && Number.isFinite(value);
}

function utf8Bytes(text) {
    let bytes = 0;
    for (let i = 0; i < text.length; ++i) {
        const code = text.charCodeAt(i);
        if (code < 0x80) bytes += 1;
        else if (code < 0x800) bytes += 2;
        else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length
                && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
            bytes += 4;
            ++i;
        } else bytes += 3;
    }
    return bytes;
}

function rejectDangerous(value) {
    const pending = [{value: value, depth: 0}];
    const seen = [];
    let nodes = 0;
    let bytes = 0;
    while (pending.length) {
        const item = pending.pop();
        const current = item.value;
        if (++nodes > MAX_NODES || item.depth > MAX_DEPTH)
            throw new Error("Configuration is too complex");
        bytes += 1;
        if (typeof current === "string") bytes += utf8Bytes(current) + 2;
        else if (typeof current === "number") {
            if (!Number.isFinite(current)) throw new Error("Invalid configuration number");
            bytes += String(current).length;
        } else if (typeof current === "boolean") bytes += current ? 4 : 5;
        else if (current === null) bytes += 4;
        else if (typeof current !== "object") throw new Error("Configuration must contain JSON values");
        if (!current || typeof current !== "object") {
            if (bytes > MAX_INPUT_BYTES) throw new Error("Configuration is too large");
            continue;
        }
        if (seen.indexOf(current) >= 0) throw new Error("Cyclic configuration");
        seen.push(current);
        const prototype = Object.getPrototypeOf(current);
        if ((Array.isArray(current) && prototype !== Array.prototype)
                || (!Array.isArray(current) && prototype !== Object.prototype && prototype !== null))
            throw new Error("Unsafe configuration prototype");
        for (const inherited in current) {
            if (!own(current, inherited)) throw new Error("Unsafe inherited configuration key");
        }
        const keys = Object.keys(current);
        for (let i = 0; i < keys.length; ++i) {
            const key = keys[i];
            bytes += utf8Bytes(key) + 3;
            if (dangerousKeys.indexOf(key) >= 0) throw new Error("Unsafe configuration key: " + key);
            if (bytes > MAX_INPUT_BYTES) throw new Error("Configuration is too large");
            pending.push({value: current[key], depth: item.depth + 1});
        }
    }
}

function clone(value) {
    if (Array.isArray(value)) return value.map(clone);
    if (value && typeof value === "object") {
        const result = {};
        Object.keys(value).forEach(function(key) { result[key] = clone(value[key]); });
        return result;
    }
    return value;
}

function defaults() {
    return {
        autohide: true,
        intelligentAutohide: true,
        minimizeMode: "active",
        showMinimizedTiles: true,
        opacity: 1,
        shape: "rounded",
        bgColor: "theme",
        iconSize: 0,
        itemSpacing: 4,
        hoverEffect: "zoom",
        showAppsButton: true,
        showTooltips: true,
        advancedTooltips: true,
        launchBounce: true,
        showUrgentHint: true,
        urgentOnNotification: true,
        urgentSound: true,
        urgentSoundName: "bell",
        folderColor: "theme",
        revealDelay: 160,
        tooltipDelay: 450,
        screen: "",
        pinnedFolders: [{path: "~/Downloads", name: "Downloads", icon: "folder-download"}]
    };
}

function enumValue(raw, key, fallback, values) {
    if (!own(raw, key)) return fallback;
    if (typeof raw[key] !== "string" || values.indexOf(raw[key]) < 0)
        throw new Error("Invalid setting: " + key);
    return raw[key];
}

function booleanValue(raw, key, fallback) {
    if (!own(raw, key)) return fallback;
    if (typeof raw[key] !== "boolean") throw new Error("Invalid setting: " + key);
    return raw[key];
}

function normalizeOpacity(raw, fallback) {
    if (!own(raw, "opacity")) return fallback;
    const value = raw.opacity;
    if (value === "theme" || value === "auto" || value === -1) return "theme";
    if (!finiteNumber(value)) throw new Error("Invalid setting: opacity");
    return Math.max(0, Math.min(1, value));
}

function normalizeShape(raw, fallback) {
    if (!own(raw, "shape")) return fallback;
    const value = raw.shape;
    if (value === "auto") return "theme";
    if (value === "pill") return "round";
    if (["rounded", "round", "square", "theme"].indexOf(value) < 0)
        throw new Error("Invalid setting: shape");
    return value;
}

function normalizeBackground(raw, fallback) {
    if (!own(raw, "bgColor")) return fallback;
    const value = raw.bgColor;
    if (value === "theme" || value === "none") return value;
    if (typeof value !== "string" || !/^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(value))
        throw new Error("Invalid setting: bgColor");
    return value;
}

function normalizeIconSize(raw, fallback) {
    if (!own(raw, "iconSize")) return fallback;
    const value = raw.iconSize;
    if (value === "auto" || value === 0) return 0;
    if (!Number.isInteger(value) || value < 28 || value > 72)
        throw new Error("Invalid setting: iconSize");
    return value;
}

function boundedDelay(raw, key, fallback, maximum) {
    if (!own(raw, key)) return fallback;
    const value = raw[key];
    if (!finiteNumber(value)) throw new Error("Invalid setting: " + key);
    return Math.max(0, Math.min(maximum, Math.round(value)));
}

function normalizeScreen(raw, fallback) {
    if (!own(raw, "screen")) return fallback;
    const value = raw.screen;
    if (typeof value !== "string" || value.length > 256 || /[\x00-\x1f]/.test(value))
        throw new Error("Invalid setting: screen");
    return value;
}

function normalizeFolders(raw, fallback) {
    if (!own(raw, "pinnedFolders")) return clone(fallback);
    const folders = raw.pinnedFolders;
    if (!Array.isArray(folders) || folders.length > 256)
        throw new Error("Invalid setting: pinnedFolders");
    folders.forEach(function(folder) {
        if (!isObject(folder) || !own(folder, "path") || !own(folder, "name") || !own(folder, "icon")
                || typeof folder.path !== "string" || !folder.path
                || typeof folder.name !== "string" || !folder.name
                || typeof folder.icon !== "string" || !folder.icon
                || folder.path.length > 4096 || folder.name.length > 512 || folder.icon.length > 512
                || /[\x00-\x1f]/.test(folder.path + folder.name + folder.icon))
            throw new Error("Invalid pinned folder");
    });
    return clone(folders);
}

function normalize(raw) {
    if (!isObject(raw)) throw new Error("Settings must be an object");
    rejectDangerous(raw);
    const d = defaults();
    const result = clone(raw); // Unknown JSON keys intentionally survive.

    result.autohide = booleanValue(raw, "autohide", d.autohide);
    result.intelligentAutohide = booleanValue(raw, "intelligentAutohide", d.intelligentAutohide);
    if (!result.autohide) result.intelligentAutohide = false;
    result.minimizeMode = enumValue(raw, "minimizeMode", d.minimizeMode, ["active", "all", "off"]);
    booleanKeys.forEach(function(key) { result[key] = booleanValue(raw, key, d[key]); });
    result.opacity = normalizeOpacity(raw, d.opacity);
    result.shape = normalizeShape(raw, d.shape);
    result.bgColor = normalizeBackground(raw, d.bgColor);
    result.iconSize = normalizeIconSize(raw, d.iconSize);
    if (own(raw, "itemSpacing") && [2, 4, 8].indexOf(raw.itemSpacing) < 0)
        throw new Error("Invalid setting: itemSpacing");
    result.itemSpacing = own(raw, "itemSpacing") ? raw.itemSpacing : d.itemSpacing;
    result.hoverEffect = enumValue(raw, "hoverEffect", d.hoverEffect, ["zoom", "wave", "off"]);
    result.urgentSoundName = enumValue(raw, "urgentSoundName", d.urgentSoundName, soundNames);
    if (result.urgentSoundName === "none") result.urgentSound = false;
    result.folderColor = enumValue(raw, "folderColor", d.folderColor, folderColors);
    result.revealDelay = boundedDelay(raw, "revealDelay", d.revealDelay, 2000);
    result.tooltipDelay = boundedDelay(raw, "tooltipDelay", d.tooltipDelay, 5000);
    result.screen = normalizeScreen(raw, d.screen);
    result.pinnedFolders = normalizeFolders(raw, d.pinnedFolders);
    return result;
}

function parse(text) {
    try {
        if (typeof text !== "string") throw new Error("Settings input must be JSON text");
        if (utf8Bytes(text) > MAX_INPUT_BYTES) throw new Error("Settings input is too large");
        return {settings: normalize(JSON.parse(text)), error: ""};
    } catch (error) {
        return {settings: defaults(), error: "Invalid parity settings: " + error.message};
    }
}

function serialize(settings) {
    const result = normalize(settings);
    if (result.iconSize === 0) delete result.iconSize;
    if (result.screen === "") delete result.screen;
    return JSON.stringify(result);
}

function hideMode(settings) {
    if (!settings || settings.autohide === false) return "always";
    return settings.intelligentAutohide === true ? "intelligent" : "standard";
}

function withHideMode(settings, mode) {
    if (["always", "standard", "intelligent"].indexOf(mode) < 0)
        throw new Error("Invalid hide mode");
    const result = normalize(settings);
    result.autohide = mode !== "always";
    result.intelligentAutohide = mode === "intelligent";
    return result;
}
