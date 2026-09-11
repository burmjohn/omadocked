import QtQuick
import QtQuick.Controls
import QtTest

TestCase {
    id: test
    name: "TooltipHoverOverlap"
    visible: true
    when: windowShown
    width: 1500
    height: 800

    // Desktop styles enable Control hovering; offscreen defaults need not.
    Control {
        id: desktop
        anchors.fill: parent
        hoverEnabled: true
    }

    function test_hoverThroughCaption_data() {
        return [{tag: "settings", index: 0}, {tag: "application", index: 1}];
    }

    function test_hoverThroughCaption(data) {
        const component = Qt.createComponent("../../ui/DockView.qml");
        compare(component.status, Component.Ready, component.errorString());
        const dock = createTemporaryObject(component, desktop, {
            autoHide: true, iconSize: 34, zoomSize: 140, waveWidth: 25,
            appsManaged: true, applications: [{id: "one", name: "Fixture application", icon: ""}]
        });
        verify(waitForRendering(dock));
        mouseMove(dock, dock.renderedSlots[data.index].center, dock.height - 30);
        const tip = findChild(dock, "app-tooltip");
        tryCompare(tip, "opened", true, 1500);
        const x = dock.renderedSlots[data.index].center;
        const y = tip.y + tip.height / 2;
        verify(y >= dock.shelfRect.y && y < dock.shelfRect.y + dock.shelfRect.height);
        for (let i = 0; i < 20; ++i) {
            // Real pointer motion re-runs hover delivery over the now-visible caption.
            mouseMove(dock, x + i % 2, y, 20);
            compare(dock.pointerInside, true, "caption must not steal row hover");
            compare(dock.visibilityState, "shown");
            compare(dock.tooltipIndex, data.index);
        }
    }
}
