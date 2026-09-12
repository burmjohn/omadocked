import QtQuick
import QtTest

TestCase {
    id: test
    name: "DockView"
    when: windowShown
    visible: true
    width: 800
    height: 800
    property var dock
    function init() {
        const component = Qt.createComponent("../../ui/DockView.qml");
        compare(component.status, Component.Ready, component.errorString());
        // Explicit test-only fixtures; the production view starts with Settings only.
        dock = component.createObject(test, {applications: [
            {id: "terminal", name: "terminal", icon: "", running: false},
            {id: "browser", name: "browser", icon: "", running: false},
            {id: "files", name: "files", icon: "", running: false},
            {id: "editor", name: "editor", icon: "", running: false},
            {id: "music", name: "music", icon: "", running: false},
            {id: "keys", name: "keys", icon: "", running: false}
        ], icons: {menu: "", "omarchy-menu": "", terminal: "", browser: "", files: "", editor: "", music: "", keys: ""}});
        verify(dock !== null);
        verify(dock.visible);
        verify(waitForRendering(dock));
        mouseMove(test, 750, 350);
    }
    function cleanup() {
        if (dock) {
            dock.destroy();
            dock = null;
        }
    }
    function settingsSlot() { return dock.renderedSlots[dock.order.indexOf("menu")]; }
    SignalSpy { id: saveSpy; signalName: "saveLauncherRequested" }
    function test_addEditorSharesBoundedPopupAndCancel() {
        dock.autoHide = false;
        dock.availableWidth = 360;
        dock.selectIndex(dock.order.indexOf("menu"));
        const popup = findChild(dock, "settings-popup");
        const geometry = dock.popupRect;
        const height = dock.height;
        const add = findChild(dock, "add-item");
        verify(add !== null, "Settings has an Add Item entry point");
        saveSpy.target = dock; saveSpy.clear();
        mouseClick(add);
        verify(dock.editorOpen); verify(dock.settingsOpen); verify(dock.wantsKeyboard);
        compare(dock.popupRect, geometry); compare(dock.height, height);
        verify(!findChild(dock, "size-slider").visible);
        const editor = findChild(dock, "launcher-editor");
        verify(editor.visible); verify(editor.width <= popup.width);

        findChild(editor, "editor-name").text = "New launcher";
        for (let i = 0; i < 30; ++i) {
            keyClick(Qt.Key_Tab);
            verify(editor.activeFocus, "focus stays inside editor, not hidden settings");
        }
        keyClick(Qt.Key_Escape);
        verify(!dock.editorOpen); verify(dock.settingsOpen);
        compare(saveSpy.count, 0); compare(dock.popupRect, geometry);
        mouseClick(add);
        compare(findChild(editor, "editor-name").text, "");
        findChild(editor, "editor-name").text = "Saved name";
        mouseClick(findChild(editor, "editor-save"));
        compare(saveSpy.count, 1); compare(saveSpy.signalArguments[0][0].id, "");
        compare(saveSpy.signalArguments[0][0].name, "Saved name");
        verify(dock.editorOpen, "draft remains until persistence acknowledgement");
        dock.launcherSaveAccepted(41);
        verify(dock.launcherSavePending);
        verify(!findChild(editor, "editor-save").enabled, "pending save cannot be submitted again");
        mouseClick(findChild(editor, "editor-save"));
        compare(saveSpy.count, 1, "disabled save does not clear or replace the pending transaction");
        dock.launcherSaveAccepted(0);
        verify(dock.launcherSavePending, "rejected repeat cannot clear prior pending transaction");
        dock.launcherSaveResult(40, true);
        verify(dock.launcherSavePending); verify(dock.editorOpen);
        dock.appError = "Save failed"; dock.launcherSaveResult(41, false);
        verify(!dock.launcherSavePending);
        verify(dock.editorOpen);
        compare(findChild(editor, "editor-name").text, "Saved name");
        compare(findChild(editor, "editor-error").text, "Save failed");
        dock.launcherSaveAccepted(42); dock.launcherSaveResult(42, true);
        verify(!dock.editorOpen); verify(dock.settingsOpen);
        mouseClick(add); dock.resetSurface();
        verify(!dock.editorOpen); verify(!dock.settingsOpen);
        saveSpy.target = null;
    }
    function test_iconDecodeCapacityIsFixedAcrossMagnification() {
        dock.iconSize = 72;
        const art = findChild(dock, "art-terminal");
        verify(art.sourceSize.width >= Math.ceil(72 * dock.peakScale), "decode covers maximum rendered size");
        verify(art.sourceSize.width <= 108, "bounded decode, not unbounded texture cache");
        const size = art.sourceSize;
        dock.pointerX = dock.renderedSlots[2].center;
        wait(140);
        compare(art.sourceSize, size, "animated scale never changes decode request");
    }
    function test_settingsDoesNotReserveEmptyMonitorRows() {
        dock.availableOutputs = [];
        dock.selectIndex(dock.order.indexOf("menu"));
        const footer = findChild(dock, "settings-footer");
        const emptyY = footer.y;
        dock.availableOutputs = Array(20).fill("output");
        compare(footer.y - emptyY, 20 * 30, "monitor space follows only the actual row count");
        const popup = findChild(dock, "settings-popup"), scroll = findChild(dock, "settings-scroll");
        verify(popup.height <= 570, "large monitor lists keep the surface bounded");
        verify(scroll.contentHeight > scroll.height, "all monitor rows use the one outer overflow viewport");
    }
    function test_settingsKeyboardFocusRevealsOverflowAndReopenResets() {
        dock.autoHide = false; dock.availableWidth = 360; dock.selectIndex(dock.order.indexOf("menu"));
        const scroll = findChild(dock, "settings-scroll");
        const field = findChild(dock, "override-desktop-id");
        verify(waitForRendering(scroll));
        field.forceActiveFocus();
        tryVerify(function() {
            const point = field.mapToItem(scroll, 0, 0);
            return point.y >= 0 && point.y + field.height <= scroll.height;
        });
        dock.closeMonitorPicker(); dock.selectIndex(dock.order.indexOf("menu"));
        compare(scroll.contentItem.contentY, 0, "settings reopen at the visible heading and Add Item");
        const add = findChild(dock, "add-item");
        verify(add.mapToItem(scroll, 0, 0).y >= 0, "rounded header buttons are not clipped by the scroller");
    }
    function test_settingsOverflowControlsArePointerReachable() {
        dock.autoHide = false; dock.availableWidth = 360;
        dock.canRecover = true; dock.selectIndex(dock.order.indexOf("menu"));
        const scroll = findChild(dock, "settings-scroll");
        verify(scroll !== null);
        tryVerify(function() { return scroll.contentHeight > scroll.height; });
        const apply = findChild(dock, "apply-override");
        const content = findChild(dock, "settings-content");
        let flick = content.parent;
        while (flick && flick.contentHeight === undefined)
            flick = flick.parent;
        verify(flick && flick.contentHeight > flick.height);
        verify(waitForRendering(scroll));
        flick.contentY = flick.contentHeight - flick.height;
        compare(flick.contentY, flick.contentHeight - flick.height, "flickable must accept contentY");
        const point = apply.mapToItem(scroll, apply.width / 2, apply.height / 2);
        verify(point.y >= 0 && point.y < scroll.height, "Apply scrolls completely into the popup");
        verify(point.x >= 0 && point.x < scroll.width);
        findChild(dock, "override-app-id").text = "exact.app";
        findChild(dock, "override-desktop-id").text = "exact.desktop";
        verify(apply.enabled);
        mouseClick(apply);
        verify(dock.settingsOpen, "in-popup action must not be interpreted as outside dismissal");
    }
    function test_popupReadabilityIsIndependentOfShelf() {
        dock.shelfColor = Qt.rgba(0.1, 0.15, 0.2, 0.3);
        dock.transparency = 100;
        dock.selectIndex(dock.order.indexOf("menu"));
        const popup = findChild(dock, "settings-popup");
        compare(popup.background.color.a, 1, "popup background is opaque even with an alpha-bearing shelf theme");
        for (const size of [28, 72]) {
            dock.iconSize = size;
            compare(findChild(dock, "size-value").font.pixelSize, 13);
            compare(findChild(dock, "transparency-value").font.pixelSize, 13);
            compare(findChild(dock, "mode-wave").contentItem.font.pixelSize, 13);
        }
        dock.settingsOpen = false;
        dock.openContext(dock.order.indexOf("terminal"));
        compare(findChild(dock, "context-card").color.a, 1);
    }
    function test_popupKeyboardContainmentAndOutsideClick() {
        dock.autoHide = false;
        dock.availableOutputs = ["left", "right"];
        dock.enterKeyboard();
        dock.focusIndex = dock.order.indexOf("menu");
        keyClick(Qt.Key_Return);
        const popup = findChild(dock, "settings-popup");
        verify(popup.activeFocus);
        const size = findChild(dock, "size-slider");
        size.forceActiveFocus();
        for (let i = 0; i < 24; ++i) {
            keyClick(Qt.Key_Tab);
            verify(popup.activeFocus, "Tab remains inside the settings popup");
            compare(dock.focusIndex, dock.order.indexOf("menu"));
        }
        keyClick(Qt.Key_Escape);
        compare(dock.settingsOpen, false);
        verify(dock.activeFocus, "Escape returns to explicit dock keyboard mode");
        keyClick(Qt.Key_Return);
        mouseClick(dock, dock.renderedSlots[2].center, dock.rowY + 22);
        compare(dock.settingsOpen, false, "outside click closes popup");
        compare(dock.selection, "", "dismissal cannot click through to an app");
        compare(dock.pressedIndex, -1);
        compare(dock.dragActive, false);
        dock.settingsOpen = true;
        wait(120);
        compare(findChild(dock, "settings-popup").modal, false);
        mouseClick(dock, 8, 4);
        compare(dock.settingsOpen, false, "click outside the settings box closes it");
    }
    function test_unmanagedDisplayControlsApplyLocally() {
        dock.availableOutputs = ["left", "right"];
        dock.selectIndex(dock.order.indexOf("menu"));
        mouseClick(findChild(dock, "selected-displays"));
        compare(dock.monitorMode, "selected");
        compare(dock.selectedOutputs, ["left", "right"]);
        const content = findChild(dock, "settings-popup").contentItem;
        verify(waitForRendering(content));
        const left = findChild(content, "output-left");
        const right = findChild(content, "output-right");
        verify(left.mapToItem(content, 0, left.height).y <= right.mapToItem(content, 0, 0).y, "output rows are polished before pointer input");
        mouseClick(right);
        compare(dock.selectedOutputs, ["left"]);
        mouseClick(findChild(content, "output-left"));
        compare(dock.selectedOutputs, ["left"], "last connected output stays selected");
        mouseClick(findChild(dock, "all-displays"));
        compare(dock.monitorMode, "all");
        compare(dock.selectedOutputs, []);
    }
    QtObject { id: appearance; property int size: 44; property int transparency: 0 }
    SignalSpy { id: sizeSpy; signalName: "iconSizeRequested" }
    SignalSpy { id: transparencySpy; signalName: "transparencyRequested" }
    function test_sliderPreviewCommitsOnceAndDismissalCancels_data() {
        return [{tag: "zoom", slider: "zoom-size-slider", signal: "zoomSizeRequested", effective: "effectiveZoomSize", stored: "zoomSize", initial: 145, maximum: 200},
            {tag: "wave", slider: "wave-width-slider", signal: "waveWidthRequested", effective: "effectiveWaveWidth", stored: "waveWidth", initial: 25, maximum: 50},
            {tag: "size", slider: "size-slider", signal: "iconSizeRequested", effective: "effectiveIconSize", stored: "iconSize", initial: 44, maximum: 72},
            {tag: "transparency", slider: "transparency-slider", signal: "transparencyRequested", effective: "effectiveTransparency", stored: "transparency", initial: 0, maximum: 100}];
    }
    SignalSpy { id: previewSpy }
    function test_sliderPreviewCommitsOnceAndDismissalCancels(data) {
        dock.settingsManaged = true; dock.autoHide = false;
        previewSpy.target = dock; previewSpy.signalName = data.signal; previewSpy.clear();
        dock.selectIndex(dock.order.indexOf("menu"));
        const slider = findChild(dock, data.slider);
        const geometry = dock.popupRect;
        const height = dock.height;
        mousePress(slider, slider.width / 2, slider.height / 2);
        for (let i = 1; i <= 5; ++i) mouseMove(slider, slider.width * i / 5 - 1, slider.height / 2);
        compare(previewSpy.count, 0, "pointer preview never persists each movement");
        compare(dock[data.stored], data.initial);
        compare(dock[data.effective], data.maximum);
        compare(dock.popupRect, geometry); compare(dock.height, height);
        mouseRelease(slider, slider.width - 1, slider.height / 2);
        compare(previewSpy.count, 1); compare(previewSpy.signalArguments[0][0], data.maximum);
        compare(dock[data.stored], data.initial, "managed binding stays intact until ack");
        dock[data.stored] = data.maximum;
        compare(slider.value, data.maximum);
        mousePress(slider, 1, slider.height / 2);
        dock.closeMonitorPicker();
        mouseRelease(dock, 1, 1);
        compare(previewSpy.count, 1, "dismissal cancels uncommitted preview");
        compare(dock[data.effective], data.maximum);
        dock.selectIndex(dock.order.indexOf("menu")); compare(slider.value, data.maximum);
        slider.forceActiveFocus(); keyClick(Qt.Key_Left);
        compare(previewSpy.count, 2, "keyboard changes commit discretely");
        previewSpy.target = null;
    }
    function test_managedAppearanceRequestsPreserveBindings() {
        appearance.size = 44; appearance.transparency = 0;
        dock.settingsManaged = true;
        dock.iconSize = Qt.binding(function() { return appearance.size; });
        dock.transparency = Qt.binding(function() { return appearance.transparency; });
        sizeSpy.target = dock; transparencySpy.target = dock;
        sizeSpy.clear(); transparencySpy.clear();
        dock.selectIndex(dock.order.indexOf("menu"));
        const size = findChild(dock, "size-slider");
        const alpha = findChild(dock, "transparency-slider");
        size.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(sizeSpy.signalArguments[0][0], 46);
        compare(dock.iconSize, 44, "managed view only requests");
        appearance.size = 60;
        compare(dock.iconSize, 60); compare(size.value, 60);
        mouseClick(size, 1, size.height / 2);
        compare(sizeSpy.signalArguments[1][0], 28);
        compare(dock.iconSize, 60);
        appearance.size = 72;
        compare(size.value, 72); compare(dock.baseIconSize, 72);
        alpha.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(transparencySpy.signalArguments[0][0], 1);
        compare(dock.transparency, 0);
        appearance.transparency = 50;
        compare(alpha.value, 50);
        mouseClick(alpha, alpha.width - 1, alpha.height / 2);
        compare(transparencySpy.signalArguments[1][0], 100);
        compare(dock.transparency, 50);
        appearance.transparency = 75;
        compare(alpha.value, 75);
        compare(findChild(dock, "shelf-background").opacity, 0.25);
        sizeSpy.target = null; transparencySpy.target = null;
    }
    function test_sizeBoundsAndTargets_data() {
        const cases = [];
        for (const size of [28, 72])
            for (const width of [360, 480, 660])
                for (const mode of ["wave", "zoom", "off"])
                    cases.push({tag: size + "-" + width + "-" + mode, size: size, outputWidth: width, mode: mode});
        return cases;
    }
    function test_sizeBoundsAndTargets(data) {
        verify(dock.availableWidth !== undefined, "output fit contract exists");
        dock.autoHide = false;
        dock.availableWidth = data.outputWidth;
        dock.iconSize = data.size;
        dock.motionMode = data.mode;
        verify(dock.width <= data.outputWidth);
        compare(dock.iconSize, data.size, "fitting never overwrites requested size");
        verify(dock.baseIconSize <= data.size);
        for (let focus = 0; focus < dock.order.length; ++focus) {
            dock.pointerX = dock.rowX + dock.slotSize * (focus + 0.5);
            wait(130);
            const bounds = dock.renderedSlots;
            verify(bounds[0].left >= 0);
            verify(bounds[bounds.length - 1].right <= dock.width);
            for (let i = 0; i < bounds.length; ++i) {
                if (i) verify(bounds[i].left >= bounds[i - 1].right + dock.iconGap - 0.01, "scaled art never overlaps");
                const art = findChild(dock, "art-" + dock.order[i]);
                const topLeft = art.mapToItem(dock, 0, 0);
                const bottomRight = art.mapToItem(dock, art.width, art.height);
                verify(topLeft.y >= 0 && topLeft.y >= dock.shelfRect.y - 0.01, "peak art never clips vertically");
                verify(bottomRight.y <= dock.height);
                compare(dock.hitIndex(bounds[i].center), i);
                verify(topLeft.x >= dock.shelfRect.x - 0.01);
                verify(bottomRight.x <= dock.shelfRect.x + dock.shelfRect.width + 0.01);
            }
        }
        dock.reducedMotion = true;
        for (let i = 0; i < dock.order.length; ++i) {
            if (dock.order[i] === "omarchy-menu" || dock.order[i] === "menu") continue;
            mouseClick(dock, dock.renderedSlots[i].center, dock.rowY + dock.baseIconSize / 2);
            compare(dock.selection, dock.order[i], "each resized app target is still inert/selectable");
        }
    }
    function test_transparencySliderDoesNotFadeContents() {
        compare(dock.transparency, 0);
        dock.reducedMotion = true;
        mouseClick(dock, settingsSlot().center, dock.rowY + 22, Qt.RightButton);
        const slider = findChild(dock, "transparency-slider");
        verify(slider !== null);
        compare(slider.from, 0); compare(slider.to, 100);
        slider.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(dock.transparency, 1);
        mousePress(slider, slider.width / 2, slider.height / 2);
        mouseMove(slider, slider.width - 1, slider.height / 2);
        compare(dock.transparency, 1, "preview is not persisted until release");
        compare(dock.effectiveTransparency, 100);
        compare(findChild(dock, "transparency-value").text, "100%");
        mouseRelease(slider, slider.width - 1, slider.height / 2);
        const shelf = findChild(dock, "shelf-background");
        compare(shelf.opacity, 0, "background including border is transparent");
        const popup = findChild(dock, "settings-popup");
        compare(popup.opacity, 1);
        compare(popup.background.opacity, 1);
        compare(popup.background.color.a, 1);
        let art = findChild(dock, "art-menu");
        verify(art !== null);
        while (art) {
            compare(art.opacity, 1, "icon ancestry is not faded by transparency");
            if (art === dock) break;
            art = art.parent;
        }
        mouseClick(slider, 1, slider.height / 2);
        compare(dock.transparency, 0);
        keyClick(Qt.Key_Right);
        compare(dock.transparency, 1);
        compare(findChild(dock, "transparency-value").text, "1%");
    }
    function test_sizeSliderLiveMouseAndKeyboard() {
        compare(dock.iconSize, 44);
        mouseClick(dock, settingsSlot().center, dock.rowY + 22, Qt.RightButton);
        const slider = findChild(dock, "size-slider");
        verify(slider !== null);
        compare(slider.from, 28); compare(slider.to, 72); compare(slider.stepSize, 2);
        const popup = findChild(dock, "settings-popup");
        const screenY = popup.y - dock.height;
        const width = dock.width;
        slider.forceActiveFocus();
        keyClick(Qt.Key_Right);
        compare(dock.iconSize, 46);
        compare(findChild(dock, "size-value").text, "46 px");
        mousePress(slider, slider.width / 2, slider.height / 2);
        mouseMove(slider, slider.width - 1, slider.height / 2);
        compare(dock.iconSize, 46, "preview is not persisted until release");
        compare(dock.effectiveIconSize, 72);
        compare(dock.baseIconSize, 72);
        compare(popup.y - dock.height, screenY, "popup screen position stays fixed while dragging");
        compare(dock.width, width);
        mouseMove(slider, 1, slider.height / 2);
        compare(dock.effectiveIconSize, 28);
        compare(dock.baseIconSize, 28);
        compare(popup.y - dock.height, screenY);
        mouseRelease(slider, 1, slider.height / 2);
        compare(slider.pressed, false);
        keyClick(Qt.Key_Right);
        compare(dock.iconSize, 30);
        compare(findChild(dock, "size-value").text, "30 px");
        keyClick(Qt.Key_Escape);
        compare(dock.settingsOpen, false);
    }
    function test_compactShelfAndPopupMask() {
        verify(dock.dockHeight <= 110, "default shelf is compact, not a demo card");
        compare(dock.popupRect, Qt.rect(0, 0, 0, 0));
        verify(!findChild(dock, "mode-wave").visible, "tuning controls only live in popup");
        dock.autoHide = false;
        dock.pointerX = dock.rowX + dock.slotSize * 3.5;
        wait(180);
        const peak = dock.baseIconSize * 0.45 + dock.baseIconSize * 20 / 44 * 0.45;
        verify(dock.rowY - peak >= dock.shelfRect.y, "peak-wave headroom is inside input region");
        const stageHeight = dock.height;
        const width = dock.width;
        mouseClick(dock, settingsSlot().center, dock.rowY + 22, Qt.RightButton);
        compare(dock.height, stageHeight, "opening Settings must not resize the bottom-anchored layer");
        compare(dock.width, width, "opening popup never shifts native x position");
        const popup = findChild(dock, "settings-popup");
        compare(dock.popupRect, Qt.rect(popup.x, popup.y, popup.width, popup.height));
        verify(dock.popupRect.y + dock.popupRect.height < dock.shelfRect.y);
        compare(dock.inputRects.length, 3);
        mouseClick(findChild(dock, "close-settings"));
        compare(dock.height, stageHeight);
        dock.openContext(2);
        const card = findChild(dock, "context-card");
        compare(dock.popupRect, Qt.rect(card.x, card.y, card.width, card.height));
        verify(card.y + card.height < dock.shelfRect.y);
    }
    function test_settingsItemCannotReorder() {
        dock.autoHide = false;
        dock.reducedMotion = true;
        const original = dock.order.slice();
        const y = dock.rowY + 22;
        mousePress(dock, dock.renderedSlots[0].center, y);
        mouseMove(dock, dock.renderedSlots[4].center, y);
        compare(dock.dragActive, false, "Omarchy menu is never a drag source");
        mouseRelease(dock, dock.renderedSlots[4].center, y);
        compare(dock.order, original);
        mousePress(dock, settingsSlot().center, y);
        mouseMove(dock, dock.renderedSlots[4].center, y);
        compare(dock.dragActive, false, "settings is never a drag source");
        mouseRelease(dock, dock.renderedSlots[4].center, y);
        compare(dock.order, original);
        compare(dock.settingsOpen, false, "dragging fixed item is not a click");
        const files = dock.order.indexOf("files");
        mousePress(dock, dock.renderedSlots[files].center, y);
        mouseMove(dock, dock.renderedSlots[0].left, y);
        compare(dock.dragActive, true);
        compare(dock.insertionIndex, 2);
        mouseRelease(dock, dock.renderedSlots[0].left, y);
        compare(dock.order[0], "omarchy-menu");
        compare(dock.order[1], "menu");
        compare(dock.order[2], "files");
        compare(dock.order.length, 8);
    }
    function test_fixedFirstOpensFunctionalSettings() {
        compare(dock.order, ["omarchy-menu", "menu", "terminal", "browser", "files", "editor", "music", "keys"]);
        const first = findChild(dock, "settings-item");
        verify(first !== null);
        mouseClick(dock, settingsSlot().center, dock.rowY + 22, Qt.RightButton);
        compare(dock.settingsOpen, true);
        const popup = findChild(dock, "settings-popup");
        verify(popup !== null && popup.opened);
        verify(dock.wantsKeyboard);
        mouseClick(findChild(dock, "mode-zoom"));
        compare(dock.motionMode, "zoom");
        keyClick(Qt.Key_Escape);
        compare(dock.settingsOpen, false);
        dock.enterKeyboard();
        dock.focusIndex = dock.order.indexOf("menu");
        keyClick(Qt.Key_Return);
        compare(dock.settingsOpen, true);
        keyClick(Qt.Key_Escape);
        compare(dock.settingsOpen, false);
    }
    SignalSpy { id: monitorSpy; signalName: "monitorsRequested" }
    function test_pickerClicksRequestPolicy() {
        dock.settingsManaged = true;
        failOnWarning("QQuickItem: Cannot set activeFocusOnTab to false once item is the active focus item.");
        dock.availableOutputs = ["left", "right"];
        mouseClick(dock, settingsSlot().center, dock.rowY + 22, Qt.RightButton);
        const card = findChild(dock, "settings-popup");
        verify(card !== null && card.visible, "bounded monitor picker exists");
        verify(waitForRendering(card.contentItem));
        monitorSpy.target = dock;
        monitorSpy.clear();
        mouseClick(findChild(card, "selected-displays"));
        compare(monitorSpy.count, 1);
        compare(monitorSpy.signalArguments[0][0], "selected");
        compare(monitorSpy.signalArguments[0][1], ["left", "right"]);
        // Controller owns the policy; controls must not break its bindings.
        dock.monitorMode = "selected";
        dock.selectedOutputs = ["left", "right"];
        mouseClick(findChild(card.contentItem, "output-right"));
        compare(monitorSpy.signalArguments[1][0], "selected");
        compare(monitorSpy.signalArguments[1][1], ["left"]);
        dock.selectedOutputs = ["left"];
        mouseClick(findChild(card.contentItem, "output-left"));
        compare(monitorSpy.count, 2, "cannot deselect last connected display: " + JSON.stringify(monitorSpy.signalArguments));
        mouseClick(findChild(card, "all-displays"));
        compare(monitorSpy.signalArguments[2][0], "all");
        compare(monitorSpy.signalArguments[2][1], []);
        mouseClick(findChild(card, "close-settings"));
        compare(dock.monitorPickerOpen, false);
        monitorSpy.target = null;
    }
    function test_pickerBackgroundConsumesInput() {
        dock.availableOutputs = ["left", "right"];
        dock.reducedMotion = true;
        mouseClick(dock, settingsSlot().center, dock.rowY + 22, Qt.RightButton);
        const card = findChild(dock, "settings-popup");
        verify(waitForRendering(card.contentItem));
        // Padding is over real row targets, not a child button.
        mouseClick(dock, dock.rowX + 24, card.y + 34);
        compare(dock.selection, "", "picker padding swallows row clicks");
        mousePress(dock, dock.rowX + 24, card.y + 34);
        mouseMove(dock, dock.rowX + 180, card.y + 34);
        compare(dock.dragActive, false);
        mouseRelease(dock, dock.rowX + 180, card.y + 34);
        compare(dock.pressedIndex, -1);
        compare(dock.monitorPickerOpen, true);
        mouseClick(dock, dock.rowX + 24, card.y + 34, Qt.RightButton);
        compare(dock.contextIndex, -1);
        keyClick(Qt.Key_Escape);
        compare(dock.wantsKeyboard, false);
    }
    QtObject { id: shared; property string mode: "wave"; property bool reduced: false; property bool hide: true }
    SignalSpy { id: modeSpy; signalName: "modeRequested" }
    SignalSpy { id: reducedSpy; signalName: "reducedMotionRequested" }
    SignalSpy { id: hideSpy; signalName: "autoHideRequested" }
    function test_managedSettingsPreserveBindings() {
        mouseClick(dock, settingsSlot().center, dock.rowY + 22, Qt.RightButton);
        verify(waitForRendering(findChild(dock, "settings-popup").contentItem));
        verify(dock.settingsManaged !== undefined, "shared settings request contract exists");
        dock.settingsManaged = true;
        dock.motionMode = Qt.binding(function() { return shared.mode; });
        dock.reducedMotion = Qt.binding(function() { return shared.reduced; });
        dock.autoHide = Qt.binding(function() { return shared.hide; });
        modeSpy.target = dock; reducedSpy.target = dock; hideSpy.target = dock;
        modeSpy.clear(); reducedSpy.clear(); hideSpy.clear();
        mouseClick(findChild(dock, "mode-zoom"));
        compare(modeSpy.signalArguments[0][0], "zoom");
        compare(dock.motionMode, "wave");
        shared.mode = "off";
        compare(dock.motionMode, "off");
        mouseClick(findChild(dock, "reduced-motion"));
        compare(reducedSpy.signalArguments[0][0], true);
        compare(dock.reducedMotion, false);
        shared.reduced = true;
        compare(dock.reducedMotion, true);
        mouseClick(findChild(dock, "auto-hide"));
        compare(hideSpy.signalArguments[0][0], false);
        compare(dock.autoHide, true);
        dock.resetSurface();
        shared.hide = false;
        compare(dock.autoHide, false);
        compare(dock.visibilityState, "hidden", "managed hidden surface stays suspended after settings changes");
        compare(modeSpy.count, 1); compare(reducedSpy.count, 1); compare(hideSpy.count, 1);
        modeSpy.target = null; reducedSpy.target = null; hideSpy.target = null;
    }
    function test_displaysPickerLocksAndEscapes() {
        dock.availableOutputs = ["left", "right"];
        mouseClick(dock, settingsSlot().center, dock.rowY + 22, Qt.RightButton);
        compare(dock.settingsOpen, true);
        compare(dock.wantsKeyboard, true);
        mouseMove(test, 750, 750);
        wait(400);
        compare(dock.visibilityState, "interacting");
        keyClick(Qt.Key_Escape);
        compare(dock.settingsOpen, false);
        compare(dock.wantsKeyboard, false);
        mouseClick(dock, settingsSlot().center, dock.rowY + 22, Qt.RightButton);
        dock.resetSurface();
        compare(dock.settingsOpen, false);
        compare(dock.wantsKeyboard, false);
    }
    function test_motionFromStableCenters() {
        verify(typeof dock.scaleAt === "function", "motion math is available");
        const center = dock.rowX + dock.slotSize / 2;
        dock.pointerX = center;
        compare(dock.scaleAt(0), 1.45);
        verify(dock.scaleAt(1) > 1);
        const fixedX = dock.rowX;
        dock.pointerX = center + dock.slotSize * 4;
        compare(dock.scaleAt(0), 1);
        compare(dock.rowX, fixedX);
        dock.motionMode = "zoom";
        compare(dock.scaleAt(3), 1);
        compare(dock.scaleAt(4), 1.45);
        dock.motionMode = "off";
        compare(dock.scaleAt(4), 1);
        dock.motionMode = "wave";
        dock.reducedMotion = true;
        compare(dock.scaleAt(4), 1);
    }
    function test_mouseSelectionIsInert() {
        const x = dock.rowX + dock.slotSize * 2.5;
        mouseMove(dock, x, dock.rowY + 22);
        tryCompare(dock, "pointerX", x);
        mouseClick(dock, x, dock.rowY + 22);
        compare(dock.selection, "terminal");
        verify(dock.actionLabel.indexOf("terminal") >= 0);
        compare(dock.actionLabel, "terminal", "view emits requests only; no desktop service is imported");
        mouseClick(dock, dock.rowX + dock.slotSize * 3.5, dock.rowY + 22);
        compare(dock.selection, "browser");
    }
    function test_revealCancellationAndHideDwell() {
        verify(typeof dock.resetSurface === "function", "visibility lifecycle exists");
        dock.resetSurface();
        compare(dock.visibilityState, "hidden");
        compare(dock.revealDelay, 160);
        compare(dock.hideDelay, 350);
        compare(dock.inputRects.length, 1);
        compare(dock.inputRects[0].height, 6);
        dock.triggerEntered();
        compare(dock.visibilityState, "revealing");
        wait(70);
        dock.triggerExited();
        wait(190);
        compare(dock.visibilityState, "hidden");
        dock.triggerEntered();
        wait(80);
        compare(dock.visibilityState, "revealing");
        tryCompare(dock, "visibilityState", "shown", 250);
        dock.shelfEntered();
        dock.triggerExited(); // pointer moved from the edge into the icon row
        dock.shelfExited();
        compare(dock.visibilityState, "hiding");
        wait(200);
        compare(dock.visibilityState, "hiding");
        dock.shelfEntered();
        wait(200);
        compare(dock.visibilityState, "shown");
        dock.shelfExited();
        tryCompare(dock, "visibilityState", "hidden", 500);
        dock.autoHide = false;
        compare(dock.visibilityState, "shown");
        dock.shelfExited();
        wait(400);
        compare(dock.visibilityState, "shown");
    }
    function test_keyboardOptInNavigationAndRelease() {
        verify(typeof dock.enterKeyboard === "function", "keyboard entry exists");
        compare(dock.keyboardActive, false);
        dock.resetSurface();
        dock.enterKeyboard();
        compare(dock.visibilityState, "interacting");
        compare(dock.keyboardActive, true);
        verify(dock.activeFocus);
        compare(dock.focusIndex, 0);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Right);
        compare(dock.focusIndex, dock.order.indexOf("terminal"));
        keyClick(Qt.Key_Return);
        compare(dock.selection, "terminal");
        dock.shelfExited();
        wait(400);
        compare(dock.visibilityState, "interacting");
        keyClick(Qt.Key_Left);
        keyClick(Qt.Key_Left);
        keyClick(Qt.Key_Left);
        compare(dock.focusIndex, dock.order.length - 1);
        keyClick(Qt.Key_Escape);
        compare(dock.keyboardActive, false);
        verify(!dock.activeFocus);
        compare(dock.visibilityState, "hiding");
    }
    function test_dragInsertionCommitsOnlyInside() {
        dock.autoHide = false;
        const original = dock.order.slice();
        const x = dock.rowX + dock.slotSize * 2.5;
        const y = dock.rowY + 22;
        mousePress(dock, x, y);
        mouseMove(dock, x + 4, y);
        compare(dock.dragActive, false);
        mouseMove(dock, x + dock.slotSize * 3, y);
        compare(dock.dragActive, true);
        compare(dock.visibilityState, "interacting");
        compare(dock.scaleAt(3), 1);
        verify(dock.insertionIndex >= 3);
        compare(dock.order, original);
        mouseRelease(dock, x + dock.slotSize * 3, y);
        compare(dock.dragActive, false);
        compare(dock.order[5], "terminal");
        compare(dock.selection, "");
        verify(dock.actionLabel.indexOf("temporary order") >= 0);
    }
    function test_dragCancel_data() {
        return [
            {
                tag: "outside"
            },
            {
                tag: "escape"
            },
            {
                tag: "surfaceRemoved"
            },
            {
                tag: "grabLost"
            }
        ];
    }
    function test_dragCancel(data) {
        dock.autoHide = false;
        dock.enterKeyboard();
        const original = dock.order.slice();
        const x = dock.rowX + dock.slotSize * 2.5;
        const y = dock.rowY + 22;
        mousePress(dock, x, y);
        mouseMove(dock, x + 120, y);
        compare(dock.dragActive, true);
        if (data.tag === "escape")
            keyClick(Qt.Key_Escape);
        else if (data.tag === "surfaceRemoved")
            dock.resetSurface();
        else if (data.tag === "grabLost") {
            const input = findChild(dock, "rowInput");
            verify(input !== null);
            input.canceled();
        } else
            mouseMove(dock, dock.width + 30, y);
        mouseRelease(dock, dock.width + 30, y);
        compare(dock.dragActive, false);
        compare(dock.order, original);
        compare(dock.selection, "");
        compare(dock.insertionIndex, -1);
        verify(dock.actionLabel.indexOf("canceled") >= 0);
    }
    function test_nativeTuningControls() {
        mouseClick(dock, settingsSlot().center, dock.rowY + 22, Qt.RightButton);
        verify(waitForRendering(findChild(dock, "settings-popup").contentItem));
        const zoom = findChild(dock, "mode-zoom");
        verify(zoom !== null, "native tuning controls exist");
        mouseClick(zoom);
        compare(dock.motionMode, "zoom");
        mouseClick(findChild(dock, "mode-off"));
        compare(dock.motionMode, "off");
        mouseClick(findChild(dock, "mode-wave"));
        compare(dock.motionMode, "wave");
        mouseClick(findChild(dock, "reduced-motion"));
        compare(dock.reducedMotion, true);
        mouseClick(findChild(dock, "auto-hide"));
        compare(dock.autoHide, false);
        compare(dock.keyboardActive, false);
    }
    function test_waveBoundsAndEnlargedArtHit() {
        verify(dock.renderedSlots !== undefined, "rendered wave geometry exists");
        dock.autoHide = false;
        dock.pointerX = dock.rowX + dock.slotSize / 2;
        wait(180);
        const bounds = dock.renderedSlots;
        for (let i = 1; i < bounds.length; ++i)
            verify(bounds[i].left - bounds[i - 1].right >= 3.99, "art never overlaps");
        verify(bounds[0].left < dock.rowX);
        const x = bounds[0].left + 2;
        compare(dock.hitIndex(x), 0);
        mouseClick(dock, settingsSlot().center, dock.rowY + 22, Qt.RightButton);
        compare(dock.settingsOpen, true);
        keyClick(Qt.Key_Escape);
        dock.pointerX = dock.rowX + dock.slotSize * 5.5;
        wait(30);
        dock.pointerX = dock.rowX + dock.slotSize * 0.5;
        wait(160);
        for (let j = 1; j < dock.renderedSlots.length; ++j)
            verify(dock.renderedSlots[j].left - dock.renderedSlots[j - 1].right >= 3.99);
    }
    function test_pointerDragEscapeTemporaryFocus() {
        dock.autoHide = false;
        const original = dock.order.slice();
        compare(dock.keyboardActive, false);
        mousePress(dock, dock.rowX + dock.slotSize * 2.5, dock.rowY + 22);
        mouseMove(dock, dock.rowX + 150, dock.rowY + 22);
        compare(dock.dragActive, true);
        verify(dock.wantsKeyboard, "drag takes transient ownership");
        verify(dock.activeFocus);
        keyClick(Qt.Key_Escape);
        compare(dock.dragActive, false);
        compare(dock.keyboardActive, false);
        compare(dock.wantsKeyboard, false);
        verify(!dock.activeFocus);
        mouseRelease(dock, dock.rowX + 150, dock.rowY + 22);
        compare(dock.order, original);
        compare(dock.selection, "");
    }
    function test_interruptibleRevealAndReducedMotion() {
        verify(dock.shelfProgress !== undefined, "animated reveal exists");
        dock.visibilityState = "hidden";
        wait(35);
        verify(dock.shelfProgress > 0 && dock.shelfProgress < 1);
        dock.shelfEntered();
        tryCompare(dock, "shelfProgress", 1, 250);
        dock.visibilityState = "hidden";
        wait(35);
        dock.reducedMotion = true;
        compare(dock.effectiveProgress, 0);
        dock.shelfEntered();
        compare(dock.effectiveProgress, 1);
        verify(dock.rowY - 44 * 0.45 - 20 * 0.45 >= 0, "peak icon fits compact headroom");
    }
    function test_contextMenuIsInertAndLocksVisibility() {
        dock.autoHide = false;
        verify(typeof dock.openContext === "function", "inert context menu exists");
        const x = dock.rowX + dock.slotSize * 2.5;
        mouseClick(dock, x, dock.rowY + 22, Qt.RightButton);
        compare(dock.contextIndex, 2);
        compare(dock.selection, "");
        compare(dock.wantsKeyboard, true);
        dock.autoHide = true;
        dock.shelfExited();
        wait(400);
        compare(dock.visibilityState, "interacting");
        keyClick(Qt.Key_Escape);
        compare(dock.contextIndex, -1);
        compare(dock.wantsKeyboard, false);
        dock.enterKeyboard();
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Right);
        keyClick(Qt.Key_Menu);
        compare(dock.contextIndex, dock.focusIndex);
        keyClick(Qt.Key_Return);
        compare(dock.selection, dock.order[dock.focusIndex]);
        compare(dock.contextIndex, -1);
        compare(dock.keyboardActive, true);
        keyClick(Qt.Key_Escape);
    }

    function test_contextCardConsumesPointer_data() {
        return [
            { tag: "heading-click", x: 130, y: 19, drag: false },
            { tag: "background-click", x: 4, y: 44, drag: false },
            { tag: "heading-drag", x: 130, y: 19, drag: true },
            { tag: "background-drag", x: 4, y: 44, drag: true }
        ];
    }
    function test_contextCardConsumesPointer(data) {
        dock.autoHide = false;
        dock.reducedMotion = true;
        dock.motionMode = "off";
        const original = dock.order.slice();
        const menuX = dock.rowX + dock.slotSize * 2.5;
        const rowY = dock.rowY + 22;
        mouseClick(dock, menuX, rowY, Qt.RightButton);
        compare(dock.contextIndex, 2);
        const card = findChild(dock, "context-card");
        verify(card !== null && card.visible);
        const x = card.x + data.x;
        const y = card.y + data.y;
        let startedDrag = false;
        if (data.drag) {
            mousePress(dock, x, y);
            mouseMove(dock, dock.rowX + dock.slotSize * 6.5, rowY);
            startedDrag = dock.dragActive;
            mouseRelease(dock, dock.rowX + dock.slotSize * 6.5, rowY);
        } else {
            mouseClick(dock, x, y);
        }
        compare(startedDrag, false, "covered row must not start a drag");
        compare(dock.selection, "", "covered row must not select an item");
        compare(dock.order, original, "covered row must not reorder items");
        compare(dock.pressedIndex, -1);
        compare(dock.contextIndex, 2, "card background must not dismiss the menu");
        // Child buttons must remain above the card's pointer barrier.
        mouseClick(dock, card.x + 187, card.y + 62);
        compare(dock.contextIndex, -1);
        compare(dock.selection, "");
        mouseClick(dock, menuX, rowY, Qt.RightButton);
        mouseClick(dock, card.x + 67, card.y + 62);
        compare(dock.contextIndex, -1);
        compare(dock.selection, "terminal");
        compare(dock.order, original);
    }

    function test_tooltipDwellAndLeave() {
        dock.autoHide = false;
        verify(typeof dock.tooltipIndex !== "undefined", "tooltip dwell exists");
        compare(dock.tooltipDelay, 450);
        const x = dock.rowX + dock.slotSize * 1.5;
        mouseMove(dock, x, dock.rowY + 22);
        wait(200);
        compare(dock.tooltipIndex, -1);
        tryCompare(dock, "tooltipIndex", 1, 500);
        mouseMove(dock, 0, 0);
        tryCompare(dock, "tooltipIndex", -1);
    }

    function test_simulatedFullscreenAndOverlapPolicy() {
        verify(typeof dock.simulatedFullscreen !== "undefined", "explicit simulated fullscreen policy exists");
        dock.reducedMotion = true;
        dock.autoHide = false;
        dock.shelfExited();
        dock.simulatedFullscreen = true;
        compare(dock.visibilityState, "hidden");
        verify(dock.simulationLabel.indexOf("SIMULATED") >= 0);
        dock.triggerEntered();
        tryCompare(dock, "visibilityState", "shown", 400);
        dock.shelfEntered();
        dock.triggerExited();
        compare(dock.visibilityState, "shown");
        dock.shelfExited();
        compare(dock.visibilityState, "hidden");
        dock.enterKeyboard();
        compare(dock.visibilityState, "interacting");
        dock.releaseKeyboard();
        dock.simulatedFullscreen = false;
        dock.autoHide = true;
        dock.simulatedIntelligent = true;
        dock.simulatedOverlap = false;
        compare(dock.visibilityState, "shown");
        dock.simulatedOverlap = true;
        compare(dock.visibilityState, "hiding");
        dock.shelfEntered();
        compare(dock.visibilityState, "shown");
    }

    function test_fixtureShelf() {
        compare(dock.baseIconSize, 44);
        compare(dock.motionMode, "wave");
        compare(dock.peakScale, 1.45);
        verify(dock.shelfRect.width < 700);
        verify(dock.width <= 1136, "transparent reserve accommodates wider settings");
        verify(dock.height > 90);
        verify(dock.order.length >= 5);
        compare(dock.actionLabel, "");
    }
}
