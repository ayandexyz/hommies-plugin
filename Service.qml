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

  /** Asks the character to play an emote (see the contract in characters/Hommie.qml). */
  signal emoteRequested(string name)

  /** Finished-turn item ids already seen; null until the first snapshot, which never celebrates. */
  property var seenFinished: null

  /** Celebrates a turn that just finished, even while the mood shows something busier. */
  function noticeFinished(next) {
    var seen = {}
    var fresh = false
    var threads = next && next.threads ? next.threads : []
    for (var threadIndex = 0; threadIndex < threads.length; threadIndex++) {
      var items = threads[threadIndex].items || []
      for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
        if (items[itemIndex].kind !== "finished" || items[itemIndex].failure) continue
        seen[items[itemIndex].id] = true
        if (root.seenFinished !== null && !root.seenFinished[items[itemIndex].id]) fresh = true
      }
    }
    root.seenFinished = seen
    if (fresh) root.emoteRequested("celebrate")
  }

  function refreshSnapshot() {
    Bridge.snapshot().then(function(next) {
      var json = JSON.stringify(next)
      if (json !== root.snapshotJson) {
        root.snapshotJson = json
        root.snapshot = next
        root.noticeFinished(next)
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

  // --- outfit ----------------------------------------------------------------

  /** Accessories the character can wear (see `outfit` in characters/Hommie.qml). */
  readonly property var outfits: ["party", "beanie", "crown", "santa", "pumpkin", "bow", "glasses", "sunglasses", "scarf"]
  /** The saved choice: "auto" (the season's, if any), "none", or one of `outfits`. */
  readonly property string outfitChoice: prefs.outfit === "none" || outfits.indexOf(prefs.outfit) >= 0 ? prefs.outfit : "auto"
  /** Today, refreshed every hour so Auto changes outfit on its own. */
  property var today: new Date()
  readonly property string seasonalOutfit: {
    var month = today.getMonth(), day = today.getDate()
    if ((month === 11 && day === 31) || (month === 0 && day === 1)) return "party"
    if (month === 11) return "santa"
    if (month === 9 && day >= 20) return "pumpkin"
    return ""
  }
  /** What the character wears now; empty for nothing. */
  readonly property string outfit: outfitChoice === "auto" ? seasonalOutfit : outfitChoice === "none" ? "" : outfitChoice

  function setOutfit(choice) {
    savePrefs({ outfit: choice === "none" || outfits.indexOf(choice) >= 0 ? choice : "auto" })
  }
  /** Steps through Auto, None, and every outfit. */
  function cycleOutfit(direction) {
    var order = ["auto", "none"].concat(outfits)
    var index = order.indexOf(outfitChoice)
    setOutfit(order[(index + direction + order.length) % order.length])
  }
  function outfitLabel(name) {
    var labels = { auto: "Auto", none: "None", party: "Party hat", beanie: "Beanie", crown: "Crown", santa: "Santa hat",
      pumpkin: "Pumpkin", bow: "Bow", glasses: "Glasses", sunglasses: "Sunglasses", scarf: "Scarf" }
    return labels[name] || String(name)
  }

  Timer {
    interval: 60 * 60 * 1000
    running: true
    repeat: true
    onTriggered: root.today = new Date()
  }

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
    // Only the port this child announces is trusted (see bridge.js).
    stdout: SplitParser {
      onRead: function(line) {
        var match = /^hommies-bridge listening on 127\.0\.0\.1:(\d+)$/.exec(String(line).trim())
        if (match && Bridge.setLivePort(Number(match[1]))) {
          root.syncPreferences()
          root.refreshSnapshot()
        }
      }
    }
    onExited: {
      Bridge.setLivePort(0)
      restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 3000
    repeat: false
    onTriggered: bridgeProcess.running = true
  }

  // The daemon rewrites port.json on every start; reconfigure the client
  // each time it changes. It takes effect once the port matches the child's.
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

  // --- keyboard shortcuts ----------------------------------------------------
  // Plugins cannot bind keys, so Hyprland binds call these over shell IPC:
  // `omarchy-shell hommies <method>` (see README).

  /** The oldest item waiting on you: permissions and questions first, then turn ends. */
  function nextPending() {
    var threads = snapshot && snapshot.threads ? snapshot.threads : []
    var rank = function(kind) { return kind === "permission" || kind === "question" ? 0 : kind === "attention" ? 1 : 2 }
    var best = null
    for (var threadIndex = 0; threadIndex < threads.length; threadIndex++) {
      var items = threads[threadIndex].items || []
      for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
        var item = items[itemIndex]
        var better = best === null || rank(item.kind) < rank(best.item.kind)
          || (rank(item.kind) === rank(best.item.kind) && String(item.createdAt) < String(best.item.createdAt))
        if (better) best = { thread: threads[threadIndex], item: item }
      }
    }
    return best
  }

  /** The newest session whose terminal can be focused, busy ones first. */
  function focusableSession() {
    var sessions = snapshot && snapshot.sessions ? snapshot.sessions : []
    var fallback = ""
    for (var index = 0; index < sessions.length; index++) {
      if (sessions[index].focusable !== true) continue
      if (sessions[index].state !== "idle") return String(sessions[index].threadId)
      if (fallback === "") fallback = String(sessions[index].threadId)
    }
    return fallback
  }

  /** Opens the card with keyboard focus, so its keys work without a click. */
  function openCard() {
    var panel = panelLoader.item
    if (!panel || !root.screen) return false
    panel.keyboardOpened = true
    panel.open()
    return true
  }

  IpcHandler {
    target: "hommies"

    function open(): string { return root.openCard() ? "open" : "unavailable" }
    function close(): void { if (panelLoader.item) panelLoader.item.close() }
    function toggle(): string {
      if (panelLoader.item && panelLoader.item.opened) {
        panelLoader.item.close()
        return "closed"
      }
      return root.openCard() ? "open" : "unavailable"
    }
    /** Opens the card on the oldest waiting permission or question (else a turn end). */
    function jumpToPending(): string {
      var next = root.nextPending()
      var panel = panelLoader.item
      if (next === null) return "none"
      if (!panel) return "unavailable"
      var provider = String(next.item.provider)
      panel.selectedProvider = panel.isBuiltIn(provider) ? provider : "other"
      panel.selectedThreadId = String(next.thread.threadId)
      return root.openCard() ? String(next.item.kind) : "unavailable"
    }
    /** Focuses the terminal of the session waiting on you, else the newest busy one. */
    function focusTerminal(): string {
      var next = root.nextPending()
      var threadId = next !== null ? String(next.thread.threadId) : root.focusableSession()
      if (threadId === "") return "none"
      Bridge.focus(threadId).catch(function(error) { console.warn("hommies could not focus the terminal:", error) })
      return "ok"
    }
    function toggleSounds(): string {
      root.setSounds(!root.sounds)
      return root.sounds ? "on" : "off"
    }
    function toggleNotifications(): string {
      root.setDesktopNotifications(!root.desktopNotifications)
      return root.desktopNotifications ? "on" : "off"
    }
    /** Sets the outfit ("auto", "none", or a name) and returns what he wears now ("none" for nothing). */
    function outfit(name: string): string {
      if (name !== "auto" && name !== "none" && root.outfits.indexOf(name) < 0) return "unknown"
      root.setOutfit(name)
      return root.outfit === "" ? "none" : root.outfit
    }
    /** Plays an emote: greet, celebrate, dizzy, wink, yawn, or look. Urgent moods block them. */
    function emote(name: string): string {
      if (["greet", "celebrate", "dizzy", "wink", "yawn", "look"].indexOf(name) < 0) return "unknown"
      root.emoteRequested(name)
      return "ok"
    }
  }

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
