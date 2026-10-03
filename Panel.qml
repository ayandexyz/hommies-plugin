import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "bridge.js" as Bridge

/**
 * agent-fold panel.
 *
 * Opened by BarWidget.qml on click. Lists pending questions and permissions
 * grouped by thread. Claude, OpenCode, and Omacode questions retain their headers, options,
 * descriptions, and multi-select behavior. The configured answer surface
 * decides whether controls here are interactive or mirror the CLI prompt.
 * `attention` items are notify-only: the agent ended its turn with a plain-text
 * question, so the reply happens in the terminal and the bar can only dismiss.
 * `finished` items mark a session whose turn ended without a question. They
 * count toward the bell like other items but render as "Done".
 * Sessions that are thinking or running tools are listed too, with their
 * latest steps, even when nothing needs an answer (`snapshot.sessions`).
 * An `attention` item with `failure` set means the turn stopped on an API
 * error or a rate limit; it renders red or orange and is dismissed the same way.
 * Custom agents (`agent-fold-hook --agent <name>`) share the "Other" tab,
 * which only appears while one of them is listed.
 * "Go to terminal" focuses the Hyprland window the session runs in, when the
 * adapter sent the agent's process ancestry (`activity.focusable`).
 *
 * Each provider tab first lists its sessions (one row per thread); clicking a
 * row opens that session's items and the back row returns to the list.
 */
