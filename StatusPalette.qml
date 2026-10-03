import QtQuick
import Quickshell.Io
import qs.Commons

// Status colors taken from the active Omarchy theme's colors.toml, so error,
// success, and working states match the theme instead of fixed hex values.
// `Color` only exposes foreground/background/accent/urgent/muted, so the
// named pigments (red, green, ...) are read here. Dark themes prefer the
// `bright_*` variants for contrast on dark surfaces. Every role falls back to
// the shell palette when the theme leaves a key out.
Item {
  id: root
  visible: false

  property var tokens: ({})
  readonly property bool lightMode: tokens.mode === "light"

  readonly property color error: pick(["red", "color1"], Color.urgent)
  readonly property color warning: pick(["orange", "yellow", "color3"], "#f97316")
  readonly property color success: pick(["green", "color2"], "#22c55e")
  readonly property color working: pick(["cyan", "blue", "color6", "color4"], Color.accent)
  readonly property color attention: Color.accent
  readonly property color muted: Color.muted

  function pick(keys, fallback) {
    for (var index = 0; index < keys.length; index++) {
      var key = keys[index]
      var bright = key.indexOf("color") === 0 ? "" : "bright_" + key
      if (!lightMode && bright !== "" && tokens[bright]) return tokens[bright]
      if (tokens[key]) return tokens[key]
    }
    return fallback
  }

  function parse(raw) {
    var result = {}
    var lines = String(raw || "").split("\n")
    for (var index = 0; index < lines.length; index++) {
      var match = lines[index].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#?[^"'#\s]+)/)
      if (match) result[match[1]] = match[2]
    }
    return result
  }

  FileView {
    path: Color.currentThemePath + "/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.tokens = root.parse(text())
  }
}
