import QtQuick
import QtTest
import "../../ui"
import "../../services/ConfigLogic.js" as Config
TestCase {
    id: test; name: "Appearance"; when: windowShown; visible: true
    width: 1400; height: 1000
    Component { id: component; DockView { autoHide:false; reducedMotion:true } }
    function test_config_preserves_explicit_values_and_rejects_invalid() {
        const before = Config.defaults().settings;
        before.iconSize = 62; before.transparency = 37; before.motionMode = "off";
        const after = Config.settings({shape:"theme", itemSpacing:8, backgroundColor:"none", themeOpacity:true}, before);
        compare(after.iconSize,62); compare(after.transparency,37); compare(after.motionMode,"off");
        compare(before.shape,"rounded"); compare(before.itemSpacing,4);
        for (const patch of [{shape:"pill"},{shape:"auto"},{itemSpacing:3},{itemSpacing:"4"},
                             {backgroundColor:"red"},{backgroundColor:"#abc"},{backgroundColor:"#80112233"},
                             {themeOpacity:"theme"},{transparency:-1}]) {
            let rejected = false;
            try { Config.settings(patch); } catch (_) { rejected = true; }
            verify(rejected, JSON.stringify(patch));
        }
    }
    function test_shape_geometry_and_input() {
        const v = createTemporaryObject(component, test);
        const shelf = findChild(v, "shelf-background");
        const rect = v.shelfRect, mask = JSON.stringify(v.inputRects), reservation = v.reservedHeight;
        for (const shape of ["rounded", "round", "square", "theme"]) {
            v.appearanceSettingsRequested({shape:shape});
            compare(shelf.radius, shape === "square" ? 0 : shape === "round" ? shelf.height / 2 : v.baseIconSize * .35);
            compare(v.shelfRect, rect); compare(JSON.stringify(v.inputRects), mask); compare(v.reservedHeight, reservation);
            const item = findChild(v, "settings-item");
            mousePress(item, item.width / 2, item.height / 2);
            verify(v.pressedIndex >= 0, "real input must reach the settings slot");
            mouseRelease(item, item.width / 2, item.height / 2);
            v.settingsOpen = false;
        }
    }
    function test_spacing_fit_and_owned_input_data() {
        const rows = []; for (const gap of [2,4,8]) for (const w of [360,1366]) rows.push({tag:gap+"-"+w, gap:gap, w:w}); return rows;
    }
    function test_spacing_fit_and_owned_input(data) {
        const v = createTemporaryObject(component, test, {availableWidth:data.w, iconSize:72, zoomSize:200, waveWidth:50, reducedMotion:false});
        v.appearanceSettingsRequested({itemSpacing:data.gap});
        compare(v.iconGap, v.baseIconSize * data.gap / 44);
        const nativeWidth = v.width, reservation = v.reservedHeight;
        const item = findChild(v, "settings-item");
        mouseMove(item, item.width / 2, item.height / 2); wait(180);
        verify(v.shelfRect.x >= 0); verify(v.shelfRect.x + v.shelfRect.width <= v.width);
        compare(v.width, nativeWidth); compare(v.reservedHeight, reservation);
        mousePress(item, item.width / 2, item.height / 2); verify(v.pressedIndex >= 0);
        mouseRelease(item, item.width / 2, item.height / 2);
    }
    function test_background_alpha_and_masks() {
        const v = createTemporaryObject(component, test, {transparency:37});
        const shelf = findChild(v, "shelf-background"), mask = JSON.stringify(v.inputRects);
        v.appearanceSettingsRequested({backgroundColor:"#181825", themeOpacity:false});
        compare(shelf.color, Qt.color("#181825")); compare(shelf.opacity, .63);
        v.themeBackground = Qt.rgba(.2,.3,.4,.4);
        v.appearanceSettingsRequested({backgroundColor:"theme", themeOpacity:true});
        compare(shelf.color, Qt.rgba(.2,.3,.4,1)); fuzzyCompare(shelf.opacity, .4, .001);
        compare(v.transparency, 37, "theme mode must retain explicit transparency");
        v.appearanceSettingsRequested({backgroundColor:"none"});
        compare(shelf.opacity, 1); compare(shelf.color, Qt.rgba(0,0,0,.25));
        fuzzyCompare(shelf.border.color.a, .48, .001);
        v.transparency = 100;
        compare(shelf.color, Qt.rgba(0,0,0,.25));
        compare(JSON.stringify(v.inputRects), mask);
        v.appearanceSettingsRequested({backgroundColor:"theme", themeOpacity:false});
        compare(shelf.opacity, 0);
        const item = findChild(v, "settings-item");
        mousePress(item, item.width/2, item.height/2); verify(v.pressedIndex >= 0);
        mouseRelease(item, item.width/2, item.height/2);
    }
    function test_new_controls_scroll_cancel_and_focus_data() {
        return ["shape-square", "spacing-8", "theme-opacity"].map(control => ({tag:control, control:control}));
    }
    function test_new_controls_scroll_cancel_and_focus(data) {
        const v = createTemporaryObject(component, test, {availableWidth:600, availableHeight:600});
        v.settingsOpen = true; wait(30);
        const popup = findChild(v, "settings-popup"), s = findChild(v, "settings-scroll");
        const button = findChild(popup.contentItem, data.control);
        button.forceActiveFocus(); wait(30);
        const p = button.mapToItem(s,0,0);
        verify(p.y >= 0 && p.y + button.height <= s.height);
        const before = JSON.stringify(v.appearanceSettings);
        mousePress(button,button.width/2,button.height/2); verify(button.pressed);
        mouseWheel(button,button.width/2,button.height/2,0,-120);
        mouseRelease(button,button.width/2,button.height/2);
        compare(JSON.stringify(v.appearanceSettings),before);
        button.forceActiveFocus(); keyClick(Qt.Key_Space);
        verify(JSON.stringify(v.appearanceSettings) !== before);
        v.appearanceSettings = JSON.parse(before);
        button.Accessible.pressAction();
        verify(JSON.stringify(v.appearanceSettings) !== before, "accessibility has no pointer press snapshot");
    }
    function test_color_popup_stays_inside_input_mask_data() {
        return [{tag:"normal",w:1366,h:1080},{tag:"compact",w:600,h:600}];
    }
    function test_color_popup_stays_inside_input_mask(data) {
        const v = createTemporaryObject(component,test,{availableWidth:data.w,availableHeight:data.h});
        v.settingsOpen = true; wait(30);
        const settings = findChild(v,"settings-popup"), picker = findChild(settings.contentItem,"background-color");
        picker.forceActiveFocus(); wait(30); keyClick(Qt.Key_Space); wait(40);
        verify(picker.popup.visible);
        const p = picker.popup.contentItem.mapToItem(v,0,0);
        verify(p.y >= v.popupRect.y && p.y + picker.popup.contentItem.height <= v.popupRect.y + v.popupRect.height,
               "color dropdown must stay within the existing native settings mask");
        keyClick(Qt.Key_Escape);
    }
    function test_host_shape_token() {
        const v = createTemporaryObject(component, test);
        verify("themeCornerRadius" in v, "installed host cornerRadius must reach production view");
        v.themeCornerRadius = 11;
        v.appearanceSettingsRequested({shape:"theme"});
        compare(findChild(v, "shelf-background").radius, 11);
        v.themeCornerRadius = 0;
        compare(findChild(v, "shelf-background").radius, 0);
    }
}
