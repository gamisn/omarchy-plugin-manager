import QtQuick
import qs.Ui

// Bar widget for Plugin Manager — a clickable icon in the bar that toggles
// the manager panel. Modeled on the first-party menu plugin's bar widget.
BarWidget {
  id: root
  moduleName: "gamisn.plugin-manager"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf013" // gear (Nerd Font / Font Awesome)
    fontFamily: "FiraCode Nerd Font"
    horizontalMargin: 7.5
    tooltipText: "Plugin Manager"
    onPressed: function(button) {
      if (!root.bar) return
      root.bar.run("omarchy-shell shell toggle gamisn.plugin-manager")
    }
  }
}
