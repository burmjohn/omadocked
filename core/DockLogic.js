.pragma library

// Compositor pixel quantization can change a centered layer's size by one.
// Still reject unmapped or stale dock-sized geometry before taking popup focus.
function nativeSizeMatches(width, height, desiredWidth, desiredHeight) {
    return width > 0 && height > 0 && desiredWidth > 0 && desiredHeight > 0
        && Math.abs(width - Math.round(desiredWidth)) <= 1
        && Math.abs(height - Math.round(desiredHeight)) <= 1;
}

// Pointer coordinates and centers always refer to the unmagnified slot grid.
function visibilityPolicy(state, autoHide, pointerInside, locked) {
    if (locked) return "interacting";
    if (!autoHide || pointerInside) return "shown";
    return state === "hidden" || state === "revealing" ? state : "hiding";
}

function monitorPolicy(mode, namesJson) {
    if (mode !== "all" && mode !== "selected") return null;
    let names;
    try { names = JSON.parse(namesJson); } catch (_) { return null; }
    if (!Array.isArray(names)) return null;
    const unique = [];
    for (const name of names) {
        if (typeof name !== "string" || !name.trim()) return null;
        if (unique.indexOf(name) < 0) unique.push(name);
    }
    if (mode === "selected" && !unique.length) return null;
    return {mode: mode, names: mode === "all" ? [] : unique};
}

function initialMonitorPolicy(raw) {
    if (!raw || raw === "all") return {mode: "all", names: []};
    return monitorPolicy("selected", JSON.stringify(raw.split(","))) || {
        mode: "selected", names: [],
        error: "Invalid OMADOCKED_SCREENS: use 'all' or comma-separated nonempty connector names."
    };
}

function claimKeyboard(surfaces, owner) {
    for (const surface of surfaces)
        if (surface !== owner) surface.releaseInteractions();
}

function activeOutputs(names, mode, selected) {
    return names.filter(function(name) { return mode === "all" || selected.indexOf(name) >= 0; });
}

function resolveOutput(names, requested, previous) {
    if (!names.length) return {name: "", fallback: true, reason: "no-outputs"};
    if (requested && names.indexOf(requested) >= 0)
        return {name: requested, fallback: false, reason: "selected"};
    const name = names.indexOf(previous) >= 0 ? previous : names[0];
    return {name: name, fallback: true, reason: requested ? "requested-output-unavailable" : "first-available"};
}

function insertOrder(order, from, boundary) {
    const result = order.slice();
    const item = result.splice(from, 1)[0];
    result.splice(boundary > from ? boundary - 1 : boundary, 0, item);
    return result;
}

function layout(scales, center, size, gap) {
    let total = Math.max(0, scales.length - 1) * gap;
    for (let i = 0; i < scales.length; ++i) total += scales[i] * size;
    let left = center - total / 2;
    const slots = [];
    for (let j = 0; j < scales.length; ++j) {
        const width = scales[j] * size;
        slots.push({left: left, right: left + width, center: left + width / 2, scale: scales[j]});
        left += width + gap;
    }
    return slots;
}

function scaleAt(index, pointer, origin, slot, mode, reduced, frozen, peak, radius) {
    if (peak === undefined) peak = 1.45;
    if (radius === undefined) radius = 2.5;
    if (reduced || frozen || mode === "off" || pointer < 0)
        return 1;
    const distance = Math.abs(pointer - (origin + (index + 0.5) * slot));
    if (mode === "zoom")
        return distance < slot / 2 ? peak : 1;
    const t = Math.min(1, distance / (slot * radius));
    return 1 + (peak - 1) * (1 + Math.cos(Math.PI * t)) / 2;
}

function resolveIconSize(stored, scale) {
    if (stored === 0) {
        const factor = typeof scale === "number" && isFinite(scale) && scale > 0 ? scale : 1;
        return Math.max(28, Math.min(72, Math.round(44 * factor)));
    }
    return stored;
}

function itemOrder(apps, showAppsButton) {
    const ids = [];
    const list = apps || [];
    for (let i = 0; i < list.length; ++i) {
        const id = typeof list[i] === "string" ? list[i] : (list[i] && list[i].id);
        if (id && id !== "menu" && ids.indexOf(id) < 0) ids.push(id);
    }
    return showAppsButton === false ? ids : ["menu"].concat(ids);
}
