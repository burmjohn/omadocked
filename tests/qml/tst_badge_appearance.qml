import QtQuick
import QtTest
import "../../ui"
import "../../services/ConfigLogic.js" as Config

TestCase {
    id: test
    name: "BadgeAppearance"
    when: windowShown
    visible: true
    width: 1200; height: 900
    Component { id: viewComponent; DockView { autoHide: false; reducedMotion: true } }
    function app(count) { return {id: "alpha", name: "Alpha", running: true, windowCount: count}; }

    function test_defaults_and_validation() {
        const defaults = Config.defaults().settings;
        compare(defaults.badgePosition, "bottom-right");
        compare(defaults.badgeBackgroundColor, "theme");
        compare(defaults.badgeTextColor, "theme");
        const legacy = Config.defaults();
        delete legacy.settings.badgePosition;
        delete legacy.settings.badgeBackgroundColor;
        delete legacy.settings.badgeTextColor;
        const parsed = Config.parse(JSON.stringify(legacy));
        compare(parsed.error, "");
        compare(parsed.config.settings.badgePosition, "bottom-right");
        compare(parsed.config.settings.badgeBackgroundColor, "theme");
        compare(parsed.config.settings.badgeTextColor, "theme");
        for (const position of ["top-left", "top-right", "bottom-left", "bottom-right"])
            compare(Config.settings({badgePosition: position}).badgePosition, position);
        for (const color of ["#112233", "#AAbbCC", "theme"])
            compare(Config.settings({badgeBackgroundColor: color, badgeTextColor: color}).badgeTextColor, color);
        for (const patch of [{badgePosition: "center"}, {badgePosition: 0},
                             {badgeBackgroundColor: "red"}, {badgeTextColor: "#abc"},
                             {badgeTextColor: "#80112233"}, {badgeBackgroundColor: null}]) {
            let rejected = false;
            try { Config.settings(patch); } catch (_) { rejected = true; }
            verify(rejected, JSON.stringify(patch));
        }
    }
    function test_four_corners_and_colors_preserve_hit_targets() {
        const v = createTemporaryObject(viewComponent, test, {applications: [app(3)]});
        const slot = findChild(v, "item-alpha"), badge = findChild(v, "window-count-alpha");
        verify(badge !== null);
        const slotRect = Qt.rect(slot.x, slot.y, slot.width, slot.height);
        const input = JSON.stringify(v.inputRects);
        const positions = [
            {value:"top-left", left:true, top:true}, {value:"top-right", left:false, top:true},
            {value:"bottom-left", left:true, top:false}, {value:"bottom-right", left:false, top:false}
        ];
        for (const size of [28, 72]) {
            v.iconSize = size;
            for (const pos of positions) {
                v.appearanceSettingsRequested({badgePosition:pos.value});
                compare(badge.x, (slot.width + (pos.left ? -v.baseIconSize : v.baseIconSize)) / 2 - (pos.left ? 0 : badge.width));
                compare(badge.y, pos.top ? 0 : v.baseIconSize - badge.height);
                compare(badge.width, 24); compare(badge.height, 15);
            }
        }
        v.iconSize = 44;
        v.appearanceSettingsRequested({badgeBackgroundColor:"#112233", badgeTextColor:"#eeaa44"});
        compare(badge.color, Qt.color("#eeaa44"));
        compare(badge.children[0].color, Qt.color("#112233"));
        v.appearanceSettingsRequested({badgeBackgroundColor:"theme", badgeTextColor:"theme"});
        compare(badge.color, v.textColor);
        compare(badge.children[0].color, Qt.rgba(v.shelfColor.r, v.shelfColor.g, v.shelfColor.b, .94));
        v.textColor = "#f0f0f0";
        v.shelfColor = "#102030";
        compare(badge.color, Qt.color("#f0f0f0"));
        compare(badge.children[0].color, Qt.rgba(v.shelfColor.r, v.shelfColor.g, v.shelfColor.b, .94));
        compare(Qt.rect(slot.x, slot.y, slot.width, slot.height), slotRect);
        compare(JSON.stringify(v.inputRects), input);
        compare(slot.Accessible.name, "Alpha, 3 windows");
    }
    function test_keyboard_settings_controls_commit_only_valid_choices() {
        const v = createTemporaryObject(viewComponent, test, {applications:[app(2)]});
        v.settingsOpen = true; wait(30);
        const popup = findChild(v, "settings-popup");
        const expand = findChild(popup.contentItem, "badge-settings");
        verify(expand !== null);
        expand.forceActiveFocus(); keyClick(Qt.Key_Space);
        verify(findChild(popup.contentItem, "badge-controls").visible);
        const corner = findChild(popup.contentItem, "badge-top-left");
        verify(corner !== null);
        corner.forceActiveFocus(); keyClick(Qt.Key_Space);
        compare(v.appearanceSettings.badgePosition, "top-left");
        const background = findChild(popup.contentItem, "badge-background-color");
        const foreground = findChild(popup.contentItem, "badge-text-color");
        verify(background !== null && foreground !== null);
        background.forceActiveFocus(); background.text = "#112233"; keyClick(Qt.Key_Return);
        foreground.forceActiveFocus(); foreground.text = "#eeaa44"; keyClick(Qt.Key_Return);
        compare(v.appearanceSettings.badgeBackgroundColor, "#112233");
        compare(v.appearanceSettings.badgeTextColor, "#eeaa44");
        background.forceActiveFocus(); background.text = "bad color"; keyClick(Qt.Key_Return);
        compare(v.appearanceSettings.badgeBackgroundColor, "#112233");
        background.text = "theme"; keyClick(Qt.Key_Return);
        foreground.forceActiveFocus(); foreground.text = "theme"; keyClick(Qt.Key_Return);
        compare(v.appearanceSettings.badgeBackgroundColor, "theme");
        compare(v.appearanceSettings.badgeTextColor, "theme");
        v.settingsOpen = false;
        compare(v.appearanceSettings.badgeBackgroundColor, "theme");
    }
    function test_modified_settings_row_labels_fit_at_normal_and_compact_width() {
        for (const width of [360, 1366]) {
            const v = createTemporaryObject(viewComponent, test, {availableWidth:width});
            v.settingsOpen = true; wait(30);
            const popup = findChild(v, "settings-popup");
            for (const name of ["background-color", "theme-opacity", "badge-settings"]) {
                const control = findChild(popup.contentItem, name);
                verify(control !== null);
                if (control.contentItem && control.contentItem.paintedWidth !== undefined)
                    verify(control.contentItem.paintedWidth <= control.width - 8,
                           name + " overflows at " + width + " px");
            }
            v.destroy();
        }
    }
    function test_attention_dot_avoids_top_right_count_badge() {
        const v = createTemporaryObject(viewComponent, test, {applications:[app(2)]});
        const art = findChild(v, "art-alpha"), dot = findChild(v, "attention-alpha");
        verify(dot !== null);
        compare(dot.x, art.x + art.width - dot.width);
        v.appearanceSettingsRequested({badgePosition:"top-right"});
        compare(dot.x, art.x);
        v.appearanceSettingsRequested({badgePosition:"bottom-right"});
        compare(dot.x, art.x + art.width - dot.width);
    }
    function test_compact_editor_reveals_focused_fields_and_discards_unsaved_draft() {
        const v = createTemporaryObject(viewComponent, test,
            {availableWidth:360, availableHeight:600, applications:[app(2)]});
        v.settingsOpen = true; wait(30);
        const panel = findChild(v, "settings-popup"), scroll = findChild(v, "settings-scroll");
        const expand = findChild(panel.contentItem, "badge-settings");
        expand.forceActiveFocus(); keyClick(Qt.Key_Space);
        const controls = findChild(panel.contentItem, "badge-controls");
        verify(controls.visible);
        const field = findChild(controls, "badge-text-color");
        field.forceActiveFocus(); wait(30);
        const point = field.mapToItem(scroll, 0, 0);
        verify(point.y >= 0 && point.y + field.height <= scroll.height);
        verify(field.width <= scroll.width);
        field.text = "#123456";
        v.settingsOpen = false; wait(0);
        compare(v.appearanceSettings.badgeTextColor, "theme");
        verify(!controls.visible);
        v.settingsOpen = true; wait(30);
        compare(field.text, "theme");
        compare(findChild(panel.contentItem, "badge-settings").chosen, false);
    }
}
