pragma ComponentBehavior: Bound
import QtQuick
import "../core/WindowPresentation.js" as Presentation

// Fixed-slot accounting. Private titles never enter the indicator projection.
Item {
    id: root
    required property var app
    required property var windows
    property color foreground: "white"
    property color accent: "cyan"
    readonly property var marks: Presentation.members(Object.assign({}, app, {windows:Array.from(app.windows || [])}), Array.from(windows || []))
        .map(w => ({parked:!!w.parked, active:!!w.active && !w.parked}))
    readonly property int totalCount: marks.length
    readonly property int parkedCount: marks.filter(w => w.parked).length
    readonly property int visibleCount: totalCount - parkedCount
    readonly property int shownCount: totalCount > 5 ? 4 : totalCount
    readonly property bool hasVisibleActive: marks.slice(0, shownCount).some(mark => mark.active)
    readonly property int overflowCount: totalCount - shownCount
    enabled: false
    height: 6
    Row {
        id: row
        anchors.horizontalCenter: parent.horizontalCenter
        height: parent.height
        spacing: root.totalCount >= 5 ? 2 : 3
        scale: Math.min(1, root.width / Math.max(1, implicitWidth))
        transformOrigin: Item.Top
        Repeater {
            model: root.shownCount
            delegate: Rectangle {
                required property int index
                readonly property bool parked: root.marks[index].parked
                readonly property bool activeWindow: root.marks[index].active
                objectName: "window-mark-" + index
                width: activeWindow ? (root.totalCount >= 5 ? 9 : 12) : (root.totalCount >= 5 ? 4 : 5)
                height: activeWindow ? 4 : width
                anchors.verticalCenter: row.verticalCenter
                radius: height / 2
                color: parked ? "transparent" : activeWindow ? root.accent : Qt.alpha(root.foreground,.88)
                border.color: parked ? Qt.alpha(root.foreground,.88) : "#73000000"
                border.width: parked ? 1.5 : 1
            }
        }
        Text {
            objectName: "window-mark-overflow"
            visible: root.overflowCount > 0
            text: "+" + root.overflowCount
            textFormat: Text.PlainText
            color: root.foreground; font.pixelSize: 7; font.bold: true
            anchors.verticalCenter: row.verticalCenter
            Accessible.ignored: true
        }
    }
}
