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
        view.openContext(1);
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
        mouseClick(input, view.rowX + view.slotSize * 2.5 - input.x, input.height / 2);
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
