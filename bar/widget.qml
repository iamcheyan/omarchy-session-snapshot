import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "hancore.session-snapshot"

    readonly property bool opened: panelLoader.item
        ? panelLoader.item.opened === true : false
    property string statusText: "No snapshot"
    property int snapshotCount: 0
    property bool autoRestore: false
    readonly property string snapshotCommand: Qt.resolvedUrl("../bin/omarchy-session-snapshot").toString().replace("file://", "")

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    function refresh() {
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function injectPanel() {
        if (!panelLoader.item) return;
        panelLoader.item.bar = root.bar;
        panelLoader.item.settings = root.settings;
        panelLoader.item.anchorItem = button;
        panelLoader.item.hostWidget = root;
    }

    function open() {
        if (!panelLoader.item) return;
        panelLoader.item.open();
    }

    function close() {
        if (panelLoader.item) panelLoader.item.close();
    }

    function toggle() {
        if (root.opened) root.close();
        else root.open();
    }

    Process {
        id: statusProcess
        command: [root.snapshotCommand, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text || "{}");
                    root.snapshotCount = Number(data.count || 0);
                    root.autoRestore = data.autoRestore === true;
                    root.statusText = data.saved
                        ? `${root.snapshotCount} window${root.snapshotCount === 1 ? "" : "s"}`
                        : "No snapshot";
                } catch (error) {
                    root.snapshotCount = 0;
                    root.autoRestore = false;
                    root.statusText = "Unavailable";
                }
            }
        }
        onExited: root.refresh()
    }

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("../SnapshotPanel.qml")
        visible: false
        onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel); }
    }

    WidgetButton {
        id: button
        bar: root.bar
        text: "󰁯"
        tooltipText: root.autoRestore
            ? `Session snapshot · ${root.statusText} · auto-restore armed`
            : `Session snapshot · ${root.statusText}`
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.LeftButton) root.toggle();
        }
    }

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()
    Component.onCompleted: root.refresh()
}
