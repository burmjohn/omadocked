.pragma library

const STATUS = ["ok", "empty", "missing", "not-directory", "unreadable", "timeout", "cancelled", "too-large", "changed"];
const colors = ["theme", "symbolic", "white", "black", "Yaru-sage", "Yaru-olive", "Yaru-blue", "Yaru-purple", "Yaru-magenta", "Yaru-red", "Yaru-yellow", "Yaru-wartybrown", "Yaru-prussiangreen", "Yaru-dark"];
const presets = ["Downloads", "Documents", "Pictures", "Projects", "Music", "Videos", "Home"];
function canonicalPath(path, home) {
    if (typeof path !== "string") return "";
    if (path === "~") path = home;
    else if (path.startsWith("~/")) path = home + path.slice(1);
    if (!absolutePath(path) || /[\x00-\x1f]/.test(path) || path.split("/").some(p => p === "." || p === "..")) return "";
    return path.replace(/\/+$/, "") || "/";
}
const TYPES = ["file", "directory", "symlink", "other"];
const CATEGORIES = ["document", "folder", "link", "image", "audio", "video", "archive", "code", "other"];

function object(value) { return !!value && typeof value === "object" && !Array.isArray(value); }
function integer(value) { return Number.isSafeInteger(value) && value >= 0; }
function decimal(value) { return typeof value === "string" && /^(?:0|[1-9][0-9]{0,19})$/.test(value); }
// Timestamps are canonical signed decimal text, not IEEE-754 numbers. Identity
// fields remain unsigned and bounded separately. Never coerce nanoseconds to Number.
function timestamp(value) { return typeof value === "string" && /^(?:0|-?[1-9][0-9]*)(?![\s\S])/.test(value); }
function compareTimestamps(a, b) {
    if (a === b) return 0;
    const negativeA = a[0] === "-";
    const negativeB = b[0] === "-";
    if (negativeA !== negativeB) return negativeA ? -1 : 1;
    const left = negativeA ? a.slice(1) : a;
    const right = negativeB ? b.slice(1) : b;
    const magnitude = left.length !== right.length ? (left.length < right.length ? -1 : 1)
        : (left < right ? -1 : 1);
    return negativeA ? -magnitude : magnitude;
}
function token(value) { return typeof value === "string" && /^[A-Za-z0-9_-]{1,128}$/.test(value); }
function absolutePath(value) { return typeof value === "string" && value.length > 0 && value[0] === "/" && value.indexOf("\u0000") === -1; }
function exactKeys(value, keys) {
    if (!object(value)) return false;
    const actual = Object.keys(value).filter(k => value[k] !== undefined).sort();
    return actual.join("\u0000") === keys.slice().sort().join("\u0000");
}

function request(path, generation, requestToken) {
    if (!absolutePath(path)) throw new Error("Folder path must be absolute");
    if (!integer(generation)) throw new Error("Invalid folder request generation");
    if (!token(requestToken)) throw new Error("Invalid folder request token");
    return {path: path, generation: generation, token: requestToken};
}

function accepts(expected, value) {
    return object(expected) && object(value) && integer(expected.generation) && token(expected.token)
        && value.version === 1 && value.generation === expected.generation && value.token === expected.token;
}

function message(status) {
    const messages = {
        "ok": "", "empty": "Folder is empty.", "missing": "Folder is no longer available.",
        "not-directory": "This location is not a folder.", "unreadable": "Folder cannot be read.",
        "timeout": "Folder scan timed out.", "cancelled": "Folder scan was cancelled.",
        "too-large": "Folder has too many items to inspect safely.",
        "changed": "Folder changed during the scan."
    };
    return Object.prototype.hasOwnProperty.call(messages, status) ? messages[status] : "Folder is unavailable.";
}

function icon(category, type) {
    const icons = {
        document: "text-x-generic-symbolic", folder: "folder-symbolic",
        link: "emblem-symbolic-link-symbolic", image: "image-x-generic-symbolic",
        audio: "audio-x-generic-symbolic", video: "video-x-generic-symbolic",
        archive: "package-x-generic-symbolic", code: "text-x-script-symbolic",
        other: "unknown-symbolic"
    };
    if (CATEGORIES.indexOf(category) !== -1) return icons[category];
    if (type === "directory") return icons.folder;
    if (type === "symlink") return icons.link;
    if (type === "file") return icons.document;
    return icons.other;
}

function safeLabel(name) {
    if (typeof name !== "string") return "Unnamed item";
    const visible = name.replace(/[\x00-\x1f\x7f-\x9f]/g, "�");
    return visible.length ? visible : "Unnamed item";
}

function expectedPath(base, name) {
    return base.endsWith("/") ? base + name : base + "/" + name;
}