Panel {
  id: root
  moduleName: "io.github.ayandexyz.hommies"
  manageIpc: false

  component ProviderTab: Button {
    id: providerTab

    required property string providerId
    required property string providerName
    required property int pendingCount

    text: ""
    implicitHeight: tabContent.implicitHeight + Style.spacing.controlPaddingY * 2

    Row {
      id: tabContent
      anchors.centerIn: parent
      spacing: Style.spacing.controlGap

      ProviderLogo {
        anchors.verticalCenter: parent.verticalCenter
        providerId: providerTab.providerId
        tint: providerTab.selected
          ? Style.selectedStateColor(providerTab.foreground, providerTab.accent)
          : providerTab.foreground
        fontFamily: providerTab.fontFamily
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        text: providerTab.providerName + "  " + providerTab.pendingCount
        color: providerTab.selected
          ? Style.selectedStateColor(providerTab.foreground, providerTab.accent)
          : providerTab.foreground
        font.family: providerTab.fontFamily
        font.pixelSize: providerTab.fontSize
        font.bold: providerTab.selected
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
  // item, or a notice such as the outdated-hooks reminder.
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

  property var anchorItem: null
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

  onSelectedProviderChanged: selectedThreadId = ""

  readonly property var builtInProviders: ["claude", "codex", "opencode", "omacode"]

  function isBuiltIn(provider) {
    return builtInProviders.indexOf(String(provider)) >= 0
  }

  /** Whether an item or session from `provider` belongs on the `tab` ("other" holds every custom agent). */
  function onTab(provider, tab) {
    return tab === "other" ? !isBuiltIn(provider) : provider === tab
  }

  function providerName(provider) {
    return provider === "codex" ? "Codex" : provider === "opencode" ? "OpenCode"
      : provider === "omacode" ? "Omacode" : provider === "other" ? "Other"
      : provider === "claude" ? "Claude" : String(provider || "Agent")
  }

  function agentName(item) {
    return providerName(item ? item.provider : "")
  }

  /** e.g. "Claude, Codex" when `hommies setup --check` would report them out of date. */
  readonly property string outdatedHooks: {
    var providers = hostWidget && hostWidget.snapshot && hostWidget.snapshot.hooksOutdated ? hostWidget.snapshot.hooksOutdated : []
    var names = []
    for (var index = 0; index < providers.length; index++) names.push(providerName(providers[index]))
    return names.join(", ")
  }

  readonly property bool showOtherTab: providerCount("other") > 0 || sessionActivity("other").length > 0

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

  function latestStep(thread) {
    var steps = thread.activity && thread.activity.steps ? thread.activity.steps : []
    return steps.length > 0 ? String(steps[steps.length - 1]) : ""
  }

  /** The open session's latest steps, newest last. */
  function recentSteps(thread) {
    var steps = thread && thread.activity && thread.activity.steps ? thread.activity.steps : []
    var result = []
    for (var index = Math.max(0, steps.length - 5); index < steps.length; index++) result.push(String(steps[index]))
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

  readonly property bool desktopNotifications: hostWidget
    ? hostWidget.desktopNotifications
    : setting("desktopNotifications", true) !== false

  readonly property bool sounds: hostWidget
    ? hostWidget.sounds
    : setting("sounds", false) === true

  function toggleSounds() {
    if (!hostWidget || typeof hostWidget.setSounds !== "function") return
    hostWidget.setSounds(!root.sounds)
  }

  function toggleDesktopNotifications() {
    if (!hostWidget || typeof hostWidget.setDesktopNotifications !== "function") return
    hostWidget.setDesktopNotifications(!root.desktopNotifications)
  }

  function toggleQuestionAnswerSurface() {
    if (!hostWidget || typeof hostWidget.setQuestionAnswerSurface !== "function") return
    hostWidget.setQuestionAnswerSurface(root.questionsAnsweredInTopbar ? "cli" : "topbar")
  }

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

    // Keep ordinary prompts compact (wide enough for the four provider tabs),
    // then grow quickly enough for long option labels. KeyboardPanel still
    // clamps the result to the monitor width.
    var width = (showOtherTab ? 620 : 540) + Math.max(0, longest - 80) * 5
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
      console.warn("agent-fold could not focus the terminal:", error)
    })
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function") {
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    }
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(root.desiredPanelWidth())
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(8)

        Text {
          width: parent.width
          text: "Agents"
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        StatusCard {
          visible: root.outdatedHooks !== ""
          width: parent.width
          implicitHeight: outdatedText.implicitHeight + Style.space(8) * 2
          tone: statusColors.warning

          Text {
            id: outdatedText
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(14)
            anchors.rightMargin: Style.space(10)
            text: root.outdatedHooks + " hooks are out of date. Run `hommies setup` to get every feature."
            textFormat: Text.PlainText
            color: statusColors.warning
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          }
        }

        Item {
          width: parent.width
          implicitHeight: answerModeRow.implicitHeight

          Row {
            id: answerModeRow
            anchors.right: parent.right
            spacing: Style.space(4)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.questionsAnsweredInTopbar ? "Answer: Top bar" : "Answer: Agent CLI"
              color: root.barForeground
              opacity: 0.72
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            ToggleSwitch {
              anchors.verticalCenter: parent.verticalCenter
              checked: root.questionsAnsweredInTopbar
              foreground: root.barForeground
              trackHeight: 22
              cursorPad: Style.space(2)
              onToggled: root.toggleQuestionAnswerSurface()
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Style.space(8)
              text: "Notify"
              color: root.barForeground
              opacity: 0.72
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            ToggleSwitch {
              anchors.verticalCenter: parent.verticalCenter
              checked: root.desktopNotifications
              foreground: root.barForeground
              trackHeight: 22
              cursorPad: Style.space(2)
              onToggled: root.toggleDesktopNotifications()
            }

            Text {
              anchors.verticalCenter: parent.verticalCenter
              leftPadding: Style.space(8)
              text: "Sound"
              color: root.barForeground
              opacity: 0.72
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.caption
            }

            ToggleSwitch {
              anchors.verticalCenter: parent.verticalCenter
              checked: root.sounds
              foreground: root.barForeground
              trackHeight: 22
              cursorPad: Style.space(2)
              onToggled: root.toggleSounds()
            }
          }
        }

        Row {
          id: providerTabs
          width: parent.width
          spacing: Style.space(8)

          readonly property int tabCount: root.showOtherTab ? 5 : 4
          readonly property real tabWidth: (width - spacing * (tabCount - 1)) / tabCount

          ProviderTab {
            width: providerTabs.tabWidth
            providerId: "claude"
            providerName: "Claude"
            pendingCount: root.providerCount("claude")
            selected: root.selectedProvider === "claude"
            bordered: true
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.body
            onClicked: { root.selectedProvider = "claude"; root.selectedThreadId = "" }
          }

          ProviderTab {
            width: providerTabs.tabWidth
            providerId: "codex"
            providerName: "Codex"
            pendingCount: root.providerCount("codex")
            selected: root.selectedProvider === "codex"
            bordered: true
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.body
            onClicked: { root.selectedProvider = "codex"; root.selectedThreadId = "" }
          }

          ProviderTab {
            width: providerTabs.tabWidth
            providerId: "opencode"
            providerName: "OpenCode"
            pendingCount: root.providerCount("opencode")
            selected: root.selectedProvider === "opencode"
            bordered: true
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.body
            onClicked: { root.selectedProvider = "opencode"; root.selectedThreadId = "" }
          }

          ProviderTab {
            width: providerTabs.tabWidth
            providerId: "omacode"
            providerName: "Omacode"
            pendingCount: root.providerCount("omacode")
            selected: root.selectedProvider === "omacode"
            bordered: true
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.body
            onClicked: { root.selectedProvider = "omacode"; root.selectedThreadId = "" }
          }

          ProviderTab {
            visible: root.showOtherTab
            width: providerTabs.tabWidth
            providerId: "other"
            providerName: "Other"
            pendingCount: root.providerCount("other")
            selected: root.selectedProvider === "other"
            bordered: true
            foreground: root.barForeground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            fontSize: Style.font.body
            onClicked: { root.selectedProvider = "other"; root.selectedThreadId = "" }
          }
        }

        Text {
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
                delegate: Text {
                  width: parent.width
                  leftPadding: Style.space(8)
                  text: modelData
                  textFormat: Text.PlainText
                  elide: Text.ElideRight
                  color: root.barForeground
                  opacity: index === root.recentSteps(threadColumn.threadData).length - 1 ? 0.9 : 0.55
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.caption
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
                    console.warn("agent-fold answer failed:", error)
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
                    console.warn("agent-fold permission response failed:", error)
                  })
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
                      width: parent.width
                      text: questionColumn.questionData.header
                      color: root.barForeground
                      opacity: 0.72
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: Style.font.caption
                      font.bold: true
                    }

                    Text {
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
      }
    }
  }
}
