import QtQuick
import qs.Commons as Commons

// Loaded only inside the installed Omarchy host's qs import root. Do not import
// a second copy of Commons by absolute path (its singletons own theme watchers).
Item {
    readonly property real cornerRadius: Commons.Style.cornerRadius
    readonly property color background: Commons.Color.bar.background
}
