.pragma library

function matched(handle, waylandRows, hyprlandRows) {
    // ObjectModel.values is a native QObjectList. Qt sequences implement the
    // array methods but fail Array.isArray; do not reject an exact native match.
    if (!handle || !waylandRows || typeof waylandRows.indexOf !== "function"
        || waylandRows.indexOf(handle) === -1 || !hyprlandRows || typeof hyprlandRows.filter !== "function") return null;
    const matches = hyprlandRows.filter(top => top && top.wayland === handle && typeof top.address === "string" && /^[0-9a-fA-F]+$/.test(top.address));
    if (matches.length !== 1) return null;
    return matches[0];
}

function identity(handle, waylandRows, hyprlandRows) {
    const top = matched(handle, waylandRows, hyprlandRows);
    if (!top) return null;
    const ipc = top.lastIpcObject;
    const address = String(ipc && ipc.address || "");
    if (!ipc || !/^0x[0-9a-fA-F]+$/.test(address) || address.slice(2).toLowerCase() !== top.address.toLowerCase()
        || !Number.isInteger(ipc.pid) || ipc.pid <= 0
        || typeof ipc.class !== "string" || !ipc.class || typeof ipc.initialClass !== "string" || !ipc.initialClass
        || typeof ipc.xwayland !== "boolean") return null;
    const result = {address:address, pid:ipc.pid, class:ipc.class, initialClass:ipc.initialClass, xwayland:ipc.xwayland};
    // Never synthesize a generation from address/PID. Older compositors are
    // correlated for display only; the helper refuses mutation without this ID.
    if (typeof ipc.stableId === "string" && /^[0-9a-f]{1,16}$/.test(ipc.stableId)) result.stableId = ipc.stableId;
    return result;
}

function recordAfterRefresh(handle, waylandRows, hyprlandRows, refresh) {
    const current = correlate(handle, waylandRows, hyprlandRows);
    if (current) return current;
    if (typeof refresh === "function") refresh();
    return correlate(handle, waylandRows, hyprlandRows);
}

function correlate(handle, waylandRows, hyprlandRows) {
    const top = matched(handle, waylandRows, hyprlandRows);
    const exactIdentity = identity(handle, waylandRows, hyprlandRows);
    if (!top || !exactIdentity) return null;
    const ipc = top.lastIpcObject;
    if (!ipc.workspace || typeof ipc.workspace.name !== "string"
        || !ipc.workspace.name || ipc.workspace.name.startsWith("special:") || !Number.isInteger(ipc.monitor)
        || typeof ipc.floating !== "boolean" || !ipc.at || typeof ipc.at.every !== "function" || ipc.at.length !== 2
        || !ipc.at.every(Number.isInteger) || !ipc.size || typeof ipc.size.every !== "function" || ipc.size.length !== 2
        || !ipc.size.every(v => Number.isInteger(v) && v >= 0)) return null;
    return {
        identity: exactIdentity,
        origin: {workspace:ipc.workspace.name, monitor:ipc.monitor, floating:ipc.floating,
            at:ipc.at.slice(), size:ipc.size.slice()}
    };
}
