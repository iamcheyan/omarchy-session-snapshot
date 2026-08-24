import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
    id: root
    moduleName: "hancore.session-snapshot"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    property bool busy: false
    property string statusText: "Loading snapshot status…"
    property string detailText: ""
    property bool saved: false
    property bool autoRestore: false
    property bool desktopEmpty: false
    property bool saveOnExit: true

    readonly property string command: Qt.resolvedUrl("bin/omarchy-session-snapshot").toString().replace("file://", "")
    readonly property string savePreferencePath: `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/omarchy/session-save-on-exit`
    readonly property color panelForeground: Color.popups.text
    readonly property color panelMuted: Util.alpha(Color.popups.text, 0.58)
    readonly property color panelSubtleFill: Util.alpha(Color.popups.text, 0.06)
    readonly property color panelControlFill: Util.alpha(Color.popups.text, 0.08)
    readonly property color panelHoverFill: Style.hoverFillFor(panelForeground, Color.accent)

    FileView {
        id: savePreference
        path: root.savePreferencePath
        watchChanges: true
        printErrors: false
        onLoaded: {
            const value = text().trim().toLowerCase();
            if (value === "true" || value === "false")
                root.saveOnExit = value === "true";
        }
        onFileChanged: reload()
    }

    function open() { root.controller.show(); root.refresh(); }
    function close() { root.controller.hide(); }
    function toggle() { root.opened ? root.close() : root.open(); }

    function settingValue(key, fallback) {
        const value = root.setting(key, fallback);
        return value === undefined || value === null ? fallback : value;
    }

    function persistSettings() {
        const entry = { id: root.moduleName, saveOnExit: root.saveOnExit };
        root.settings = entry;
        if (root.hostWidget && "settings" in root.hostWidget)
            root.hostWidget.settings = entry;
        if (root.bar && root.bar.shell
                && typeof root.bar.shell.updateEntryInline === "function")
            root.bar.shell.updateEntryInline(root.moduleName, entry);
        savePreference.setText(root.saveOnExit ? "true\n" : "false\n");
    }

    function refresh() {
        if (!statusProcess.running) statusProcess.running = true;
        if (!clientsProcess.running) clientsProcess.running = true;
    }

    function run(action) {
        if (busy) return;
        actionProcess.command = [root.command, action];
        root.busy = true;
        actionProcess.running = true;
    }

    function applyClients(raw) {
        try {
            const clients = JSON.parse(raw || "[]");
            root.desktopEmpty = Array.isArray(clients) && clients.length === 0;
        } catch (error) {
            // A failed compositor query is not proof of an empty desktop.
            root.desktopEmpty = false;
        }
    }

    function restoreIfEmpty() {
        if (root.desktopEmpty)
            Quickshell.execDetached([root.command, "restore"]);
    }

    function applyStatus(raw) {
        try {
            const data = JSON.parse(raw || "{}");
            root.saved = data.saved === true;
            root.autoRestore = data.autoRestore === true;
            const count = Number(data.count || 0);
            const when = Number(data.savedAt || 0);
            root.statusText = root.saved
                ? `${count} window${count === 1 ? "" : "s"} saved`
                : "No saved snapshot";
            root.detailText = when > 0
                ? `Last saved ${Qt.formatDateTime(new Date(when * 1000), "yyyy-MM-dd HH:mm")}`
                : "The snapshot engine has not saved a session yet.";
        } catch (error) {
            root.saved = false;
            root.autoRestore = false;
            root.statusText = "Snapshot status unavailable";
            root.detailText = "The session snapshot command could not be read.";
        }
    }

    Component.onCompleted: {
        root.saveOnExit = Boolean(root.setting("saveOnExit", true));
        root.refresh();
    }

    onSettingsChanged: {
        root.saveOnExit = Boolean(root.setting("saveOnExit", true));
    }

    Process {
        id: statusProcess
        command: [root.command, "status"]
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(text)
        }
        onExited: root.busy = false
    }

    Process {
        id: clientsProcess
        command: ["hyprctl", "-j", "clients"]
        stdout: StdioCollector {
            onStreamFinished: root.applyClients(text)
        }
        onExited: function(code) {
            if (code !== 0) root.desktopEmpty = false;
        }
    }

    Process {
        id: actionProcess
        stdout: StdioCollector { }
        stderr: StdioCollector { }
        onExited: {
            root.busy = false;
            root.refresh();
        }
    }

    KeyboardPanel {
        id: panel
        anchorItem: root.anchorItem
        owner: root.hostWidget || root
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: panel.fittedContentWidth(Style.space(360))
        contentHeight: panel.fittedContentHeight(content.implicitHeight)

        PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onCloseRequested: root.close()

            ColumnLayout {
                id: content
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Style.space(10)

                Text {
                    text: "Session snapshot"
                    color: root.panelForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.title
                    font.bold: true
                }

                Text {
                    Layout.fillWidth: true
                    text: root.detailText
                    color: root.panelMuted
                    wrapMode: Text.Wrap
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 66
                    radius: Style.space(8)
                    color: root.panelSubtleFill
                    border.width: 1
                    border.color: root.autoRestore ? Color.accent : Color.popups.border

                    Column {
                        anchors.fill: parent
                        anchors.margins: Style.space(10)
                        spacing: Style.space(3)
                        Text {
                            text: root.statusText
                            color: root.panelForeground
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.body
                            font.bold: true
                        }
                        Text {
                            text: root.autoRestore ? "Auto-restore is armed for the next login."
                                : "Auto-restore is not armed."
                            color: root.panelMuted
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.caption
                        }
                    }
                }

                RowLayout {
                    visible: !root.desktopEmpty
                    Layout.fillWidth: true
                    spacing: Style.space(8)

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: Style.space(7)
                        color: saveMouse.containsMouse ? root.panelHoverFill : root.panelControlFill
                        Text {
                            anchors.centerIn: parent
                            text: root.busy ? "Saving…" : "Save snapshot"
                            color: root.panelForeground
                            font.pixelSize: Style.font.body
                        }
                        MouseArea {
                            id: saveMouse
                            anchors.fill: parent
                            enabled: !root.busy
                            onClicked: root.run("save")
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 42
                        radius: Style.space(7)
                        color: saveCloseMouse.containsMouse ? root.panelHoverFill : root.panelControlFill
                        Text {
                            anchors.centerIn: parent
                            text: "Save & clear desktop"
                            color: root.panelForeground
                            font.pixelSize: Style.font.body
                        }
                        MouseArea {
                            id: saveCloseMouse
                            anchors.fill: parent
                            enabled: !root.busy
                            onClicked: root.run("save-close")
                        }
                    }
                }

                Rectangle {
                    visible: root.desktopEmpty && root.saved
                    Layout.fillWidth: true
                    implicitHeight: 42
                    radius: Style.space(7)
                    color: restoreMouse.containsMouse ? root.panelHoverFill : root.panelControlFill
                    Text {
                        anchors.centerIn: parent
                        text: "Restore snapshot"
                        color: root.panelForeground
                        font.pixelSize: Style.font.body
                    }
                    MouseArea {
                        id: restoreMouse
                        anchors.fill: parent
                        enabled: !root.busy && root.desktopEmpty && root.saved
                        onClicked: {
                            root.close();
                            root.restoreIfEmpty();
                        }
                    }
                }

                Text {
                    visible: root.desktopEmpty && !root.saved
                    Layout.fillWidth: true
                    text: "The desktop is empty. Save a session before closing applications."
                    color: root.panelMuted
                    wrapMode: Text.Wrap
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 54
                    radius: Style.space(7)
                    color: root.panelSubtleFill
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: Style.space(10)
                        Text {
                            Layout.fillWidth: true
                            text: "Save before logout, reboot, or shutdown"
                            color: root.panelForeground
                            wrapMode: Text.Wrap
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.body
                        }
                        Rectangle {
                            implicitWidth: 44
                            implicitHeight: 24
                            radius: 12
                            color: root.saveOnExit ? Color.accent : root.panelMuted
                            Rectangle {
                                width: 18
                                height: 18
                                radius: 9
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.right: root.saveOnExit ? parent.right : undefined
                                anchors.left: root.saveOnExit ? undefined : parent.left
                                anchors.margins: 3
                                color: root.panelForeground
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    root.saveOnExit = !root.saveOnExit;
                                    root.persistSettings();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
