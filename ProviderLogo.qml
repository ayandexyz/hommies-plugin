import QtQuick
import QtQuick.Effects
import qs.Commons

// Provider mark adapted from omarchy-tokentracker. The source SVG is hidden
// and recolored so it follows the active Omarchy theme.
Item {
  id: root

  property string providerId: ""
  property color tint: Color.foreground
  property string fontFamily: Style.font.family

  readonly property string logoFile: providerId === "claude" ? "claude.svg"
    : providerId === "codex" ? "codex.svg"
    : providerId === "opencode" ? "opencode.svg"
    : providerId === "omacode" ? "omacode.svg"
    : ""
  readonly property bool logoReady: logoFile !== "" && logoImage.status === Image.Ready

  implicitWidth: Style.space(16)
  implicitHeight: Style.space(16)

  Image {
    id: logoImage
    anchors.fill: parent
    source: root.logoFile === "" ? "" : Qt.resolvedUrl("assets/" + root.logoFile)
    sourceSize.width: Math.max(1, root.width * 2)
    sourceSize.height: Math.max(1, root.height * 2)
    fillMode: Image.PreserveAspectFit
    visible: false
    layer.enabled: true
  }

  MultiEffect {
    anchors.fill: logoImage
    source: logoImage
    visible: root.logoReady
    colorization: 1.0
    colorizationColor: root.tint
  }

  Text {
    textFormat: Text.PlainText
    anchors.centerIn: parent
    visible: !root.logoReady
    text: root.providerId === "claude" ? "C" : root.providerId === "codex" ? "O"
      : root.providerId === "opencode" ? "OC" : root.providerId === "omacode" ? "OM"
      : root.providerId === "other" ? "+" : "?"
    color: root.tint
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
  }
}
