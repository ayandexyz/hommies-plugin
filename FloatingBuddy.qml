import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The floating Hommies character. A full-screen, transparent layer
// surface (like the notification toasts) so the character can sit anywhere
// without the surface resizing; the input mask keeps every pixel except the
// character click-through. Clicking the character opens the agent tabs
// (FloatingPanel.qml `body`) in a card next to it; right-clicking opens the
// settings menu. While either is open the whole surface takes input so a
// click outside closes it.
//
// Drag the character to move it (the position is saved).
PanelWindow {
  id: root

  // Service.qml: snapshot, mood, totalCount, prefs, savePrefs().
  required property var host
  // The FloatingPanel.qml instance whose `body` the card shows.
  required property var panel

  readonly property bool cardOpen: panel ? panel.opened === true : false
  property bool menuOpen: false
  // Card and menu open toward the middle of the screen.
  readonly property bool opensLeft: buddy.x + buddy.width / 2 > width / 2
  readonly property bool opensDown: buddy.y + buddy.height / 2 < height / 2
  readonly property int edgeMargin: Style.space(20)
  readonly property int gap: Style.space(10)

  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  anchors { top: true; bottom: true; left: true; right: true }

  WlrLayershell.namespace: "hommies-buddy"
  // Overlay sits above fullscreen windows; Top hides under them (e.g. a
  // fullscreen video). Toggled by "Over fullscreen" in the menu.
  WlrLayershell.layer: host.overFullscreen ? WlrLayer.Overlay : WlrLayer.Top
  // A card opened by a shortcut takes the keyboard at once; one opened by a click gets it on demand.
  WlrLayershell.keyboardFocus: !cardOpen ? WlrKeyboardFocus.None
    : panel && panel.keyboardOpened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand

  mask: cardOpen || menuOpen ? null : buddyRegion
  Region { id: buddyRegion; item: buddy }

  function clamp(value, low, high) { return Math.max(low, Math.min(high, value)) }
  function closeAll() {
    menuOpen = false
    panel.close()
  }
  // x/y for a popup of the given size beside the character.
  function besideX(popupWidth) {
    return clamp(opensLeft ? buddy.x - popupWidth - gap : buddy.x + buddy.width + gap,
      edgeMargin, width - popupWidth - edgeMargin)
  }
  function besideY(popupHeight) {
    return clamp(opensDown ? buddy.y : buddy.y + buddy.height - popupHeight,
      edgeMargin, height - popupHeight - edgeMargin)
  }

  function savePosition() {
    if (width <= 0 || height <= 0) return
    host.savePrefs({
      x: (buddy.x + buddy.width / 2) / width,
      y: (buddy.y + buddy.height / 2) / height
    })
  }

  function placeBuddy() {
    if (width <= 0 || height <= 0 || dragArea.drag.active) return
    var fx = typeof host.prefs.x === "number" ? host.prefs.x : 1
    var fy = typeof host.prefs.y === "number" ? host.prefs.y : 1
    buddy.x = clamp(fx * width - buddy.width / 2, edgeMargin, width - buddy.width - edgeMargin)
    buddy.y = clamp(fy * height - buddy.height / 2, edgeMargin, height - buddy.height - edgeMargin)
  }

  onWidthChanged: placeBuddy()
  onHeightChanged: placeBuddy()
  onCardOpenChanged: if (cardOpen) Qt.callLater(function() { if (cardBody.item) cardBody.item.forceActiveFocus() })

  // Outside-click dismissal while the card or menu is open.
  MouseArea {
    anchors.fill: parent
    enabled: root.cardOpen || root.menuOpen
    acceptedButtons: Qt.AllButtons
    onPressed: root.closeAll()
  }

  BorderSurface {
    id: card

    readonly property real wanted: root.panel ? root.panel.desiredPanelWidth() : Style.space(540)
    readonly property bool onLeft: root.opensLeft
    readonly property bool below: root.opensDown
    readonly property real insetX: contentLeftInset + contentRightInset
    readonly property real insetY: contentTopInset + contentBottomInset
    readonly property real bodyHeight: cardBody.item ? cardBody.item.contentHeight : 0

    width: Math.min(wanted + insetX, root.width - root.edgeMargin * 2)
    height: Math.min(bodyHeight + insetY, root.height - root.edgeMargin * 2)
    x: root.besideX(width)
    y: root.besideY(height)

    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.popupPadding
    radius: Style.cornerRadius
    visible: opacity > 0
    opacity: root.cardOpen ? 1 : 0
    scale: root.cardOpen ? 1 : 0.96
    transformOrigin: onLeft ? (below ? Item.TopRight : Item.BottomRight) : (below ? Item.TopLeft : Item.BottomLeft)
    Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

    // Swallow clicks so they don't reach the dismissal area behind.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Flickable {
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      clip: true
      contentWidth: width
      contentHeight: card.bodyHeight
      boundsBehavior: Flickable.StopAtBounds

      Loader {
        id: cardBody
        width: parent.width
        height: card.bodyHeight
        active: root.panel !== null
        sourceComponent: root.panel ? root.panel.body : null
      }
    }
  }

  component MenuToggle: Item {
    id: menuToggle
    property string label: ""
    property bool checked: false
    signal toggled()

    width: parent ? parent.width : 0
    implicitHeight: Math.max(toggleLabel.implicitHeight, toggleSwitch.implicitHeight)

    Text {
      id: toggleLabel
      anchors.left: parent.left
      anchors.right: toggleSwitch.left
      anchors.rightMargin: Style.space(12)
      anchors.verticalCenter: parent.verticalCenter
      text: menuToggle.label
      textFormat: Text.PlainText
      elide: Text.ElideRight
      color: Commons.Color.popups.text
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }

    ToggleSwitch {
      id: toggleSwitch
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      checked: menuToggle.checked
      foreground: Commons.Color.popups.text
      trackHeight: 22
      cursorPad: Style.space(2)
      onToggled: menuToggle.toggled()
    }
  }

  // Right-click settings menu. These used to sit at the top of the panel.
  BorderSurface {
    id: menu

    width: Style.space(260)
    height: menuColumn.implicitHeight + contentTopInset + contentBottomInset
    x: root.besideX(width)
    y: root.besideY(height)

    color: Commons.Color.popups.background
    borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Math.max(1, Style.space(2)))
    padding: Style.spacing.popupPadding
    radius: Style.cornerRadius
    visible: opacity > 0
    opacity: root.menuOpen ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    Column {
      id: menuColumn
      x: menu.contentLeftInset
      y: menu.contentTopInset
      width: menu.width - menu.contentLeftInset - menu.contentRightInset
      spacing: Style.space(10)

      MenuToggle {
        label: "Answer questions here"
        checked: root.host.questionAnswerSurface === "topbar"
        onToggled: root.host.setQuestionAnswerSurface(checked ? "cli" : "topbar")
      }
      MenuToggle {
        label: "Desktop notifications"
        checked: root.host.desktopNotifications
        onToggled: root.host.setDesktopNotifications(!checked)
      }
      MenuToggle {
        label: "Sounds"
        checked: root.host.sounds
        onToggled: root.host.setSounds(!checked)
      }
      // Outfit: ‹ › step through Auto, None, and every outfit.
      Item {
        width: parent.width
        height: Math.max(outfitText.implicitHeight, previousOutfit.height)

        Text {
          id: outfitText
          anchors.left: parent.left
          anchors.right: previousOutfit.left
          anchors.rightMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "Outfit: " + root.host.outfitLabel(root.host.outfitChoice)
            + (root.host.outfitChoice === "auto" && root.host.outfit !== "" ? " (" + root.host.outfitLabel(root.host.outfit) + ")" : "")
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: Commons.Color.popups.text
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
        }
        Button {
          id: previousOutfit
          anchors.right: nextOutfit.left
          anchors.rightMargin: Style.space(4)
          anchors.verticalCenter: parent.verticalCenter
          text: "\u2039"
          bordered: true
          tooltipText: "Previous outfit"
          onClicked: root.host.cycleOutfit(-1)
        }
        Button {
          id: nextOutfit
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: "\u203a"
          bordered: true
          tooltipText: "Next outfit"
          onClicked: root.host.cycleOutfit(1)
        }
      }
      MenuToggle {
        label: "Over fullscreen"
        checked: root.host.overFullscreen
        onToggled: root.host.setOverFullscreen(!checked)
      }
      Button {
        visible: Quickshell.screens.length > 1
        width: parent.width
        text: "Move to next monitor"
        bordered: true
        onClicked: {
          root.menuOpen = false
          root.host.moveToNextScreen()
        }
      }
    }
  }

  Item {
    id: buddy
    width: Style.space(84)
    height: Style.space(84)
    Component.onCompleted: root.placeBuddy()

    Loader {
      id: character
      anchors.fill: parent
      source: Qt.resolvedUrl("characters/" + root.host.character + ".qml")
      onLoaded: syncCharacter()
      function syncCharacter() {
        if (!item) return
        item.mood = Qt.binding(function() { return root.host.mood })
        item.lookX = Qt.binding(function() { return character.lookX })
        item.lookY = Qt.binding(function() { return character.lookY })
        // Optional in the contract: characters without `outfit` simply wear nothing.
        if ("outfit" in item) item.outfit = Qt.binding(function() { return root.host.outfit })
      }

      // Emotes from the service (a finished turn, or `omarchy-shell hommies emote <name>`).
      Connections {
        target: root.host
        function onEmoteRequested(name) {
          if (character.item && typeof character.item.emote === "function") character.item.emote(name)
        }
      }

      // Follow the pointer while hovered, glance at the card while it's
      // open, otherwise look ahead.
      readonly property real lookX: dragArea.containsMouse
        ? root.clamp((dragArea.mouseX - width / 2) / (width / 2), -1, 1)
        : root.cardOpen ? (card.onLeft ? -0.8 : 0.8) : 0
      readonly property real lookY: dragArea.containsMouse
        ? root.clamp((dragArea.mouseY - height / 2) / (height / 2), -1, 1)
        : root.cardOpen ? 0.2 : 0
    }

    // Pending count, top-right of the character.
    Rectangle {
      visible: root.host.totalCount > 0
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(4)
      height: countText.implicitHeight + Style.space(4)
      width: Math.max(height, countText.implicitWidth + Style.space(10))
      radius: height / 2
      color: Commons.Color.accent

      Text {
        id: countText
        anchors.centerIn: parent
        text: root.host.totalCount > 99 ? "99+" : String(root.host.totalCount)
        textFormat: Text.PlainText
        color: Commons.Color.background
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }

    // One-line status under the character while hovered.
    Rectangle {
      visible: dragArea.containsMouse && !dragArea.drag.active && !root.cardOpen && !root.menuOpen
      anchors.top: parent.bottom
      anchors.horizontalCenter: parent.horizontalCenter
      width: statusText.implicitWidth + Style.space(16)
      height: statusText.implicitHeight + Style.space(8)
      radius: height / 2
      color: Commons.Color.popups.background
      border.width: Style.normalBorderWidth
      border.color: Commons.Color.popups.border

      Text {
        id: statusText
        anchors.centerIn: parent
        text: root.host.statusLine
        textFormat: Text.PlainText
        color: Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }

    MouseArea {
      id: dragArea
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.PointingHandCursor
      drag.target: buddy
      drag.threshold: Style.space(6)
      drag.minimumX: root.edgeMargin
      drag.minimumY: root.edgeMargin
      drag.maximumX: root.width - buddy.width - root.edgeMargin
      drag.maximumY: root.height - buddy.height - root.edgeMargin

      // A drag that ends over the character must not also count as a click.
      property bool dragged: false
      onPressed: dragged = false
      onPositionChanged: if (drag.active) dragged = true
      onReleased: if (dragged) root.savePosition()
      onClicked: function (mouse) {
        if (dragged) return
        if (mouse.button === Qt.RightButton) {
          root.panel.close()
          root.menuOpen = !root.menuOpen
          return
        }
        root.menuOpen = false
        if (character.item && typeof character.item.poke === "function") character.item.poke()
        root.panel.toggle()
      }
    }
  }
}
