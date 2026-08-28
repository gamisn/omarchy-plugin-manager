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

  function removePlugin(id) {
    if (busy || !id) return
    busy = true
    statusText = "Removing " + id + "…"
    removeProcess.command = ["omarchy", "plugin", "remove", id, "--yes"]
    removeProcess.running = true
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
              onClicked: root.removePlugin(modelData.id)
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
    }
  }
}
