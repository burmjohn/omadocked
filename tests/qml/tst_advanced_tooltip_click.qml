import QtQuick
import QtQuick.Controls
import QtTest

TestCase {
    id: test
    name: "AdvancedTooltipClick"
    when: windowShown
    visible: true
    width: 1200; height: 900
    SignalSpy { id: activation; signalName: "activateRequested" }
    function test_visibleTooltipCannotInterceptIcon_data() {
        const rows = [];
        for (const motion of ["off","wave","zoom"])
            for (const phase of ["dwell","enter","shown","exit","adjacent","overlap","disabled"])
                rows.push({tag:motion+"-"+phase,motion:motion,phase:phase});
        return rows;
    }
    function test_visibleTooltipCannotInterceptIcon(data) {
        const c = Qt.createComponent("../../ui/DockView.qml");
        compare(c.status, Component.Ready, c.errorString());
        const d = createTemporaryObject(c,test,{autoHide:false,motionMode:data.motion,zoomSize:200,waveWidth:5,appsManaged:true,advancedTooltips:true,
            // Singleton apps retain the passive advanced caption in production.
            windowGroups:{one:[{key:"key-0",title:"Owned private title"}]},
            applications:[{id:"one",running:true,windows:["key-0"],windowCount:1,name:"One tooltip with a long name",icon:""},{id:"two",name:"Second",icon:""}]});
        verify(waitForRendering(d)); activation.target = d; activation.clear();
        const row = findChild(d,"rowInput"), tip = findChild(d,"app-tooltip");
        mouseMove(test,1190,890);
        mouseMove(d,d.renderedSlots[1].center,d.height-25);
        const input = JSON.stringify(d.inputRects), width=d.width, height=d.height;
        if (data.phase !== "dwell") {
            tryCompare(d,"tooltipIndex",1,1000);
            if (data.phase === "enter") {
                verify(tip.visible); verify(tip.opacity > 0 && tip.opacity < 1);
            } else tryCompare(tip,"opened",true);
        }
        if (data.phase !== "dwell") {
            const loader=findChild(d,"window-hover-loader"); verify(loader.item); compare(loader.item.shownCount,1); compare(loader.item.overflowCount,0);
        }
        let index = 1;
        if (data.phase === "adjacent") {
            index = 2; mouseMove(d,d.renderedSlots[2].center,d.height-25);
            compare(d.tooltipIndex,2);
        }
        if (data.phase === "exit") {
            d.clearTooltip(); wait(30);
            verify(tip.visible); verify(tip.opacity > 0 && tip.opacity < 1);
        }
        if (data.phase === "disabled") { d.showAppNames=false; compare(tip.opacity,0); }
        if (["overlap","enter","shown","exit"].indexOf(data.phase)>=0) {
            // Force the original blocking geometry, proving this is not merely
            // fixed by moving the caption away from the click point.
            tip.y = d.height - tip.height;
            verify(d.height-25 >= tip.y && d.height-25 < tip.y+tip.height);
        }
        const x=d.renderedSlots[index].center, y=d.height-25;
        mousePress(d,x,y);
        verify(row.pressed,"visible tooltip must deliver the actual Qt press to rowInput");
        compare(d.pressedId,index===1?"one":"two");
        mouseRelease(d,x,y);
        compare(activation.count,1); compare(activation.signalArguments[0][0],index===1?"one":"two");
        compare(d.width,width); compare(d.height,height);
        if (data.motion === "off") compare(JSON.stringify(d.inputRects),input);
        compare(d.inputRects.length,2); // Only shelf + trigger; magnification may resize shelf.
        verify(!d.wantsKeyboard); compare(d.popupRect.width,0);
    }
}
