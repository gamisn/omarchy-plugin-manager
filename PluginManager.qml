import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Plugin Manager — a panel that lists installed Omarchy plugins with their
// description, author, version, and source link, and lets you remove them.
// Summon with:
//   omarchy-shell shell toggle gamisn.plugin-manager
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool closingFromHost: false
  property var plugins: []
  property string statusText: ""
  property bool busy: false

  // Remove-dialog state
  property var removeTarget: null
  property string removeCommand: ""
  property string removeOutput: ""
  property bool removeRunning: false
  property bool removeDone: false
  property bool removeSuccess: false
  property int pollAttempts: 0

  readonly property string sourceDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string helperPath: sourceDir ? sourceDir + "/bin/plugin-manager" : ""

  // ---- lifecycle (panel contract) ----------------------------------------
  function open(payloadJson) {
    closingFromHost = false
    window.visible = true
    refresh()
  }

  function close() {
    closingFromHost = true
    window.visible = false
    closingFromHost = false
  }

  function requestClose() {
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide("gamisn.plugin-manager")
    else
      close()
  }

  // ---- data --------------------------------------------------------------
  function refresh() {
    if (listProcess.running) return
    statusText = "Loading…"
    if (helperPath) {
      listProcess.command = [helperPath]
    } else {
      listProcess.command = ["omarchy", "plugin", "list", "--json"]
    }
    listProcess.running = true
  }

  function openSource(url) {
    if (!url) return
    if (root.shell && typeof root.shell.run === "function")
      root.shell.run("xdg-open " + url)
    else
      Quickshell.execDetached(["xdg-open", url])
  }

  function kindLabel(kinds) {
    if (!kinds || !kinds.length) return ""
    return kinds.join(", ")
  }

  // ---- remove dialog -----------------------------------------------------
  function confirmRemove(plugin) {
    if (busy || !plugin) return
    removeTarget = plugin
    removeCommand = "omarchy plugin remove " + plugin.id + " --yes"
    removeOutput = ""
    removeRunning = false
    removeDone = false
    removeSuccess = false
    removeDialog.opened = true
  }

  function cancelRemove() {
    if (removeRunning) return
    removeDialog.opened = false
    removeTarget = null
  }

  // Launch a real terminal (foot) running the remove command so the user can
  // watch the live process. The panel stays open. The terminal keeps the
  // window open after the command finishes so the output is readable.
  function runRemove() {
    if (removeRunning) return
    removeRunning = true
    removeDone = false
    removeSuccess = false
    removeOutput = ""
    var cmd = "omarchy plugin remove " + removeTarget.id + " --yes"
    var keepOpen = "echo; echo '--- done (exit ' $? ') ---'; echo 'Press Enter to close'; read"
    var shellCmd = "bash -c " + JSON.stringify(cmd + "; " + keepOpen)
    Quickshell.execDetached(["foot", "-T", "Plugin Manager - Remove", shellCmd])
    // Poll the plugin list until the target disappears (or a timeout) so the
    // dialog can report the result once the terminal command has finished.
    pollAttempts = 0
    pollTimer.start()
  }

  Process {
    id: listProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = []
        try { parsed = JSON.parse(text) } catch (e) { /* ignore */ }
        root.plugins = parsed
        root.statusText = parsed.length + " plugins installed"
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.statusText = "Failed to list plugins"
    }
  }

  // Polls the plugin list while the terminal remove command runs. When the
  // target plugin disappears from the list, the removal succeeded.
  Timer {
    id: pollTimer
    interval: 1000
    repeat: true
    onTriggered: {
      root.pollAttempts++
      if (root.pollAttempts > 30) { // 30s timeout
        root.removeRunning = false
        root.removeDone = true
        root.removeSuccess = false
        root.removeOutput = "Timed out waiting for removal to finish."
        stop()
        return
      }
      pollProcess.command = ["omarchy", "plugin", "list", "--json"]
      pollProcess.running = true
    }
  }

  Process {
    id: pollProcess
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = []
        try { parsed = JSON.parse(text) } catch (e) { /* ignore */ }
        var stillThere = false
        for (var i = 0; i < parsed.length; i++) {
          if (parsed[i] && parsed[i].id === root.removeTarget.id) { stillThere = true; break }
        }
        if (!stillThere) {
          // Removal finished (plugin gone from list).
          root.removeRunning = false
          root.removeDone = true
          root.removeSuccess = true
          root.removeOutput = "Removed " + root.removeTarget.id + "."
          root.statusText = "Removed " + root.removeTarget.id
          root.refresh()
          pollTimer.stop()
        }
      }
    }
  }

  // ---- window ------------------------------------------------------------
  FloatingWindow {
    id: window
    title: "Plugin Manager"
    color: Color.background
    implicitWidth: 640
    implicitHeight: 720
    minimumSize: Qt.size(480, 440)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("gamisn.plugin-manager")
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (removeDialog.opened) root.cancelRemove()
          else root.requestClose()
          event.accepted = true
        }
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.gapsOut + 8
        spacing: 10

        // Header
        RowLayout {
          Layout.fillWidth: true
          Text {
            text: "Installed Plugins"
            font.pixelSize: Style.font.title
            font.bold: true
            color: Color.foreground
          }
          Item { Layout.fillWidth: true }
          Text {
            text: root.statusText
            font.pixelSize: Style.font.caption
            color: Color.muted
          }
        }

        // List
        ListView {
          id: listView
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: root.plugins
          spacing: 4

          delegate: Rectangle {
            id: row
            width: listView.width
            height: 96
            radius: Style.cornerRadius
            color: Color.pick("panel.item", "transparent")

            // Name + id (top-left)
            Column {
              anchors.left: parent.left
              anchors.right: removeButton.left
              anchors.top: parent.top
              anchors.leftMargin: 12
              anchors.rightMargin: 8
              anchors.topMargin: 8
              spacing: 2

              Text {
                width: parent.width
                text: modelData.name
                font.pixelSize: Style.font.body
                font.bold: true
                color: Color.foreground
                elide: Text.ElideRight
              }
              Text {
                width: parent.width
                text: modelData.id + "  ·  " + root.kindLabel(modelData.kinds)
                font.pixelSize: Style.font.caption
                color: Color.muted
                elide: Text.ElideRight
              }
            }

            // Status + Remove (right)
            Text {
              id: statusText
              anchors.right: removeButton.left
              anchors.rightMargin: 10
              anchors.verticalCenter: parent.verticalCenter
              width: 28
              horizontalAlignment: Text.AlignHCenter
              text: modelData.enabled ? "on" : "off"
              font.pixelSize: Style.font.caption
              color: modelData.enabled ? Color.accent : Color.muted
            }

            Button {
              id: removeButton
              anchors.right: parent.right
              anchors.rightMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              width: 76
              text: "Remove"
              enabled: !root.busy
              onClicked: root.confirmRemove(modelData)
            }

            // Description (always visible)
            Text {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              anchors.topMargin: 44
              text: modelData.description || "No description."
              font.pixelSize: Style.font.bodySmall
              color: Color.foreground
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }

            // Author + version + source link (bottom)
            Row {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              anchors.bottomMargin: 6
              spacing: 12

              Text {
                text: modelData.author ? "by " + modelData.author : ""
                font.pixelSize: Style.font.caption
                color: Color.muted
              }
              Text {
                text: modelData.version ? "v" + modelData.version : ""
                font.pixelSize: Style.font.caption
                color: Color.muted
              }
              Item { width: 1; height: 1 }
              Text {
                visible: !!modelData.sourceUrl
                text: "Open source ↗"
                font.pixelSize: Style.font.caption
                color: Color.accent
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.openSource(modelData.sourceUrl)
                }
              }
            }
          }
        }
      }

      // ---- Remove confirmation / result dialog ---------------------------
      Rectangle {
        id: removeDialog
        property bool opened: false
        visible: opened
        anchors.fill: parent
        color: Util.alpha(Color.background, 0.85)
        z: 100

        MouseArea {
          anchors.fill: parent
          enabled: !root.removeRunning
          onClicked: root.cancelRemove()
        }

        Rectangle {
          id: dialogCard
          width: Math.min(parent.width - 40, 480)
          height: 300
          anchors.centerIn: parent
          radius: Style.cornerRadius
          color: Color.background
          border.color: root.removeDone
            ? (root.removeSuccess ? Color.accent : Color.urgent)
            : Color.muted
          border.width: 1

          MouseArea { anchors.fill: parent; onClicked: {} }

          ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // Title
            Text {
              Layout.fillWidth: true
              text: root.removeDone
                ? (root.removeSuccess ? "Removed" : "Remove failed")
                : "Remove plugin?"
              font.pixelSize: Style.font.title
              font.bold: true
              color: root.removeDone
                ? (root.removeSuccess ? Color.accent : Color.urgent)
                : Color.foreground
            }

            // Plugin name
            Text {
              Layout.fillWidth: true
              text: root.removeTarget ? root.removeTarget.name + " (" + root.removeTarget.id + ")" : ""
              font.pixelSize: Style.font.body
              color: Color.foreground
              elide: Text.ElideRight
            }

            // Command (always visible)
            Text {
              Layout.fillWidth: true
              text: "Command:"
              font.pixelSize: Style.font.caption
              font.bold: true
              color: Color.muted
            }
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: 30
              radius: 4
              color: Color.pick("panel.item", "transparent")
              border.color: Color.muted
              border.width: 1
              Text {
                anchors.fill: parent
                anchors.margins: 6
                text: root.removeCommand
                font.family: "monospace"
                font.pixelSize: Style.font.bodySmall
                color: Color.foreground
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
              }
            }

            // Output (after running)
            Rectangle {
              visible: root.removeDone
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 4
              color: Color.pick("panel.item", "transparent")
              border.color: root.removeSuccess ? Color.accent : Color.urgent
              border.width: 1
              clip: true
              Flickable {
                anchors.fill: parent
                anchors.margins: 6
                contentWidth: width
                contentHeight: outputText.height
                Text {
                  id: outputText
                  width: parent.width
                  text: root.removeOutput || "(no output)"
                  font.family: "monospace"
                  font.pixelSize: Style.font.bodySmall
                  color: root.removeSuccess ? Color.foreground : Color.urgent
                  wrapMode: Text.Wrap
                }
              }
            }

            // Hint while running
            Text {
              visible: root.removeRunning
              Layout.fillWidth: true
              text: "A terminal has opened — watch the process there. The panel stays open."
              font.pixelSize: Style.font.caption
              color: Color.muted
              wrapMode: Text.WordWrap
            }

            // Buttons
            RowLayout {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignBottom
              spacing: 8

              Item { Layout.fillWidth: true }

              Button {
                visible: !root.removeDone
                text: "Cancel"
                enabled: !root.removeRunning
                onClicked: root.cancelRemove()
              }
              Button {
                visible: !root.removeDone
                text: root.removeRunning ? "Removing…" : "Remove"
                enabled: !root.removeRunning
                onClicked: root.runRemove()
              }
              Button {
                visible: root.removeDone
                text: "Close"
                onClicked: root.cancelRemove()
              }
            }
          }
        }
      }
    }
  }
}
