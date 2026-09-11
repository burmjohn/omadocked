import QtQuick
import QtTest

TestCase {
    id: test
    name: "PreviewCard"
    when: windowShown
    visible: true
    width: 800
    height: 600
    property var card: null

    function makeCard(properties) {
        const component = Qt.createComponent("../../ui/PreviewCard.qml");
        compare(component.status, Component.Ready, component.errorString());
        card = component.createObject(test, properties || {});
        verify(card !== null);
        return card;
    }

    function cleanup() {
        if (card) card.destroy();
        card = null;
    }

    function test_fallbackGroupAndCountLayersStayBounded() {
        const item = makeCard({requestedWidth: 900, requestedHeight: 900,
            card: {count: 8, titleSummary: "One\nTwo\nThree\nFour\nFive\nSix\n+2"}});
        compare(item.width, 320);
        compare(item.height, 240);
        verify(item.clip);
        const still = findChild(item, "preview-still");
        const fallback = findChild(item, "preview-fallback");
        const group = findChild(item, "preview-group");
        const count = findChild(item, "preview-count");
        verify(still !== null && fallback !== null && group !== null && count !== null);
        verify(!still.visible);
        verify(fallback.visible);
        verify(group.visible);
        verify(count.visible);
        compare(count.text, "8");
        compare(group.textFormat, Text.PlainText);
        compare(group.text, "One\nTwo\nThree\nFour\nFive\nSix\n+2");
        [still, fallback, group, count].forEach(layer => {
            verify(layer.x >= 0 && layer.y >= 0);
            verify(layer.x + layer.width <= item.width);
            verify(layer.y + layer.height <= item.height);
        });
    }

    function test_pngHeaderDimensionsSummaryCountAndDecodeSizeAreBounded() {
        const hugeHeader = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAJxAAAAABCAQAAAA=";
        const item = makeCard({fixtureImageSource: hugeHeader,
            card: {count: Number.MAX_SAFE_INTEGER, titleSummary: "x".repeat(5000)}});
        verify(!item.fixtureSourceAccepted);
        compare(item.safeSummary.length, 1024);
        compare(item.exactCount, 1);
        const still = findChild(item, "preview-still");
        verify(still.sourceSize.width <= 320);
        verify(still.sourceSize.height <= 240);

        item.fixtureImageSource = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
        verify(item.fixtureSourceAccepted);
        compare(item.fixturePixelWidth, 1);
        compare(item.fixturePixelHeight, 1);
    }

    function test_onlyInjectedDataPngFixtureCanPopulateStill() {
        const fixture = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
        const item = makeCard({fixtureImageSource: fixture, card: {count: 1, titleSummary: "Fixture"}});
        const still = findChild(item, "preview-still");
        const fallback = findChild(item, "preview-fallback");
        verify(item.fixtureSourceAccepted);
        compare(still.source.toString(), fixture);
        tryCompare(still, "status", Image.Ready);
        verify(still.visible);
        verify(!fallback.visible);
        verify(!findChild(item, "preview-group").visible);
        verify(!findChild(item, "preview-count").visible);
        item.fixtureImageSource = "file:///tmp/private.png";
        verify(!item.fixtureSourceAccepted);
        compare(still.source.toString(), "");
        verify(fallback.visible);
        item.fixtureImageSource = "https://example.invalid/private.png";
        verify(!item.fixtureSourceAccepted);
        compare(still.source.toString(), "");
    }
}
