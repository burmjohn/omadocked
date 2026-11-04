import QtQuick
import QtTest
import "../../ui"

TestCase {
    id: test
    name: "IconFallback"
    when: windowShown
    visible: true
    width: 900; height: 600
    Component { id: viewComponent; DockView { autoHide: false; iconSize: 28; zoomSize: 140; waveWidth: 25 } }
    function test_fallback_follows_art_without_changing_targets() {
        const v = createTemporaryObject(viewComponent, test, {applications: [{id:"window:9", name:"Notes", icon:""}]});
        const art = findChild(v, "art-window:9"), fallback = findChild(v, "fallback-window:9");
        compare(fallback.width, art.width);
        compare(fallback.height, art.height);
        const index = v.order.indexOf("window:9");
        v.pointerX = v.renderedSlots[index].center;
        wait(250);
        verify(art.scale > 1);
        compare(fallback.scale, art.scale);
        compare(fallback.y, art.y);
        compare(fallback.transformOrigin, art.transformOrigin);
        verify(findChild(fallback, "fallback-background") !== null);
        const input = JSON.stringify(v.inputRects);
        const target = Qt.rect(art.parent.x, art.parent.y, art.parent.width, art.parent.height);
        art.source = "data:image/svg+xml," + encodeURIComponent('<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28"><rect width="28" height="28" fill="steelblue"/></svg>');
        tryCompare(art, "status", Image.Ready);
        compare(fallback.visible, false);
        compare(JSON.stringify(v.inputRects), input);
        compare(Qt.rect(art.parent.x, art.parent.y, art.parent.width, art.parent.height), target);
    }
    function test_failed_image_and_metadata_refresh() {
        const v = createTemporaryObject(viewComponent, test, {applications:[{id:"window:Chatgpt", name:"Chatgpt", icon:""}]});
        const art = findChild(v, "art-window:Chatgpt");
        ignoreWarning(/.*Cannot open:.*owned-missing-icon-fixture.svg/);
        art.source = Qt.resolvedUrl("owned-missing-icon-fixture.svg");
        tryCompare(art, "status", Image.Error);
        compare(findChild(v, "fallback-window:Chatgpt").text, "C");
        verify(findChild(v, "fallback-window:Chatgpt").visible);
        v.applications = [{id:"window:Chatgpt", name:"T3 Code", icon:""}];
        compare(findChild(v, "fallback-window:Chatgpt").text, "T");
        v.applications = [{id:"window:Chatgpt", name:"window:Chatgpt", icon:""}];
        compare(findChild(v, "fallback-window:Chatgpt").text, "◇");
    }
    function test_display_name_not_window_identity() {
        const v = createTemporaryObject(viewComponent, test, {applications: [
            {id: "window:42", name: "  Firefox", icon: ""},
            {id: "window:43", name: "Éditeur", icon: ""},
            {id: "window:44", name: "", icon: ""}
        ]});
        compare(findChild(v, "fallback-window:42").text, "F");
        compare(findChild(v, "fallback-window:43").text, "É");
        compare(findChild(v, "fallback-window:44").text, "◇");
        const fallback = findChild(v, "fallback-window:42");
        verify(fallback.visible);
        compare(fallback.textFormat, Text.PlainText);
        const slot = findChild(v, "item-window:42");
        compare(slot.Accessible.name, "  Firefox");
    }
}
