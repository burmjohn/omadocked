.pragma library

// Presentation only: intersect private rows with current stable app membership.
// Neither a title nor a cached count can establish a window's identity.
function members(app, rows) {
    if (!app || !app.running || app.canEdit || (app.kind && app.kind !== "application")
            || !Array.isArray(app.windows) || !Array.isArray(rows)) return [];
    const seen = new Set();
    return rows.filter(row => {
        if (!row || typeof row.key !== "string" || !row.key || seen.has(row.key)
                || app.windows.indexOf(row.key) < 0) return false;
        seen.add(row.key);
        return true;
    });
}
