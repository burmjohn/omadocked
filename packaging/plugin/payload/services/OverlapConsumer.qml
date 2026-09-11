import QtQml

// Membership only; all clocks and requests live in the shared NativeOverlap.
QtObject {
    id: root
    property var source: null
    property string key: ""
    property bool mapped: false
    property bool enabled: false
    property var registeredSource: null
    property string registeredKey: ""
    function release(): void {
        if (registeredSource) registeredSource.setConsumer(registeredKey, false);
        registeredSource = null;
        registeredKey = "";
    }
    function sync(): void {
        const wanted = source && key && mapped && enabled;
        if (wanted && registeredSource === source && registeredKey === key) return;
        release();
        if (wanted) {
            registeredSource = source;
            registeredKey = key;
            source.setConsumer(key, true);
        }
    }
    onSourceChanged: sync()
    onKeyChanged: sync()
    onMappedChanged: sync()
    onEnabledChanged: sync()
    Component.onCompleted: sync()
    Component.onDestruction: release()
}
