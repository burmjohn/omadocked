import QtQuick
import QtTest

TestCase {
    id: test
    name: "StationaryMetadata"
    when: windowShown
    visible: true
    width: 1800; height: 400
    function test_stationaryMetadata() {
        const c = Qt.createComponent("../../ui/DockView.qml");
        compare(c.status, Component.Ready, c.errorString());
        const apps = [];
        for (let i=0; i<18; ++i) apps.push({id:"fixture"+i,name:"Fixture",icon:"",running:true,active:false,windows:["key"+i],windowCount:1,pending:false,launchToken:0});
        const dock = createTemporaryObject(c,test,{applications:apps,appsManaged:true,autoHide:true,iconSize:34,transparency:46,zoomSize:140,waveWidth:25});
        dock.shelfEntered();
        verify(waitForRendering(dock));
        mouseMove(dock,dock.rowX+dock.slotSize*8.5,dock.height-30);
        wait(250);
        verify(dock.pointerInside);
        const owner = dock.hoveredIndex, pointer = dock.pointerX, slots = JSON.stringify(dock.renderedSlots);
        let orders=0, layouts=0, owners=0, replaced=0;
        dock.orderChanged.connect(function(){++orders;});
        dock.renderedSlotsChanged.connect(function(){++layouts;});
        dock.hoveredIndexChanged.connect(function(){++owners;});
        const art = findChild(dock,"art-fixture7");
        for (let n=0; n<12; ++n) {
            dock.applications = apps.map((a,i)=>Object.assign({},a,{active:i===n%2}));
            const groups = {};
            apps.forEach((a,i)=>groups[a.id]=[{key:"key"+i,title:"Owned metadata "+n,active:i===n%2,parked:false}]);
            dock.windowGroups = groups;
            wait(100);
            if (findChild(dock,"art-fixture7") !== art) ++replaced;
            compare(dock.pointerX,pointer);
            compare(dock.hoveredIndex,owner);
            compare(JSON.stringify(dock.renderedSlots),slots);
        }
        console.log("stationary updates",JSON.stringify({orders:orders,layouts:layouts,owners:owners,replaced:replaced}));
        compare(replaced,0,"metadata must retain icon delegates and animation lifetime");
        // Both frozen builds emit one structurally identical layout per metadata
        // update. Count that work, but do not confuse it with animation resets.
        compare(layouts,12);
        compare(owners,0);
        let activations = [];
        dock.activateRequested.connect(function(id){activations.push(id);});
        for (const index of [8,9]) {
            mouseMove(dock,dock.renderedSlots[index].center,dock.height-30);
            wait(180);
            const target = dock.order[dock.hoveredIndex];
            mouseClick(dock,dock.renderedSlots[dock.hoveredIndex].center,dock.height-30);
            compare(activations[activations.length-1],target);
        }
        mouseMove(test,0,300);
        wait(400);
        const idleSlots = JSON.stringify(dock.renderedSlots), idleLayouts = layouts;
        wait(400);
        compare(JSON.stringify(dock.renderedSlots),idleSlots);
        compare(layouts,idleLayouts,"no input must settle without periodic updates");
    }
}
