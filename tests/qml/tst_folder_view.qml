import QtQuick
import QtTest
import "../../ui"

TestCase {
    id: test
    name: "FolderView"
    when: windowShown
    visible: true
    width: 800; height: 700
    property string idA: "launcher:11111111-1111-4111-8111-111111111111"
    property var record: ({id:idA, kind:"folder", name:"Owned <folder>", target:"/tmp/owned", enabled:true})
    Component { id: component; DockView { reducedMotion:true; autoHide:false } }
    SignalSpy { id: openSpy; signalName:"folderOpenRequested" }
    SignalSpy { id: launchSpy; signalName:"activateRequested" }
    SignalSpy { id: presetSpy; signalName:"folderPresetRequested" }
    SignalSpy { id: directSpy; signalName:"folderDirectRequested" }
    SignalSpy { id: actionSpy; signalName:"actionRequested" }
    function createView() {
        const view = createTemporaryObject(component, test, {applications:[{id:idA,kind:"folder",name:"Owned",enabled:true,canEdit:true}], launcherRecords:[record]});
        verify(view !== null);
        openSpy.target = view; openSpy.clear(); launchSpy.target = view; launchSpy.clear();
        return view;
    }
    function test_short_output_contains_last_folder_row_and_controls() {
        const view = createView();
        view.availableHeight = 400;
        view.folderResult = {complete:true, entries:Array.from({length:16}, (_, i) => ({path:"/owned/"+i, label:"Owned "+i, type:"file", size:4, relativeTime:"now"}))};
        view.selectId(idA);
        const chooser = view.activeFolderChooser;
        const card = findChild(view, "context-card");
        verify(card.y + card.height <= view.height - view.dockHeight, "chooser stays above reserved shelf envelope");
        const list = findChild(chooser, "folder-list");
        verify(list.height >= 52);
        for (let i=0; i<16; ++i) chooser.handleKey(Qt.Key_Down, 0);
        list.forceLayout();
        compare(chooser.selectionPath, "/owned/15");
        const row = list.itemAtIndex(15);
        verify(row !== null);
        const point = row.mapToItem(view, 0, 0);
        verify(point.y >= card.y && point.y + row.height <= card.y + card.height);
        const close = findChild(chooser, "folder-close");
        mouseClick(close);
        compare(view.folderChooserOpen, false);
    }
    function test_firstUpSelectsLast() {
        const view = createView();
        const entries = ["a", "b", "c"].map(name => ({path:"/owned/" + name, label:name, type:"file", size:0, relativeTime:"now"}));
        view.folderResult = {entries:entries};
        view.selectId(idA);
        const chooser = view.activeFolderChooser;
        chooser.handleKey(Qt.Key_Up, Qt.NoModifier);
        compare(chooser.selectionPath, "/owned/c");
        view.folderResult = {entries:entries.slice(0, 2)};
        compare(chooser.selectionPath, "");
        chooser.handleKey(Qt.Key_Up, Qt.NoModifier);
        compare(chooser.selectionPath, "/owned/b");
        view.folderResult = {entries:entries.slice(0, 1)};
        chooser.handleKey(Qt.Key_Up, Qt.NoModifier);
        compare(chooser.selectionPath, "/owned/a");
        view.folderResult = {entries:[]};
        chooser.handleKey(Qt.Key_Up, Qt.NoModifier);
        compare(chooser.selectionPath, "");
        compare(launchSpy.count, 0);
    }
    function test_primary_opens_toggles_and_never_directly_launches() {
        const view = createView();
        view.selectId(idA);
        compare(launchSpy.count, 0);
        compare(openSpy.count, 1);
        compare(view.folderChooserOpen, true);
        compare(view.interactionLocked, true);
        tryVerify(() => view.activeFolderChooser !== null);
        view.selectId(idA);
        compare(view.folderChooserOpen, false);
        tryCompare(view, "activeFolderChooser", null);
        compare(launchSpy.count, 0);
    }
    function test_settings_have_real_presets_and_cancel_safe_picker() {
        const view = createView();
        view.settingsOpen = true;
        const settings = findChild(view, "folder-settings");
        verify(settings !== null);
        presetSpy.target = view; presetSpy.clear();
        settings.preset("Downloads");
        compare(presetSpy.count, 1);
        const revision = settings.beginSelection(false);
        settings.cancelSelection();
        compare(settings.acceptSelection(revision, "file:///tmp/late"), false);
        compare(launchSpy.count, 0);
    }
    function test_context_has_manager_and_terminal_without_scan() {
        const view = createView();
        directSpy.target = view; directSpy.clear();
        view.openContext(2);
        verify(view.contextActions.indexOf(12) >= 0);
        verify(view.contextActions.indexOf(13) >= 0);
        view.invokeContext(13);
        compare(directSpy.count, 1);
        compare(directSpy.signalArguments[0][0], idA);
        compare(directSpy.signalArguments[0][1], "terminal");
        compare(openSpy.count, 0);
    }
    function test_pointer_switches_folder_in_one_click() {
        const view = createView();
        const idB = "launcher:22222222-2222-4222-8222-222222222222";
        view.applications = view.applications.concat([{id:idB,kind:"folder",name:"B",enabled:true,canEdit:true}]);
        view.launcherRecords = [record, {id:idB,kind:"folder",name:"B",target:"/tmp/b",enabled:true}];
        view.selectId(idA);
        wait(30);
        const input = findChild(view, "rowInput");
        mouseClick(input, view.rowX + view.slotSize * 3.5 - input.x, input.height / 2);
        compare(view.folderChooserOpen, true);
        compare(view.contextId, idB);
        compare(openSpy.count, 2);
    }
    function test_real_pointer_release_rejects_replaced_rows() {
        const view = createView();
        view.folderResult = {complete:true, entries:[{path:"/tmp/owned/a", label:"A", type:"file", size:4, relativeTime:"just now", icon:"text-x-generic"}]};
        view.selectId(idA);
        tryVerify(() => view.activeFolderChooser !== null);
        const chooser = view.activeFolderChooser;
        actionSpy.target = chooser; actionSpy.clear();
        const list = findChild(chooser, "folder-list");
        list.forceLayout();
        tryVerify(() => list.itemAtIndex(0) !== null);
        const button = list.itemAtIndex(0);
        mousePress(button, 30, 25);
        compare(button.pressed, true);
        view.folderResult = {complete:true, entries:[{path:"/tmp/owned/b", label:"B", type:"file", size:4, relativeTime:"just now", icon:"text-x-generic"}]};
        mouseRelease(list, 30, 25);
        compare(actionSpy.count, 0);
        chooser.selectionPath = "/tmp/owned/b";
        chooser.handleKey(Qt.Key_Return, 0);
        compare(actionSpy.count, 1);
        compare(actionSpy.signalArguments[0][1], "/tmp/owned/b");
    }
}
