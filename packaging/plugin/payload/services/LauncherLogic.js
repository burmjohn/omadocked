.pragma library

function localPath(url) {
    if (!url.startsWith("file:///")) throw new Error("Helper URL must be local");
    return decodeURIComponent(url.slice(7));
}

function uuid() {
    return "launcher:" + "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => {
        const r = Math.floor(Math.random() * 16);
        return (c === "x" ? r : (r & 3) | 8).toString(16);
    });
}
function validDesktopId(id) {
    return typeof id === "string" && id.length > 0 && id.length <= 512 && id !== "menu"
        && id !== "." && id !== ".." && !/[\/\\\x00-\x1f]/.test(id);
}
function normalize(record) {
    if (!record || typeof record !== "object" || Array.isArray(record)) throw new Error("Invalid launcher record");
    const r = {id: "", kind: "", name: "", icon: "", desktopId: "", program: "", args: [],
        workingDirectory: "", terminal: false, target: "", action: "", enabled: false};
    Object.keys(record).forEach(k => {
        if (!Object.prototype.hasOwnProperty.call(r, k)) throw new Error("Unsupported launcher field: " + k);
        r[k] = record[k];
    });
    for (const k of ["id", "kind", "name", "icon", "desktopId", "program", "workingDirectory", "target", "action"])
        if (typeof r[k] !== "string" || r[k].length > 8192 || /[\x00-\x1f]/.test(r[k])) throw new Error("Invalid launcher " + k);
    if (!/^launcher:[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(r.id)) throw new Error("Invalid launcher ID");
    if (["application", "command", "link", "file", "folder", "action", "separator"].indexOf(r.kind) === -1) throw new Error("Invalid launcher kind");
    if (!r.name && r.kind !== "separator") throw new Error("Launcher name is required");
    if (typeof r.terminal !== "boolean" || typeof r.enabled !== "boolean") throw new Error("Invalid launcher flags");
    if (!Array.isArray(r.args) || r.args.length > 256 || r.args.some(a => typeof a !== "string" || a.length > 32768 || a.indexOf("\u0000") !== -1)) throw new Error("Invalid argument vector");
    if (r.workingDirectory && !r.workingDirectory.startsWith("/")) throw new Error("Working directory must be absolute");
    if (r.kind === "command" && (!r.program || (r.program.indexOf("/") !== -1 && !r.program.startsWith("/")))) throw new Error("Program must be an executable name or absolute path");
    if (r.kind === "application" && !validDesktopId(r.desktopId)) throw new Error("Invalid desktop entry ID");
    if (r.kind === "link" && !/^https?:\/\/[^\s\/]+(?:[\/?#][^\s]*)?$/i.test(r.target)) throw new Error("Only absolute HTTP/HTTPS URLs are supported");
    if ((r.kind === "file" || r.kind === "folder") && !r.target.startsWith("/")) throw new Error("Target path must be absolute");
    if (r.kind === "action" && ["quick-menu", "keybindings"].indexOf(r.action) === -1) throw new Error("Unsupported Omarchy action");
    return r;
}
function item(r) {
    return {id: r.id, name: r.name || "Separator", icon: r.icon, kind: r.kind,
        canEdit: true, canDuplicate: true, canRemove: true, canNewInstance: false,
        running: false, active: false, pinned: true, canPin: false, windowCount: 0,
        pending: false, windows: [], enabled: r.enabled, pinReason: "Custom launcher"};
}
