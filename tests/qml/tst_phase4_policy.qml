import QtQuick
import QtTest
import "../../core/DockLogic.js" as Logic

TestCase {
    name: "Phase4Policy"

    function test_explicit_icon_size_is_unchanged() {
        compare(Logic.resolveIconSize(28, 1), 28);
        compare(Logic.resolveIconSize(44, 2), 44);
        compare(Logic.resolveIconSize(72, 0.5), 72);
    }

    function test_auto_icon_size_follows_scale_and_clamps() {
        compare(Logic.resolveIconSize(0, 1), 44);
        compare(Logic.resolveIconSize(0, 1.25), 55);
        compare(Logic.resolveIconSize(0, 2), 72);
        compare(Logic.resolveIconSize(0, 0.5), 28);
    }

    function test_item_order_keeps_settings_slot_by_default() {
        const apps = [{id: "brave-browser"}, {id: "signal"}];
        compare(Logic.itemOrder(apps, true), ["menu", "brave-browser", "signal"]);
    }

    function test_item_order_can_hide_settings_slot() {
        const apps = [{id: "brave-browser"}, {id: "signal"}];
        compare(Logic.itemOrder(apps, false), ["brave-browser", "signal"]);
    }
}
