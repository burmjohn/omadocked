.pragma library

// Identifiers are exact tokens, never trimmed, case-folded or suffix-repaired.
function validId(id) {
    return typeof id === "string" && id.length > 0 && id.length <= 512
        && id === id.trim() && id !== "." && id !== ".."
        && !/[\/\\;\x00-\x1f\x7f]/.test(id);
}

// Settings reserves an app ID, not a desktop-entry action ID.
function validAppId(id) {
    return validId(id) && id !== "menu";
}

function metadata(actions, requireExec) {
    if (!actions || typeof actions.length !== "number") return [];
    const counts = Object.create(null), rows = [];
    for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        if (action && validId(action.id)) counts[action.id] = (counts[action.id] || 0) + 1;
    }
    for (let i = 0; i < actions.length; i++) {
        const action = actions[i];
        if (!action || !validId(action.id) || counts[action.id] !== 1) continue;
        if (requireExec && (typeof action.execString !== "string" || !action.execString.trim())) continue;
        const name = typeof action.name === "string" && action.name.trim()
            && !/[\x00-\x1f\x7f]/.test(action.name) ? action.name : action.id;
        rows.push({id: action.id, name: name});
    }
    return rows;
}
