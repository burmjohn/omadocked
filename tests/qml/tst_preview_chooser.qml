import QtQuick
import QtTest
import "../../ui"

TestCase {
    id: test
    name: "PreviewChooser"
    visible: true
    when: windowShown
    width: 600; height: 600
    Component { id: factory; WindowChooser { width:320; height:480 } }
    SignalSpy { id: activations; signalName: "activateRequested" }
    SignalSpy { id: closes; signalName: "closeRequested" }
    function test_pointerHoverSelectsPreviewWithoutActivation() {
        const chooser=createTemporaryObject(factory,test,{windows:[
            {key:"one",title:"Owned one",active:true},{key:"two",title:"Owned two",active:false}]});
        const target=findChild(chooser,"window-activate-two");
        verify(target);
        activations.target=chooser;activations.clear();closes.target=chooser;closes.clear();
        verify(waitForRendering(chooser));
        mouseMove(test,590,590);
        mouseMove(target,target.width/2,target.height/2);
        compare(target.hovered,true,"row must receive actual hover, independently of platform defaults");
        compare(chooser.previewKey,"two");
        const first=findChild(chooser,"window-activate-one");
        mouseMove(first,first.width/2,first.height/2);
        compare(chooser.previewKey,"one");
        mouseMove(target,target.width/2,target.height/2);
        compare(chooser.previewKey,"two");
        compare(activations.count,0);compare(closes.count,0);
    }
    function test_groupCardUsesBoundedPrivateSummaryAndSelection() {
        const rows = [];
        for (let i=0; i<8; ++i) rows.push({key:"owned-"+i,title:"Fixture "+i, active:i===2});
        const chooser = createTemporaryObject(factory, test, {windows:rows});
        const card = findChild(chooser, "window-preview-card");
        verify(card !== null, "Production chooser must instantiate PreviewCard");
        compare(card.exactCount, 8);
        verify(card.safeSummary.endsWith("+2"));
        compare(chooser.previewKey, "owned-2");
        verify(findChild(card, "preview-fallback").visible);
        chooser.handleKey(Qt.Key_Down, 0);
        compare(chooser.previewKey, "owned-3");
        chooser.windows = rows.filter(r=>r.key!=="owned-3");
        compare(chooser.previewKey, "");
        chooser.previewsEnabled = false;
        tryVerify(()=>findChild(chooser, "window-preview-card")===null);
    }
}
