import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "bridge.js" as Bridge

/**
 * agent-fold bar widget.
 *
 * Shows a bell glyph with a pending count badge. Click toggles the Panel
 * (defined in Panel.qml), which lists the pending items grouped by thread.
 *
 * The `bridge.mjs` module is the only thing in this plugin that talks to
 * the bridge daemon — it is loaded lazily and exposes `Bridge.snapshot()`,
 * `Bridge.subscribe()`, `Bridge.respond()`.
 *
 * Module name MUST match the manifest id and the `moduleName` in Panel.qml
 * and Service.qml.
 */
BarWidget {
  id: root
  moduleName: "io.github.ayandexyz.hommies"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  readonly property string questionAnswerSurface: String(setting("questionAnswerSurface", "Top bar")) === "Claude CLI"
    ? "cli" : "topbar"
  readonly property bool desktopNotifications: setting("desktopNotifications", true) !== false
  readonly property bool sounds: setting("sounds", false) === true
  property var snapshot: ({ totalCount: 0, threads: [], sessions: [] })
  // The last snapshot as JSON. Polls that return the same data are dropped
  // so the panel's delegates (and their animations) are not rebuilt.
  property string snapshotJson: ""
  // False until the first snapshot lands, so startup doesn't ring the bell.
  property bool primed: false
  property int lastTotalCount: 0
  readonly property int totalCount: snapshot && snapshot.totalCount ? snapshot.totalCount : 0
  /** Sessions thinking or running tools; shown as a dot next to the bell. */
  readonly property int busyCount: {
    var sessions = snapshot && snapshot.sessions ? snapshot.sessions : []
    var count = 0
    for (var index = 0; index < sessions.length; index++) {
      if (sessions[index].state === "working" || sessions[index].state === "thinking") count++
    }
    return count
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }
  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }
  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }
  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.settings = root.settings
  }
  function refreshSnapshot() {
    if (typeof Bridge !== "undefined") {
      Bridge.snapshot().then((s) => {
        var json = JSON.stringify(s)
        if (json !== root.snapshotJson) {
          root.snapshotJson = json
          root.snapshot = s
        }
        root.primed = true
      }).catch((error) => {
        console.warn("agent-fold snapshot failed:", error)
      })
    }
  }
  function syncPreferences() {
    if (typeof Bridge === "undefined") return
    Bridge.setPreferences({
      questionAnswerSurface: root.questionAnswerSurface,
      desktopNotifications: root.desktopNotifications,
      sounds: root.sounds
    }).catch((error) => {
      console.warn("agent-fold preference sync failed:", error)
    })
  }
  function setQuestionAnswerSurface(surface) {
    updateSetting("questionAnswerSurface", surface === "cli" ? "Claude CLI" : "Top bar")
  }
  function setDesktopNotifications(enabled) {
    updateSetting("desktopNotifications", enabled === true)
  }
  function setSounds(enabled) {
    updateSetting("sounds", enabled === true)
  }
  function updateSetting(name, value) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry[name] = value

    // Update the live widget first, then persist through Omarchy's supported
    // inline-settings API. The binding above synchronizes the bridge.
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onQuestionAnswerSurfaceChanged: syncPreferences()
  onDesktopNotificationsChanged: syncPreferences()
  onSoundsChanged: syncPreferences()
  onTotalCountChanged: {
    if (primed && totalCount > lastTotalCount) ring.restart()
    lastTotalCount = totalCount
  }

  StatusPalette { id: statusColors }

  FileView {
    path: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/agent-fold/port.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        Bridge.configure(JSON.parse(text()))
        root.syncPreferences()
        root.refreshSnapshot()
      } catch (error) {
        console.warn("agent-fold connection file invalid:", error)
      }
    }
  }

  Timer {
    id: pollTimer
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshSnapshot()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The bell, badge, and working dot are drawn below so they can animate;
    // the built-in label stays empty.
    labelVisible: false
    hasVisualContent: true
    fixedWidth: vertical ? -1 : bellContent.implicitWidth + scaledHorizontalMargin * 2
    fixedHeight: vertical ? bellContent.implicitHeight + scaledVerticalPadding * 2 : -1
    tooltipText: (root.totalCount > 0
      ? root.totalCount + " pending agent item(s)"
      : "Hommies: no pending items")
      + (root.busyCount > 0 ? "\n" + root.busyCount + " agent session(s) working" : "")
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }

    Grid {
      id: bellContent
      anchors.centerIn: parent
      columns: button.vertical ? 1 : 3
      spacing: Style.space(4)
      horizontalItemAlignment: Grid.AlignHCenter
      verticalItemAlignment: Grid.AlignVCenter

      Text {
        id: bellGlyph
        text: "\ud83d\udd14"
        textFormat: Text.PlainText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: button.fontSize
        renderType: Text.NativeRendering
        transformOrigin: Item.Top
      }

      Rectangle {
        id: badge
        visible: root.totalCount > 0
        height: badgeText.implicitHeight + Style.space(2)
        width: Math.max(height, badgeText.implicitWidth + Style.space(8))
        radius: height / 2
        color: statusColors.attention

        Text {
          id: badgeText
          anchors.centerIn: parent
          text: root.totalCount > 99 ? "99+" : String(root.totalCount)
          textFormat: Text.PlainText
          color: Color.background
          font.family: button.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }
      }

      PulseDot {
        visible: root.busyCount > 0
        tone: statusColors.working
        running: root.busyCount > 0
        size: Style.space(6)
      }
    }

    // Rings the bell and pops the badge when the pending count goes up.
    ParallelAnimation {
      id: ring

      SequentialAnimation {
        NumberAnimation { target: bellGlyph; property: "rotation"; to: 20; duration: 70; easing.type: Easing.OutQuad }
        NumberAnimation { target: bellGlyph; property: "rotation"; to: -16; duration: 110; easing.type: Easing.InOutQuad }
        NumberAnimation { target: bellGlyph; property: "rotation"; to: 11; duration: 100; easing.type: Easing.InOutQuad }
        NumberAnimation { target: bellGlyph; property: "rotation"; to: -6; duration: 90; easing.type: Easing.InOutQuad }
        NumberAnimation { target: bellGlyph; property: "rotation"; to: 0; duration: 90; easing.type: Easing.OutQuad }
      }
      SequentialAnimation {
        NumberAnimation { target: badge; property: "scale"; from: 1; to: 1.35; duration: 120; easing.type: Easing.OutQuad }
        NumberAnimation { target: badge; property: "scale"; to: 1; duration: 260; easing.type: Easing.OutBack }
      }
    }
  }
}
