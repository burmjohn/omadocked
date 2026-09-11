pragma ComponentBehavior: Bound
import QtQuick

// Presentation only; the disposable native adapter owns capture and private pixels.
Item {
    id: preview
    property var card: ({count: 1, titleSummary: "Untitled window"})
    property real requestedWidth: 280
    property real requestedHeight: 180
    property url fixtureImageSource: ""
    property Component contentComponent
    readonly property var contentItem: contentLoader.item
    function pngInfo(value) {
        const prefix = "data:image/png;base64,";
        if (typeof value !== "string" || !value.startsWith(prefix) || value.length > 2097174)
            return {valid: false, width: 0, height: 0};
        const encoded = value.slice(prefix.length);
        if (encoded.length < 32 || encoded.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(encoded))
            return {valid: false, width: 0, height: 0};
        const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
        const bytes = [];
        let bits = 0;
        let bitCount = 0;
        for (let i = 0; i < encoded.length && bytes.length < 24; ++i) {
            if (encoded[i] === "=") break;
            const digit = alphabet.indexOf(encoded[i]);
            if (digit < 0) return {valid: false, width: 0, height: 0};
            bits = bits * 64 + digit;
            bitCount += 6;
            if (bitCount >= 8) {
                bitCount -= 8;
                bytes.push(Math.floor(bits / Math.pow(2, bitCount)) & 255);
                bits %= Math.pow(2, bitCount);
            }
        }
        const signature = [137, 80, 78, 71, 13, 10, 26, 10];
        if (bytes.length < 24 || signature.some(function(byte, index) { return bytes[index] !== byte; })
                || bytes[8] !== 0 || bytes[9] !== 0 || bytes[10] !== 0 || bytes[11] !== 13
                || bytes[12] !== 73 || bytes[13] !== 72 || bytes[14] !== 68 || bytes[15] !== 82)
            return {valid: false, width: 0, height: 0};
        const width = bytes[16] * 16777216 + bytes[17] * 65536 + bytes[18] * 256 + bytes[19];
        const height = bytes[20] * 16777216 + bytes[21] * 65536 + bytes[22] * 256 + bytes[23];
        const valid = width > 0 && height > 0 && width <= 2048 && height <= 2048
            && width * height <= 4194304;
        return {valid: valid, width: valid ? width : 0, height: valid ? height : 0};
    }
    readonly property var fixturePngInfo: pngInfo(fixtureImageSource.toString())
    readonly property bool fixtureSourceAccepted: fixturePngInfo.valid
    readonly property int fixturePixelWidth: fixturePngInfo.width
    readonly property int fixturePixelHeight: fixturePngInfo.height
    readonly property int exactCount: card && Number.isSafeInteger(card.count) && card.count > 0 && card.count <= 512 ? card.count : 1
    readonly property string safeSummary: card && typeof card.titleSummary === "string"
        ? card.titleSummary.slice(0, 1024) : "Untitled window"
    width: Math.max(160, Math.min(320, requestedWidth))
    height: Math.max(120, Math.min(240, requestedHeight))
    clip: true

    Rectangle {
        anchors.fill: parent
        radius: 12
        color: "#242833"
        border.width: 1
        border.color: "#596171"
    }

    Image {
        id: still
        objectName: "preview-still"
        anchors.fill: parent
        source: preview.fixtureSourceAccepted ? preview.fixtureImageSource : ""
        sourceSize: Qt.size(Math.ceil(preview.width), Math.ceil(preview.height))
        fillMode: Image.PreserveAspectCrop
        asynchronous: false
        cache: false
        visible: status === Image.Ready && source.toString().length > 0
    }

    Loader {
        id: contentLoader
        anchors.fill: parent
        sourceComponent: preview.contentComponent
    }

    Rectangle {
        id: fallback
        objectName: "preview-fallback"
        anchors.fill: parent
        color: "#242833"
        visible: !still.visible && !(preview.contentItem && preview.contentItem.hasContent)
        Text {
            anchors.centerIn: parent
            width: parent.width - 24
            text: "Preview unavailable"
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: "#c9ced8"
        }
    }

    Text {
        id: group
        objectName: "preview-group"
        visible: preview.exactCount > 1
        x: 12
        y: preview.height / 2
        width: preview.width - 24
        height: preview.height / 2 - 12
        text: preview.safeSummary
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        maximumLineCount: 7
        color: "#f2f4f8"
        verticalAlignment: Text.AlignBottom
    }

    Text {
        id: count
        objectName: "preview-count"
        visible: preview.exactCount > 1
        x: preview.width - width - 8
        y: 8
        width: 36
        height: 24
        text: String(preview.exactCount)
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        color: "white"
        font.bold: true
        Rectangle {
            anchors.fill: parent
            z: -1
            radius: 12
            color: "#cc1c2029"
        }
    }
}
