import QtQuick
import QtTest
import "../../core/ParkingLogic.js" as Parking
import "../../ui"
import "../../core/AttentionLogic.js" as Attention
import "../../core/WindowLogic.js" as Windows
import "../../services/FolderLogic.js" as Folder

TestCase {
    name: "AstraAudit"
    when: windowShown
    width: 800; height: 800
    QtObject { id: owned }
    Component { id: dockComponent; DockView { width: 700; height: 700 } }
    function test_native_address_contract_must_correlate() {
        // Quickshell v0.3.1 addressStr() is QString::number(mAddress,16), no prefix.
        const row = {wayland:owned, address:"abc", lastIpcObject:{address:"0xabc",pid:77,
            class:"Fixture",initialClass:"Fixture",xwayland:false,workspace:{name:"1"},
            monitor:0,floating:false,at:[0,0],size:[300,200]}};
        verify(Parking.correlate(owned,[owned],[row]) !== null,
               "Real Quickshell address format must not reject every native window");
    }
    function test_failed_parking_is_not_a_parked_window() {
        const apps=[{id:"app",kind:"application",windows:["k"],name:"Fixture"}];
        const windows=[{key:"k",title:"Fixture",active:true}];
        const group=Windows.groups(apps,windows,[{key:"k",state:"parking",sequence:1}]);
        verify(group.app[0].parked !== true,"Unverified failed move cannot be shown as parked");
    }
    function test_overflow_baseline_must_not_replay_history() {
        const rows=[];
        for(let i=0;i<1025;++i) rows.push({id:"n"+i,timestampMs:i,appId:"app",pwaId:"",browserId:""});
        const state=Attention.beginGeneration(Attention.newState(),"generation",rows);
        verify(state.overflow);
        const app={id:"app",notificationIds:["app"],pwaIds:[],browserIds:[],focused:false,launchPending:false,openedAtMs:0,windows:[]};
        const result=Attention.processNotifications(state,"generation",[rows[0]],[app],
            {enabled:true,soundEnabled:true,soundName:"bell",dnd:false},10000);
        compare(result.matches,[],"Lost baseline must fail closed rather than replay an old notification");
    }
    function test_folder_scanner_unicode_order_is_accepted() {
        const xhr=new XMLHttpRequest();xhr.open("GET",Qt.resolvedUrl("../fixtures/folder-unicode.json"),false);xhr.send();
        const fixture=JSON.parse(xhr.responseText);
        let error="";
        try { Folder.normalize(fixture.result,fixture.request); } catch(e) { error=e.message; }
        compare(error,"","Actual Python scanner output must satisfy its QML consumer");
    }
    function test_old_save_receipt_must_not_close_reopened_editor() {
        const dock=createTemporaryObject(dockComponent,this);
        verify(dock.openItemEditor(""));
        dock.launcherSaveAccepted(41);
        dock.closeItemEditor();
        verify(dock.openItemEditor(""));
        dock.launcherSaveResult(41,true);
        verify(dock.editorOpen,"Receipt for canceled editor must not dismiss a fresh draft");
    }
}
