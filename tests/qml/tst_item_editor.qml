import QtQuick
import QtTest

TestCase {
    id: test
    name: "ItemEditor"
    when: windowShown
    visible: true
    width: 420; height: 520
    property var editor
    SignalSpy { id: saved; signalName: "accepted" }
    SignalSpy { id: canceled; signalName: "canceled" }
    function init() {
        const component = Qt.createComponent("../../ui/ItemEditor.qml");
        compare(component.status, Component.Ready, component.errorString());
        editor = component.createObject(test, {width: 360, height: 448});
        verify(editor !== null);
        saved.target = editor; canceled.target = editor;
        saved.clear(); canceled.clear();
    }
    function cleanup() {
        saved.target = null; canceled.target = null;
        if (editor) editor.destroy();
        editor = null;
    }
    function test_desktopRefreshPreservesExactSelectionAndPopupBounds() {
        editor.desktopEntries = [{id: "one.desktop", name: "Same"}, {id: "two.desktop", name: "Same"}];
        editor.begin({kind: "application", desktopId: "two.desktop"});
        const desktop = findChild(editor, "editor-desktop");
        desktop.currentIndex = 0; desktop.activated(0);
        editor.desktopEntries = [{id: "two.desktop", name: "Renamed"}, {id: "one.desktop", name: "Same"}];
        compare(editor.draft().desktopId, "one.desktop", "metadata churn cannot retarget a draft");
        editor.desktopEntries = Array.from({length: 100}, (_, index) => ({id: "app" + index + ".desktop", name: "Application " + index}));
        const combo = findChild(editor, "editor-desktop");
        combo.popup.open();
        tryVerify(function() { return combo.popup.height <= 220; });
        compare(combo.popup.popupType, 0, "dropdown stays in the existing native popup scene");
        combo.popup.close();
        compare(editor.draft().desktopId, "one.desktop", "uninstalled ID stays explicit, not silently replaced");
        compare(saved.count, 0);
    }
    function test_keyboardFocusScrollsLongFormsIntoView() {
        failOnWarning(/Binding loop/);
        editor.begin({kind: "command", args: Array(20).fill("literal")});
        const scroll = findChild(editor, "editor-scroll");
        const field = findChild(editor, "argument-19");
        verify(waitForRendering(editor));
        field.forceActiveFocus();
        tryVerify(function() {
            const point = field.mapToItem(scroll, 0, 0);
            return point.y >= 0 && point.y + field.height <= scroll.height;
        });
        editor.errorMessage = "Save failed: read-only directory";
        const error = findChild(editor, "editor-error");
        tryVerify(function() {
            const point = error.mapToItem(editor, 0, 0);
            return point.y >= 0 && point.y + error.height < editor.height;
        });
    }
    function test_filledFieldsKeepVisibleLabelsAndThemedFocus() {
        editor.begin({kind: "command", name: "Named", icon: "utilities-terminal", program: "printf", args: ["one two"], workingDirectory: "/tmp"});
        for (const key of ["editor-name", "editor-icon", "editor-program", "argument-0", "editor-working-directory"]) {
            const field = findChild(editor, key);
            verify(field.label !== undefined && field.label.length > 0, "filled field still identifies " + key);
            const label = findChild(field, "field-label");
            verify(label !== null && label.visible);
            compare(label.text, field.label);
            field.forceActiveFocus();
            compare(field.background.border.width, 2, "focus is visible");
            verify(field.background.radius > 0);
        }
        const save = findChild(editor, "editor-save");
        compare(save.primary, true);
        verify(save.background.radius > 0);
        const enabled = findChild(editor, "editor-enabled");
        enabled.forceActiveFocus();
        compare(enabled.contentItem.color, editor.textColor);
        const scroll = findChild(editor, "editor-scroll");
        tryVerify(function() {
            const point = enabled.mapToItem(scroll, 0, 0);
            return point.y >= 0 && point.y + enabled.height <= scroll.height;
        });
    }
    function test_addRemoveArgumentsAndEscapeAreSafe() {
        editor.begin({kind: "command", args: ["one two"]});
        const add = findChild(editor, "add-argument");
        verify(add !== null, "arguments have discrete Add controls, not shell splitting");
        add.clicked();
        compare(editor.draft().args, ["one two", ""]);
        findChild(editor, "argument-1").text = "  ";
        compare(editor.draft().args, ["one two", "  "]);
        findChild(editor, "remove-argument-0").clicked();
        compare(editor.draft().args, ["  "]);
        findChild(editor, "editor-name").forceActiveFocus();
        keyClick(Qt.Key_Escape);
        compare(canceled.count, 1); compare(saved.count, 0);
        editor.begin({kind: "command", args: Array(20).fill("literal")});
        const scroll = findChild(editor, "editor-scroll");
        verify(scroll.height < editor.height);
        tryVerify(function() { return scroll.contentHeight > scroll.height; });
        compare(findChild(editor, "editor-save").mapToItem(editor, 0, 0).y + findChild(editor, "editor-save").height, editor.height);
        const name = findChild(editor, "editor-name");
        name.forceActiveFocus();
        for (let i = 0; i < 60; ++i) {
            keyClick(Qt.Key_Tab);
            verify(editor.activeFocus, "focus stays inside editor");
        }
    }
    function test_typeSpecificFieldsAndExactDesktopIds() {
        editor.desktopEntries = [{id: "org.Example.One.desktop", name: "Same name"}, {id: "other.desktop", name: "Same name"}];
        editor.begin({kind: "application", desktopId: "other.desktop"});
        const types = findChild(editor, "editor-kind");
        verify(types !== null, "typed launcher selector exists");
        const desktop = findChild(editor, "editor-desktop");
        compare(desktop.currentValue, "other.desktop");
        verify(desktop.visible); verify(!findChild(editor, "editor-program").visible);
        desktop.currentIndex = 0;
        desktop.activated(0);
        compare(editor.draft().desktopId, "org.Example.One.desktop");
        for (const kind of ["command", "link", "file", "folder", "action", "separator"]) {
            types.currentIndex = types.indexOfValue(kind);
            compare(editor.draft().kind, kind);
            compare(findChild(editor, "editor-program").visible, kind === "command");
            compare(findChild(editor, "editor-target").visible, ["link", "file", "folder"].indexOf(kind) >= 0);
            compare(findChild(editor, "editor-action").visible, kind === "action");
        }
        editor.begin({kind: "link", target: "https://example.org/path?q=hello world"});
        compare(editor.draft().target, "https://example.org/path?q=hello world");
        verify(findChild(editor, "editor-target").Accessible.name.indexOf("HTTP") >= 0);
        editor.begin({kind: "folder", target: "/tmp/folder with spaces", icon: "/missing/icon.svg"});
        compare(editor.draft().target, "/tmp/folder with spaces");
        compare(editor.draft().icon, "/missing/icon.svg");
        editor.begin({kind: "action", action: "keybindings"});
        compare(findChild(editor, "editor-action").currentValue, "keybindings");
        compare(editor.draft().action, "keybindings");
        compare(saved.count, 0, "selecting any type never saves or executes");
        editor.begin({kind: "application", desktopId: "missing.desktop"});
        compare(editor.draft().desktopId, "missing.desktop", "unavailable exact IDs survive rename");
    }
    function test_commandSaveIsExplicitAndArgumentsAreLiteral() {
        const record = {id: "launcher:fixture", kind: "command", name: "Original", icon: "", program: "printf", args: ["one two", "  padded  "], workingDirectory: "/tmp", terminal: true, enabled: true};
        editor.begin(record);
        compare(findChild(editor, "editor-program").text, "printf");
        compare(findChild(editor, "argument-0").text, "one two");
        findChild(editor, "editor-name").text = "Renamed";
        findChild(editor, "argument-1").text = " literal ; $(not a shell) ";
        compare(saved.count, 0);
        compare(record.name, "Original");
        compare(record.args[1], "  padded  ");
        mouseClick(findChild(editor, "editor-save"));
        compare(saved.count, 1);
        const result = saved.signalArguments[0][0];
        compare(result.id, record.id);
        compare(result.name, "Renamed");
        compare(result.args, ["one two", " literal ; $(not a shell) "]);
        compare(result.workingDirectory, "/tmp"); compare(result.terminal, true);
        editor.begin(record);
        findChild(editor, "editor-name").text = "Discard me";
        mouseClick(findChild(editor, "editor-cancel"));
        compare(canceled.count, 1); compare(saved.count, 1);
        editor.begin(record);
        compare(findChild(editor, "editor-name").text, "Original");
    }
}
