import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "security.mjs" as Sec

// Plugin Manager — a panel that lists installed Omarchy plugins with their
// description, author, version, and source link, and lets you remove them.
// Summon with:
//   omarchy-shell shell toggle gamisn.plugin-manager
//
// Untrusted-input rule: for this manager, an installed plugin's manifest and
// git config are untrusted input, not configuration. Anything read out of
// ~/.config/omarchy/plugins reaches a Process only as an argv element and a
// Text only with textFormat: Text.PlainText, and is length-capped.
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

  // List-pipeline state
  property string listBuffer: ""
  property bool listTimedOut: false
  property bool listTooBig: false

  // Caps (producer/consumer)
  readonly property int maxPlugins: 512
  readonly property int maxFieldLen: 256
  readonly property int maxListBytes: 2 * 1024 * 1024
  readonly property int maxRemoveOutputChars: 64 * 1024

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
    listBuffer = ""
    listTimedOut = false
    listTooBig = false
    if (helperPath) {
      listProcess.command = [helperPath]
    } else {
      listProcess.command = ["omarchy", "plugin", "list", "--json"]
    }
    listProcess.running = true
    listWatchdog.restart()
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

  // Run the remove command directly via Process, streaming its output live
  // into the dialog. No external terminal needed; the panel stays open and
  // shows the process output as it happens.
  function runRemove() {
    if (removeRunning) return
    removeRunning = true
    removeDone = false
    removeSuccess = false
    removeOutput = ""
    // argv-only: the id stays a single argument, never shell syntax.
    removeProcess.command = ["omarchy", "plugin", "remove", removeTarget.id, "--yes"]
    removeProcess.running = true
    removeWatchdog.restart()
  }

  function appendRemoveOutput(data) {
    var next = root.removeOutput ? root.removeOutput + "\n" + data : data
    if (next.length > root.maxRemoveOutputChars) {
      // Keep the tail; drop the oldest characters when the cap is exceeded.
      next = "…\n" + next.substring(next.length - root.maxRemoveOutputChars)
    }
    root.removeOutput = next
  }

  // Watchdog: the list collector must not run without a deadline (first
  // review, item 3). Kill the producer and report if it exceeds 10s.
  Timer {
    id: listWatchdog
    interval: 10000
    onTriggered: {
      if (listProcess.running) {
        root.listTimedOut = true
        listProcess.running = false
      }
    }
  }

  // Watchdog for the remove process; onExited normally stops it.
  Timer {
    id: removeWatchdog
    interval: 120000
    onTriggered: {
      if (removeProcess.running) {
        removeProcess.running = false
        root.appendRemoveOutput("(timed out after 120s)")
      }
    }
  }

  Process {
    id: listProcess
    // Reassemble stdout line-by-line with a hard byte cap, instead of an
    // unbounded StdioCollector.
    stdout: SplitParser {
      onRead: function(data) {
        root.listBuffer = root.listBuffer ? root.listBuffer + "\n" + data : data
        if (root.listBuffer.length > root.maxListBytes) {
          root.listTooBig = true
          root.listBuffer = ""
          listProcess.running = false
        }
      }
    }
    onExited: function(exitCode) {
      listWatchdog.stop()
      if (root.listTimedOut) {
        root.statusText = "Listing timed out"
      } else if (root.listTooBig) {
        root.statusText = "Plugin list too large"
      } else if (exitCode !== 0) {
        root.statusText = "Failed to list plugins"
      } else {
        var parsed = []
        try { parsed = JSON.parse(root.listBuffer) } catch (e) { parsed = [] }
        root.plugins = Sec.sanitizePlugins(parsed, root.maxPlugins, root.maxFieldLen)
        root.statusText = root.plugins.length + " plugins installed"
      }
      root.listBuffer = ""
    }
  }

  // Runs the remove command and streams its output live into the dialog.
  Process {
    id: removeProcess
    stdout: SplitParser {
      onRead: function(data) { root.appendRemoveOutput(data) }
    }
    stderr: SplitParser {
      onRead: function(data) { root.appendRemoveOutput(data) }
    }
    onExited: function(exitCode) {
      removeWatchdog.stop()
      root.removeRunning = false
      root.removeDone = true
      root.removeSuccess = (exitCode === 0)
      if (exitCode === 0) {
        root.statusText = "Removed " + Sec.boundString(root.removeTarget.id, 64)
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
            textFormat: Text.PlainText
            font.pixelSize: Style.font.caption
            color: Color.muted
          }
        }

        // List — page-notched wheel scrolling, no rubber-band overshoot,
        // keyboard navigation (arrows/PageUp/PageDown/Home/End), hover
        // highlight, and a real draggable scrollbar. Flickable keeps touchpad
        // flicks but stops hard at both ends (no overshoot, no blank gaps).
        Item {
          id: listContainer
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true

          ListView {
            id: listView
            anchors.fill: parent
            anchors.rightMargin: scrollBar.visible ? 10 : 0
            model: root.plugins
            spacing: 4
            reuseItems: true
            cacheBuffer: listView.height > 0 ? listView.height * 3 : 1200
            boundsBehavior: Flickable.StopAtBounds
            flickDeceleration: 6000
            maximumFlickVelocity: 3000
            highlightMoveDuration: 120
            keyNavigationWraps: false
            focus: true

            // Wheel scrolling: deltas apply INSTANTLY (no serialized glide
            // animation — that was making scrolling feel glacial). One notch
            // steps ~85% of the viewport; touchpad pixel deltas apply 1:2.
            function scrollBy(delta) {
              var maxScroll = Math.max(0, contentHeight - height)
              contentY = Math.max(0, Math.min(contentY + delta, maxScroll))
            }

            WheelHandler {
              acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
              onWheel: function(ev) {
                if (ev.pixelDelta.y !== 0)
                  listView.scrollBy(-ev.pixelDelta.y * 3)
                else
                  listView.scrollBy(-(ev.angleDelta.y / 120) * Math.max(180, listView.height * 0.85))
                ev.accepted = true
              }
            }

            Keys.onPressed: function(event) {
              var rowStep = 100 // row height + spacing
              var idx = listView.currentIndex
              var last = listView.count - 1
              var handled = true
              if (event.key === Qt.Key_Down) {
                listView.currentIndex = Math.min(last, Math.max(0, idx + 1))
              } else if (event.key === Qt.Key_Up) {
                listView.currentIndex = idx < 0 ? last : Math.max(0, idx - 1)
              } else if (event.key === Qt.Key_PageDown) {
                listView.currentIndex = Math.min(last, (idx < 0 ? 0 : idx) + Math.max(1, Math.floor(listView.height / rowStep) - 1))
              } else if (event.key === Qt.Key_PageUp) {
                listView.currentIndex = Math.max(0, (idx < 0 ? 0 : idx) - Math.max(1, Math.floor(listView.height / rowStep) - 1))
              } else if (event.key === Qt.Key_Home) {
                listView.currentIndex = 0
              } else if (event.key === Qt.Key_End) {
                listView.currentIndex = last
              } else {
                handled = false
              }
              if (handled && listView.count > 0) {
                listView.positionViewAtIndex(listView.currentIndex, ListView.Contain)
                event.accepted = true
              }
            }

            delegate: Rectangle {
              id: row
              width: listView.width
              height: 96
              radius: Style.cornerRadius
              color: ListView.isCurrentItem
                ? Util.alpha(Color.accent, 0.14)
                : (rowHover.containsMouse ? Util.alpha(Color.foreground, 0.05)
                  : Color.pick("panel.item", "transparent"))

              Behavior on color { ColorAnimation { duration: 80 } }

              MouseArea {
                id: rowHover
                anchors.fill: parent
                hoverEnabled: true
                onClicked: listView.currentIndex = index
              }

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
                  textFormat: Text.PlainText
                  font.pixelSize: Style.font.body
                  font.bold: true
                  color: Color.foreground
                  elide: Text.ElideRight
                }
                Text {
                  width: parent.width
                  text: modelData.id + "  ·  " + root.kindLabel(modelData.kinds)
                  textFormat: Text.PlainText
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
                textFormat: Text.PlainText
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
                textFormat: Text.PlainText
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
                  textFormat: Text.PlainText
                  font.pixelSize: Style.font.caption
                  color: Color.muted
                }
                Text {
                  text: modelData.version ? "v" + modelData.version : ""
                  textFormat: Text.PlainText
                  font.pixelSize: Style.font.caption
                  color: Color.muted
                }
                Item { width: 1; height: 1 }
                Text {
                  // Only render a clickable link when the URL passes validation.
                  visible: !!modelData.sourceUrl && Sec.isSafeSourceUrl(modelData.sourceUrl)
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

          // Scrollbar (draggable, brightens on hover)
          Rectangle {
            id: scrollBar
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            width: 8
            radius: 4
            visible: listView.contentHeight > listView.height + 1
            opacity: scrollBarArea.containsMouse || scrollBarArea.pressed ? 1.0 : 0.35
            color: "transparent"

            Behavior on opacity { NumberAnimation { duration: 120 } }

            Rectangle {
              id: thumb
              x: 0
              width: parent.width
              radius: parent.radius
              color: Util.alpha(Color.muted, scrollBarArea.pressed ? 1.0 : 0.7)
              height: Math.max(40, listView.visibleArea.heightRatio * listView.height)
              y: {
                var maxScroll = Math.max(0, listView.contentHeight - listView.height)
                var denom = scrollBar.height - height
                return denom > 0 ? (listView.contentY / maxScroll) * denom : 0
              }
            }

            MouseArea {
              id: scrollBarArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPressed: function(mouse) { scrollToMouse(mouse) }
              onPositionChanged: function(mouse) { if (pressed) scrollToMouse(mouse) }

              // Map the pointer position on the track to list content position.
              function scrollToMouse(mouse) {
                var track = scrollBar.height - thumb.height
                if (track <= 0) return
                var frac = Math.max(0, Math.min(1, (mouse.y - thumb.height / 2) / track))
                var maxScroll = Math.max(0, listView.contentHeight - listView.height)
                listView.contentY = maxScroll * frac
              }
            }
          }

          // Empty state
          Text {
            visible: root.plugins.length === 0
            anchors.centerIn: parent
            text: "No plugins found"
            textFormat: Text.PlainText
            font.pixelSize: Style.font.body
            color: Color.muted
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
              textFormat: Text.PlainText
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
                textFormat: Text.PlainText
                font.family: "monospace"
                font.pixelSize: Style.font.bodySmall
                color: Color.foreground
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
              }
            }

            // Output (live while running, final after done)
            Rectangle {
              visible: root.removeRunning || root.removeDone
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 4
              color: Color.pick("panel.item", "transparent")
              border.color: root.removeDone
                ? (root.removeSuccess ? Color.accent : Color.urgent)
                : Color.muted
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
                  text: root.removeOutput || (root.removeRunning ? "Running…" : "(no output)")
                  textFormat: Text.PlainText
                  font.family: "monospace"
                  font.pixelSize: Style.font.bodySmall
                  color: root.removeDone && !root.removeSuccess ? Color.urgent : Color.foreground
                  wrapMode: Text.Wrap
                }
              }
            }

            // Hint while running
            Text {
              visible: root.removeRunning
              Layout.fillWidth: true
              text: "Removing… watch the output below. The panel stays open."
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