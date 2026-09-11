import QtQuick
import QtTest
import "../../ui"

TestCase {
    id: test
    name: "LaunchFeedback"
    width: 1000; height: 600
    visible: true
    when: windowShown
    Component { id: viewFactory; DockView { width: 900; height: 500; autoHide: false } }
    function test_preference_control_is_committed_only() {
        const view = createTemporaryObject(viewFactory, test);
        view.settingsManaged = true;
        view.settingsOpen = true;
        const control = findChild(view, "launch-bounce-setting");
        verify(control);
        mouseClick(control, control.width / 2, control.height / 2);
        compare(view.launchBounce, true);
    }
    function test_finite_lifecycle_and_input_envelope_data() {
        return [{tag:"wave-peak", mode:"wave", zoom:200}, {tag:"zoom-peak", mode:"zoom", zoom:200}, {tag:"off", mode:"off", zoom:100}];
    }
    function test_finite_lifecycle_and_input_envelope(data) {
        const view = createTemporaryObject(viewFactory, test);
        view.motionMode = data.mode;
        view.zoomSize = data.zoom;
        view.iconSize = 72;
        view.applications = [{id:"one", name:"One", pending:true, launchToken:1}, {id:"two", name:"Two"}];
        const feedback = findChild(view, "launch-feedback-one");
        const art = findChild(view, "art-one");
        const input = findChild(view, "rowInput");
        verify(feedback && input);
        const firstSlot = findChild(view, "item-one");
        const hover = firstSlot.mapToItem(input, firstSlot.width / 2, firstSlot.height / 2);
        mouseMove(input, hover.x, hover.y);
        wait(150);
        if (data.mode !== "off") verify(art.scale > 1.9);
        const shelf = JSON.stringify(view.shelfRect);
        const regions = JSON.stringify(view.inputRects);
        const dockHeight = view.dockHeight;
        tryCompare(feedback, "animating", true);
        for (let i = 0; i < 20; ++i) {
            wait(20);
            verify(art.parent.y + art.y - (art.scale - 1) * art.height >= view.height - view.dockHeight - 0.01);
            compare(JSON.stringify(view.shelfRect), shelf);
            compare(JSON.stringify(view.inputRects), regions);
            compare(view.dockHeight, dockHeight);
        }
        tryCompare(feedback, "animating", false, 2200);
        compare(feedback.offset, 0);
        verify(findChild(view, "pending-one").visible, "static pending survives animation budget");
        view.applications = [{id:"one", name:"One", pending:true, launchToken:2}, {id:"two", name:"Two"}];
        tryCompare(feedback, "animating", true);
        const slot = findChild(view, "item-two");
        const p = slot.mapToItem(input, slot.width / 2, slot.height / 2);
        mousePress(input, p.x, p.y);
        verify(input.pressed);
        mouseRelease(input, p.x, p.y);
        view.surfaceSuspended = true;
        compare(feedback.offset, 0);
        compare(feedback.animating, false);
        view.surfaceSuspended = false;
        view.updateVisibility();
        wait(50);
        compare(feedback.animating, false);
        view.applications = [{id:"one", name:"One", pending:true, launchToken:3}, {id:"two", name:"Two"}];
        tryCompare(feedback, "animating", true);
        view.destroy();
        wait(50); // QObject-owned animation and coalesced callback must die with view.
    }
    function test_pending_caption_tracks_receipt_without_moving_anchor() {
        const view = createTemporaryObject(viewFactory, test);
        view.reducedMotion = true;
        view.applications = [{id:"one", name:"One", pending:true, launchToken:1}];
        view.tooltipIndex = 1;
        const tip = findChild(view, "app-tooltip");
        compare(tip.text, "One [starting…]");
        const anchor = tip.anchorX;
        view.applications = [{id:"one", name:"One", pending:false, launchToken:0}];
        compare(tip.text, "One");
        compare(tip.anchorX, anchor);
        verify(!tip.enabled);
    }
    function test_hidden_view_cancels_without_replay() {
        const view = createTemporaryObject(viewFactory, test);
        view.applications = [{id:"one", name:"One", pending:true, launchToken:1}];
        const feedback = findChild(view, "launch-feedback-one");
        tryCompare(feedback, "animating", true);
        view.visible = false;
        compare(feedback.animating, false);
        compare(feedback.offset, 0);
        view.visible = true;
        wait(50);
        compare(feedback.animating, false);
    }
    function test_preference_and_drag_cancel_without_replay() {
        const view = createTemporaryObject(viewFactory, test);
        view.applications = [{id:"one", name:"One", pending:true, launchToken:1}];
        const feedback = findChild(view, "launch-feedback-one");
        tryCompare(feedback, "animating", true);
        view.launchBounce = false;
        compare(feedback.animating, false);
        compare(feedback.offset, 0);
        view.launchBounce = true;
        wait(40);
        compare(feedback.animating, false);
        view.applications = [{id:"one", name:"One", pending:true, launchToken:2}];
        tryCompare(feedback, "animating", true);
        view.dragActive = true;
        compare(feedback.animating, false);
        compare(feedback.offset, 0);
    }
    function test_pending_art_is_bounded_and_cancels() {
        const view = createTemporaryObject(viewFactory, test);
        view.motionMode = "off";
        view.applications = [{id:"one", name:"One", pending:true, launchToken:1}];
        const art = findChild(view, "art-one");
        verify(art);
        const rest = art.y;
        tryVerify(() => art.y < rest - 0.1, 600);
        view.reducedMotion = true;
        compare(art.y, rest);
        view.reducedMotion = false;
        wait(150);
        compare(art.y, rest); // Never replay the consumed request on policy return.
        view.applications = [{id:"one", name:"One", pending:true, launchToken:2}];
        tryVerify(() => art.y < rest - 0.1, 600);
        view.applications = [{id:"one", name:"One", pending:false, launchToken:0}];
        compare(art.y, rest);
    }
}
