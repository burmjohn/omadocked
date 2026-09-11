pragma ComponentBehavior: Bound
import QtQuick
import "../core/WindowPresentation.js" as Presentation

// Private, disposable text presentation. No actions, capture, focus or handlers.
Column {
    id: root
    required property var app
    required property var windows
    property string selectedKey: ""
    property color foreground: "white"
    property color accent: "cyan"
    property real maximumHeight: 180
    readonly property var rows: Presentation.members(Object.assign({}, app, {windows:Array.from(app.windows || [])}), Array.from(windows || [])).filter(w => !w.parked)
    readonly property int capacity: Math.max(0, Math.min(8, Math.floor(maximumHeight / 18) - 1))
    readonly property int shownCount: Math.min(capacity, rows.length)
    readonly property int overflowCount: rows.length - shownCount
    enabled: false
    focus: false
    spacing: 0
    width: 298
    Repeater {
        model: root.shownCount
        delegate: Text {
            required property int index
            readonly property var row: root.rows[index]
            readonly property bool selected: row.key === root.selectedKey
            objectName: "hover-title-" + index
            width: root.width; height: 18
            text: (selected ? "› " : "• ") + (String(row.title || root.app.name || "Untitled window").replace(/[\r\n\t]/g, " "))
            textFormat: Text.PlainText
            elide: Text.ElideRight
            maximumLineCount: 1
            font.pixelSize: 12
            font.bold: selected || !!row.active
            color: selected ? root.accent : Qt.alpha(root.foreground, row.active ? 1 : .8)
            Accessible.ignored: true
        }
    }
    Text {
        objectName: "hover-overflow"
        visible: root.overflowCount > 0
        width: root.width; height: visible ? 18 : 0
        text: "+" + root.overflowCount + " more"
        textFormat: Text.PlainText; elide: Text.ElideRight
        color: Qt.alpha(root.foreground, .6); font.pixelSize: 11
        Accessible.ignored: true
    }
}
