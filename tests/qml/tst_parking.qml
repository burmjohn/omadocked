import QtQuick
import QtTest
import "../../core/ParkingLogic.js" as Parking

TestCase {
    name: "ParkingLogic"
    QtObject { id: owned }
    QtObject { id: stale }
    function row(handle, address, klass) {
        return {wayland:handle,address:address.slice(2),lastIpcObject:{address:address,pid:77,class:klass,initialClass:klass,
            xwayland:false,workspace:{name:"3"},monitor:1,floating:true,at:[10,20],size:[300,200]}};
    }
    // Native ObjectModel.values is QObjectList, not a JavaScript Array.
    property list<QtObject> nativeWaylandRows: [owned]
    property list<QtObject> nativeHyprlandRows: [
        QtObject {
            property QtObject wayland: owned
            property string address: "abc"
            property var lastIpcObject: ({address:"0xabc",pid:77,class:"Owned",initialClass:"Owned",
                stableId:"18000009",xwayland:false,workspace:{name:"3"},monitor:1,
                floating:true,at:[10,20],size:[300,200]})
        }
    ]
    function test_nativeQObjectListsPreserveExactParkingAndRestoreIdentity() {
        const result = Parking.correlate(owned, nativeWaylandRows, nativeHyprlandRows);
        verify(result !== null, "native collection must correlate the exact window before parking");
        compare(result.identity.stableId, "18000009");
        compare(Parking.identity(owned, nativeWaylandRows, nativeHyprlandRows), result.identity);
        compare(Parking.correlate(stale, nativeWaylandRows, nativeHyprlandRows), null);
        const top = nativeHyprlandRows[0];
        const saved = top.lastIpcObject;
        try {
            top.lastIpcObject = {};
            compare(Parking.correlate(owned, nativeWaylandRows, nativeHyprlandRows), null);
            compare(Parking.identity(owned, nativeWaylandRows, nativeHyprlandRows), null);
            top.lastIpcObject = Object.assign({}, saved, {address:"0xdef"});
            compare(Parking.correlate(owned, nativeWaylandRows, nativeHyprlandRows), null);
            top.lastIpcObject = Object.assign({}, saved, {workspace:{name:"special:Omadocked"}});
            compare(Parking.correlate(owned, nativeWaylandRows, nativeHyprlandRows), null);
            compare(Parking.identity(owned, nativeWaylandRows, nativeHyprlandRows), result.identity);
        } finally { top.lastIpcObject = saved; }
    }
    property list<int> nativeAt: [10, 20]
    property list<int> nativeSize: [300, 200]
    function test_nativeGeometrySequencesRetainValidatedOrigin() {
        const top = row(owned, "0xabc", "Owned");
        top.lastIpcObject.at = nativeAt;
        top.lastIpcObject.size = nativeSize;
        const result = Parking.correlate(owned, [owned], [top]);
        verify(result !== null, "native IPC geometry sequences must retain the exact origin");
        compare(result.origin.at, [10, 20]);
        compare(result.origin.size, [300, 200]);
        top.lastIpcObject.size = [-1, 200];
        compare(Parking.correlate(owned, [owned], [top]), null);
    }
    function test_correlatesExactQObjectAndFullHyprlandIdentity() {
        const result=Parking.correlate(owned,[owned],[row(owned,"0xabc","Owned")]);
        compare(result.identity,{address:"0xabc",pid:77,class:"Owned",initialClass:"Owned",xwayland:false});
        compare(result.origin,{workspace:"3",monitor:1,floating:true,at:[10,20],size:[300,200]});
        compare(Parking.correlate(stale,[owned],[row(owned,"0xabc","Owned")]),null);
        compare(Parking.correlate(owned,[owned],[row(owned,"0xabc","Owned"),row(owned,"0xdef","Owned")]),null);
    }
    function test_pidOnlyOrMalformedOrSpecialWorkspaceNeverCorrelates() {
        const good=row(owned,"0xabc","Owned");
        for (const patch of [{class:""},{initialClass:""},{xwayland:null},{address:"0xdef"},
                              {workspace:{name:"special:Omadocked"}},{at:[1]},{size:[1]}]) {
            const changed=Object.assign({},good.lastIpcObject,patch);
            compare(Parking.correlate(owned,[owned],[Object.assign({},good,{lastIpcObject:changed})]),null,JSON.stringify(patch));
        }
        compare(Parking.correlate(owned,[owned],[{wayland:owned,address:"0xabc",lastIpcObject:{pid:77}}]),null);
    }
    function test_parkedQObjectStillHasAFullFreshIdentityForRestore() {
        const parked=row(owned,"0xabc","Owned");
        parked.lastIpcObject.workspace={name:"special:Omadocked"};
        compare(Parking.correlate(owned,[owned],[parked]),null,"a parked window cannot supply a new origin");
        compare(Parking.identity(owned,[owned],[parked]),
                {address:"0xabc",pid:77,class:"Owned",initialClass:"Owned",xwayland:false});
    }
    function test_emptyIpcRefreshesOnceThenCorrelates() {
        const top = row(owned, "0xabc", "Owned");
        const saved = top.lastIpcObject;
        top.lastIpcObject = {};
        let refreshes = 0;
        const result = Parking.recordAfterRefresh(owned, [owned], [top], () => {
            refreshes++;
            top.lastIpcObject = saved;
        });
        compare(refreshes, 1);
        verify(result !== null);
        compare(result.identity.address, "0xabc");
        compare(Parking.recordAfterRefresh(owned, [owned], [top], () => { refreshes++; }), result);
        compare(refreshes, 1);
    }
}
