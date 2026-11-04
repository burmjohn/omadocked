import QtQuick
import QtTest
import "../../ui"

TestCase {
    id: test
    name: "CompactBadges"
    visible: true
    when: windowShown
    width: 1200; height: 900
    Component { id: viewComponent; DockView { autoHide: false; iconSize: 28; zoomSize: 140; waveWidth: 25; transparency: 46 } }
    function test_compact_count_fits_without_changing_targets() {
        const v = createTemporaryObject(viewComponent, test, {applications:[{id:"notes", name:"Notes", running:true, windowCount:2}]});
        const badge = findChild(v, "window-count-notes"), slot = findChild(v, "item-notes");
        verify(badge.width <= 16, "single digit should not cover most of a 28px icon");
        verify(badge.height <= 13);
        const target = Qt.rect(slot.x, slot.y, slot.width, slot.height);
        const input = JSON.stringify(v.inputRects);
        for (const count of [2, 12, 100]) {
            v.applications = [{id:"notes", name:"Notes", running:true, windowCount:count}];
            const b = findChild(v, "window-count-notes");
            compare(b.text, count > 99 ? "99+" : String(count));
            verify(b.width >= b.contentWidth + 4, "text has horizontal breathing room");
            verify(b.width <= 24);
            verify(b.contentHeight <= b.height);
            for (const corner of ["top-left", "top-right", "bottom-left", "bottom-right"]) {
                v.appearanceSettingsRequested({badgePosition:corner});
                verify(b.x >= 0 && b.x + b.width <= slot.width);
                verify(b.y >= 0 && b.y + b.height <= v.baseIconSize);
                compare(Qt.rect(slot.x, slot.y, slot.width, slot.height), target);
                compare(JSON.stringify(v.inputRects), input);
            }
        }
    }
}
