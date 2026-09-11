import QtQuick
import QtTest
import "../../services/ConfigLogic.js" as Config
import "../../core/DockLogic.js" as Logic

TestCase {
    id: test
    name: "Magnification"
    when: windowShown
    visible: true
    width: 1200; height: 1000

    function test_controlsLabelsModesAndResponsiveFocus() {
        const component = Qt.createComponent("../../ui/DockView.qml");
        const dock = createTemporaryObject(component,test,{autoHide:false});
        dock.settingsOpen = true;
        const zoom = findChild(dock,"zoom-size-slider"), wave = findChild(dock,"wave-width-slider");
        compare(findChild(dock,"zoom-size-value").text,"1.45×");
        compare(findChild(dock,"wave-width-value").text,"2.5 icons / side");
        for (const outputWidth of [360,900,1366]) {
            dock.availableWidth = outputWidth; dock.availableHeight = 600;
            for (const slider of [zoom,wave]) {
                slider.forceActiveFocus();
                const scroll = findChild(dock,"settings-scroll");
                tryVerify(function() {
                    const p = slider.mapToItem(scroll,0,0);
                    return p.x >= 0 && p.x+slider.width <= scroll.width && p.y >= 0 && p.y+slider.height <= scroll.height;
                });
                const value = slider.value;
                mouseWheel(slider,slider.width/2,slider.height/2,0,-120); wait(20);
                compare(slider.value,value,"wheel scrolls, never edits magnification");
            }
        }
        dock.motionMode = "zoom"; verify(zoom.enabled); verify(!wave.enabled);
        dock.motionMode = "off"; verify(!zoom.enabled); verify(!wave.enabled);
        dock.motionMode = "wave"; dock.reducedMotion = true; verify(!zoom.enabled); verify(!wave.enabled);
        compare(dock.zoomSize,145); compare(dock.waveWidth,25);
    }

    function test_stationaryOwnedPointerDoesNotOscillateAtMaximum() {
        const component = Qt.createComponent("../../ui/DockView.qml");
        const apps = [];
        for (let i=0; i<6; ++i) apps.push({id:"fixture"+i,name:"Fixture",icon:""});
        const dock = createTemporaryObject(component,test,{applications:apps,autoHide:false,zoomSize:200,waveWidth:50,iconSize:72,availableWidth:800});
        verify(waitForRendering(dock));
        for (const mode of ["wave","zoom"]) {
            dock.motionMode = mode;
            for (const index of [0,3,6,0]) {
                const x = dock.rowX + dock.slotSize*(index+0.5);
                mouseMove(dock,x,dock.height-30); wait(180);
                verify(dock.pointerInside); verify(dock.pointerX >= 0);
                const pointer = dock.pointerX, slots = JSON.stringify(dock.renderedSlots), width = dock.width, height = dock.height;
                wait(200);
                compare(dock.pointerX,pointer); compare(JSON.stringify(dock.renderedSlots),slots);
                compare(dock.width,width); compare(dock.height,height);
            }
        }
    }

    function test_zoomAndWaveFitActualLayout() {
        const component = Qt.createComponent("../../ui/DockView.qml");
        compare(component.status, Component.Ready, component.errorString());
        const apps = [];
        for (let i=0; i<20; ++i) apps.push({id:"fixture"+i,name:"Fixture",icon:""});
        const dock = createTemporaryObject(component, test, {applications:apps,autoHide:false});
        verify(dock.zoomSize !== undefined, "zoom size is a view setting");
        dock.zoomSize = 200; dock.iconSize = 72;
        for (const outputWidth of [360,1136]) for (const wave of [10,15,25,50]) {
            dock.availableWidth = outputWidth; dock.waveWidth = wave;
            for (const mode of ["wave","zoom","off"]) {
                dock.motionMode = mode;
                const width = dock.width, height = dock.height, origin = dock.rowX;
                for (const pos of [0,0.25,0.5,1,5,10,20,20.5]) {
                    dock.pointerX = dock.rowX + dock.slotSize * pos;
                    wait(120);
                    compare(dock.width,width); compare(dock.height,height); compare(dock.rowX,origin);
                    verify(dock.shelfRect.x >= -0.01);
                    verify(dock.shelfRect.x+dock.shelfRect.width <= dock.width+0.01);
                    for (let i=0; i<dock.order.length; ++i) {
                        const art = findChild(dock,"art-"+dock.order[i]);
                        const top = art.mapToItem(dock,0,0), bottom = art.mapToItem(dock,art.width,art.height);
                        verify(top.x >= dock.shelfRect.x-0.01 && bottom.x <= dock.shelfRect.x+dock.shelfRect.width+0.01);
                        verify(top.y >= dock.shelfRect.y-0.01 && bottom.y <= dock.shelfRect.y+dock.shelfRect.height+0.01);
                        verify(top.y >= 0 && bottom.y <= dock.height);
                        verify(art.sourceSize.width >= Math.ceil(72*dock.peakScale));
                    }
                }
            }
        }
    }

    function test_scaleParametersPreserveDefaultsAndStaticModes() {
        compare(Logic.scaleAt(0,24,0,48,"wave",false,false,2,5), 2);
        compare(Logic.scaleAt(0,24,0,48,"zoom",false,false,2,5), 2);
        verify(Logic.scaleAt(3,24,0,48,"wave",false,false,2,5) > 1);
        compare(Logic.scaleAt(3,24,0,48,"wave",false,false,2,1), 1);
        for (const mode of ["wave","zoom","off"]) {
            compare(Logic.scaleAt(0,24,0,48,mode,true,false,2,5), 1);
            compare(Logic.scaleAt(0,24,0,48,mode,false,true,2,5), 1);
            compare(Logic.scaleAt(0,-1,0,48,mode,false,false,2,5), 1);
            compare(Logic.scaleAt(0,24,0,48,mode,false,false,1,5), 1);
        }
        compare(Logic.scaleAt(0,24,0,48,"off",false,false,2,5), 1);
        for (let p=0; p<400; p+=3) {
            compare(Logic.scaleAt(2,p,0,48,"wave",false,false), Logic.scaleAt(2,p,0,48,"wave",false,false,1.45,2.5));
        }
    }

    function test_typedSettingsAndMigration() {
        for (const text of ['{"version":1,"pins":["fixture"]}', JSON.stringify({version:2,pins:["fixture"],launchers:[],settings:{iconSize:50,transparency:46,autoHide:true,monitorMode:"selected",selectedOutputs:["fixture-output"]},overrides:{}})]) {
            const result = Config.parse(text);
            compare(result.error, "");
            compare(result.config.settings.zoomSize, 145);
            compare(result.config.settings.waveWidth, 25);
            compare(result.config.pins[0], "fixture");
        }
        for (const zoom of [100,145,200]) for (const wave of [10,25,50]) {
            const c = Config.defaults();
            c.settings.zoomSize = zoom; c.settings.waveWidth = wave;
            const result = Config.parse(JSON.stringify(c));
            compare(result.error, "");
            compare(result.config.settings.zoomSize, zoom);
            compare(result.config.settings.waveWidth, wave);
        }
        for (const patch of [{zoomSize:99},{zoomSize:201},{zoomSize:145.5},{zoomSize:"145"},{zoomSize:true},{zoomSize:null},
                             {waveWidth:5},{waveWidth:55},{waveWidth:26},{waveWidth:"25"},{waveWidth:false},{waveWidth:null}]) {
            let rejected = false;
            try { Config.settings(patch); } catch (_) { rejected = true; }
            verify(rejected, JSON.stringify(patch));
        }
        for (const value of [NaN,Infinity,-Infinity]) {
            for (const key of ["zoomSize","waveWidth"]) {
                let rejected = false;
                const patch = {}; patch[key] = value;
                try { Config.settings(patch); } catch (_) { rejected = true; }
                verify(rejected);
            }
        }
    }
}
