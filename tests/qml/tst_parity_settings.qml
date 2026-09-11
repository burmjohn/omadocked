import QtQuick
import QtTest
import "../../core/ParitySettings.js" as Settings

TestCase {
    name: "ParitySettings"

    function parsed(text) {
        const result = Settings.parse(text);
        compare(result.error, "", text + ": " + result.error);
        return result.settings;
    }

    function roundTrip(text) {
        const first = parsed(text);
        return parsed(Settings.serialize(first));
    }

    function test_defaultsCoverPhaseThreePreferences() {
        const s = parsed("{}");
        compare(Settings.hideMode(s), "intelligent");
        compare(s.minimizeMode, "active");
        compare(s.showMinimizedTiles, true);
        compare(s.opacity, 1);
        compare(s.shape, "rounded");
        compare(s.bgColor, "theme");
        compare(s.iconSize, 0);
        compare(s.itemSpacing, 4);
        compare(s.hoverEffect, "zoom");
        for (const key of ["showAppsButton", "showTooltips", "advancedTooltips", "launchBounce",
                           "showUrgentHint", "urgentOnNotification", "urgentSound"])
            compare(s[key], true, key);
        compare(s.urgentSoundName, "bell");
        compare(s.folderColor, "theme");
        compare(s.revealDelay, 160);
        compare(s.tooltipDelay, 450);
        compare(s.screen, "");
        compare(s.pinnedFolders, [{path:"~/Downloads", name:"Downloads", icon:"folder-download"}]);
    }

    function test_hideModesRoundTrip_data() {
        return [
            {tag:"always", mode:"always", autohide:false, intelligent:false},
            {tag:"standard", mode:"standard", autohide:true, intelligent:false},
            {tag:"intelligent", mode:"intelligent", autohide:true, intelligent:true}
        ];
    }

    function test_hideModesRoundTrip(data) {
        const changed = Settings.withHideMode(parsed("{}"), data.mode);
        compare(changed.autohide, data.autohide);
        compare(changed.intelligentAutohide, data.intelligent);
        compare(Settings.hideMode(roundTrip(Settings.serialize(changed))), data.mode);
    }

    function test_enumeratedPreferencesRoundTrip_data() {
        const rows = [];
        function add(key, values) {
            for (const value of values) rows.push({tag:key + "-" + value, key:key, value:value});
        }
        add("minimizeMode", ["active", "all", "off"]);
        add("itemSpacing", [2, 4, 8]);
        add("hoverEffect", ["zoom", "wave", "off"]);
        add("urgentSoundName", ["bell", "message-new-instant", "complete", "dialog-information",
                                "dialog-warning", "phone-incoming-call", "alarm-clock-elapsed", "none"]);
        add("folderColor", ["theme", "symbolic", "white", "black", "Yaru-sage", "Yaru-olive",
                            "Yaru-blue", "Yaru-purple", "Yaru-magenta", "Yaru-red", "Yaru-yellow",
                            "Yaru-wartybrown", "Yaru-prussiangreen", "Yaru-dark"]);
        return rows;
    }

    function test_enumeratedPreferencesRoundTrip(data) {
        const patch = {};
        patch[data.key] = data.value;
        compare(roundTrip(JSON.stringify(patch))[data.key], data.value);
    }

    function test_booleanPreferencesRoundTrip_data() {
        const rows = [];
        const keys = ["showMinimizedTiles", "showAppsButton", "showTooltips", "advancedTooltips",
                      "launchBounce", "showUrgentHint", "urgentOnNotification", "urgentSound"];
        for (const key of keys)
            for (const value of [false, true]) rows.push({tag:key + "-" + value, key:key, value:value});
        return rows;
    }

    function test_booleanPreferencesRoundTrip(data) {
        const patch = {};
        patch[data.key] = data.value;
        compare(roundTrip(JSON.stringify(patch))[data.key], data.value);
    }

    function test_opacityAliasesClampAndRoundTrip_data() {
        return [
            {tag:"theme", value:"theme", expected:"theme"},
            {tag:"auto", value:"auto", expected:"theme"},
            {tag:"minus-one", value:-1, expected:"theme"},
            {tag:"zero", value:0, expected:0},
            {tag:"eighty-percent", value:0.8, expected:0.8},
            {tag:"sixty-five-percent", value:0.65, expected:0.65},
            {tag:"thirty-five-percent", value:0.35, expected:0.35},
            {tag:"one", value:1, expected:1},
            {tag:"low-clamp", value:-2, expected:0},
            {tag:"high-clamp", value:2, expected:1}
        ];
    }

    function test_opacityAliasesClampAndRoundTrip(data) {
        compare(roundTrip(JSON.stringify({opacity:data.value})).opacity, data.expected);
    }

    function test_shapeAliasesRoundTrip_data() {
        return [
            {tag:"rounded", value:"rounded", expected:"rounded"},
            {tag:"round", value:"round", expected:"round"},
            {tag:"pill", value:"pill", expected:"round"},
            {tag:"square", value:"square", expected:"square"},
            {tag:"theme", value:"theme", expected:"theme"},
            {tag:"auto", value:"auto", expected:"theme"}
        ];
    }

    function test_shapeAliasesRoundTrip(data) {
        compare(roundTrip(JSON.stringify({shape:data.value})).shape, data.expected);
    }

    function test_backgroundChoicesAndHexRoundTrip_data() {
        const values = ["theme", "none", "#000000", "#181825", "#1e1e2e", "#0f172a", "#111827",
                        "#062e24", "#1c1917", "#2c0b16", "#1e102d", "#334155", "#AbC", "#1234abcd"];
        return values.map(function(value) { return {tag:value, value:value}; });
    }

    function test_backgroundChoicesAndHexRoundTrip(data) {
        compare(roundTrip(JSON.stringify({bgColor:data.value})).bgColor, data.value);
    }

    function test_iconAutoAndEveryCurrentSupportedSizeRoundTrip_data() {
        const rows = [{tag:"auto-string", value:"auto", expected:0}, {tag:"auto-zero", value:0, expected:0}];
        for (let size = 28; size <= 72; ++size) rows.push({tag:"size-" + size, value:size, expected:size});
        return rows;
    }

    function test_iconAutoAndEveryCurrentSupportedSizeRoundTrip(data) {
        compare(roundTrip(JSON.stringify({iconSize:data.value})).iconSize, data.expected);
    }

    function test_delaysRoundClampAndRoundTrip_data() {
        return [
            {tag:"reveal-low", key:"revealDelay", value:-1, expected:0},
            {tag:"reveal-zero", key:"revealDelay", value:0, expected:0},
            {tag:"reveal-round", key:"revealDelay", value:160.6, expected:161},
            {tag:"reveal-max", key:"revealDelay", value:2000, expected:2000},
            {tag:"reveal-high", key:"revealDelay", value:2001, expected:2000},
            {tag:"tooltip-low", key:"tooltipDelay", value:-1, expected:0},
            {tag:"tooltip-zero", key:"tooltipDelay", value:0, expected:0},
            {tag:"tooltip-round", key:"tooltipDelay", value:450.4, expected:450},
            {tag:"tooltip-max", key:"tooltipDelay", value:5000, expected:5000},
            {tag:"tooltip-high", key:"tooltipDelay", value:5001, expected:5000}
        ];
    }

    function test_delaysRoundClampAndRoundTrip(data) {
        const patch = {};
        patch[data.key] = data.value;
        compare(roundTrip(JSON.stringify(patch))[data.key], data.expected);
    }

    function test_screenCanBeSetAndExplicitlyCleared() {
        compare(roundTrip('{"screen":"DP-1"}').screen, "DP-1");
        const cleared = parsed('{"screen":""}');
        compare(cleared.screen, "");
        const saved = JSON.parse(Settings.serialize(cleared));
        verify(!Object.prototype.hasOwnProperty.call(saved, "screen"));
    }

    function test_absentPinnedFoldersDefaultsButExplicitEmptyStaysEmpty() {
        compare(parsed("{}").pinnedFolders.length, 1);
        compare(roundTrip('{"pinnedFolders":[]}').pinnedFolders, []);
        const folders = [{path:"/tmp/fixture folder", name:"Fixture", icon:"folder-test", marker:{safe:true}}];
        compare(roundTrip(JSON.stringify({pinnedFolders:folders})).pinnedFolders, folders);
    }

    function test_unknownKeysSurviveCanonicalRoundTrip() {
        const fixture = {futureSetting:{enabled:true, values:[1, "two"]}, opacity:"auto"};
        const saved = JSON.parse(Settings.serialize(parsed(JSON.stringify(fixture))));
        compare(saved.futureSetting, fixture.futureSetting);
        compare(saved.opacity, "theme");
    }

    function test_malformedKnownTypesAreRejected_data() {
        return [
            {tag:"root-array", text:"[]"},
            {tag:"autohide", text:'{"autohide":"true"}'},
            {tag:"tiles", text:'{"showMinimizedTiles":1}'},
            {tag:"opacity", text:'{"opacity":null}'},
            {tag:"shape", text:'{"shape":"oval"}'},
            {tag:"background", text:'{"bgColor":"red"}'},
            {tag:"icon", text:'{"iconSize":27}'},
            {tag:"spacing", text:'{"itemSpacing":3}'},
            {tag:"hover", text:'{"hoverEffect":true}'},
            {tag:"sound", text:'{"urgentSoundName":"arbitrary"}'},
            {tag:"folder-color", text:'{"folderColor":"orange"}'},
            {tag:"delay", text:'{"revealDelay":"160"}'},
            {tag:"screen", text:'{"screen":1}'},
            {tag:"folders", text:'{"pinnedFolders":{}}'},
            {tag:"folder-record", text:'{"pinnedFolders":[{"path":1,"name":"x","icon":"x"}]}' }
        ];
    }

    function test_malformedKnownTypesAreRejected(data) {
        verify(Settings.parse(data.text).error.length > 0, data.text);
    }

    function test_prototypePollutionKeysAreRejectedAtEveryDepth_data() {
        return [
            {tag:"proto", text:'{"__proto__":{"polluted":true}}'},
            {tag:"constructor", text:'{"future":{"constructor":{"prototype":{"polluted":true}}}}'},
            {tag:"prototype", text:'{"pinnedFolders":[{"path":"/tmp/x","name":"x","icon":"x","prototype":{}}]}' }
        ];
    }

    function test_prototypePollutionKeysAreRejectedAtEveryDepth(data) {
        verify(Settings.parse(data.text).error.length > 0);
        compare(({}).polluted, undefined);
    }

    function test_pinnedFolderFieldsMustBeOwnDespitePollutedObjectPrototype() {
        Object.prototype.path = "/inherited";
        Object.prototype.name = "Inherited";
        Object.prototype.icon = "folder";
        let rejected = false;
        try { Settings.serialize({pinnedFolders: [{}]}); } catch (_) { rejected = true; }
        delete Object.prototype.path;
        delete Object.prototype.name;
        delete Object.prototype.icon;
        verify(rejected);
    }

    function test_objectInputsRejectCyclesDepthNodeAndByteOverflow() {
        const cyclic = {};
        cyclic.self = cyclic;
        let deep = {};
        let cursor = deep;
        for (let i = 0; i < 40; ++i) { cursor.next = {}; cursor = cursor.next; }
        const wide = {};
        for (let i = 0; i < 5000; ++i) wide["k" + i] = i;
        const cases = [cyclic, deep, wide, {future: "x".repeat(70000)}];
        cases.forEach(function(value) {
            let rejected = false;
            try { Settings.serialize(value); } catch (_) { rejected = true; }
            verify(rejected);
        });
        verify(Settings.parse(JSON.stringify({future: "x".repeat(70000)})).error.length > 0);
    }

    function test_nonJsonPollutedPrototypeIsRejectedBeforeSerialization() {
        const polluted = {};
        polluted.__proto__ = {injected:true};
        let rejected = false;
        try { Settings.serialize(polluted); } catch (_) { rejected = true; }
        verify(rejected);
        compare(({}).injected, undefined);
    }
}
