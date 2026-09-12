import QtQuick
import QtQuick.Controls
import QtTest
import "../../services/ConfigLogic.js" as Config

TestCase {
    id: test
    name: "AdvancedTooltip"
    when: windowShown
    visible: true
    width: 1200; height: 900
    function init() { failOnWarning(/.*/); }
    function makeDock(count) {
        const keys = [], rows = [];
        for (let n=0;n<count;n++) { keys.push("key-"+n); rows.push({key:"key-"+n,title:"Owned title "+n,parked:n===0,active:n===1}); }
        const c=Qt.createComponent("../../ui/DockView.qml"); compare(c.status,Component.Ready,c.errorString());
        const d=createTemporaryObject(c,test,{autoHide:false,reducedMotion:true,motionMode:"off",appsManaged:true,
            applications:[{id:"one",name:"One",running:true,windowCount:count,windows:keys,icon:""}],windowGroups:{one:rows}});
        verify(d); compare(d.advancedTooltips,false); d.advancedTooltips=true;
        d.tooltipDelay=20; d.shelfEntered(); d.pointerX=d.renderedSlots[2].center;
        tryCompare(d,"tooltipIndex",2); return d;
    }
    function test_privateVisibleList() {
        const d=makeDock(11), loader=findChild(d,"window-hover-loader");
        verify(loader && loader.item, "advanced list must be disposable scene content");
        compare(loader.item.rows.length,10); compare(loader.item.shownCount,8); compare(loader.item.overflowCount,2);
        verify(findChild(loader.item,"hover-title-0").text.indexOf("Owned title 1")>=0);
        const rows=d.windowGroups.one.slice(); rows[1]=Object.assign({},rows[1],{title:"Changed private title"});
        d.windowGroups={one:rows};
        verify(findChild(loader.item,"hover-title-0").text.indexOf("Changed private title")>=0);
        d.windowActionsAllowed=false; compare(loader.active,false); tryCompare(loader,"item",null);
        d.windowActionsAllowed=true; verify(loader.item);
        d.showAppNames=false; compare(loader.active,false); tryCompare(loader,"item",null);
    }
    function test_activeWindowHasOnlyOneAccentBar() {
        const d=makeDock(2), marks=findChild(d,"running-one");
        d.applications=[Object.assign({},d.applications[0],{active:true})];
        verify(findChild(marks,"window-mark-1").activeWindow);
        verify(!findChild(d,"active-one").visible,"do not duplicate the active window's accent bar");
        // A focused member hidden in overflow still needs one aggregate signal.
        const overflowDock=makeDock(7), rows=overflowDock.windowGroups.one.map((w,i)=>Object.assign({},w,{active:i===6}));
        overflowDock.applications=[Object.assign({},overflowDock.applications[0],{active:true})];
        overflowDock.windowGroups={one:rows};
        verify(findChild(overflowDock,"active-one").visible);
    }
    function test_indicatorInkFitsShelf() {
        const d=makeDock(11), marks=findChild(d,"running-one"), shelf=findChild(d,"shelf-background");
        d.applications=[Object.assign({},d.applications[0],{active:true})];
        const active=findChild(d,"active-one"), overflow=findChild(marks,"window-mark-overflow");
        for (const item of [active,overflow,findChild(marks,"window-mark-0")]) {
            const top=item.mapToItem(shelf,0,0), bottom=item.mapToItem(shelf,item.width,item.height);
            verify(top.y>=0,"indicator ink above shelf");
            verify(bottom.y<=shelf.height,"indicator ink below shelf: "+bottom.y+" > "+shelf.height);
        }
    }
    function test_indicatorsDistinguishParkedAndOverflow() {
        const d=makeDock(7), marks=findChild(d,"running-one");
        verify(marks); compare(marks.totalCount,7); compare(marks.shownCount,4); compare(marks.overflowCount,3);
        compare(findChild(marks,"window-mark-0").parked,true);
        compare(findChild(marks,"window-mark-0").color.a,0);
        compare(findChild(marks,"window-mark-1").activeWindow,true);
        verify(findChild(marks,"window-mark-1").width>findChild(marks,"window-mark-2").width);
        compare(findChild(marks,"window-mark-overflow").text,"+3");
        const keys=d.applications[0].windows.slice(0,5);
        d.applications=[Object.assign({},d.applications[0],{windows:keys,windowCount:5})];
        compare(marks.totalCount,5); compare(marks.shownCount,5); compare(marks.overflowCount,0);
        d.windowGroups={one:[{key:"stale",title:"Must not appear"},d.windowGroups.one[0],d.windowGroups.one[0]]};
        compare(marks.totalCount,1); compare(marks.parkedCount,1); compare(marks.visibleCount,0);
        d.windowGroups={}; compare(marks.totalCount,0);
        compare(findChild(d,"window-count-one").text,"5"); // existing total badge remains usable
    }
    property QtObject rememberedList: null
    function test_destructionAndReorderDoNotRetainPrivateRows() {
        const d=makeDock(3), loader=findChild(d,"window-hover-loader");
        rememberedList=loader.item; verify(rememberedList!==null);
        d.applications=[{id:"other",name:"Other",running:true,windowCount:1,windows:["other-key"]},d.applications[0]];
        compare(loader.active,false); tryCompare(test,"rememberedList",null);
        d.pointerX=d.renderedSlots[3].center; tryCompare(d,"tooltipIndex",3);
        verify(loader.item); rememberedList=loader.item;
        d.destroy(); tryCompare(test,"rememberedList",null);
        const pending=makeDock(2); pending.clearTooltip(); pending.tooltipDelay=100;
        pending.refreshTooltip(); pending.destroy(); wait(150);
    }
    function test_lifetimeAndMembership() {
        const d=makeDock(4), loader=findChild(d,"window-hover-loader");
        const rows=d.windowGroups.one.slice();
        d.windowGroups={one:rows.concat([{key:"foreign",title:"Foreign private title"},rows[1]])};
        compare(loader.item.rows.length,3);
        d.applications=[Object.assign({},d.applications[0],{windows:["key-2"]})];
        compare(loader.item.rows.length,1); compare(loader.item.rows[0].key,"key-2");
        d.windowGroups={one:[]}; tryCompare(loader,"item",null);
        d.windowGroups={one:rows}; verify(loader.item);
        d.clearTooltip(); compare(loader.active,false); tryCompare(loader,"item",null);
        d.tooltipIndex=2; verify(loader.item);
        d.surfaceSuspended=true; compare(loader.active,false); tryCompare(loader,"item",null);
        d.surfaceSuspended=false; d.tooltipIndex=2; verify(loader.item);
        d.resetSurface(); compare(loader.active,false); tryCompare(loader,"item",null);
        // Ordinary chooser remains independently usable with hover and images off.
        d.surfaceSuspended=false; d.advancedTooltips=false; d.previewsEnabled=false;
        verify(d.openWindowChooser("one")); verify(d.activeWindowChooser);
        d.windowActionsAllowed=false; compare(d.contextIndex,-1);
    }
    function test_policyAndBounds_data() {
        const rows=[];
        for (const width of [160,360,1136]) for (const height of [220,900])
            rows.push({tag:width+"-"+height,width:width,height:height});
        return rows;
    }
    function test_policyAndBounds(data) {
        const d=makeDock(12), loader=findChild(d,"window-hover-loader"),tip=findChild(d,"app-tooltip");
        d.availableWidth=data.width; d.availableHeight=data.height; wait(30);
        d.pointerX=d.renderedSlots[2].center; tryCompare(d,"tooltipIndex",2);
        verify(tip.x>=0); verify(tip.x+tip.width<=d.width+.01);
        verify(tip.y>=0); verify(tip.y+tip.height<=d.height+.01);
        compare(loader.item.shownCount,Math.min(8,Math.max(0,Math.floor((d.height-d.dockHeight)/18)-1)));
        const height=d.height, rects=JSON.stringify(d.inputRects), reservation=d.reservedHeight;
        d.clearTooltip(); compare(d.height,height); compare(JSON.stringify(d.inputRects),rects); compare(d.reservedHeight,reservation);
        d.tooltipIndex=2; d.reducedMotion=false; wait(30); d.reducedMotion=true;
        compare(tip.opacity,0); tryCompare(d,"tooltipIndex",2); compare(tip.opacity,1);
        d.showAppNames=false; compare(loader.active,false); compare(tip.opacity,0);
        d.showAppNames=true; d.tooltipDelay=250; d.refreshTooltip();
        d.surfaceSuspended=true; wait(300); compare(d.tooltipIndex,-1);
    }
    function test_toggleWheelAndKeyboard() {
        const d=makeDock(3); d.availableHeight=500; d.settingsOpen=true;
        const button=findChild(d,"advanced-tooltips-setting"); verify(button);
        button.forceActiveFocus(); wait(30);
        const viewport=findChild(d,"settings-scroll");
        tryVerify(function() { const p=button.mapToItem(viewport,0,0); return p.y>=0 && p.y+button.height<=viewport.height; });
        mouseWheel(button,button.width/2,button.height/2,0,-120); compare(d.advancedTooltips,true);
        button.forceActiveFocus(); wait(30);
        mousePress(button,button.width/2,button.height/2); verify(button.pressed);
        mouseWheel(button,button.width/2,button.height/2,0,-120);
        mouseRelease(button,button.width/2,button.height/2);
        compare(d.advancedTooltips,true); compare(button.checked,true);
        button.forceActiveFocus(); keyClick(Qt.Key_Space); compare(d.advancedTooltips,false);
        button.Accessible.pressAction(); compare(d.advancedTooltips,true);
    }
    function test_optInContract() {
        compare(Config.defaults().settings.advancedTooltips, false);
        const config = Config.defaults();
        config.settings.advancedTooltips = true;
        compare(Config.parse(JSON.stringify(config)).config.settings.advancedTooltips, true);
        for (const value of [1,"true",null,[]]) {
            config.settings.advancedTooltips = value;
            verify(Config.parse(JSON.stringify(config)).error !== "");
        }
    }
}
