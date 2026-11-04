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

    function test_generic_labels_do_not_own_web_windows() {
        const entries = [{id:"org.gnome.Music", name:"Music", launchable:true}];
        const web = "brave-music.youtube.com__-Default";
        compare(Apps.match(entries, web, {}), null);
        const groups = Apps.build(entries, [{key:"native", appId:"org.gnome.Music"},
            {key:"web", appId:web}], [], [], {});
        compare(groups.length, 2);
        compare(groups.find(g => g.id === "org.gnome.Music").windows, ["native"]);
        compare(Apps.match([{id:"YouTube Music", name:"YouTube Music"}],
            "brave-music.unrelated.example__-Default", {}), null);
    }

    function test_explicit_pwa_domains_preserve_exact_identity_and_ambiguity() {
        const entries = [{id:"Google Messages", name:"Messages"}, {id:"WhatsApp", name:"WhatsApp"},
            {id:"YouTube Music", name:"YouTube Music"}, {id:"org.gnome.Music", name:"Music"}];
        compare(Apps.match(entries, "brave-messages.google.com__web_conversations-Default", {}).id, "Google Messages");
        compare(Apps.match(entries, "brave-web.whatsapp.com__-Default", {}).id, "WhatsApp");
        compare(Apps.match(entries, "brave-music.youtube.com__-Default", {}).id, "YouTube Music");
        compare(Apps.match(entries.concat([{id:"YouTube Music", name:"duplicate"}]),
            "brave-music.youtube.com__-Default", {}), null);
        compare(Apps.match([{id:"youtube music", name:"YouTube Music"}],
            "brave-music.youtube.com__-Default", {}), null);
        compare(Apps.match(entries, "brave-music.youtube.com.evil.example__-Default", {}), null);
    }

    function test_unknown_pwa_class_does_not_use_browser_fallback() {
        const entries = [
            {id: "brave-browser", name: "Brave", icon: "", startupClass: "brave-browser", launchable: true}
        ];
        compare(Apps.match(entries, "brave-music.youtube.com__-Default", {}), null);
    }
}
