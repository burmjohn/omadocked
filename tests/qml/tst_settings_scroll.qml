import QtQuick
import QtTest
import "../../ui"
TestCase {
    id: test
    name: "SettingsScroll"
    when: windowShown
    visible: true
    width: 1200; height: 1000
    Component { id: component; DockView { reducedMotion: true; autoHide: false; availableOutputs: ["DP-1", "DP-2", "HDMI-A-1"]; monitorMode: "selected"; selectedOutputs: ["DP-1", "DP-2"] } }
    SignalSpy { id: monitors; signalName: "monitorsRequested" }
    function test_scroll_during_monitor_press_cancels_click() {
        const v = createTemporaryObject(component, test);
        v.settingsOpen = true; wait(30);
        const check = findChild(findChild(v, "settings-popup").contentItem, "output-DP-1");
        monitors.target = v; monitors.clear();
        mousePress(check, 50, 15); compare(check.pressed, true);
        mouseWheel(check, 50, 15, 0, -120);
        mouseRelease(check, 50, 15); wait(30);
        compare(monitors.count, 0, "scroll gesture must cancel pending monitor click");
        compare(check.checked, true);
    }
    function test_explicit_buttons_still_edit() {
        const v = createTemporaryObject(component, test); v.settingsOpen = true; wait(30);
        const b = findChild(v, "reduced-motion");
        mousePress(b, b.width / 2, b.height / 2); compare(b.pressed, true);
        mouseRelease(b, b.width / 2, b.height / 2);
        compare(v.reducedMotion, false);
    }
    SignalSpy { id: samples; signalName: "soundSampleRequested" }
    function test_sample_is_deliberate_keyboard_accessible_and_inert_settings() {
        const v = createTemporaryObject(component, test);
        const b = findChild(v, "urgent-sound-sample");
        verify(b !== null, "explicit sample control required");
        samples.target = v; samples.clear();
        v.settingsOpen = true; wait(30);
        compare(samples.count, 0);
        verify(!b.enabled);
        v.urgentSound = true; v.urgentSoundName = "complete";
        v.soundSampleStatus = "ready";
        compare(samples.count, 0, "enable/name/open never sample");
        findChild(v, "urgent-sound-setting").forceActiveFocus();
        keyClick(Qt.Key_Tab); verify(b.activeFocus, "sample is in Settings tab order");
        keyClick(Qt.Key_Space);
        compare(samples.count, 1);
        keyClick(Qt.Key_Return); compare(samples.count, 2);
        b.Accessible.pressAction(); compare(samples.count, 3);
        compare(b.Accessible.name, "Play sound sample");
        v.soundSampleStatus = "busy";
        b.Accessible.pressAction(); compare(samples.count, 3);
        v.settingsOpen = false; v.settingsOpen = true; wait(20);
        compare(samples.count, 3);
    }
    function test_normal_screen_has_columns_without_scroll_data() {
        return ["ready", "off: enable attention sound first", "unavailable: visible, unlocked dock required",
                "unavailable: sound player failed to start", "unavailable: canberra-gtk-play missing",
                "unavailable: sound playback timed out", "busy", "cooldown: wait briefly"]
            .map(status => ({tag: status, status: status}));
    }
    function test_normal_screen_has_columns_without_scroll(data) {
        const v = createTemporaryObject(component, test, {availableWidth: 1366, soundSampleStatus: data.status});
        v.settingsOpen = true; wait(30);
        const popup = findChild(v, "settings-popup"), s = findChild(v, "settings-scroll");
        verify(popup.width >= 1000, "settings should use screen width");
        verify(s.contentHeight <= s.height, "normal settings should fit without scrolling: " + s.contentHeight);
    }
    function test_wheel_never_edits_controls_data() {
        return ["size-slider", "transparency-slider", "folder-color", "reduced-motion", "auto-hide", "output-DP-1", "output-HDMI-A-1"].map(name => ({tag: name, control: name}));
    }
    function test_wheel_never_edits_controls(data) {
        const v = createTemporaryObject(component, test, {availableWidth: 600, availableHeight: 600});
        v.settingsOpen = true; wait(30);
        const popup = findChild(v, "settings-popup"), s = findChild(v, "settings-scroll");
        const c = findChild(popup.contentItem, data.control);
        c.forceActiveFocus(); wait(30);
        const value = c.value, index = c.currentIndex, checked = c.checked;
        monitors.target = v; monitors.clear();
        for (const delta of [-120, 120]) {
            // Focus reveal places each actual control back inside the viewport.
            s.revealFocus(); wait(10);
            mouseWheel(c, c.width / 2, c.height / 2, 0, delta); wait(10);
        }
        compare(c.value, value); compare(c.currentIndex, index); compare(c.checked, checked);
        compare(v.iconSize, 44); compare(v.transparency, 0); compare(v.reducedMotion, true);
        compare(monitors.count, 0); compare(v.selectedOutputs, ["DP-1", "DP-2"]);
    }
    function test_monitor_explicit_keyboard_and_accessible_actions() {
        const v = createTemporaryObject(component, test); v.settingsOpen = true; wait(30);
        const c = findChild(findChild(v, "settings-popup").contentItem, "output-DP-1");
        c.forceActiveFocus(); keyClick(Qt.Key_Space); compare(v.selectedOutputs, ["DP-2"]);
        c.Accessible.pressAction(); compare(v.selectedOutputs, ["DP-2", "DP-1"]);
    }
    function test_small_screen_bounds_and_focus_data() {
        return [{tag: "single", w: 360, h: 600}, {tag: "two", w: 900, h: 700}, {tag: "ordinary", w: 1366, h: 768}];
    }
    function test_small_screen_bounds_and_focus(data) {
        const v = createTemporaryObject(component, test, {availableWidth: data.w, availableHeight: data.h});
        v.settingsOpen = true; wait(30);
        const popup = findChild(v, "settings-popup"), s = findChild(v, "settings-scroll");
        verify(v.height <= data.h); verify(v.width <= data.w);
        verify(popup.x >= 0); verify(popup.x + popup.width <= v.width);
        const folders = findChild(v, "folder-settings");
        folders.beginSelection(false);
        v.folderResult = {complete: true, entries: Array.from({length: 16}, (_, i) => ({type: "directory", label: "Owned " + i, path: "/tmp/owned/" + i}))};
        const field = findChild(v, "folder-picker-path");
        field.forceActiveFocus(); wait(30);
        const p = field.mapToItem(s, 0, 0);
        verify(p.x >= 0 && p.x + field.width <= s.width);
        verify(p.y >= 0 && p.y + field.height <= s.height);
        verify(s.contentHeight > s.height, "expanded picker has safe overflow");
    }
    function test_wheel_over_monitor_scrolls_without_toggling() {
        const v = createTemporaryObject(component, test, {availableWidth: 600});
        v.settingsOpen = true; wait(30);
        const s = findChild(v, "settings-scroll");
        const check = findChild(findChild(v, "settings-popup").contentItem, "output-DP-1");
        monitors.target = v; monitors.clear();
        check.forceActiveFocus(); wait(20);
        const before = s.contentItem.contentY;
        mouseWheel(check, 50, 15, 0, -120); wait(100);
        compare(monitors.count, 0, "wheel must not request monitor changes");
        compare(check.checked, true);
        verify(s.contentItem.contentY > before, "wheel over monitor must reach outer scroll");
    }
}
