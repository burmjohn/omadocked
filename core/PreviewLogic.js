.pragma library

function age(row) {
    return typeof row.parkedAt === "number" && isFinite(row.parkedAt) ? row.parkedAt : Number.MAX_SAFE_INTEGER;
}

function ordered(rows) {
    return rows.map((row, index) => ({row: row, index: index})).sort((a, b) => {
        const byAge = age(a.row) - age(b.row);
        return byAge || a.index - b.index;
    }).map(entry => entry.row);
}

function sanitizeTitle(title) {
    if (typeof title !== "string") return "Untitled window";
    const clean = title.replace(/[\x00-\x1f\x7f-\x9f]/g, " ").replace(/\s+/g, " ").trim().slice(0, 160);
    return clean || "Untitled window";
}

function validRows(rows) {
    if (!Array.isArray(rows) || rows.length > 512) return false;
    const seen = Object.create(null);
    for (let i = 0; i < rows.length; ++i) {
        const row = rows[i];
        if (!row || typeof row !== "object" || Array.isArray(row)
                || typeof row.key !== "string" || !row.key.length || row.key.length > 512
                || /[\x00-\x1f\x7f]/.test(row.key)
                || typeof row.appId !== "string" || row.appId.length > 512
                || /[\x00-\x1f\x7f]/.test(row.appId)
                || typeof row.title !== "string" || row.title.length > 4096
                || typeof row.parkedAt !== "number" || !Number.isFinite(row.parkedAt)
                || Object.prototype.hasOwnProperty.call(seen, row.key)) return false;
        seen[row.key] = true;
    }
    return true;
}

function cardFromMembers(mode, members) {
    const titles = members.slice(0, 6).map(row => sanitizeTitle(row.title));
    const remaining = Math.max(0, members.length - titles.length);
    return {
        identitySignature: JSON.stringify([mode, members.map(row => String(row.key)).sort()]),
        representativeKey: members[0].key,
        memberKeys: members.map(row => row.key),
        count: members.length,
        titles: titles,
        remainingTitleCount: remaining,
        titleSummary: titles.concat(remaining ? ["+" + remaining] : []).join("\n")
    };
}

function buildCards(mode, rows) {
    if (!validRows(rows)) return [];
    const sorted = ordered(rows);
    if (mode === "active") return sorted.map(row => cardFromMembers(mode, [row]));
    if (mode !== "all") return [];
    const groups = Object.create(null);
    sorted.forEach(row => {
        const groupKey = typeof row.appId === "string" && row.appId.length ? "app:" + row.appId : "window:" + row.key;
        if (!groups[groupKey]) groups[groupKey] = [];
        groups[groupKey].push(row);
    });
    return Object.keys(groups).map(key => groups[key]).sort((a, b) => age(a[0]) - age(b[0])).map(members => cardFromMembers(mode, members));
}

function newCapture(identitySignature, options) {
    if (typeof identitySignature !== "string" || !identitySignature.length || identitySignature.length > 300000
            || !options || typeof options.captureToken !== "string" || !options.captureToken.length
            || options.captureToken.length > 512 || !Number.isSafeInteger(options.generation)
            || options.generation < 0)
        throw new Error("Invalid capture identity");
    const requested = options && Number.isInteger(options.maxAttempts) ? options.maxAttempts : 6;
    const maxAttempts = Math.max(1, Math.min(6, requested));
    return {
        identitySignature: String(identitySignature),
        captureToken: options.captureToken,
        generation: options.generation,
        readiness: "pre-park",
        attempts: 0,
        maxAttempts: maxAttempts,
        captureRequested: true,
        canPark: false,
        hasStill: false,
        fallback: false,
        terminal: false,
        allowLive: !!(options && options.allowLive),
        popupVisible: false,
        live: false,
        sourceAttached: true,
        ownerVisible: true,
        lockState: "unlocked",
        tornDown: false
    };
}

function captureEventMatches(state, event) {
    return event.captureToken === state.captureToken
        && event.identitySignature === state.identitySignature
        && event.generation === state.generation;
}

function reduceCapture(state, event) {
    if (!state || !event) return state;
    const boundEvent = event.type === "capture-ready" || event.type === "capture-failed"
        || event.type === "capture-stopped" || event.type === "source-removed" || event.type === "destroy";
    if (boundEvent && !captureEventMatches(state, event)) return state;
    const unsafe = event.type === "source-removed" || event.type === "destroy"
        || (event.type === "owner-visible" && event.visible !== true)
        || (event.type === "lock-state" && event.state !== "unlocked");
    if (unsafe) return Object.assign({}, state, {
        readiness: state.hasStill ? "ready" : "fallback",
        captureRequested: false,
        canPark: true,
        fallback: !state.hasStill,
        terminal: true,
        popupVisible: false,
        live: false,
        sourceAttached: false,
        ownerVisible: event.type === "owner-visible" ? false : state.ownerVisible,
        lockState: event.type === "lock-state" ? event.state : state.lockState,
        tornDown: true
    });
    if (state.terminal || state.tornDown) return state;
    if (event.type === "lock-state") return Object.assign({}, state, {lockState: "unlocked"});
    if (event.type === "owner-visible") return Object.assign({}, state, {ownerVisible: true});
    if (event.type === "capture-ready" && state.captureRequested) return Object.assign({}, state, {
        readiness: "ready", attempts: state.attempts + 1, captureRequested: false, canPark: true, hasStill: true,
        fallback: false, live: false
    });
    if (event.type === "popup-visible") {
        const popupVisible = event.visible === true;
        return Object.assign({}, state, {
            popupVisible: popupVisible,
            live: popupVisible && state.allowLive && state.hasStill && state.ownerVisible
                && state.lockState === "unlocked" && state.sourceAttached
        });
    }
    if ((event.type === "capture-failed" || event.type === "capture-stopped") && state.captureRequested) {
        const next = Object.assign({}, state, {attempts: state.attempts + 1});
        if (next.attempts >= next.maxAttempts) return Object.assign(next, {
            readiness: "fallback", captureRequested: false, canPark: true,
            fallback: true, terminal: true, live: false
        });
        return next;
    }
    return state;
}
