import QtQuick
import QtQuick.Controls
import QtTest
import "../../services/ConfigLogic.js" as Config

TestCase {
    id: test
    name: "AppTooltip"
    when: windowShown
    visible: true
    width: 1200; height: 900

    function makeDock(extra) {
        const c = Qt.createComponent("../../ui/DockView.qml");
        compare(c.status, Component.Ready, c.errorString());
        const d = createTemporaryObject(c, test, Object.assign({autoHide:false, motionMode:"off",
            applications:[{id:"one",name:"One <b>literal</b>",icon:""},{id:"two",name:"Second",icon:""}]}, extra || {}));
        verify(waitForRendering(d));
        mouseMove(test, 1190, 890);
        return d;
    }
    function hover(d, index) { mouseMove(d, d.renderedSlots[index].center, d.height - 25); }

    function test_toggleCancelsDwellAndShownButPreservesSettingsAndErrors() {
        const d = makeDock();
        compare(d.showAppNames, true);
        hover(d, 2); wait(100); d.showAppNames = false;
        wait(d.tooltipDelay + 50); compare(d.tooltipIndex, -1);
        const tip = findChild(d,"app-tooltip"); verify(!tip.visible);
        d.showAppNames = true; hover(d,3);
        tryCompare(d,"tooltipIndex",3,1000); tryCompare(tip,"opened",true);
        d.showAppNames = false; compare(d.tooltipIndex,-1); compare(tip.opacity,0);
        wait(20); compare(tip.opacity,0);
        tryCompare(tip,"visible",false,200);
        d.appError = "Owned fixture failure"; verify(findChild(d,"app-status").visible);
        compare(findChild(d,"art-one").parent.Accessible.name,"One <b>literal</b>");
        hover(d,1); tryCompare(d,"tooltipIndex",1,1000); compare(tip.text,"Settings");
        verify(!d.wantsKeyboard); compare(d.popupRect.width,0);
    }
    function test_settingsControlUsesCommittedStateAndKeyboard() {
        const d = makeDock({settingsManaged:true}); d.settingsOpen = true;
        const button = findChild(d,"show-app-names"); verify(button !== null);
        compare(button.text,"Show app names"); verify(button.checked);
        button.forceActiveFocus(); keyClick(Qt.Key_Space); wait(10);
        verify(button.checked,"a rejected managed write cannot change the checkmark");
        d.settingsManaged = false; keyClick(Qt.Key_Space); compare(d.showAppNames,false); verify(!button.checked);
        d.settingsOpen = false; d.settingsOpen = true; verify(!button.checked);
    }
    function test_wheelDoesNotToggleAndFocusIsVisible() {
        const d = makeDock(); d.settingsOpen = true;
        verify(waitForRendering(d)); wait(30);
        const button = findChild(d,"show-app-names"), scroll = findChild(d,"settings-scroll");
        verify(button !== null && button.width > 0);
        button.forceActiveFocus();
        tryVerify(function() { const p = button.mapToItem(scroll,0,0); return p.y >= 0 && p.y + button.height <= scroll.height; });
        mousePress(button, Math.min(12, button.width / 2), button.height / 2); verify(button.pressed);
        mouseWheel(button,button.width/2,button.height/2,0,-120);
        mouseRelease(button,button.width/2,button.height/2);
        verify(d.showAppNames,"scrolling during a press must cancel the setting change");
    }

    function test_interruptEnterAndTeardownNeverReplays() {
        const d = makeDock(); const tip = findChild(d,"app-tooltip");
        hover(d,2); tryCompare(d,"tooltipIndex",2,1000);
        d.reducedMotion = true; compare(tip.opacity,0); compare(d.tooltipIndex,-1);
        tryCompare(tip,"opened",true,1000); compare(tip.motionOffset,0); compare(tip.opacity,1);
        d.reducedMotion = false; hover(d,3); d.resetSurface();
        compare(d.tooltipIndex,-1); compare(tip.opacity,0);
        wait(d.tooltipDelay + 150); compare(d.tooltipIndex,-1); verify(!tip.visible);
        const pending = makeDock(); hover(pending,2); pending.destroy();
        wait(600); // Timer/Connections owners are destroyed, without stale callbacks.
    }

    function test_transitionsPassiveStableAndReducedMotion() {
        const d = makeDock(); const tip = findChild(d,"app-tooltip");
        hover(d,2); tryCompare(d,"tooltipIndex",2,1000); tryCompare(tip,"opened",true);
        verify(tip.parent === findChild(d,"rowInput").parent); verify(!tip.focus); verify(!tip.enabled);
        verify(tip.background.radius >= 9); compare(tip.textFormat,Text.PlainText);
        const width = d.width, height = d.height, shelf = JSON.stringify(d.shelfRect);
        hover(d,3); compare(d.tooltipIndex,3); verify(tip.opened);
        wait(150); compare(tip.text,"Second"); compare(d.width,width); compare(d.height,height);
        compare(JSON.stringify(d.shelfRect),shelf);
        mouseMove(test,1190,890); tryCompare(d,"tooltipIndex",-1,200);
        verify(tip.visible,"ordinary leave retains the fading popup");
        wait(35); verify(tip.opacity > 0 && tip.opacity < 1);
        tryCompare(tip,"visible",false,500);
        d.reducedMotion = true; hover(d,2); tryCompare(tip,"opened",true,1000);
        compare(tip.opacity,1); compare(tip.motionOffset,0);
        d.resetSurface(); compare(d.tooltipIndex,-1); verify(!tip.visible);
    }

    function test_captionSitsAboveShelf() {
        const d = makeDock(); const tip = findChild(d,"app-tooltip");
        hover(d,2); tryCompare(tip,"opened",true,1000);
        verify(tip.height > 0);
        verify(tip.y + tip.height <= d.height - d.dockHeight - 12);
        verify(tip.y >= 0);
    }

    function test_configDefaultValidationAndRoundtrip() {
        compare(Config.defaults().settings.showAppNames, true);
        const old = Config.defaults(); delete old.settings.showAppNames;
        compare(Config.parse(JSON.stringify(old)).config.settings.showAppNames, true);
        old.settings.showAppNames = false;
        const parsed = Config.parse(JSON.stringify(old));
        compare(parsed.error, ""); compare(parsed.config.settings.showAppNames, false);
        for (const value of [0, 1, "false", null]) {
            old.settings.showAppNames = value;
            verify(Config.parse(JSON.stringify(old)).error.length > 0);
        }
    }
}
