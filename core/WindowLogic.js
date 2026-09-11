.pragma library

function cycleKey(rows, delta) {
    if ((delta !== 1 && delta !== -1) || !rows.length) return "";
    const active = rows.findIndex(w => w.active);
    if (active === -1) return rows[delta === 1 ? 0 : rows.length - 1].key;
    return rows[(active + delta + rows.length) % rows.length].key;
}

// View-only metadata. Membership comes from Apps.build, never from titles.
function groups(apps, windows, parked) {
    const result = Object.create(null);
    const byKey = new Map(windows.map(w => [w.key, w]));
    const parkedByKey = new Map((parked || []).map(r => [r.key, r]));
    apps.filter(app => !app.canEdit && app.kind === "application").sort((a, b) => a.id < b.id ? -1 : a.id > b.id ? 1 : 0).forEach(app => {
        result[app.id] = app.windows.map(key => {
            const w = byKey.get(key);
            const record = parkedByKey.get(key);
            const row = {key: key, title: typeof w.title === "string" && w.title.trim() ? w.title : app.name || "Untitled window",
                active: !!w.active && !(record && record.state === "parked")};
            if (record) {
                row.parkingState = record.state;
                row.parked = record.state === "parked";
                row.sequence = record.sequence;
            }
            return row;
        });
    });
    return result;
}
