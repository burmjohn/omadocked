.pragma library
.import "LauncherLogic.js" as Launchers
.import "FolderLogic.js" as Folders
.import "../core/ParitySettings.js" as Parity

function defaults() {
    return {version: 2, pins: [], launchers: [], settings: {iconSize: 44, transparency: 0, shape: "rounded", itemSpacing: 4,
        backgroundColor: "theme", themeOpacity: false, zoomSize: 145, waveWidth: 25,
        motionMode: "wave", reducedMotion: false, showAppNames: true, advancedTooltips: false, launchBounce: true, tooltipDelay:450, revealDelay:160, autoHide: true, intelligentHide: false, minimizeMode: "active",
        reserveSpace: false, followActiveOutput: false, monitorMode: "all", selectedOutputs: [], folderColor: "theme",
        previewsEnabled: true, livePreviews: false, showUrgentHint:true, urgentOnNotification:true,
        urgentSound:false, urgentSoundName:"bell", showAppsButton: true}, overrides: {}};
}
function object(v) { return !!v && typeof v === "object" && !Array.isArray(v); }
function validAppId(v) { return typeof v === "string" && v.length > 0 && v.length <= 512 && !/[\x00-\x1f]/.test(v); }
function settings(patch, base) {
    if (!object(patch)) throw new Error("Invalid settings");
    const s = Object.assign({}, base || defaults().settings);
    Object.keys(patch).forEach(k => {
        const v = patch[k];
        let valid = false;
        if (k === "iconSize") valid = Number.isInteger(v) && (v === 0 || (v >= 28 && v <= 72));
        else if (k === "zoomSize") valid = Number.isInteger(v) && v >= 100 && v <= 200;
        else if (k === "waveWidth") valid = Number.isInteger(v) && v >= 10 && v <= 50 && v % 5 === 0;
        else if (k === "transparency") valid = Number.isInteger(v) && v >= 0 && v <= 100;
        else if (k === "tooltipDelay") valid = Number.isInteger(v) && v >= 0 && v <= 5000;
        else if (k === "revealDelay") valid = Number.isInteger(v) && v >= 0 && v <= 2000;
        else if (k === "shape") valid = ["rounded", "round", "square", "theme"].indexOf(v) !== -1;
        else if (k === "itemSpacing") valid = [2, 4, 8].indexOf(v) !== -1;
        else if (k === "backgroundColor") valid = typeof v === "string" && (v === "theme" || v === "none" || /^#[0-9a-fA-F]{6}$/.test(v));
        else if (k === "themeOpacity") valid = typeof v === "boolean";
        else if (k === "motionMode") valid = ["wave", "zoom", "off"].indexOf(v) !== -1;
        else if (k === "minimizeMode") valid = ["active", "all", "off"].indexOf(v) !== -1;
        else if (k === "folderColor") valid = Folders.colors.indexOf(v) !== -1;
        else if (k === "urgentSoundName") valid = Parity.soundNames.indexOf(v) >= 0;
        else if (["followActiveOutput", "reserveSpace", "showAppNames", "advancedTooltips", "launchBounce", "reducedMotion", "autoHide", "intelligentHide", "previewsEnabled", "livePreviews", "showUrgentHint", "urgentOnNotification", "urgentSound", "showAppsButton"].indexOf(k) >= 0) valid = typeof v === "boolean";
        else if (k === "monitorMode") valid = ["all", "selected"].indexOf(v) !== -1;
        else if (k === "selectedOutputs") valid = Array.isArray(v) && v.length <= 64 && v.every((n, i) =>
            typeof n === "string" && n.trim().length > 0 && n.length <= 256 && !/[\x00-\x1f]/.test(n) && v.indexOf(n) === i);
        if (!valid) throw new Error("Invalid setting: " + k);
        s[k] = v;
    });
    if (s.monitorMode === "selected" && !s.selectedOutputs.length) throw new Error("Selected monitor mode requires at least one output name");
    return s;
}
function parse(text) {
    try {
        const c = JSON.parse(text);
        if (!c || (c.version !== 1 && c.version !== 2)) throw new Error("Unsupported configuration version");
        const fields = c.version === 1 ? ["version", "pins"] : ["version", "pins", "launchers", "settings", "overrides"];
        if (Object.keys(c).some(k => fields.indexOf(k) === -1)) throw new Error("Unsupported configuration field");
        if (!Array.isArray(c.pins) || c.pins.length > 256 || c.pins.some((id, i) =>
            typeof id !== "string" || !id || id.length > 512 || id === "menu" || id === "." || id === ".." || id.startsWith("launcher:")
            || /[\/\\\x00-\x1f]/.test(id) || c.pins.indexOf(id) !== i)) throw new Error("Invalid pins list");
        const result = defaults();
        result.pins = c.pins;
        if (c.version === 2) {
            if (!Array.isArray(c.launchers) || c.launchers.length > 256 || !object(c.overrides)
                || Object.keys(c.overrides).length > 256) throw new Error("Invalid launcher/override configuration");
            const overrides = Object.create(null);
            Object.keys(c.overrides).forEach(k => {
                if (!validAppId(k) || !Launchers.validDesktopId(c.overrides[k])) throw new Error("Invalid application override");
                overrides[k] = c.overrides[k];
            });
            result.overrides = overrides;
            result.launchers = c.launchers.map(Launchers.normalize);
            const ids = result.launchers.map(r => r.id);
            if (ids.some((id, i) => ids.indexOf(id) !== i)) throw new Error("Duplicate launcher ID");
            result.settings = settings(c.settings);
        }
        return {config: result, error: ""};
    } catch (e) { return {config: defaults(), error: "Configuration is read-only: " + e.message}; }
}
