import QtQuick
import Quickshell
import "../../services" as Services

ShellRoot {
    Services.AppService { id: service }
    function verify(value) { if (!value) throw new Error("Icon service assertion failed"); }
    function compare(actual, expected) { verify(actual === expected); }
    Timer {
        interval: 100
        running: true
        onTriggered: {
            try {
                verify(service.testMode);
                compare(service.configPath, "");
                verify(service.ready);
                // Absolute fixture URLs isolate resolution from offscreen theme availability.
                verify(service.fixtureSet([
                    {id:"t3code", name:"T3 Code", startupClass:"t3code", icon:"/icons/T3 Code#%.png", launchable:true},
                    {id:"chatgpt", name:"ChatGPT", icon:"/icons/chatgpt.png", launchable:true}
                ], [{key:"t3", appId:"com.t3tools.T3Code"}, {key:"chat", appId:"Chatgpt"}]));
                const t3 = service.items.find(i => i.id === "t3code");
                const chat = service.items.find(i => i.id === "chatgpt");
                verify(!!t3 && !!chat);
                compare(t3.icon, "file:///icons/T3%20Code%23%25.png");
                compare(chat.icon, "file:///icons/chatgpt.png");
                verify(service.setPinned("t3code", true));
                compare(service.items.length, 2);
                verify(service.items[0].pinned);
                verify(service.newInstance("t3code"));
                compare(service._pending.t3code.desktopId, "t3code");
                verify(!service.newInstance("com.t3tools.T3Code"));
                verify(service.newInstance("chatgpt"));
                compare(service._pending.chatgpt.desktopId, "chatgpt");
                console.log("ICON_SERVICE_PASS");
            } catch (error) { console.log("ICON_SERVICE_FAIL " + error.message); }
            Qt.quit();
        }
    }
}
