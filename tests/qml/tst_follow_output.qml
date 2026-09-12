import QtQuick
import QtTest
import "../../services/ConfigLogic.js" as Config
TestCase {
    id: test; name: "FollowOutput"; visible: true; when: windowShown
    width: 1200; height: 900
    QtObject { id: left; property string name: "left" }
    QtObject { id: right; property string name: "right" }
    QtObject { id: native; property QtObject focusedMonitor: left }
    SignalSpy { id: routingChanges; signalName:"activeOutputsChanged" }
    function test_base_policy_updates_under_lock_data() {
        return [{tag:"all-reconnect", initial:["left"], next:["left","right"]},
                {tag:"selected-reconnect", initial:["left"], next:["left","right"]},
                {tag:"selected-edit", initial:["left"], next:["right"]},
                {tag:"selected-empty", initial:["left"], next:[]}];
    }
    function test_base_policy_updates_under_lock(data) {
        const c=Qt.createComponent("../../ui/OutputRouter.qml");
        const route=createTemporaryObject(c,test,{availableOutputs:["left"],baseOutputs:data.initial});
        tryCompare(route,"activeOutputs",["left"]);
        route.interactionLocked=true;
        route.availableOutputs=["left","right"]; route.baseOutputs=data.next;
        tryCompare(route,"activeOutputs",data.next);
        route.availableOutputs=[]; tryCompare(route,"activeOutputs",[]);
        route.availableOutputs=["left","right"]; tryCompare(route,"activeOutputs",data.next);
    }
    function test_toggle_during_interaction_data() {
        return [{tag:"all", base:["left","right"]}, {tag:"selected", base:["left"]}];
    }
    function test_toggle_during_interaction(data) {
        native.focusedMonitor=right;
        const c=Qt.createComponent("../../ui/OutputRouter.qml");
        const route=createTemporaryObject(c,test,{backend:native,availableOutputs:["left","right"],baseOutputs:data.base});
        tryCompare(route,"activeOutputs",data.base);
        route.interactionLocked=true; route.followActiveOutput=true;
        wait(30); compare(route.activeOutputs,data.base,"enable retains connected interacting routes until release");
        route.interactionLocked=false; tryCompare(route,"activeOutputs",["right"]);
        route.interactionLocked=true; native.focusedMonitor=left;
        wait(30); compare(route.activeOutputs,["right"]);
        route.followActiveOutput=false;
        tryCompare(route,"activeOutputs",data.base,5000,"disable immediately restores base policy despite lock");
        route.baseOutputs=[]; tryCompare(route,"activeOutputs",[]);
        route.followActiveOutput=true; tryCompare(route,"activeOutputs",["left"],5000);
        route.availableOutputs=[]; tryCompare(route,"activeOutputs",[]);
        native.focusedMonitor=null; route.availableOutputs=["right","left"];
        tryCompare(route,"activeOutputs",["left"],5000);
        native.focusedMonitor=left;
    }
    function test_native_focus_routing() {
        const c=Qt.createComponent("../../ui/OutputRouter.qml");
        compare(c.status,Component.Ready,c.errorString());
        const route=createTemporaryObject(c,test,{backend:native,availableOutputs:["left","right"],baseOutputs:["left","right"]});
        tryCompare(route,"activeOutputs",["left","right"]);
        route.followActiveOutput=true;
        tryCompare(route,"activeOutputs",["left"]);
        native.focusedMonitor=right;
        tryCompare(route,"activeOutputs",["right"]);
        route.followActiveOutput=false;
        tryCompare(route,"activeOutputs",["left","right"]);
        native.focusedMonitor=left;
    }
    function test_interaction_bridge() {
        const c=Qt.createComponent("../../ui/DockView.qml");
        compare(c.status,Component.Ready,c.errorString());
        const dock=createTemporaryObject(c,test,{autoHide:false,reducedMotion:true,applications:[{id:"one",name:"One"},{id:"two",name:"Two"}]});
        compare(dock.outputRoutingLocked,false);
        const routing=Qt.createComponent("../../ui/OutputRouter.qml");
        const route=createTemporaryObject(routing,test,{backend:native,availableOutputs:["left","right"],followActiveOutput:true});
        route.interactionLocked=Qt.binding(()=>dock.outputRoutingLocked);
        native.focusedMonitor=left; tryCompare(route,"activeOutputs",["left"]);
        dock.settingsOpen=true; compare(dock.outputRoutingLocked,true);
        native.focusedMonitor=right; wait(30); compare(route.activeOutputs,["left"]);
        dock.releaseInteractions();
        tryCompare(route,"activeOutputs",["right"]);
        dock.openWindowChooser("one");
        dock.contextIndex=2; compare(dock.outputRoutingLocked,true);
        dock.releaseInteractions();
        mouseMove(dock,dock.renderedSlots[2].center,dock.rowY+15);
        compare(dock.outputRoutingLocked,true);
        mousePress(dock,dock.renderedSlots[2].center,dock.rowY+15);
        verify(dock.pressedIndex>=0);
        mouseMove(dock,dock.renderedSlots[3].center,dock.rowY+15,20);
        verify(dock.dragActive); compare(dock.outputRoutingLocked,true);
        native.focusedMonitor=left; wait(30); compare(route.activeOutputs,["right"]);
        mouseRelease(dock,dock.renderedSlots[3].center,dock.rowY+15);
        mouseMove(test,0,0); dock.shelfExited(); dock.triggerExited();
        dock.releaseInteractions(); compare(dock.outputRoutingLocked,false);
        tryCompare(route,"activeOutputs",["left"]);
    }
    function test_freeze_settle_hotplug_and_churn() {
        const c=Qt.createComponent("../../ui/OutputRouter.qml");
        const route=createTemporaryObject(c,test,{backend:native,availableOutputs:["left","right"],baseOutputs:["left"],followActiveOutput:true});
        compare(route.interactionLocked,false);
        tryCompare(route,"activeOutputs",["left"]);
        route.interactionLocked=true; native.focusedMonitor=right;
        wait(30); compare(route.activeOutputs,["left"]);
        route.interactionLocked=false;
        tryCompare(route,"activeOutputs",["right"]);
        native.focusedMonitor=null;
        wait(30); compare(route.activeOutputs,["right"],"missing native focus retains surviving output");
        route.availableOutputs=["right","left"];
        wait(30); compare(route.activeOutputs,["right"]);
        route.interactionLocked=true;
        route.availableOutputs=["left"];
        tryCompare(route,"activeOutputs",["left"],5000);
        route.availableOutputs=[];
        tryCompare(route,"activeOutputs",[]);
        route.availableOutputs=["right","left"];
        tryCompare(route,"activeOutputs",["left"],5000);
        route.interactionLocked=false;
        routingChanges.target=route; routingChanges.clear();
        native.focusedMonitor=right; native.focusedMonitor=left;
        tryCompare(route,"activeOutputs",["left"]);
        wait(30); compare(routingChanges.count,0,"same-turn focus churn does not remap surfaces");
        routingChanges.target=null;
        route.followActiveOutput=false;
        tryCompare(route,"activeOutputs",["left"]);
        route.baseOutputs=[]; tryCompare(route,"activeOutputs",[]);
    }
    SignalSpy { id: followRequests; signalName: "followActiveOutputRequested" }
    function test_settings_committed_control_and_wheel_cancel() {
        const c=Qt.createComponent("../../ui/DockView.qml");
        const dock=createTemporaryObject(c,test,{settingsManaged:true,autoHide:false,reducedMotion:true,availableOutputs:["left","right"],monitorMode:"selected",selectedOutputs:["left"],settingsOpen:true});
        const button=findChild(dock,"follow-active-output"); verify(button!==null,"durable follow output control");
        followRequests.target=dock; followRequests.clear();
        button.forceActiveFocus();
        const scroll=findChild(dock,"settings-scroll");
        tryVerify(()=>{const p=button.mapToItem(scroll,0,0); return p.y>=0 && p.y+button.height<=scroll.height;});
        mouseClick(button,button.width/2,button.height/2);
        compare(followRequests.count,1); compare(dock.followActiveOutput,false); compare(button.checked,false);
        compare(dock.monitorMode,"selected"); compare(dock.selectedOutputs,["left"]);
        followRequests.clear();
        mousePress(button,button.width/2,button.height/2); verify(button.pressed);
        mouseWheel(button,button.width/2,button.height/2,0,-120);
        mouseRelease(button,button.width/2,button.height/2);
        compare(followRequests.count,0);
        button.forceActiveFocus(); keyClick(Qt.Key_Space); compare(followRequests.count,1);
        followRequests.target=null;
    }
    function test_preference_preserves_monitor_policy() {
        compare(Config.defaults().settings.followActiveOutput, false);
        const base = Config.settings({monitorMode:"selected", selectedOutputs:["missing","left"]});
        const on = Config.settings({followActiveOutput:true}, base);
        compare(on.monitorMode,"selected"); compare(on.selectedOutputs,base.selectedOutputs);
        const off = Config.settings({followActiveOutput:false},on);
        compare(off,base);
        let rejected=false; try { Config.settings({followActiveOutput:"true"}); } catch(e) { rejected=true; }
        verify(rejected);
    }
}
