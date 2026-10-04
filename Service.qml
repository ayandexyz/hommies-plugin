import QtQuick
import Quickshell
import Quickshell.Io
import "bridge.js" as Bridge

// Headless singleton owned by the Omarchy shell. Spawns the bridge daemon,
// and hosts the floating character (FloatingBuddy.qml) that replaces the bar
// bell: it polls the bridge, keeps the answer-surface/notification/sound
// preferences, and is the `hostWidget` that FloatingPanel.qml reads from.
// Keep this as an Item: a file named Service.qml cannot instantiate Service
// or it recursively instantiates itself.
Item {
  id: root

  readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share"
  readonly property string dataDir: dataHome + "/hommies"
  // The folder from before the rename to Hommies; preferences saved there are carried over once.
  readonly property string legacyDataDir: dataHome + "/agent-fold"

  // --- host API used by Panel.qml (same shape as BarWidget.qml) ----------

  property var snapshot: ({ totalCount: 0, threads: [], sessions: [] })
  property string snapshotJson: ""
  readonly property int totalCount: snapshot && snapshot.totalCount ? snapshot.totalCount : 0

  // Floating UI preferences, saved to <dataDir>/floating.json.
  property var prefs: ({})
  property bool prefsLoaded: false
  readonly property string questionAnswerSurface: prefs.questionAnswerSurface === "cli" ? "cli" : "topbar"
  readonly property bool desktopNotifications: prefs.desktopNotifications !== false
  readonly property bool sounds: prefs.sounds === true
  /** Draw the character above fullscreen windows (Overlay layer) instead of under them (Top layer). */
  readonly property bool overFullscreen: prefs.overFullscreen !== false
  /** File name (without .qml) in characters/. */
  readonly property string character: typeof prefs.character === "string" && /^[A-Za-z0-9_-]+$/.test(prefs.character)
    ? prefs.character : "Hommie"

  function refreshSnapshot() {
    Bridge.snapshot().then(function(next) {
      var json = JSON.stringify(next)
      if (json !== root.snapshotJson) {
        root.snapshotJson = json
        root.snapshot = next
      }
    }).catch(function(error) {
      console.warn("hommies snapshot failed:", error)
    })
  }
  function syncPreferences() {
    if (!prefsLoaded) return
    Bridge.setPreferences({
      questionAnswerSurface: root.questionAnswerSurface,
      desktopNotifications: root.desktopNotifications,
      sounds: root.sounds
    }).catch(function(error) {
      console.warn("hommies preference sync failed:", error)
    })
  }
  function setQuestionAnswerSurface(surface) { savePrefs({ questionAnswerSurface: surface === "cli" ? "cli" : "topbar" }) }
  function setDesktopNotifications(enabled) { savePrefs({ desktopNotifications: enabled === true }) }
  function setSounds(enabled) { savePrefs({ sounds: enabled === true }) }
  function setOverFullscreen(enabled) { savePrefs({ overFullscreen: enabled === true }) }

  function savePrefs(changes) {
    var next = {}
    for (var key in root.prefs) next[key] = root.prefs[key]
    for (var change in changes) next[change] = changes[change]
    root.prefs = next
    prefsFile.setText(JSON.stringify(next, null, 2) + "\n")
  }

  onQuestionAnswerSurfaceChanged: syncPreferences()
  onDesktopNotificationsChanged: syncPreferences()
  onSoundsChanged: syncPreferences()

  // --- character mood ------------------------------------------------------

  // Seconds of nothing at all before the character falls asleep.
  readonly property int sleepAfter: 600
  property bool asleep: false

  /** What the character shows, most urgent first. */
  readonly property string mood: {
    var permission = false, question = false, error = false, ratelimit = false, finished = false
    var threads = snapshot && snapshot.threads ? snapshot.threads : []
    for (var threadIndex = 0; threadIndex < threads.length; threadIndex++) {
      var items = threads[threadIndex].items || []
      for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
        var item = items[itemIndex]
        if (item.failure === "ratelimit") ratelimit = true
        else if (item.failure) error = true
        else if (item.kind === "permission") permission = true
        else if (item.kind === "question" || item.kind === "attention") question = true
        else if (item.kind === "finished") finished = true
      }
    }
    var working = false, thinking = false
    var sessions = snapshot && snapshot.sessions ? snapshot.sessions : []
    for (var index = 0; index < sessions.length; index++) {
      if (sessions[index].state === "working") working = true
      else if (sessions[index].state === "thinking") thinking = true
    }
    return permission ? "approval"
      : question ? "question"
      : error ? "error"
      : ratelimit ? "ratelimit"
      : working ? "working"
      : thinking ? "thinking"
      : finished ? "finished"
      : asleep ? "sleeping" : "idle"
  }

  readonly property string statusLine: {
    switch (mood) {
      case "approval": return "Needs your approval"
      case "question": return "Has a question for you"
      case "error": return "A turn failed"
      case "ratelimit": return "Rate limited"
      case "working": return "Agents working…"
      case "thinking": return "Thinking…"
      case "finished": return "Done — " + totalCount + " to review"
      case "sleeping": return "Zzz… no agents running"
      default: return "No pending items"
    }
  }

  onMoodChanged: {
    if (mood !== "idle" && mood !== "sleeping") asleep = false
    sleepTimer.restart()
  }

  Timer {
    id: sleepTimer
    interval: root.sleepAfter * 1000
    running: true
    onTriggered: if (root.mood === "idle") root.asleep = true
  }

  // --- screen ----------------------------------------------------------------

  readonly property var screen: {
    var screens = Quickshell.screens
    for (var index = 0; index < screens.length; index++) {
      if (screens[index].name === prefs.screen) return screens[index]
    }
    return screens.length > 0 ? screens[0] : null
  }

  function moveToNextScreen() {
    var screens = Quickshell.screens
    if (screens.length < 2 || !root.screen) return
    var current = screens.indexOf(root.screen)
    savePrefs({ screen: screens[(current + 1) % screens.length].name })
  }

  // --- bridge daemon ---------------------------------------------------------

  Process {
    id: bridgeProcess
    command: ["hommies-bridge", "--data-dir", root.dataDir, "--port", "0"]
    running: true
    onExited: restartTimer.restart()
  }

  Timer {
    id: restartTimer
    interval: 3000
    repeat: false
    onTriggered: bridgeProcess.running = true
  }

  // The daemon rewrites port.json on every start; reconfigure the client
  // each time it changes.
  FileView {
    path: root.dataDir + "/port.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        Bridge.configure(JSON.parse(text()))
        root.syncPreferences()
        root.refreshSnapshot()
      } catch (error) {
        console.warn("hommies connection file invalid:", error)
      }
    }
  }

  FileView {
    id: prefsFile
    path: root.dataDir + "/floating.json"
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        if (parsed && typeof parsed === "object") root.prefs = parsed
      } catch (_) {}
      root.prefsLoaded = true
      root.syncPreferences()
    }
    onLoadFailed: legacyPrefsFile.path = root.legacyDataDir + "/floating.json"
  }

  // No floating.json in the Hommies folder yet: load the one saved before the
  // rename, if any, and save it under the new folder.
  FileView {
    id: legacyPrefsFile
    path: ""
    printErrors: false
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        if (parsed && typeof parsed === "object") {
          root.prefs = parsed
          prefsFile.setText(JSON.stringify(parsed, null, 2) + "\n")
        }
      } catch (_) {}
      root.prefsLoaded = true
      root.syncPreferences()
    }
    onLoadFailed: {
      root.prefsLoaded = true
      root.syncPreferences()
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshSnapshot()
  }

  // --- floating UI -----------------------------------------------------------

  Loader {
    id: panelLoader
    Component.onCompleted: setSource(Qt.resolvedUrl("FloatingPanel.qml"), { hostWidget: root })
  }

  LazyLoader {
    active: root.screen !== null && panelLoader.item !== null

    FloatingBuddy {
      screen: root.screen
      host: root
      panel: panelLoader.item
    }
  }
}