function validRelativeTime(value) {
    return typeof value === "string" && value.length <= 40 && (value === "just now"
        || /^(?:0|[1-9][0-9]*) (?:second|minute|hour|day|month|year)s? ago$/.test(value));
}

function normalizedEntry(value, expected) {
    const keys = ["name", "path", "type", "size", "mtimeNs", "relativeTime", "iconCategory"];
    if (!exactKeys(value, keys) || typeof value.name !== "string" || value.name.length === 0
        || value.name.startsWith(".") || value.name.indexOf("/") !== -1 || value.name.indexOf("\u0000") !== -1
        || value.path !== expectedPath(expected.path, value.name)
        || TYPES.indexOf(value.type) === -1 || CATEGORIES.indexOf(value.iconCategory) === -1
        || !timestamp(value.mtimeNs) || !validRelativeTime(value.relativeTime)
        || (value.type === "file" ? !integer(value.size) : value.size !== null))
        throw new Error("Invalid folder entry metadata");
    return {name: value.name, label: safeLabel(value.name), path: value.path, type: value.type,
        size: value.size, mtimeNs: value.mtimeNs, relativeTime: value.relativeTime,
        iconCategory: value.iconCategory, icon: icon(value.iconCategory, value.type)};
}

function normalize(value, expected) {
    if (!accepts(expected, value)) throw new Error("Stale or invalid folder result");
    if (!absolutePath(expected.path) || STATUS.indexOf(value.status) === -1 || typeof value.complete !== "boolean"
        || !integer(value.inspected) || !Array.isArray(value.entries) || value.entries.length > 16)
        throw new Error("Invalid folder result");
    if (!exactKeys(value.receipt, ["generation", "token", "inspected", "complete"])
        || value.receipt.generation !== value.generation || value.receipt.token !== value.token
        || value.receipt.inspected !== value.inspected || value.receipt.complete !== value.complete)
        throw new Error("Invalid private folder receipt");

    const completedStatus = value.status === "ok" || value.status === "empty";
    if (value.complete !== completedStatus) throw new Error("Invalid folder completion state");
    if (completedStatus) {
        if (!exactKeys(value.rootIdentity, ["device", "inode"])
                || !decimal(value.rootIdentity.device) || !decimal(value.rootIdentity.inode))
            throw new Error("Invalid folder root identity");
        if (!integer(value.total) || !integer(value.omitted) || value.total < value.entries.length
            || value.omitted !== Math.max(0, value.total - 16)
            || value.entries.length !== Math.min(16, value.total)
            || value.status !== (value.total === 0 ? "empty" : "ok"))
            throw new Error("Inaccurate folder total");
    } else if (value.total !== undefined || value.omitted !== undefined || value.rootIdentity !== undefined
            || value.entries.length !== 0) {
        throw new Error("Incomplete scans cannot claim totals");
    }
    if (value.status === "too-large") {
        if (!integer(value.observedAtLeast) || value.observedAtLeast <= value.inspected)
            throw new Error("Invalid large-folder bound");
    } else if (value.observedAtLeast !== undefined) {
        throw new Error("Unexpected folder bound");
    }
    if (!completedStatus) {
        if (!exactKeys(value.error, ["code", "message"]) || value.error.code !== value.status
            || value.error.message !== message(value.status)) throw new Error("Invalid folder error");
    } else if (value.error !== undefined) {
        throw new Error("Unexpected folder error");
    }

    const entries = value.entries.map(entry => normalizedEntry(entry, expected));
    for (let i = 1; i < entries.length; ++i) {
        const previousTime = entries[i - 1].mtimeNs;
        const currentTime = entries[i].mtimeNs;
        if (compareTimestamps(previousTime, currentTime) < 0
            || (previousTime === currentTime && compareNames(entries[i - 1].name, entries[i].name) > 0))
            throw new Error("Folder entries are not newest-first");
    }
    const result = {status: value.status, complete: value.complete, inspected: value.inspected,
        entries: entries, message: message(value.status), receipt: Object.assign({}, value.receipt),
        remainingLabel: value.complete && value.omitted > 0 ? "+" + value.omitted
            : value.status === "too-large" ? "More items" : ""};
    if (value.complete) { result.total = value.total; result.omitted = value.omitted; }
    if (value.complete) result.rootIdentity = Object.assign({}, value.rootIdentity);
    if (value.status === "too-large") result.observedAtLeast = value.observedAtLeast;
    return result;
}

// Wire tie ordering is Unicode scalar order, matching Python str ordering.
function compareNames(left, right) {
    let i = 0;
    let j = 0;
    while (i < left.length && j < right.length) {
        const a = left.codePointAt(i);
        const b = right.codePointAt(j);
        if (a !== b) return a - b;
        i += a > 0xffff ? 2 : 1;
        j += b > 0xffff ? 2 : 1;
    }
    return (left.length - i) - (right.length - j);
}
