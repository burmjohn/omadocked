import QtQuick
import QtTest
import "../../ui"
import "../../services/ConfigLogic.js" as Config

TestCase {
    id: test
    name: "AttentionIndicatorProduction"
    visible: true
    Component { id: dockComponent; DockView {} }
    function test_dockWiringAndSettings() {
        const view = createTemporaryObject(dockComponent, test, {autoHide:false,
            applications:[{id:"fixture", name:"Fixture", running:true, windowCount:1, active:false, icon:""}]});
        const indicator = findChild(view, "attention-fixture");
        verify(indicator !== null, "production dock must present attention");
        view.attentionPresentationEnabled = true;
        view.attentionApps = ["fixture"];
        compare(indicator.attention, true);
        verify(indicator.width <= 8, "attention chrome must not frame the icon");
        verify(indicator.height <= 8);
        compare(indicator.border.width, 0);
        view.surfaceSuspended = true;
        compare(indicator.presentationEnabled, false);
        verify(findChild(view, "attention-hints-setting") !== null);
        verify(findChild(view, "notification-attention-setting") !== null);
        verify(findChild(view, "urgent-sound-setting") !== null);
        verify(findChild(view, "urgent-sound-name") !== null);
        const settings = Config.settings({showUrgentHint:false, urgentOnNotification:false, urgentSound:false, urgentSoundName:"none"});
        compare(settings.showUrgentHint, false);
        compare(settings.urgentSoundName, "none");
    }
    function test_boundedMotionAndHideNoReplay() {
        const c = Qt.createComponent("../../ui/AttentionIndicator.qml");
        compare(c.status, Component.Ready, c.errorString());
        const indicator = createTemporaryObject(c, test, {presentationEnabled:true});
        indicator.attention = true;
        verify(indicator.animating);
        tryCompare(indicator, "animating", false, 3000);
        indicator.attention = false;
        indicator.attention = true;
        verify(indicator.animating);
        indicator.presentationEnabled = false;
        compare(indicator.animating, false);
        compare(indicator.visible, false);
        indicator.presentationEnabled = true;
        compare(indicator.animating, false);
        indicator.reducedMotion = true;
        indicator.attention = false;
        indicator.attention = true;
        compare(indicator.animating, false);
        compare(indicator.visible, false);
        indicator.destroy();
    }
    function test_outlineDoesNotRemainAfterPulse() {
        const c = Qt.createComponent("../../ui/AttentionIndicator.qml");
        compare(c.status, Component.Ready, c.errorString());
        const indicator = createTemporaryObject(c, test, {presentationEnabled:true, width:32, height:32});
        indicator.attention = true;
        verify(indicator.visible);
        tryCompare(indicator, "animating", false, 3000);
        compare(indicator.attention, true);
        compare(indicator.visible, false);
        indicator.destroy();
    }
}
