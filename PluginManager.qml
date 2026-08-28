import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Plugin Manager — a simple panel that lists installed Omarchy plugins and
// lets you remove them. Summon with:
//   omarchy-shell shell toggle gamisn.plugin-manager
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool closingFromHost: false
  property var plugins: []
  property string statusText: ""
  property bool busy: false

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
    listProcess.command = ["omarchy", "plugin", "list", "--json"]
    listProcess.running = true
  }

  function removePlugin(id) {
    if (busy || !id) return
    busy = true
    statusText = "Removing " + id + "…"
    removeProcess.command = ["omarchy", "plugin", "remove", id, "--yes"]
    removeProcess.running = true
  }

  function kindLabel(kinds) {
    if (!kinds || !kinds.length) return ""
    return kinds.join(", ")
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

  Process {
    id: removeProcess
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      root.busy = false
      if (exitCode === 0) {
        root.statusText = "Removed"
        root.refresh()
      } else {
        root.statusText = "Remove failed"
      }
    }
  }

  // ---- window ------------------------------------------------------------
  FloatingWindow {
    id: window
    title: "Plugin Manager"
    color: Color.background
    implicitWidth: 560
    implicitHeight: 640
    minimumSize: Qt.size(420, 400)

    onVisibleChanged: {
      if (!visible && !root.closingFromHost && root.shell && typeof root.shell.hide === "function")
        root.shell.hide("gamisn.plugin-manager")
    }

    FocusScope {
      id: focusScope
      anchors.fill: parent
      focus: true

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) { root.requestClose(); event.accepted = true }
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
            width: listView.width
            height: 52
            radius: Style.cornerRadius
            color: Color.pick("panel.item", "transparent")

            RowLayout {
              anchors.fill: parent
              anchors.leftMargin: 12
              anchors.rightMargin: 8
              spacing: 8

              ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                  Layout.fillWidth: true
                  text: modelData.name
                  font.pixelSize: Style.font.body
                  color: Color.foreground
                  elide: Text.ElideRight
                }
                Text {
                  Layout.fillWidth: true
                  text: modelData.id + "  ·  " + root.kindLabel(modelData.kinds)
                  font.pixelSize: Style.font.caption
                  color: Color.muted
                  elide: Text.ElideRight
                }
              }

              Text {
                text: modelData.enabled ? "on" : "off"
                font.pixelSize: Style.font.caption
                color: modelData.enabled ? Color.accent : Color.muted
              }

              Button {
                text: "Remove"
                enabled: !root.busy
                onClicked: root.removePlugin(modelData.id)
              }
            }
          }
        }
      }
    }
  }
}
