import QtQuick
import QtTest
import "../../ui"
import "../../services/ConfigLogic.js" as Config

TestCase {
    id: test
    name: "PreviewIntegration"
    when: windowShown
    visible: true
    width:700; height:700
    property int created:0
    property int disposed:0
    property int peakActive:0
    property bool deliverFrames:true
    function cleanup() { deliverFrames=true; }
    QtObject { id: ownedSource }
    QtObject {
        id: controller
        property string previewLockState:"unlocked"
        property QtObject previewCaptureOwner:null
        property var windowGroups: ({app:[{key:"owned", title:"Owned fixture", active:true}]})
        function previewTarget(appId, key) { return appId==="app" && key==="owned" ? ownedSource : null; }
    }
    Component {
        id: driver
        Rectangle {
            property var captureSource:null
            property bool live:false
            property bool paintCursor:false
            property size constraintSize
            readonly property bool hasContent:captureSource!==null && test.deliverFrames
            signal stopped()
            color:"#8844cc"
            Component.onCompleted: { test.created++; test.peakActive=Math.max(test.peakActive,test.created-test.disposed); }
            Component.onDestruction: test.disposed++
        }
    }
    Component { id: viewFactory; DockView { appsManaged:true; autoHide:false; reducedMotion:true; motionMode:"off"; applications:[{id:"app",name:"Owned",running:true,kind:"application",windows:["owned"]}] } }
    function test_unavailableCaptureRetainsHostedTextActions_data() {
        return [{tag:"previews-on",enabled:true},{tag:"previews-off",enabled:false}];
    }
    function test_unavailableCaptureRetainsHostedTextActions(data) {
        controller.previewLockState="unlocked"; created=0;
        const view=createTemporaryObject(viewFactory,test,{windowGroups:controller.windowGroups,previewsEnabled:data.enabled});
        const component=Qt.createComponent("../../services/PreviewIntegration.qml");
        const adapter=createTemporaryObject(component,test,{view:view,controller:controller,mapped:true});
        verify(view.openWindowChooser("app")); wait(50);
        verify(findChild(view,"window-activate-owned")!==null);
        verify(findChild(view,"window-close-owned")!==null);
        verify(findChild(view,"windows-previous")!==null);
        verify(findChild(view,"windows-next")!==null);
        compare(created,0);
        controller.previewLockState="unknown";
        verify(view.windowChooserOpen, "Unknown capture authority must not remove ordinary text actions");
        compare(findChild(view,"window-activate-owned").text,"Owned fixture");
        compare(adapter.eligible,false);
        controller.previewLockState="locked";
        tryCompare(view,"activeWindowChooser",null);
        verify(!view.openWindowChooser("app"));
    }
    SignalSpy { id: activateSpy; signalName:"activateWindowRequested" }
    SignalSpy { id: closeSpy; signalName:"closeWindowRequested" }
    function test_unknownAuthorityKeepsTitledActionsWithoutCapture_data() {
        return [{tag:"previews-on",enabled:true},{tag:"previews-off",enabled:false}];
    }
    function test_unknownAuthorityKeepsTitledActionsWithoutCapture(data) {
        controller.previewLockState="unknown"; created=0;
        const view=createTemporaryObject(viewFactory,test,{windowGroups:controller.windowGroups,previewsEnabled:data.enabled});
        const component=Qt.createComponent("../../services/PreviewIntegration.qml");
        const adapter=createTemporaryObject(component,test,{view:view,controller:controller,mapped:true,driverComponent:driver});
        activateSpy.target=view; activateSpy.clear(); closeSpy.target=view; closeSpy.clear();
        verify(view.openWindowChooser("app")); wait(20);
        const close=findChild(view,"window-close-owned");
        const activate=findChild(view,"window-activate-owned");
        compare(activate.text,"Owned fixture");
        mousePress(close,close.width/2,close.height/2); verify(close.pressed);
        mouseRelease(close,close.width/2,close.height/2);
        compare(closeSpy.count,1); compare(closeSpy.signalArguments[0][1],"owned");
        mouseClick(activate);
        compare(activateSpy.count,1); compare(activateSpy.signalArguments[0][1],"owned");
        wait(30); compare(created,0); compare(adapter.privacyAllowed,false);
        compare(controller.previewLockState,"unknown");
        activateSpy.target=null; closeSpy.target=null;
    }
    function test_twoSurfacesCaptureOnlyLatestSelectionWithoutRetry() {
        controller.previewLockState="unlocked"; created=0; disposed=0; peakActive=0; deliverFrames=false;
        const component=Qt.createComponent("../../services/PreviewIntegration.qml");
        const first=createTemporaryObject(viewFactory,test,{windowGroups:controller.windowGroups});
        const a=createTemporaryObject(component,test,{view:first,controller:controller,mapped:true,driverComponent:driver});
        verify(first.openWindowChooser("app")); tryCompare(test,"created",1);
        const second=createTemporaryObject(viewFactory,test,{windowGroups:controller.windowGroups});
        const b=createTemporaryObject(component,test,{view:second,controller:controller,mapped:true,driverComponent:driver});
        verify(second.openWindowChooser("app")); tryCompare(test,"created",2);
        compare(peakActive,1,"Previous driver is disposed before another surface attaches");
        verify(first.windowChooserOpen); compare(findChild(first,"window-activate-owned").text,"Owned fixture");
        tryCompare(test,"disposed",2,2000);
        wait(1100); compare(created,2,"No background retry on either surface");
        b.mapped=false; wait(100); compare(created,2);
    }
    function test_livePreferenceStillUsesOneShotCapture() {
        controller.previewLockState="unlocked"; created=0; disposed=0;
        const view=createTemporaryObject(viewFactory,test,{windowGroups:controller.windowGroups,livePreviews:true});
        const component=Qt.createComponent("../../services/PreviewIntegration.qml");
        createTemporaryObject(component,test,{view:view,controller:controller,mapped:true,driverComponent:driver});
        verify(view.openWindowChooser("app"));
        tryCompare(test,"created",1);
        tryCompare(test,"disposed",1);
        wait(100); compare(created,1);
    }
    function test_liveControlTruthfullyMarksDeferredBehavior() {
        const view=createTemporaryObject(viewFactory,test,{livePreviews:true});
        view.settingsOpen=true;
        compare(findChild(view,"live-previews"), null);
        const still=findChild(view,"previews-enabled");
        verify(still !== null);
        verify(still.enabled);
    }
    function test_settingsRoundTripAndRejectNonBoolean() {
        const s = Config.defaults();
        compare(s.settings.previewsEnabled,true);
        compare(s.settings.livePreviews,false);
        s.settings=Config.settings({previewsEnabled:false,livePreviews:true});
        const parsed=Config.parse(JSON.stringify(s));
        compare(parsed.error,"");
        compare(parsed.config.settings.previewsEnabled,false);
        compare(parsed.config.settings.livePreviews,true);
        verify(Config.parse(JSON.stringify(Object.assign({},s,{settings:{livePreviews:"true"}}))).error!=="");
    }
    function test_productionViewAdapterOwnsAndDisposesOnLockHide() {
        created=0; disposed=0; controller.previewLockState="unlocked";
        const view=createTemporaryObject(viewFactory,test,{windowGroups:controller.windowGroups});
        const component=Qt.createComponent("../../services/PreviewIntegration.qml");
        compare(component.status,Component.Ready,component.errorString());
        const adapter=createTemporaryObject(component,test,{view:view,controller:controller,mapped:true,driverComponent:driver});
        verify(adapter);
        verify(view.openWindowChooser("app"));
        tryVerify(()=>created===1);
        tryVerify(()=>disposed===1);
        controller.previewLockState="locked";
        compare(view.windowChooserOpen,false);
        tryVerify(()=>view.activeWindowChooser===null);
        wait(100); compare(created,1);
        controller.previewLockState="unknown";
        verify(view.openWindowChooser("app"));
        compare(adapter.eligible,false);
        view.openContext(view.order.indexOf("app"));
        const unavailable=findChild(view,"context-windows");
        verify(unavailable.enabled);
        compare(unavailable.text,"Windows…");
        controller.previewLockState="unlocked";
        verify(view.openWindowChooser("app"));
        tryCompare(test,"created",2);
        adapter.mapped=false;
        tryCompare(test,"disposed",2);
        compare(view.windowChooserOpen,false);
    }
}
