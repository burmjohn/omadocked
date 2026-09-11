import QtQuick
import QtTest
import "../../services/ConfigLogic.js" as Config
TestCase {
    id: test; name:"DelayPreferences"; visible:true; when:windowShown
    width:1200; height:900
    property var dock
    SignalSpy { id: requests; signalName:"delaySettingsRequested" }
    function init() {
        const c=Qt.createComponent("../../ui/DockView.qml"); compare(c.status,Component.Ready,c.errorString());
        dock=createTemporaryObject(c,test,{autoHide:false,reducedMotion:true,applications:[{id:"one",name:"One"}]});
        requests.target=dock; requests.clear();
    }
    function cleanup() { requests.target=null; }
    function test_configRangesAndDefaults() {
        compare(Config.defaults().settings.tooltipDelay,450); compare(Config.defaults().settings.revealDelay,160);
        compare(Config.settings({tooltipDelay:5000,revealDelay:2000}).tooltipDelay,5000);
        compare(Config.settings({tooltipDelay:0,revealDelay:0}).revealDelay,0);
        for (const p of [{tooltipDelay:5001},{revealDelay:2001},{tooltipDelay:-1},{revealDelay:1.5},{tooltipDelay:"4"}]) {
            let rejected=false; try { Config.settings(p); } catch(e) { rejected=true; } verify(rejected);
        }
    }
    function test_sliderCommitRejectedWriteAndKeyboardFocus() {
        dock.settingsManaged=true; dock.settingsOpen=true;
        const slider=findChild(dock,"tooltip-delay-slider"); verify(slider!==null);
        slider.forceActiveFocus(); keyClick(Qt.Key_Right); compare(requests.count,1);
        compare(dock.tooltipDelay,450); compare(slider.value,450);
        dock.settingsManaged=false; keyClick(Qt.Key_Right); compare(dock.tooltipDelay,500);
        const reveal=findChild(dock,"reveal-delay-slider"); verify(reveal!==null);
        reveal.forceActiveFocus(); keyClick(Qt.Key_Right); compare(dock.revealDelay,170);
        const scroll=findChild(dock,"settings-scroll");
        tryVerify(()=>{const p=reveal.mapToItem(scroll,0,0); return p.y>=0 && p.y+reveal.height<=scroll.height;});
        const previous=dock.revealDelay;
        mouseWheel(reveal,reveal.width/2,reveal.height/2,0,-120); compare(dock.revealDelay,previous);
        mousePress(reveal,reveal.width-2,reveal.height/2); verify(reveal.pressed);
        mouseWheel(reveal,reveal.width-2,reveal.height/2,0,-120);
        mouseRelease(reveal,reveal.width-2,reveal.height/2);
        compare(dock.revealDelay,previous,"wheel during delay adjustment cancels the draft");
    }
    function test_delaysDriveRealTimersAndCancel() {
        dock.delaySettingsRequested({tooltipDelay:40,revealDelay:40});
        compare(dock.tooltipDelay,40); compare(dock.revealDelay,40);
        mouseMove(dock,dock.renderedSlots[1].center,dock.rowY+15);
        tryCompare(dock,"tooltipIndex",1,300);
        dock.clearTooltip(); dock.shelfExited(); dock.autoHide=true;
        dock.visibilityState="hidden"; dock.triggerEntered();
        compare(dock.visibilityState,"revealing"); dock.triggerExited(); wait(80); compare(dock.visibilityState,"hidden");
        dock.triggerEntered(); tryCompare(dock,"visibilityState","shown",300);
    }
}
