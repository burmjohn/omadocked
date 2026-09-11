import QtQuick
import QtTest
import "../../core/AppLogic.js" as Apps

TestCase {
    name: "PwaDomainMatch"

    function test_named_pwa_entry_matches_brave_web_class() {
        const entries = [
            {id: "YouTube Music", name: "YouTube Music", icon: "", startupClass: "", launchable: true},
            {id: "brave-browser", name: "Brave", icon: "", startupClass: "brave-browser", launchable: true}
        ];
        const hit = Apps.match(entries, "brave-music.youtube.com__-Default", {});
        compare(hit && hit.id, "YouTube Music");
    }

    function test_unknown_pwa_class_does_not_use_browser_fallback() {
        const entries = [
            {id: "brave-browser", name: "Brave", icon: "", startupClass: "brave-browser", launchable: true}
        ];
        compare(Apps.match(entries, "brave-music.youtube.com__-Default", {}), null);
    }
}
