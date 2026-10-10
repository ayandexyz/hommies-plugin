import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "bridge.js" as Bridge
import "markdown.js" as Markdown

/**
 * Hommies floating panel.
 *
 * The card that FloatingBuddy.qml opens next to the floating character. It
 * started as a copy of Panel.qml (the bar popout) and is kept separate on
 * purpose so the two can diverge: this one shows only the provider tabs
 * with their sessions and items. Settings live in the character's
 * right-click menu instead (see FloatingBuddy.qml).
 *
 * Rendering rules for items are the same as Panel.qml: Claude, OpenCode, and
 * Omacode questions keep their headers, options, descriptions, and
 * multi-select; `attention` items are notify-only; `finished` items render as
 * "Done"; failed turns render red or orange; busy sessions are listed with
 * their latest steps; "Go to terminal" focuses the agent's Hyprland window.
 */
Panel {
  id: root
  moduleName: "io.github.ayandexyz.hommies"
  manageIpc: false

  // Square, logo-only tab for the vertical rail. The agent name is the
  // tooltip; the pending count is a badge in the corner.
  component ProviderTab: Button {
    id: providerTab

    // Not `required`: the tabs are Repeater delegates (see SessionRow).
    property string providerId: ""
    property string providerName: ""
    property int pendingCount: 0

    text: ""
    tooltipText: providerName

    ProviderLogo {
      anchors.centerIn: parent
      width: Style.space(18)
      height: Style.space(18)
      providerId: providerTab.providerId
      tint: providerTab.selected
        ? Style.selectedStateColor(providerTab.foreground, providerTab.accent)
        : providerTab.foreground
      fontFamily: providerTab.fontFamily
    }

    Rectangle {
      visible: providerTab.pendingCount > 0
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(2)
      height: tabCount.implicitHeight + Style.space(2)
      width: Math.max(height, tabCount.implicitWidth + Style.space(6))
      radius: height / 2
      color: statusColors.attention

      Text {
        id: tabCount
        anchors.centerIn: parent
        text: providerTab.pendingCount > 9 ? "9+" : String(providerTab.pendingCount)
        textFormat: Text.PlainText
        color: Commons.Color.background
        font.family: providerTab.fontFamily
        font.pixelSize: Style.font.caption * 0.85
        font.bold: true
      }
    }
  }

  component SessionRow: Button {
    id: sessionRow

    // Not `required`: a required property on a Repeater delegate stops QML
    // from injecting `modelData`, which the delegate binds this from.
    property var threadData: ({ threadId: "", title: "", items: [] })

    readonly property bool finished: !busy && root.threadFinished(threadData)
    readonly property int pendingCount: root.pendingItemCount(threadData)
    readonly property string activityState: threadData.activity ? String(threadData.activity.state) : ""
    readonly property bool busy: pendingCount === 0 && (activityState === "working" || activityState === "thinking")
    readonly property string failure: root.threadFailure(threadData)
    // Status color for the stripe, fill, and label; "transparent" when idle.
    readonly property color tone: busy ? statusColors.working
      : failure !== "" ? root.failureColor(failure)
      : pendingCount > 0 ? statusColors.attention
      : finished ? statusColors.success : "transparent"
    readonly property bool toned: tone.a > 0
    // 0 → 1 the first time this session appears (see `root.firstSighting`).
    property real entrance: 1

    text: ""
    leftAlign: true
    bordered: true
    background: toned ? Util.alpha(tone, 0.07) : "transparent"
    opacity: (finished ? 0.72 : 1) * entrance
    implicitHeight: sessionContent.implicitHeight + Style.spacing.controlPaddingY * 2
    transform: Translate { id: sessionShift }

    Component.onCompleted: if (root.firstSighting("session:" + threadData.threadId)) sessionEnter.start()

    ParallelAnimation {
      id: sessionEnter
      NumberAnimation { target: sessionRow; property: "entrance"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
      NumberAnimation { target: sessionShift; property: "x"; from: Style.space(14); to: 0; duration: 320; easing.type: Easing.OutCubic }
    }

    Rectangle {
      visible: sessionRow.toned
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: Style.normalBorderWidth
      width: Style.space(3)
      radius: Math.min(Style.cornerRadius, width / 2)
      color: sessionRow.tone
      Behavior on color { ColorAnimation { duration: 200 } }
    }

    Column {
      id: sessionContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: sessionRow.horizontalPadding + Style.normalBorderWidth + Style.space(3)
      anchors.rightMargin: sessionRow.horizontalPadding + Style.normalBorderWidth
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(6)

        Text {
          id: sessionTitle
          width: parent.width - sessionCount.width - sessionChevron.width - parent.spacing * 2
          text: root.sessionLabel(sessionRow.threadData)
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: sessionRow.foreground
          font.family: sessionRow.fontFamily
          font.pixelSize: sessionRow.fontSize
          font.bold: true
        }
        Row {
          id: sessionCount
          spacing: Style.space(6)

          PulseDot {
            visible: sessionRow.busy
            anchors.verticalCenter: parent.verticalCenter
            tone: sessionRow.tone
            running: sessionRow.busy
          }
          Text {
            textFormat: Text.PlainText
            text: sessionRow.busy ? (sessionRow.activityState === "working" ? "Working" : "Thinking")
              : sessionRow.failure !== "" && sessionRow.pendingCount === 1 ? root.failureLabel(sessionRow.failure)
              : sessionRow.finished ? "Done" : String(sessionRow.pendingCount)
            color: sessionRow.toned ? sessionRow.tone : sessionRow.foreground
            font.family: sessionRow.fontFamily
            font.pixelSize: sessionRow.fontSize
            font.bold: true
            Behavior on color { ColorAnimation { duration: 200 } }
          }
        }
        Text {
          textFormat: Text.PlainText
          id: sessionChevron
          text: "\u203a"
          color: sessionRow.foreground
          opacity: 0.72
          font.family: sessionRow.fontFamily
          font.pixelSize: sessionRow.fontSize
        }
      }

      Text {
        width: parent.width
        text: root.sessionPreview(sessionRow.threadData)
        textFormat: Text.PlainText
        elide: Text.ElideRight
        color: sessionRow.foreground
        opacity: 0.65
        font.family: sessionRow.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // A tinted surface with a status stripe on the left. Holds one pending
  // item.
  component StatusCard: Rectangle {
    id: statusCard

    property color tone: root.barForeground

    color: Util.alpha(tone, 0.07)
    border.width: Style.normalBorderWidth
    border.color: Util.alpha(tone, 0.28)
    radius: Style.cornerRadius
    Behavior on color { ColorAnimation { duration: 200 } }

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.margins: statusCard.border.width
      width: Style.space(3)
      radius: Math.min(statusCard.radius, width / 2)
      color: statusCard.tone
      Behavior on color { ColorAnimation { duration: 200 } }
    }
  }

  StatusPalette { id: statusColors }

  property var hostWidget: null
  // Keys of sessions and items already shown once. Delegates are rebuilt
  // whenever the snapshot changes, so only a key's first sighting animates.
  property var seenKeys: ({})

  function firstSighting(key) {
    if (seenKeys[key]) return false
    seenKeys[key] = true
    return true
  }
  property string selectedProvider: "claude"
  /** Empty shows the session list; otherwise the open session's thread id. */
  property string selectedThreadId: ""

  readonly property var currentThreads: providerThreads(selectedProvider)
  // Falls back to the list when the open session has no pending items left.
  readonly property var openThread: {
    for (var index = 0; index < currentThreads.length; index++) {
      if (currentThreads[index].threadId === selectedThreadId) return currentThreads[index]
    }
    return null
  }

  onSelectedProviderChanged: {
    selectedThreadId = ""
    sessionCursor = 0
  }

  readonly property var builtInProviders: ["claude", "codex", "opencode", "omacode", "gemini", "antigravity", "grok"]
  /** Tabs shown before any agent is connected or active; the newer agents appear once they are. */
  readonly property var defaultProviders: ["claude", "codex", "opencode", "omacode"]

  function isBuiltIn(provider) {
    return builtInProviders.indexOf(String(provider)) >= 0
  }

  /** Whether an item or session from `provider` belongs on the `tab` ("other" holds every custom agent). */
  function onTab(provider, tab) {
    return tab === "other" ? !isBuiltIn(provider) : provider === tab
  }

  function providerName(provider) {
    return provider === "codex" ? "Codex" : provider === "opencode" ? "OpenCode"
      : provider === "omacode" ? "Omacode" : provider === "gemini" ? "Gemini"
      : provider === "antigravity" ? "Antigravity" : provider === "grok" ? "Grok"
      : provider === "other" ? "Other"
      : provider === "claude" ? "Claude" : String(provider || "Agent")
  }

  function agentName(item) {
    return providerName(item ? item.provider : "")
  }

  readonly property bool showOtherTab: providerCount("other") > 0 || sessionActivity("other").length > 0

  /**
   * Built-in agents that get a tab: the ones with Hommies hooks (the bridge's
   * `hooksConnected`) plus any that reported a session or item, such as
   * Omacode, which has no config to detect. `defaultProviders` until one qualifies.
   */
  readonly property var shownProviders: {
    var connected = hostWidget && hostWidget.snapshot && hostWidget.snapshot.hooksConnected
      ? hostWidget.snapshot.hooksConnected : []
    var shown = []
    for (var index = 0; index < builtInProviders.length; index++) {
      var provider = builtInProviders[index]
      var isConnected = false
      // XMLHttpRequest JSON arrays can arrive as array-like objects; no indexOf.
      for (var connectedIndex = 0; connectedIndex < connected.length; connectedIndex++) {
        if (String(connected[connectedIndex]) === provider) isConnected = true
      }
      if (isConnected || providerCount(provider) > 0 || sessionActivity(provider).length > 0) shown.push(provider)
    }
    return shown.length > 0 ? shown : defaultProviders
  }

  // Keep the selection on a visible tab when tabs come and go.
  function keepSelectionVisible() {
    if (selectedProvider !== "other" && shownProviders.indexOf(selectedProvider) < 0) selectedProvider = shownProviders[0]
  }
  onShownProvidersChanged: keepSelectionVisible()
  Component.onCompleted: keepSelectionVisible()

  function sessionProject(thread) {
    if (thread.project) return String(thread.project)
    // Bridges older than `project` only send "Claude Code — <folder>".
    var title = String(thread.title || "")
    var separator = title.indexOf(" \u2014 ")
    return separator >= 0 ? title.slice(separator + 3) : title
  }

  // The agent's own session title names the session; the folder is the fallback,
  // with a short id so two untitled sessions in one folder stay distinct.
  function sessionLabel(thread) {
    var prefix = thread.agent ? String(thread.agent) + "  \u00b7  " : ""
    if (thread.sessionTitle) return prefix + String(thread.sessionTitle)
    return prefix + sessionProject(thread) + "  \u00b7  " + String(thread.threadId).slice(0, 8)
  }

  /** Turn-end items whose full message is shown, by item id; kept here so a refresh does not fold them. */
  property var openMessages: ({})

  function messageOpen(item) {
    return item && openMessages[item.id] === true
  }

  function toggleMessage(item) {
    var next = {}
    for (var key in openMessages) next[key] = openMessages[key]
    if (next[item.id]) delete next[item.id]
    else next[item.id] = true
    openMessages = next
  }

  /** Line counts for step `index`, or null when it is not a file edit (older bridges never send them). */
  function stepEdit(thread, index) {
    var edits = thread && thread.activity && thread.activity.stepEdits ? thread.activity.stepEdits : null
    var edit = edits && index < edits.length ? edits[index] : null
    return edit && typeof edit.added === "number" && typeof edit.removed === "number" ? edit : null
  }

  function editLabel(edit) {
    return edit ? "+" + edit.added + " \u2212" + edit.removed : ""
  }

  function latestStep(thread) {
    var steps = thread.activity && thread.activity.steps ? thread.activity.steps : []
    if (steps.length === 0) return ""
    var edit = stepEdit(thread, steps.length - 1)
    return String(steps[steps.length - 1]) + (edit ? "  " + editLabel(edit) : "")
  }

  /**
   * How many steps the open session lists: at least 5, and more (up to the
   * bridge's 20) while the agent rail leaves the card taller than its content.
   * Set by the body's `fitSteps()`.
   */
  property int stepLimit: 5

  /** The open session's latest steps, newest last, as `{ text, edit }`. */
  function recentSteps(thread) {
    var steps = thread && thread.activity && thread.activity.steps ? thread.activity.steps : []
    var result = []
    for (var index = Math.max(0, steps.length - stepLimit); index < steps.length; index++) {
      result.push({ text: String(steps[index]), edit: stepEdit(thread, index) })
    }
    return result
  }

  function sessionPreview(thread) {
    var items = thread.items || []
    var latest = items.length > 0 ? items[items.length - 1] : null
    if (!latest || (latest.kind === "finished" && thread.activity && thread.activity.state !== "idle")) {
      var step = latestStep(thread)
      if (!step) return thread.sessionTitle ? sessionProject(thread) : ""
      return thread.sessionTitle ? sessionProject(thread) + "  \u00b7  " + step : step
    }
    var prefix = latest.kind === "permission" ? "Permission: "
      : latest.failure ? failureLabel(latest.failure) + ": "
      : latest.kind === "attention" ? "Waiting: "
      : latest.kind === "finished" ? "Finished: " : "Question: "
    var preview = prefix + String(latest.summary || "")
    return thread.sessionTitle ? sessionProject(thread) + "  \u00b7  " + preview : preview
  }

  readonly property bool questionsAnsweredInTopbar: hostWidget
    ? hostWidget.questionAnswerSurface === "topbar"
    : String(setting("questionAnswerSurface", "Top bar")) !== "Claude CLI"

  function sessionActivity(provider) {
    var sessions = hostWidget && hostWidget.snapshot && hostWidget.snapshot.sessions ? hostWidget.snapshot.sessions : []
    var result = []
    for (var index = 0; index < sessions.length; index++) {
      if (onTab(sessions[index].provider, provider)) result.push(sessions[index])
    }
    return result
  }

  function providerCount(provider) {
    var count = 0
    var threads = hostWidget && hostWidget.snapshot ? hostWidget.snapshot.threads : []
    for (var threadIndex = 0; threadIndex < threads.length; threadIndex++) {
      var items = threads[threadIndex].items || []
      for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
        if (onTab(items[itemIndex].provider, provider)) count++
      }
    }
    return count
  }

  function pendingItemCount(thread) {
    var count = 0
    var items = thread.items || []
    for (var index = 0; index < items.length; index++) {
      if (items[index].kind !== "finished") count++
    }
    return count
  }

  function threadFinished(thread) {
    return (thread.items || []).length > 0 && pendingItemCount(thread) === 0
  }

  /** "error" or "ratelimit" when one of the thread's items is a failed turn, else "". */
  function threadFailure(thread) {
    var items = thread.items || []
    for (var index = 0; index < items.length; index++) {
      if (items[index].failure) return String(items[index].failure)
    }
    return ""
  }

  function failureLabel(failure) {
    return failure === "ratelimit" ? "Rate limited" : "Error"
  }

  function failureColor(failure) {
    return failure === "ratelimit" ? statusColors.warning : statusColors.error
  }

  function itemTone(item) {
    return item.failure ? failureColor(item.failure)
      : item.kind === "permission" ? statusColors.warning
      : item.kind === "finished" ? statusColors.success
      : statusColors.attention
  }

  function threadBusy(thread) {
    var state = thread.activity ? thread.activity.state : ""
    return pendingItemCount(thread) === 0 && (state === "working" || state === "thinking")
  }

  function providerThreads(provider) {
    var result = []
    var byId = {}
    var threads = hostWidget && hostWidget.snapshot ? hostWidget.snapshot.threads : []
    for (var threadIndex = 0; threadIndex < threads.length; threadIndex++) {
      var thread = threads[threadIndex]
      var items = []
      for (var itemIndex = 0; itemIndex < thread.items.length; itemIndex++) {
        if (onTab(thread.items[itemIndex].provider, provider)) items.push(thread.items[itemIndex])
      }
      if (items.length > 0) {
        var entry = {
          threadId: thread.threadId,
          title: thread.title,
          sessionTitle: thread.sessionTitle,
          project: thread.project,
          items: items,
          activity: null,
          agent: provider === "other" ? items[0].provider : ""
        }
        byId[thread.threadId] = entry
        result.push(entry)
      }
    }
    // Bridges older than `sessions` send none, so this adds nothing for them.
    var sessions = sessionActivity(provider)
    for (var sessionIndex = 0; sessionIndex < sessions.length; sessionIndex++) {
      var session = sessions[sessionIndex]
      var existing = byId[session.threadId]
      if (existing) {
        existing.activity = session
        if (!existing.sessionTitle && session.sessionTitle) existing.sessionTitle = session.sessionTitle
      } else if (session.state !== "idle") {
        result.push({
          threadId: session.threadId,
          title: session.project || "",
          sessionTitle: session.sessionTitle,
          project: session.project,
          items: [],
          activity: session,
          agent: provider === "other" ? session.provider : ""
        })
      }
    }
    // Sessions that need you first, then busy ones; finished ones keep their relative order.
    var waiting = result.filter(function(thread) { return pendingItemCount(thread) > 0 })
    var busy = result.filter(function(thread) { return threadBusy(thread) })
    var rest = result.filter(function(thread) { return pendingItemCount(thread) === 0 && !threadBusy(thread) })
    return waiting.concat(busy).concat(rest)
  }

  function desiredPanelWidth() {
    var longest = 0
    var threads = providerThreads(root.selectedProvider)
    for (var threadIndex = 0; threadIndex < threads.length; threadIndex++) {
      var items = threads[threadIndex].items || []
      for (var itemIndex = 0; itemIndex < items.length; itemIndex++) {
        var item = items[itemIndex]
        var questions = item.questions || []
        for (var questionIndex = 0; questionIndex < questions.length; questionIndex++) {
          var question = questions[questionIndex]
          longest = Math.max(longest, String(question.question || "").length)
          var options = question.options || []
          for (var optionIndex = 0; optionIndex < options.length; optionIndex++) {
            longest = Math.max(longest, String(options[optionIndex].label || "").length)
          }
        }
      }
    }

    // Keep ordinary prompts compact, then grow quickly enough for long
    // option labels. FloatingBuddy still clamps the result to the monitor
    // width.
    var width = 500 + Math.max(0, longest - 80) * 5
    return Style.space(Math.min(760, width))
  }

  function open() {
    root.controller.show()
  }
  function close() {
    root.controller.hide()
  }
  function focusTerminal(thread) {
    Bridge.focus(thread.threadId).then(function() {
      root.close()
    }).catch(function(error) {
      console.warn("hommies could not focus the terminal:", error)
    })
  }

  // --- keyboard --------------------------------------------------------------
  // Arrows (or h/j/k/l) pick a session, Enter opens it, Esc goes back, and
  // in an open session a / d / A answer a permission, 1-9 pick a question
  // option, x dismisses a turn-end item, and t jumps to the terminal.

  /** The session row the arrow keys point at; drawn once a key was pressed. */
  property int sessionCursor: 0
  property bool keyboardNav: false
  /** True while a custom-answer field has focus: every key then goes to the field, not the shortcuts. */
  property bool typingAnswer: false
  /** Asks the matching question card to pick option `number` (1-based), or to submit. */
  signal optionKeyPressed(string itemId, int number)
  signal submitKeyPressed(string itemId)

  /** Set when a shortcut opened the card: FloatingBuddy then takes keyboard focus without a click. */
  property bool keyboardOpened: false

  onOpenedChanged: {
    keyboardNav = false
    sessionCursor = 0
    typingAnswer = false
    if (!opened) keyboardOpened = false
  }

  function cursorThread() {
    if (currentThreads.length === 0) return null
    return currentThreads[Math.max(0, Math.min(sessionCursor, currentThreads.length - 1))]
  }

  /** The open session's first item that a key can answer or dismiss. */
  function keyItem(kinds) {
    var items = openThread ? openThread.items : []
    for (var index = 0; index < items.length; index++) {
      if (kinds.indexOf(String(items[index].kind)) >= 0) return items[index]
    }
    return null
  }

  function switchProvider(direction) {
    var tabs = showOtherTab ? shownProviders.concat(["other"]) : shownProviders
    if (tabs.length === 0) return
    var index = tabs.indexOf(selectedProvider)
    selectedProvider = tabs[(Math.max(0, index) + direction + tabs.length) % tabs.length]
  }

  function moveCursor(dx, dy) {
    keyboardNav = true
    if (selectedThreadId !== "") {
      if (dx < 0) selectedThreadId = ""
      return
    }
    if (dx !== 0) {
      switchProvider(dx)
      return
    }
    if (currentThreads.length > 0) sessionCursor = Math.max(0, Math.min(currentThreads.length - 1, sessionCursor + dy))
  }

  function activateCursor() {
    keyboardNav = true
    if (selectedThreadId === "") {
      var thread = cursorThread()
      if (thread) selectedThreadId = thread.threadId
      return
    }
    var question = keyItem(["question"])
    if (question) submitKeyPressed(question.id)
  }

  function goBackOrClose() {
    if (selectedThreadId !== "") selectedThreadId = ""
    else close()
  }

  function respondKey(item, decision) {
    Bridge.respond({ threadId: openThread.threadId, requestId: item.id, decision: decision }).then(function() {
      if (root.hostWidget && typeof root.hostWidget.refreshSnapshot === "function") root.hostWidget.refreshSnapshot()
    }).catch(function(error) {
      console.warn("hommies keyboard response failed:", error)
    })
  }

  function dismissKey() {
    var item = keyItem(["attention", "finished"])
    if (item) respondKey(item, "cancel")
  }

  function handleTextKey(text) {
    keyboardNav = true
    var thread = selectedThreadId !== "" ? openThread : cursorThread()
    if (text === "t") {
      if (thread && thread.activity && thread.activity.focusable === true) focusTerminal(thread)
      return
    }
    if (selectedThreadId === "") {
      // 1-9 open the session at that position in the list.
      if (/^[1-9]$/.test(text) && Number(text) <= currentThreads.length) selectedThreadId = currentThreads[Number(text) - 1].threadId
      return
    }
    var permission = keyItem(["permission"])
    if (permission) {
      if (text === "a") respondKey(permission, "accept")
      else if (text === "d") respondKey(permission, "decline")
      else if (text === "A" && permission.canAcceptAlways === true) respondKey(permission, "acceptAlways")
      return
    }
    var question = keyItem(["question"])
    if (question && /^[1-9]$/.test(text)) optionKeyPressed(question.id, Number(text))
  }

  /** The keys that do something right now, shown under the panel once a key was used. */
  readonly property string keyHint: {
    if (selectedThreadId === "") return "\u2191\u2193 select  \u00b7  \u21b5 open  \u00b7  \u2190\u2192 agent  \u00b7  t terminal  \u00b7  esc close"
    var permission = keyItem(["permission"])
    if (permission) return "a allow  \u00b7  d deny" + (permission.canAcceptAlways === true ? "  \u00b7  A always" : "") + "  \u00b7  t terminal  \u00b7  esc back"
    if (keyItem(["question"])) return "1\u20139 option  \u00b7  \u21b5 submit  \u00b7  t terminal  \u00b7  esc back"
    if (keyItem(["attention", "finished"])) return "x dismiss  \u00b7  t terminal  \u00b7  esc back"
    return "t terminal  \u00b7  esc back"
  }

  // FloatingBuddy.qml instantiates `body` inside its own card.
  readonly property Component body: bodyComponent

  Component {
    id: bodyComponent

    PanelKeyCatcher {
      id: keyCatcher
      readonly property real contentHeight: content.implicitHeight
      blocked: root.typingAnswer
      onCloseRequested: root.goBackOrClose()
      onMoveRequested: function (dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: root.activateCursor()
      onDeleteRequested: root.dismissKey()
      onTextKey: function (text) { root.handleTextKey(text) }

      Item {
        id: content
        width: parent.width
        implicitHeight: Math.max(providerTabs.implicitHeight, sessionColumn.implicitHeight)

        // The card is as tall as the agent rail; fill the space it leaves
        // under a session with more of its steps instead of a gap. Run after
        // layout settles (callLater), so a changed limit cannot loop.
        function fitSteps() {
          if (!root.openThread) {
            root.stepLimit = 5
            return
          }
          var shown = root.recentSteps(root.openThread).length
          var spare = providerTabs.implicitHeight - sessionColumn.implicitHeight
          var rowHeight = stepProbe.implicitHeight + Style.space(2)
          var next = Math.max(5, Math.min(20, shown + Math.floor(spare / Math.max(1, rowHeight))))
          if (next !== root.stepLimit) root.stepLimit = next
        }
        Connections {
          target: root
          function onOpenThreadChanged() { Qt.callLater(content.fitSteps) }
        }

        // Measures one step row (same font as the step list).
        Text {
          id: stepProbe
          visible: false
          text: "Ag"
          textFormat: Text.PlainText
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        // Vertical rail of logo-only provider tabs.
        Column {
          id: providerTabs
          width: Style.space(40)
          spacing: Style.space(6)
          onImplicitHeightChanged: Qt.callLater(content.fitSteps)

          Repeater {
            model: root.showOtherTab ? root.shownProviders.concat(["other"]) : root.shownProviders

            delegate: ProviderTab {
              width: providerTabs.width
              height: providerTabs.width
              providerId: modelData
              providerName: root.providerName(modelData)
              pendingCount: root.providerCount(modelData)
              selected: root.selectedProvider === modelData
              bordered: true
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              onClicked: { root.selectedProvider = modelData; root.selectedThreadId = "" }
            }
          }
        }

        Column {
          id: sessionColumn
          anchors.left: providerTabs.right
          anchors.leftMargin: Style.space(10)
          anchors.right: parent.right
          spacing: Style.space(8)
          onImplicitHeightChanged: Qt.callLater(content.fitSteps)

          Text {
            textFormat: Text.PlainText
            visible: root.currentThreads.length === 0
            width: parent.width
            topPadding: Style.space(12)
            bottomPadding: Style.space(12)
            text: "No active " + root.providerName(root.selectedProvider) + " sessions"
            color: root.barForeground
            opacity: 0.65
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Repeater {
            model: root.openThread ? [] : root.currentThreads
            delegate: SessionRow {
              width: parent.width
              threadData: modelData
              hasCursor: root.keyboardNav && root.selectedThreadId === "" && index === Math.min(root.sessionCursor, root.currentThreads.length - 1)
              foreground: root.barForeground
              fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
              fontSize: Style.font.body
              onClicked: root.selectedThreadId = modelData.threadId
            }
          }

          Repeater {
            model: root.openThread ? [root.openThread] : []
            delegate: Column {
              id: threadColumn
              property var threadData: modelData
              width: parent.width
              spacing: Style.space(4)
              Button {
                width: parent.width
                text: "\u2039  " + root.sessionLabel(modelData)
                leftAlign: true
                bordered: true
                foreground: root.barForeground
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                fontSize: Style.font.body
                onClicked: root.selectedThreadId = ""
              }
              Button {
                visible: threadColumn.threadData.activity ? threadColumn.threadData.activity.focusable === true : false
                width: parent.width
                text: "↗  Go to terminal"
                bordered: true
                foreground: statusColors.attention
                background: Util.alpha(statusColors.attention, 0.08)
                fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                fontSize: Style.font.bodySmall
                onClicked: root.focusTerminal(threadColumn.threadData)
              }
              Column {
                visible: root.recentSteps(threadColumn.threadData).length > 0
                width: parent.width
                spacing: Style.space(2)

                Row {
                  id: activityHeader
                  width: parent.width
                  spacing: Style.space(6)

                  readonly property bool busy: root.threadBusy(threadColumn.threadData)

                  PulseDot {
                    visible: activityHeader.busy
                    anchors.verticalCenter: parent.verticalCenter
                    tone: statusColors.working
                    running: activityHeader.busy
                    size: Style.space(6)
                  }
                  Text {
                    textFormat: Text.PlainText
                    text: threadColumn.threadData.activity && threadColumn.threadData.activity.state === "working" ? "Working"
                      : threadColumn.threadData.activity && threadColumn.threadData.activity.state === "thinking" ? "Thinking"
                      : "Recent activity"
                    color: activityHeader.busy ? statusColors.working : root.barForeground
                    opacity: activityHeader.busy ? 1 : 0.72
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                Repeater {
                  model: root.recentSteps(threadColumn.threadData)
                  delegate: Item {
                    id: stepRow
                    width: parent.width
                    height: stepText.implicitHeight
                  
                    readonly property real stepOpacity: index === root.recentSteps(threadColumn.threadData).length - 1 ? 0.9 : 0.55
                  
                    Text {
                      id: stepText
                      anchors.left: parent.left
                      anchors.right: editCounts.visible ? editCounts.left : parent.right
                      anchors.rightMargin: editCounts.visible ? Style.space(6) : 0
                      leftPadding: Style.space(8)
                      text: modelData.text
                      textFormat: Text.PlainText
                      elide: Text.ElideRight
                      color: root.barForeground
                      opacity: stepRow.stepOpacity
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                    }
                    // Lines the edit adds and removes; the bridge never sees the edited text.
                    Row {
                      id: editCounts
                      visible: modelData.edit !== null && (modelData.edit.added > 0 || modelData.edit.removed > 0)
                      anchors.right: parent.right
                      anchors.verticalCenter: stepText.verticalCenter
                      spacing: Style.space(4)
                      opacity: Math.min(1, stepRow.stepOpacity + 0.1)
                  
                      Text {
                        visible: modelData.edit !== null && modelData.edit.added > 0
                        text: modelData.edit ? "+" + modelData.edit.added : ""
                        textFormat: Text.PlainText
                        color: statusColors.success
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption
                      }
                      Text {
                        visible: modelData.edit !== null && modelData.edit.removed > 0
                        text: modelData.edit ? "\u2212" + modelData.edit.removed : ""
                        textFormat: Text.PlainText
                        color: statusColors.error
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }
              }
              Repeater {
                model: modelData.items
                delegate: Item {
                  id: itemDelegate

                  property var itemData: modelData
                  property var draftAnswers: ({})
                  // XMLHttpRequest JSON arrays can arrive in QML as array-like
                  // QVariant values, for which Array.isArray() returns false.
                  // Repeater accepts those values directly, so only guard for a
                  // missing field instead of discarding a valid question list.
                  readonly property var questions: itemData.kind === "question" && itemData.questions
                    ? itemData.questions : []
                  readonly property bool answerInTopbar: itemData.answerSurface !== "cli"
                  // Multi-question prompts page one question at a time so a long
                  // list never pushes the panel off screen.
                  property int questionPage: 0
                  readonly property int currentQuestion: Math.max(0,
                    Math.min(questionPage, questions.length - 1))

                  function showQuestion(index) {
                    questionPage = Math.max(0, Math.min(index, questions.length - 1))
                  }

                  function answerFor(questionId) {
                    return draftAnswers[questionId]
                  }

                  function optionSelected(questionId, label) {
                    var answer = answerFor(questionId)
                    return Array.isArray(answer) ? answer.indexOf(label) >= 0 : answer === label
                  }

                  function chooseOption(question, label) {
                    if (!answerInTopbar) return
                    var next = Object.assign({}, draftAnswers)
                    if (question.multiSelect) {
                      var selected = Array.isArray(next[question.id]) ? next[question.id].slice() : []
                      var index = selected.indexOf(label)
                      if (index >= 0) selected.splice(index, 1)
                      else selected.push(label)
                      next[question.id] = selected
                    } else {
                      next[question.id] = label
                    }
                    draftAnswers = next
                    if (!question.multiSelect) showQuestion(currentQuestion + 1)
                  }

                  function setCustomAnswer(questionId, answer) {
                    if (!answerInTopbar) return
                    var next = Object.assign({}, draftAnswers)
                    next[questionId] = answer
                    draftAnswers = next
                  }

                  function readyToSubmit() {
                    if (questions.length === 0) return false
                    for (var index = 0; index < questions.length; index++) {
                      var answer = answerFor(questions[index].id)
                      if (Array.isArray(answer)) {
                        if (answer.length === 0) return false
                      } else if (typeof answer !== "string" || answer.trim().length === 0) {
                        return false
                      }
                    }
                    return true
                  }

                  function submitAnswers() {
                    if (!readyToSubmit()) return
                    var answers = {}
                    for (var index = 0; index < questions.length; index++) {
                      var question = questions[index]
                      var answer = answerFor(question.id)
                      answers[question.id] = Array.isArray(answer) ? answer.join(", ") : answer.trim()
                    }
                    Bridge.respond({
                      threadId: threadColumn.threadData.threadId,
                      requestId: itemData.id,
                      answers: answers
                    }).then(function() {
                      itemDelegate.draftAnswers = ({})
                      root.close()
                    }).catch(function(error) {
                      console.warn("hommies answer failed:", error)
                    })
                  }

                  // "cancel" releases the hook without a decision, so the
                  // provider falls back to its native terminal prompt. For
                  // attention items any decision simply dismisses them.
                  function respondPermission(decision) {
                    Bridge.respond({
                      threadId: threadColumn.threadData.threadId,
                      requestId: itemData.id,
                      decision: decision
                    }).then(function() {
                      if (root.hostWidget && typeof root.hostWidget.refreshSnapshot === "function")
                        root.hostWidget.refreshSnapshot()
                    }).catch(function(error) {
                      console.warn("hommies permission response failed:", error)
                    })
                  }

                  Connections {
                    target: root
                    function onOptionKeyPressed(itemId, number) {
                      if (itemId !== itemDelegate.itemData.id || itemDelegate.questions.length === 0) return
                      var question = itemDelegate.questions[itemDelegate.currentQuestion]
                      var options = question && question.options ? question.options : []
                      if (number <= options.length) itemDelegate.chooseOption(question, options[number - 1].label)
                    }
                    function onSubmitKeyPressed(itemId) {
                      if (itemId === itemDelegate.itemData.id) itemDelegate.submitAnswers()
                    }
                  }

                  readonly property color tone: root.itemTone(itemData)
                  readonly property real cardPadding: Style.space(8)
                  property real entrance: 1

                  width: parent.width
                  implicitHeight: itemColumn.implicitHeight + cardPadding * 2
                  opacity: entrance
                  transform: Translate { id: itemShift }

                  Component.onCompleted: if (root.firstSighting("item:" + itemData.id)) itemEnter.start()

                  ParallelAnimation {
                    id: itemEnter
                    NumberAnimation { target: itemDelegate; property: "entrance"; from: 0; to: 1; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { target: itemShift; property: "y"; from: -Style.space(8); to: 0; duration: 320; easing.type: Easing.OutCubic }
                  }

                  StatusCard {
                    anchors.fill: parent
                    tone: itemDelegate.tone
                  }

                  Column {
                    id: itemColumn
                    x: itemDelegate.cardPadding + Style.space(3)
                    y: itemDelegate.cardPadding
                    width: parent.width - x - itemDelegate.cardPadding
                    spacing: Style.space(6)
                    Row {
                    id: itemRow
                    visible: itemDelegate.itemData.kind !== "question"
                    width: parent.width
                    spacing: Style.space(8)
                    Text {
                      textFormat: Text.PlainText
                      text: itemDelegate.itemData.failure ? "!"
                        : itemDelegate.itemData.kind === "attention" ? "\u21a9"
                        : itemDelegate.itemData.kind === "finished" ? "\u2713" : "!"
                      color: itemDelegate.tone
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                    Text {
                      text: itemDelegate.itemData.summary
                      textFormat: Text.PlainText
                      color: root.barForeground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.body
                      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                      width: itemRow.width - 32
                    }
                  }

                  Item {
                    id: questionPager
                    visible: itemDelegate.questions.length > 1
                    width: parent.width
                    height: visible ? Style.space(28) : 0

                    Button {
                      id: previousQuestion
                      anchors.left: parent.left
                      width: Style.space(40)
                      height: parent.height
                      text: "‹"
                      bordered: true
                      foreground: root.barForeground
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      fontSize: Style.font.body
                      opacity: itemDelegate.currentQuestion > 0 ? 1 : 0.35
                      onClicked: itemDelegate.showQuestion(itemDelegate.currentQuestion - 1)
                    }

                    Text {
                      textFormat: Text.PlainText
                      anchors.centerIn: parent
                      text: (itemDelegate.currentQuestion + 1) + " / " + itemDelegate.questions.length
                      color: root.barForeground
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }

                    Button {
                      anchors.right: parent.right
                      width: previousQuestion.width
                      height: parent.height
                      text: "›"
                      bordered: true
                      foreground: root.barForeground
                      fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                      fontSize: Style.font.body
                      opacity: itemDelegate.currentQuestion < itemDelegate.questions.length - 1 ? 1 : 0.35
                      onClicked: itemDelegate.showQuestion(itemDelegate.currentQuestion + 1)
                    }
                  }

                  Repeater {
                    model: itemDelegate.questions

                    delegate: Column {
                      id: questionColumn
                      property var questionData: modelData
                      visible: index === itemDelegate.currentQuestion
                      width: itemColumn.width
                      spacing: Style.space(4)

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: questionColumn.questionData.header
                        color: root.barForeground
                        opacity: 0.72
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                      }

                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: questionColumn.questionData.question
                        color: root.barForeground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.body
                        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                      }

                      Repeater {
                        model: questionColumn.questionData.options

                        delegate: Column {
                          id: optionColumn
                          property var optionData: modelData
                          width: questionColumn.width
                          spacing: Style.space(2)

                          Button {
                            id: optionButton
                            width: parent.width
                            height: Math.max(Style.space(32), optionLabel.implicitHeight
                              + verticalPadding * 2 + Style.normalBorderWidth * 2)
                            text: ""
                            leftAlign: true
                            bordered: true
                            selected: itemDelegate.optionSelected(
                              questionColumn.questionData.id, optionColumn.optionData.label)
                            foreground: root.barForeground
                            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                            fontSize: Style.font.bodySmall
                            opacity: itemDelegate.answerInTopbar ? 1 : 0.72
                            onClicked: itemDelegate.chooseOption(
                              questionColumn.questionData, optionColumn.optionData.label)

                            Text {
                              id: optionLabel
                              anchors.left: parent.left
                              anchors.right: parent.right
                              anchors.verticalCenter: parent.verticalCenter
                              anchors.leftMargin: optionButton.horizontalPadding + Style.normalBorderWidth
                              anchors.rightMargin: optionButton.horizontalPadding + Style.normalBorderWidth
                              textFormat: Text.PlainText
                              text: optionColumn.optionData.label
                              color: optionButton.selected
                                ? Style.selectedStateColor(optionButton.foreground, optionButton.accent)
                                : optionButton.foreground
                              font.family: optionButton.fontFamily
                              font.pixelSize: optionButton.fontSize
                              font.bold: optionButton.selected
                              wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                            }
                          }

                          Text {
                            textFormat: Text.PlainText
                            visible: optionColumn.optionData.description !== undefined
                              && optionColumn.optionData.description !== ""
                            width: parent.width
                            leftPadding: Style.space(8)
                            rightPadding: Style.space(8)
                            text: optionColumn.optionData.description || ""
                            color: root.barForeground
                            opacity: 0.62
                            font.family: root.bar ? root.bar.fontFamily : Style.font.family
                            font.pixelSize: Style.font.caption
                            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                          }
                        }
                      }

                      TextInput {
                        visible: itemDelegate.answerInTopbar
                        width: parent.width
                        color: root.barForeground
                        font.family: root.bar ? root.bar.fontFamily : Style.font.family
                        font.pixelSize: Style.font.body
                        text: ""
                        focus: false
                        clip: true
                        onTextEdited: itemDelegate.setCustomAnswer(questionColumn.questionData.id, text)
                        onAccepted: itemDelegate.submitAnswers()
                        onActiveFocusChanged: root.typingAnswer = activeFocus
                      }
                    }
                  }

                  Text {
                    visible: itemDelegate.itemData.kind === "question"
                      && itemDelegate.questions.length === 0
                    width: parent.width
                    text: itemDelegate.itemData.summary || (root.agentName(itemDelegate.itemData) + " needs your input")
                    textFormat: Text.PlainText
                    color: root.barForeground
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                  }

                  Text {
                    textFormat: Text.PlainText
                    visible: itemDelegate.itemData.kind === "question"
                    text: itemDelegate.answerInTopbar
                      ? (itemDelegate.questions.length > 0
                          ? "Select or type an answer for every question"
                          : "This question has no structured input")
                      : "Answer this question in " + root.agentName(itemDelegate.itemData)
                    color: root.barForeground
                    opacity: 0.65
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.body
                  }

                  Button {
                    visible: itemDelegate.itemData.kind === "question"
                      && itemDelegate.answerInTopbar
                      && itemDelegate.questions.length > 0
                    width: parent.width
                    text: "Send answer"
                    bordered: true
                    foreground: itemDelegate.readyToSubmit() ? statusColors.attention : root.barForeground
                    background: itemDelegate.readyToSubmit() ? Util.alpha(statusColors.attention, 0.14) : "transparent"
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    fontSize: Style.font.body
                    opacity: itemDelegate.readyToSubmit() ? 1 : 0.5
                    Behavior on opacity { NumberAnimation { duration: 160 } }
                    onClicked: itemDelegate.submitAnswers()
                  }

                  Text {
                    textFormat: Text.PlainText
                    visible: itemDelegate.itemData.kind === "attention" || itemDelegate.itemData.kind === "finished"
                    text: itemDelegate.itemData.failure === "ratelimit"
                      ? root.agentName(itemDelegate.itemData) + " stopped on a usage limit; retry in the terminal when it resets"
                      : itemDelegate.itemData.failure
                      ? root.agentName(itemDelegate.itemData) + " stopped on an error; retry in the terminal"
                      : itemDelegate.itemData.kind === "finished"
                      ? root.agentName(itemDelegate.itemData) + " finished this turn"
                      : root.agentName(itemDelegate.itemData) + " is waiting for your reply in the terminal"
                    color: root.barForeground
                    opacity: 0.65
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    font.pixelSize: Style.font.caption
                  }

                  // The agent's full final message, folded by default. Long ones scroll inside
                  // a capped box: the panel itself is sized to its content and does not scroll.
                  Button {
                    visible: typeof itemDelegate.itemData.message === "string" && itemDelegate.itemData.message.length > 0
                    width: parent.width
                    leftAlign: true
                    text: root.messageOpen(itemDelegate.itemData) ? "\u25be Hide full message" : "\u25b8 Show full message"
                    foreground: root.barForeground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    fontSize: Style.font.caption
                    onClicked: root.toggleMessage(itemDelegate.itemData)
                  }

                  Flickable {
                    id: messageBox
                    visible: root.messageOpen(itemDelegate.itemData) && typeof itemDelegate.itemData.message === "string"
                    width: parent.width
                    height: visible ? Math.min(messageText.implicitHeight, Style.space(240)) : 0
                    contentWidth: width
                    contentHeight: messageText.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Text {
                      id: messageText
                      width: messageBox.width - Style.space(8)
                      // markdown.js escapes the message and adds only formatting tags, never <img> or <a>.
                      text: messageBox.visible ? Markdown.toStyledText(itemDelegate.itemData.message) : ""
                      textFormat: Text.StyledText
                      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                      color: root.barForeground
                      opacity: 0.85
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    // A thin bar on the right while the message is taller than the box.
                    Rectangle {
                      visible: messageBox.contentHeight > messageBox.height
                      x: messageBox.width - width
                      y: messageBox.contentY + messageBox.visibleArea.yPosition * messageBox.height
                      width: Style.space(2)
                      height: Math.max(Style.space(16), messageBox.visibleArea.heightRatio * messageBox.height)
                      radius: width / 2
                      color: root.barForeground
                      opacity: 0.35
                    }
                  }

                  Button {
                    visible: itemDelegate.itemData.kind === "attention" || itemDelegate.itemData.kind === "finished"
                    width: parent.width
                    text: "Dismiss"
                    bordered: true
                    foreground: root.barForeground
                    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                    fontSize: Style.font.bodySmall
                    onClicked: itemDelegate.respondPermission("cancel")
                  }

                  Row {
                    id: permissionRow
                    visible: itemDelegate.itemData.kind === "permission"
                    width: parent.width
                    spacing: Style.space(4)

                    // "Always" only appears when the agent can remember the rule
                    // (Claude with permission suggestions, OpenCode).
                    readonly property var choices: itemDelegate.itemData.canAcceptAlways === true
                      ? [
                          { label: "✓ Allow", decision: "accept" },
                          { label: "✓✓ Always", decision: "acceptAlways" },
                          { label: "✕ Deny", decision: "decline" },
                          { label: "Ask in CLI", decision: "cancel" }
                        ]
                      : [
                          { label: "✓ Allow", decision: "accept" },
                          { label: "✕ Deny", decision: "decline" },
                          { label: "Ask in CLI", decision: "cancel" }
                        ]

                    function choiceTone(decision) {
                      return decision === "accept" ? statusColors.success
                        : decision === "acceptAlways" ? statusColors.attention
                        : decision === "decline" ? statusColors.error
                        : root.barForeground
                    }

                    Repeater {
                      model: permissionRow.choices

                      delegate: Button {
                        readonly property color tone: permissionRow.choiceTone(modelData.decision)
                        readonly property bool plain: modelData.decision === "cancel"

                        width: (permissionRow.width - permissionRow.spacing * (permissionRow.choices.length - 1))
                          / permissionRow.choices.length
                        text: modelData.label
                        bordered: true
                        foreground: tone
                        background: plain ? "transparent" : Util.alpha(tone, modelData.decision === "accept" ? 0.18 : 0.1)
                        opacity: plain ? 0.8 : 1
                        fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
                        fontSize: Style.font.bodySmall
                        onClicked: itemDelegate.respondPermission(modelData.decision)
                      }
                    }
                  }
                  }
                }
              }
            }
          }

          Text {
            visible: root.keyboardNav
            width: parent.width
            text: root.keyHint
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            color: root.barForeground
            opacity: 0.5
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
