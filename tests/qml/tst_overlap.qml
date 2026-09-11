import QtQuick
import QtTest
import "../../ui"

TestCase {
    name: "ProductionOverlap"
    when: windowShown
    visible: true
    width: 1200; height: 900
    Component { id: factory; DockView { reducedMotion: true } }
    function test_reservation_stable_and_committed_control() {
        const view = createTemporaryObject(factory, this);
        compare(view.reserveSpace, false, "Reservation is explicit opt-in");
        compare(view.reservedHeight, 0);
        view.settingsManaged = true; view.settingsOpen = true;
        const control = findChild(view, "reserve-space"); verify(control);
        control.forceActiveFocus(); keyClick(Qt.Key_Space);
        compare(view.reserveSpace, false, "No optimistic unsaved reservation");
        view.reserveSpace = true;
        const zone = view.reservedHeight; verify(zone > 0);
        view.settingsOpen = false; view.visibilityState = "hidden";
        compare(view.reservedHeight, zone);
        view.nativeOverlap = true; view.pointerX = view.width / 2;
        view.settingsOpen = true; view.appError = "Owned error";
        compare(view.reservedHeight, zone, "No popup/overlap/hover/status layout feedback");
        view.reserveSpace = false; compare(view.reservedHeight, 0);
    }
    function test_setting_control() {
        const view = createTemporaryObject(factory, this);
        view.settingsManaged = true;
        view.settingsOpen = true;
        const control = findChild(view, "intelligent-hide");
        verify(control, "Overlap mode must be discoverable in Settings");
        control.forceActiveFocus();
        keyClick(Qt.Key_Space);
        compare(view.intelligentHide, false, "Rejected/unacknowledged preference cannot toggle itself");
        verify(!control.checked);
        view.intelligentHide = true;
        verify(control.checked);
        view.autoHide = false;
        verify(!control.enabled);
    }
    function test_interaction_freeze() {
        const view = createTemporaryObject(factory, this);
        view.nativeOverlap = true;
        view.intelligentHide = true;
        view.applications = [{id:"alpha", name:"Alpha", running:true}];
        view.windowGroups = {alpha:[{key:"owned", title:"Owned fixture", active:true}]};
        verify(view.openWindowChooser("alpha"));
        verify(view.contextIndex >= 0);
        view.nativeFullscreen = true;
        compare(view.visibilityState, "interacting");
        view.nativeOverlap = false;
        compare(view.visibilityState, "interacting");
        view.releaseInteractions();
        compare(view.visibilityState, "hidden");
        view.nativeFullscreen = false;
        view.nativeOverlapAvailable = false;
        view.visibilityState = "shown";
        view.updateVisibility();
        compare(view.visibilityState, "hiding", "Missing adapter falls back to ordinary auto-hide");
        view.settingsOpen = true;
        view.resetSurface();
        compare(view.visibilityState, "hidden", "Unmapping still overrides interaction freeze");
        verify(!view.settingsOpen);
    }
    function test_native_policy() {
        const view = createTemporaryObject(factory, this);
        verify(view.nativeOverlap !== undefined, "Production overlap input must exist");
        view.intelligentHide = true;
        view.nativeOverlap = false;
        view.updateVisibility();
        compare(view.visibilityState, "shown");
        view.nativeOverlap = true;
        compare(view.visibilityState, "hiding");
        view.settingsOpen = true;
        view.nativeFullscreen = true;
        compare(view.visibilityState, "interacting");
        view.settingsOpen = false;
        compare(view.visibilityState, "hidden");
        view.triggerEntered();
        compare(view.visibilityState, "revealing");
        view.nativeOverlap = !view.nativeOverlap;
        view.updateVisibility();
        compare(view.visibilityState, "revealing", "Native update must not bypass reveal dwell");
        view.triggerExited();
        compare(view.visibilityState, "hidden");
        view.nativeFullscreen = false;
        view.intelligentHide = false;
        view.nativeOverlap = false;
        view.visibilityState = "shown";
        view.updateVisibility();
        compare(view.visibilityState, "hiding", "Ordinary auto-hide survives");
        view.autoHide = false;
        compare(view.visibilityState, "shown");
    }
}
