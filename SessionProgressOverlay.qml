import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root
  property var shell: null
  property var manifest: null
  property bool opened: false
  property string mode: "restore"
  property string action: ""
  property string doneFile: ""
  property int current: 0
  property int total: 0
  property string appName: "Preparing workspace"
  property string detail: ""
  property string headline: mode === "save" ? "Saving your workspace" : "Restoring your workspace"
  property bool failed: false
  readonly property string engine: Qt.resolvedUrl("bin/omarchy-session-snapshot").toString().replace("file://", "")
  readonly property string actionScript: Qt.resolvedUrl("scripts/session-action").toString().replace("file://", "")
  readonly property real fraction: total > 0 ? Math.min(1, current / total) : 0

  function open(payloadJson) {
    var payload = ({})
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) { payload = ({}) }
    root.mode = payload.mode === "save" ? "save" : "restore"
    root.action = String(payload.action || "")
    root.doneFile = String(payload.doneFile || "")
    root.current = 0
    root.total = Number(payload.total || 0)
    root.appName = root.mode === "save" ? "Reading open windows" : "Waiting for applications"
    root.detail = ""
    root.failed = false
    root.opened = true
    progressProc.command = [root.engine, root.mode === "save" ? "save-auto-progress" : "restore-auto-progress"]
    progressProc.running = true
  }

  function close() {
    // Transactions cannot be dismissed by user input. The host may only call
    // close after the worker has ended.
    if (!progressProc.running) root.opened = false
  }

  function handleLine(raw) {
    var data
    try { data = JSON.parse(String(raw)) } catch (e) { return }
    if (!data.event) return
    if (data.total !== undefined) root.total = Number(data.total || 0)
    if (data.current !== undefined) root.current = Number(data.current || 0)
    if (data.app) root.appName = String(data.app)
    if (data.title) root.detail = String(data.title)
    if (data.event === "complete") {
      root.appName = root.mode === "save" ? "Workspace saved" : "Workspace restored"
    } else if (data.event === "error") {
      root.failed = true
      root.appName = root.mode === "save" ? "Workspace could not be saved" : "Restore finished with errors"
      root.detail = String(data.message || "")
    }
  }

  function signalDone() {
    if (root.doneFile) Quickshell.execDetached(["touch", root.doneFile])
  }

  Process {
    id: progressProc
    stdout: SplitParser { onRead: function(line) { root.handleLine(line) } }
    stderr: SplitParser { onRead: function(line) { root.detail = String(line) } }
    onExited: function(code) {
      root.failed = code !== 0
      if (root.mode === "save" && code === 0 && root.action) {
        root.appName = "Workspace saved"
        root.detail = root.action === "reboot" ? "Restarting" : root.action === "shutdown" ? "Shutting down" : "Logging out"
        commitTimer.start()
      } else {
        if (code === 0) root.appName = "Workspace restored"
        else if (!root.detail) root.detail = "The transaction stopped before every application completed"
        root.signalDone()
        finishTimer.start()
      }
    }
  }

  Timer {
    id: commitTimer
    interval: 650
    repeat: false
    onTriggered: Quickshell.execDetached([root.actionScript, "--commit", root.action])
  }

  Timer {
    id: finishTimer
    interval: root.failed ? 3500 : 900
    repeat: false
    onTriggered: {
      root.opened = false
      if (root.shell && typeof root.shell.hide === "function")
        root.shell.hide((root.manifest && root.manifest.id) || "hancore.session-snapshot")
    }
  }

  Variants {
    model: Quickshell.screens
    PanelWindow {
      required property var modelData
      screen: modelData
      visible: root.opened
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "hancore-session-snapshot-progress"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
      anchors { top: true; bottom: true; left: true; right: true }

      Rectangle { anchors.fill: parent; color: Color.menu.scrim }
      MouseArea { anchors.fill: parent }

      Rectangle {
        width: Math.min(parent.width - Style.space(48), Style.space(460))
        height: Style.space(210)
        anchors.centerIn: parent
        radius: Style.cornerRadius
        color: Color.popups.background
        border.width: 1
        border.color: Color.popups.border

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.space(24)
          spacing: Style.space(14)

          Text {
            Layout.fillWidth: true
            text: root.headline
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
          }
          Text {
            Layout.fillWidth: true
            text: root.appName
            color: root.failed ? Color.urgent : Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
          Text {
            Layout.fillWidth: true
            text: root.detail || (root.total > 0 ? `${root.current} / ${root.total}` : "Preparing…")
            color: Util.alpha(Color.popups.text, 0.65)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideMiddle
          }
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(10)
            radius: height / 2
            color: Util.alpha(Color.popups.text, 0.12)
            clip: true
            Rectangle {
              width: parent.width * root.fraction
              height: parent.height
              radius: height / 2
              color: root.failed ? Color.urgent : Color.accent
              Behavior on width { NumberAnimation { duration: 180 } }
            }
          }
          Text {
            Layout.fillWidth: true
            text: root.total > 0 ? `${root.current} of ${root.total} applications` : "Please wait"
            color: Util.alpha(Color.popups.text, 0.65)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
