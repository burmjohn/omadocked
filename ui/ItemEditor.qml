pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls

// A disposable draft. Only the Save button emits a persistence request.
FocusScope {
    id: root
    property var desktopEntries: []
    property color textColor: "#eef0f6"
    property color accentColor: "#a7c7ff"
    property string errorMessage: ""
    property string recordId: ""
    readonly property string kind: typeField.currentValue || "application"
    property string originalDesktopId: ""
    property bool submissionPending: false
    signal accepted(var record)
    signal canceled
    ListModel {
        id: argumentsModel
    }
    Keys.onEscapePressed: event => {
        root.canceled();
        event.accepted = true;
    }
    function revealField(item: Item): void {
        let ancestor = item.parent;
        while (ancestor && ancestor !== editorColumn)
            ancestor = ancestor.parent;
        if (!ancestor)
            return;
        const flickable = editorScroll.contentItem as Flickable;
        if (!flickable)
            return;
        const top = item.mapToItem(editorScroll, 0, 0).y;
        if (top < 0)
            flickable.contentY += top;
        else if (top + item.height > editorScroll.height)
            flickable.contentY += top + item.height - editorScroll.height;
    }
    component EditorField: TextField {
        id: field
        onActiveFocusChanged: if (activeFocus)
            root.revealField(field)
        property string label: Accessible.name
        implicitHeight: 56
        topPadding: 23
        bottomPadding: 7
        leftPadding: 10
        rightPadding: 10
        color: root.textColor
        placeholderTextColor: Qt.alpha(root.textColor, 0.5)
        selectionColor: root.accentColor
        selectedTextColor: "#20232b"
        font.pixelSize: 13
        background: Rectangle {
            radius: 7
            color: Qt.alpha(root.accentColor, 0.06)
            border.width: field.activeFocus ? 2 : 1
            border.color: Qt.alpha(root.accentColor, field.activeFocus ? 1 : 0.25)
        }
        Label {
            objectName: "field-label"
            x: 10
            y: 5
            width: parent.width - 20
            text: field.label
            color: root.accentColor
            font.pixelSize: 11
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }
    component EditorButton: Button {
        id: button
        property bool primary: false
        onActiveFocusChanged: if (activeFocus)
            root.revealField(button)
        implicitHeight: 34
        background: Rectangle {
            radius: 7
            color: button.primary ? root.accentColor : Qt.alpha(root.accentColor, button.hovered ? 0.18 : 0.07)
            border.width: button.activeFocus ? 2 : 1
            border.color: Qt.alpha(root.accentColor, button.activeFocus ? 1 : 0.3)
        }
        contentItem: Text {
            text: button.text
            color: button.primary ? "#20232b" : root.textColor
            font.pixelSize: 13
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
        }
    }
    component EditorCheck: CheckBox {
        id: check
        onActiveFocusChanged: if (activeFocus)
            root.revealField(check)
        implicitHeight: 34
        contentItem: Text {
            text: check.text
            color: root.textColor
            font.pixelSize: 13
            leftPadding: 30
            verticalAlignment: Text.AlignVCenter
            textFormat: Text.PlainText
        }
        indicator: Rectangle {
            x: 2
            y: (check.height - height) / 2
            width: 20
            height: 20
            radius: 5
            color: Qt.alpha(root.accentColor, check.checked ? 0.25 : 0.05)
            border.width: check.activeFocus ? 2 : 1
            border.color: root.accentColor
            Text {
                anchors.centerIn: parent
                text: check.checked ? "✓" : ""
                color: root.textColor
                font.pixelSize: 14
            }
        }
    }
    component EditorCombo: ComboBox {
        id: combo
        onActiveFocusChanged: if (activeFocus)
            root.revealField(combo)
        implicitHeight: 56
        palette.text: root.textColor
        palette.buttonText: root.textColor
        palette.base: "#20232b"
        palette.window: "#20232b"
        palette.highlight: root.accentColor
        palette.highlightedText: "#20232b"
        popup.popupType: Popup.Item
        popup.height: Math.min(220, root.height - 32, popup.implicitHeight)
        background: Rectangle {
            radius: 7
            color: Qt.alpha(root.accentColor, 0.06)
            border.width: combo.activeFocus ? 2 : 1
            border.color: Qt.alpha(root.accentColor, combo.activeFocus ? 1 : 0.25)
        }
        contentItem: Text {
            text: combo.displayText
            color: root.textColor
            font.pixelSize: 13
            leftPadding: 10
            rightPadding: 26
            topPadding: 19
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
        Label {
            x: 10
            y: 5
            width: parent.width - 30
            text: combo.Accessible.name
            color: root.accentColor
            font.pixelSize: 11
            elide: Text.ElideRight
            textFormat: Text.PlainText
        }
    }

    function begin(record: var): void {
        const item = record || {};
        recordId = item.id || "";
        typeField.currentIndex = Math.max(0, typeField.indexOfValue(item.kind || "application"));
        originalDesktopId = item.desktopId || "";
        desktopField.currentIndex = desktopField.indexOfValue(originalDesktopId);
        targetField.text = item.target || "";
        actionField.currentIndex = item.action === "keybindings" ? 1 : 0;
        nameField.text = item.name || "";
        iconField.text = item.icon || "";
        programField.text = item.program || "";
        workingField.text = item.workingDirectory || "";
        terminalField.checked = !!item.terminal;
        enabledField.checked = item.enabled !== false;
        argumentsModel.clear();
        for (const value of item.args || [])
            argumentsModel.append({
                value: value
            });
        editorScroll.contentItem.contentY = 0;
        nameField.forceActiveFocus();
    }
    function draft(): var {
        const args = [];
        for (let i = 0; i < argumentsModel.count; ++i)
            args.push(argumentsModel.get(i).value);
        return {
            id: recordId,
            kind: kind,
            name: nameField.text,
            icon: iconField.text,
            desktopId: originalDesktopId,
            program: programField.text,
            args: args,
            workingDirectory: workingField.text,
            terminal: terminalField.checked,
            target: targetField.text,
            action: actionField.currentValue,
            enabled: enabledField.checked
        };
    }
    ScrollView {
        id: editorScroll
        objectName: "editor-scroll"
        anchors {
            top: parent.top
            bottom: errorLabel.top
            bottomMargin: 10
            left: parent.left
            right: parent.right
        }
        clip: true
        contentWidth: availableWidth
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        Column {
            id: editorColumn
            width: editorScroll.availableWidth - 12
            spacing: 8
            Label {
                text: root.recordId ? "Edit item" : "Add item"
                color: root.textColor
                font.bold: true
                font.pixelSize: 15
            }

            EditorCombo {
                id: typeField
                objectName: "editor-kind"
                width: parent.width
                textRole: "label"
                valueRole: "kind"
                Accessible.name: "Item type"
                KeyNavigation.backtab: saveButton
                model: [
                    {
                        kind: "application",
                        label: "Application"
                    },
                    {
                        kind: "command",
                        label: "Command"
                    },
                    {
                        kind: "link",
                        label: "Web link"
                    },
                    {
                        kind: "file",
                        label: "File"
                    },
                    {
                        kind: "folder",
                        label: "Folder"
                    },
                    {
                        kind: "action",
                        label: "Omarchy action"
                    },
                    {
                        kind: "separator",
                        label: "Separator"
                    }
                ]
            }
            EditorField {
                id: nameField
                objectName: "editor-name"
                width: parent.width
                placeholderText: "Item name"
                Accessible.name: "Item name"
            }
            EditorField {
                id: iconField
                objectName: "editor-icon"
                width: parent.width
                placeholderText: "Automatic fallback if empty"
                Accessible.name: "Icon name or path (optional)"
            }
            EditorCombo {
                id: desktopField
                objectName: "editor-desktop"
                width: parent.width
                visible: root.kind === "application"
                textRole: "label"
                valueRole: "id"
                model: root.desktopEntries.map(entry => ({
                            id: entry.id,
                            label: (entry.name || entry.id) + " — " + entry.id
                        }))
                onActivated: root.originalDesktopId = currentValue
                onModelChanged: currentIndex = indexOfValue(root.originalDesktopId)
                displayText: currentIndex >= 0 ? currentText : root.originalDesktopId ? root.originalDesktopId + " (unavailable)" : "Choose an application"
                Accessible.name: "Application desktop entry (exact ID)"
            }
            EditorField {
                id: programField
                objectName: "editor-program"
                width: parent.width
                visible: root.kind === "command"
                placeholderText: "Executable, never a shell expression"
                Accessible.name: "Command program"
            }
            Repeater {
                model: argumentsModel
                Row {
                    id: argumentRow
                    required property int index
                    required property string value
                    visible: root.kind === "command"
                    width: parent.width
                    spacing: 6
                    EditorField {
                        objectName: "argument-" + argumentRow.index
                        width: parent.width - removeArgument.width - parent.spacing
                        text: argumentRow.value
                        Accessible.name: "Argument " + (argumentRow.index + 1)
                        onTextChanged: if (text !== argumentRow.value)
                            argumentsModel.setProperty(argumentRow.index, "value", text)
                    }
                    EditorButton {
                        id: removeArgument
                        anchors.verticalCenter: parent.verticalCenter
                        objectName: "remove-argument-" + argumentRow.index
                        text: "Remove"
                        Accessible.name: "Remove argument " + (argumentRow.index + 1)
                        onClicked: argumentsModel.remove(argumentRow.index)
                    }
                }
            }
            EditorButton {
                objectName: "add-argument"
                text: "Add Argument"
                visible: root.kind === "command"
                Accessible.name: "Add command argument"
                onClicked: argumentsModel.append({
                    value: ""
                })
            }
            EditorField {
                id: workingField
                objectName: "editor-working-directory"
                width: parent.width
                visible: root.kind === "command"
                placeholderText: "Default if empty"
                Accessible.name: "Working directory (optional)"
            }
            EditorCheck {
                id: terminalField
                objectName: "editor-terminal"
                visible: root.kind === "command"
                text: "Run in terminal"
                Accessible.name: text
            }
            EditorField {
                id: targetField
                objectName: "editor-target"
                width: parent.width
                visible: ["link", "file", "folder"].indexOf(root.kind) >= 0
                placeholderText: root.kind === "link" ? "https://example.org" : "Absolute local path"
                Accessible.name: root.kind === "link" ? "Web link (HTTP or HTTPS)" : root.kind === "folder" ? "Local folder path" : "Local file path"
            }
            EditorCombo {
                id: actionField
                objectName: "editor-action"
                width: parent.width
                visible: root.kind === "action"
                textRole: "label"
                valueRole: "action"
                Accessible.name: "Omarchy action preset"
                model: [
                    {
                        action: "quick-menu",
                        label: "Quick Menu"
                    },
                    {
                        action: "keybindings",
                        label: "Keyboard Shortcuts"
                    }
                ]
            }
            EditorCheck {
                id: enabledField
                objectName: "editor-enabled"
                text: "Enabled"
                Accessible.name: "Launcher enabled"
            }
        }
    }
    Label {
        id: errorLabel
        objectName: "editor-error"
        anchors {
            left: parent.left
            right: parent.right
            bottom: buttons.top
            bottomMargin: 8
        }
        text: root.errorMessage
        visible: !!text
        height: visible ? 48 : 0
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        textFormat: Text.PlainText
        color: root.textColor
    }
    Row {
        id: buttons
        anchors {
            right: parent.right
            bottom: parent.bottom
        }
        spacing: 8
        EditorButton {
            objectName: "editor-cancel"
            text: "Cancel"
            Accessible.name: "Cancel item editing"
            onClicked: root.canceled()
        }
        EditorButton {
            id: saveButton
            objectName: "editor-save"
            text: "Save"
            primary: true
            enabled: !root.submissionPending
            Accessible.name: "Save item"
            KeyNavigation.tab: typeField
            onClicked: if (!root.submissionPending) root.accepted(root.draft())
        }
    }
}
