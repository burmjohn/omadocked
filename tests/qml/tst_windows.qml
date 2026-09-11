import QtQuick
import QtTest
import "../../core/AppLogic.js" as Apps
import "../../core/WindowLogic.js" as Windows

TestCase {
    name: "Windows"
    function test_groupsFollowExactAppMembershipAndExcludeCustomLaunchers() {
        const entries = [{id:"a", name:"A", startupClass:"Shared"}, {id:"b", name:"B", startupClass:"Shared"}, {id:"closed", name:"Closed"}];
        const windows = [{key:"1", appId:"a", title:"Same", active:true}, {key:"2", appId:"a", title:"Same"},
            {key:"3", appId:"Shared", title:""}, {key:"4", appId:"Unmatched", title:"   "}, {key:"5", appId:"", title:""}];
        const apps = Apps.build(entries, windows, ["closed"], []);
        const groups = Windows.groups(apps.concat([{id:"custom-a", kind:"application", canEdit:true, windows:["1"]},
            {id:"custom-b", kind:"application", canEdit:true, windows:["1"]}]), windows);
        compare(Object.keys(groups), ["a", "closed", "window:5", "window:Shared", "window:Unmatched"]);
        compare(groups.a, [{key:"1", title:"Same", active:true}, {key:"2", title:"Same", active:false}]);
        compare(groups.closed, []);
        compare(groups["window:Shared"][0].title, "Shared");
        compare(groups["window:Unmatched"][0].title, "Unmatched");
        compare(groups["window:5"][0].key, "5");
        compare(Object.keys(Windows.groups([], [])), []);
        const overridden = Windows.groups(Apps.build(entries, windows, [], [], {Shared:"b"}), windows);
        compare(overridden.b[0].key, "3");
        verify(!Object.prototype.hasOwnProperty.call(overridden, "window:Shared"));
    }
    function test_titlesNeverDetermineIdentityOrOrder() {
        const windows = [{key:"2", appId:"a", title:"Z"}, {key:"1", appId:"a", title:"A"}];
        const apps = Apps.build([{id:"a", name:"App"}], windows, [], []);
        compare(Windows.groups(apps, windows).a.map(w => w.key), ["2", "1"]);
        windows[0].title = "A"; windows[1].title = "Z"; windows[1].active = true;
        const rows = Windows.groups(apps, windows).a;
        compare(rows.map(w => w.key), ["2", "1"]);
        compare(rows.map(w => w.active), [false, true]);
        compare(Windows.groups([{id:"empty", kind:"application", name:"", windows:["2"]}], [{key:"2"}]).empty[0].title, "Untitled window");
    }
    function test_cycleAnchorsActiveWrapsAndRejectsInvalidSteps() {
        verify(typeof Windows.cycleKey === "function");
        const rows = [{key:"a", active:false}, {key:"b", active:true}, {key:"c", active:false}];
        compare(Windows.cycleKey(rows, 1), "c");
        compare(Windows.cycleKey(rows, -1), "a");
        rows[1].active = false; rows[2].active = true;
        compare(Windows.cycleKey(rows, 1), "a");
        rows[2].active = false;
        compare(Windows.cycleKey(rows, 1), "a");
        compare(Windows.cycleKey(rows, -1), "c");
        compare(Windows.cycleKey([{key:"only", active:true}], 1), "only");
        compare(Windows.cycleKey([], 1), "");
        for (const delta of [0, 2, -2, 0.5, NaN, Infinity, "1", null, true])
            compare(Windows.cycleKey(rows, delta), "");
    }
}
