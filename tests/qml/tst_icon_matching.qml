import QtQuick
import QtTest
import "../../core/AppLogic.js" as Apps

TestCase {
    name: "IconMatching"
    function test_ambiguousHigherPriorityIdentityNeverFallsThroughAlias() {
        const target = {id:"chatgpt", name:"ChatGPT", icon:"chatgpt"};
        const exact = {id:"Chatgpt", name:"First"};
        compare(Apps.match([target, exact, exact], "Chatgpt"), null);
        const byClass = {id:"first", startupClass:"Chatgpt"};
        compare(Apps.match([target, byClass, {id:"second", startupClass:"Chatgpt"}], "Chatgpt"), null);
        const suffixed = {id:"Chatgpt.desktop", startupClass:"Chatgpt.desktop"};
        compare(Apps.match([target, suffixed, suffixed], "Chatgpt.desktop"), null);
    }
    function test_t3ReverseDnsClassUsesInstalledLauncherIdentity() {
        const entry = {id:"t3code", name:"T3 Code", startupClass:"t3code", icon:"t3code", launchable:true};
        const items = Apps.build([entry], [{key:"one", appId:"com.t3tools.T3Code"}], ["t3code"], []);
        compare(items.length, 1);
        compare(items[0].id, "t3code");
        compare(items[0].icon, "t3code");
        verify(items[0].running && items[0].pinned && items[0].canPin);
        compare(Apps.match([entry], "com.t3tools.t3code"), null);
        compare(Apps.match([entry], "com.t3tools.T3Code", {"com.t3tools.T3Code":"missing"}), null);
        compare(Apps.match([entry, {id:"other", startupClass:"com.t3tools.T3Code"}], "com.t3tools.T3Code").id, "other");
        compare(Apps.match([entry, {id:"com.t3tools.T3Code"}], "com.t3tools.T3Code").id, "com.t3tools.T3Code");
        compare(Apps.match([entry, entry], "com.t3tools.T3Code"), null);
    }
    function test_explicitXwaylandChatgptIdentity() {
        const entry = {id:"chatgpt", name:"ChatGPT", icon:"chatgpt", launchable:true};
        const items = Apps.build([entry], [{key:"one", appId:"Chatgpt"}], [], []);
        compare(items[0].id, "chatgpt");
        compare(items[0].icon, "chatgpt");
        verify(items[0].canPin);
        compare(Apps.match([entry], "CHATGPT"), null);
        compare(Apps.match([entry], "Chatgpt", {Chatgpt:"missing"}), null);
        const exact = {id:"Chatgpt", icon:"other"};
        compare(Apps.match([entry, exact], "Chatgpt"), exact);
        compare(Apps.match([entry, {id:"other", startupClass:"Chatgpt"}], "Chatgpt").id, "other");
        compare(Apps.match([entry, entry], "Chatgpt"), null);
    }
}
