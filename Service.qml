import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property string setupCommand: Qt.resolvedUrl("scripts/setup-systemd").toString().replace("file://", "")

    Component.onCompleted: {
        setupProcess.running = true;
    }

    Process {
        id: setupProcess
        command: [root.setupCommand]
    }
}
