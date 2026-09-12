import QtQuick
import QtTest
import "../../core/AppLogic.js" as Apps
import "../../services/LauncherLogic.js" as Launchers
import "../../services/ConfigLogic.js" as Config

TestCase {
    name: "Apps"
    function test_helperFileUrlDecodesOnce() {
        compare(Launchers.localPath("file:///tmp/a%20b%23%25/launch_app.py"), "/tmp/a b#%/launch_app.py");
        compare(Launchers.localPath("file:///tmp/%2520/launch_app.py"), "/tmp/%20/launch_app.py");
    }
    function test_configurationDoesNotDiscardUnknownFieldsOrMergeNamespaces() {
        const config = Config.defaults();
        config.imported = true;
        verify(Config.parse(JSON.stringify(config)).error.length > 0);
        verify(Config.parse('{"version":1,"pins":[],"launchers":[]}').error.length > 0);
        delete config.imported;
        config.pins = ["launcher:12345678-1234-4123-8123-123456789abc"];
        verify(Config.parse(JSON.stringify(config)).error.length > 0);
    }
    function test_typedSettingsRejectFractionalAndUnusableOutputSelection() {
        for (const patch of [{iconSize:44.5}, {transparency:0.5}, {monitorMode:"selected"},
                             {selectedOutputs:["   "]}, {selectedOutputs:["\t"]}]) {
            const config = Config.defaults();
            config.settings = Object.assign({}, config.settings, patch);
            verify(Config.parse(JSON.stringify(config)).error.length > 0, JSON.stringify(patch));
        }
        const config = Config.defaults();
        config.settings.monitorMode = "selected";
        config.settings.selectedOutputs = ["fixture-A"];
        compare(Config.parse(JSON.stringify(config)).error, "");
    }
    function test_minimizeModeIsTypedAndDefaultsToActive() {
        compare(Config.defaults().settings.minimizeMode, "active");
        for (const mode of ["active", "all", "off"]) {
            const config = Config.defaults();
            config.settings.minimizeMode = mode;
            const parsed = Config.parse(JSON.stringify(config));
            compare(parsed.error, "", mode);
            compare(parsed.config.settings.minimizeMode, mode);
        }
        for (const mode of ["ACTIVE", "", "minimized", true, 1, null]) {
            const config = Config.defaults();
            config.settings.minimizeMode = mode;
            verify(Config.parse(JSON.stringify(config)).error.length > 0, JSON.stringify(mode));
        }
    }
    function test_launcherRecordsValidateWithoutExecution() {
        const valid = [{kind:"application", desktopId:"one"}, {kind:"command", program:"echo", args:["", "a b", "$(bad)"]},
            {kind:"link", target:"https://example.com/a%20b"}, {kind:"file", target:"/tmp/a #.txt"},
            {kind:"folder", target:"/tmp"}, {kind:"action", action:"quick-menu"}, {kind:"action", action:"keybindings"}, {kind:"separator"}];
        valid.forEach(r => compare(Launchers.normalize(Object.assign({id:"launcher:12345678-1234-4123-8123-123456789abc", name:"Fixture"}, r)).kind, r.kind));
        const bad = [{kind:"link", target:"javascript:alert(1)"}, {kind:"link", target:"file:///tmp/x"},
            {kind:"file", target:"relative"}, {kind:"folder", target:"~/tmp"}, {kind:"action", action:"arbitrary"},
            {kind:"application", desktopId:"../bad"}, {kind:"command", program:"x", args:[1]},
            {kind:"command", program:"x", args:["a\u0000b"]}, {kind:"command", program:"x", terminal:"true"}];
        bad.forEach(r => {
            let failed = false;
            try { Launchers.normalize(Object.assign({id:"launcher:12345678-1234-4123-8123-123456789abc", name:"Fixture"}, r)); }
            catch (e) { failed = true; }
            verify(failed, JSON.stringify(r));
        });
    }
    function test_identity_precedence_and_ambiguous_classes() {
        const entries = [{id: "app", startupClass: "shared"}, {id: "app.desktop", startupClass: "shared"}];
        compare(Apps.match(entries, "app.desktop").id, "app.desktop");
        compare(Apps.match(entries, "shared"), null);
        compare(Apps.match(entries, "APP"), null);
    }
    function test_duplicateExactAndSuffixedIdsRemainUnmatched() {
        const entries = [{id: "duplicate", name: "First"}, {id: "duplicate", name: "Second"}];
        compare(Apps.match(entries, "duplicate"), null);
        compare(Apps.match(entries, "duplicate.desktop"), null);
        const items = Apps.build(entries, [{key: "w", appId: "duplicate"}], [], []);
        compare(items.length, 1);
        compare(items[0].id, "window:duplicate");
        verify(!items[0].canPin);
    }
    function test_overridePrecedesExactForXwaylandElectronAndPwa() {
        const entries = [{id:"electron", startupClass:"Electron"}, {id:"pwa", startupClass:"chrome-site-Default"},
            {id:"x11", startupClass:"Shared"}, {id:"other", startupClass:"Shared"}, {id:"__proto__"}];
        compare(Apps.match(entries, "electron", {electron:"pwa"}).id, "pwa");
        compare(Apps.match(entries, "Shared"), null);
        compare(Apps.match(entries, "Shared", {Shared:"x11"}).id, "x11");
        compare(Apps.match(entries, "Electron").id, "electron");
        compare(Apps.match(entries, "chrome-site-Profile-2"), null);
        compare(Apps.match(entries, "Electron", {Electron:"missing"}), null);
        compare(Apps.match(entries, "__proto__").id, "__proto__");
        compare(Apps.match(entries, "toString"), null);
        compare(Apps.build(entries, [{key:"w", appId:"electron"}], [], [], {electron:"pwa"})[0].id, "pwa");
    }
    function test_pins_first_and_surviving_transient_order_stable() {
        const entries = [{id: "closed", name: "Closed", launchable: true}];
        const items = Apps.build(entries, [{key: "2", appId: "z"}, {key: "1", appId: "a"}], ["closed"], ["window:z"]);
        compare(items.map(i => i.id), ["closed", "window:z", "window:a"]);
        verify(items[0].pinned);
        verify(!items[0].running);
        const missing = Apps.build([], [], ["closed"], []);
        verify(!missing[0].canPin);
    }
    function test_explicitWebappAliasesNeverFuzzyMerge() {
        const entries = [{id: "Google Messages", name: "Messages", launchable: true},
                         {id: "WhatsApp", name: "WhatsApp", launchable: true}];
        compare(Apps.match(entries, "brave-messages.google.com__web_conversations-Default").id, "Google Messages");
        compare(Apps.match(entries, "brave-web.whatsapp.com__-Default").id, "WhatsApp");
        compare(Apps.match(entries, "brave-web.whatsapp.com__-Profile-2").id, "WhatsApp");
        compare(Apps.match(entries, "brave-unknown.example__-Default"), null);
        entries.push({id: "native", startupClass: "brave-web.whatsapp.com__-Default"});
        compare(Apps.match(entries, "brave-web.whatsapp.com__-Default").id, "native");
    }
    function test_configValidation() {
        compare(Apps.parsePins('{"version":1,"pins":["browser","pwa-one"]}').pins, ["browser", "pwa-one"]);
        for (const text of ['{', '', '{"version":2,"pins":[]}', '{"version":1,"pins":["a","a"]}',
                            '{"version":1,"pins":["menu"]}', '{"version":1,"pins":["omarchy-menu"]}', '{"version":1,"pins":["../a"]}']) {
            verify(Apps.parsePins(text).error.length > 0, text);
        }
    }
    function test_exactGrouping() {
        const entries = [{id: "browser", name: "Browser", startupClass: "Browser", icon: "browser", launchable: true},
                         {id: "pwa-one", name: "One", startupClass: "chrome-one-Default", launchable: true}];
        const items = Apps.build(entries, [{key: "1", appId: "Browser", active: true},
            {key: "2", appId: "Browser"}, {key: "3", appId: "chrome-one-Default"},
            {key: "4", appId: "chrome-two-Default"}], [], []);
        compare(items.length, 3);
        compare(items[0].id, "browser");
        compare(items[0].windowCount, 2);
        verify(items[0].active);
        compare(items[1].id, "pwa-one");
        verify(!items[2].canPin);
        verify(items[2].pinReason.length > 0);
    }
}
