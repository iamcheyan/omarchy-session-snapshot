import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    readonly property string snapshotCommand: Qt.resolvedUrl("bin/omarchy-session-snapshot").toString().replace("file://", "")
    readonly property string setupCommand: Qt.resolvedUrl("scripts/setup-systemd").toString().replace("file://", "")
    readonly property int maxSnapshotAge: 7 * 24 * 3600

    Component.onCompleted: {
        setupProcess.running = true;
        autoRestoreTimer.start();
    }

    Process {
        id: setupProcess
        command: [root.setupCommand]
    }

    Timer {
        id: autoRestoreTimer
        interval: 1800
        repeat: false
        onTriggered: statusProcess.running = true
    }

    Process {
        id: statusProcess
        command: [root.snapshotCommand, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text || "{}");
                    const age = Math.floor(Date.now() / 1000) - Number(data.savedAt || 0);
                    if (data.saved === true && data.autoRestore === true
                            && age >= 0 && age <= root.maxSnapshotAge)
                        restoreProcess.running = true;
                    else if (data.autoRestore === true && age > root.maxSnapshotAge)
                        disarmProcess.running = true;
                } catch (error) {
                    console.warn("session-snapshot: failed to read restore status", error);
                }
            }
        }
    }

    Process {
        id: restoreProcess
        command: [root.snapshotCommand, "restore-auto"]
    }

    Process {
        id: disarmProcess
        command: [root.snapshotCommand, "disarm"]
    }
}
