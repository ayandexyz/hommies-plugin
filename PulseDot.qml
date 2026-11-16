import QtQuick
import qs.Commons
import qs.Commons as Commons

// A solid dot with a ripple that grows and fades out on a loop. Marks
// sessions that are thinking or running tools. The ripple only animates
// while `running` and visible, so idle dots cost nothing. It steps at
// 20 fps from a Timer rather than a vsync Animation: every step repaints
// the whole window it sits in (the bar), and the ripple is too small and
// soft for the extra frames to show.
Item {
  id: root

  property color tone: Commons.Color.accent
  property bool running: true
  property real size: Style.space(7)

  readonly property int growMs: 1100
  readonly property int cycleMs: 1450
  /** Milliseconds into the current grow-then-pause cycle. */
  property int phase: 0
  readonly property real progress: Math.min(1, phase / growMs)
  readonly property real eased: 1 - Math.pow(1 - progress, 3)

  implicitWidth: size
  implicitHeight: size

  Rectangle {
    id: ripple
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: width / 2
    color: root.tone
    scale: pulse.running && root.phase < root.growMs ? 1 + 1.6 * root.eased : 1
    opacity: pulse.running && root.phase < root.growMs ? 0.55 * (1 - root.eased) : 0
  }

  Rectangle {
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: width / 2
    color: root.tone
  }

  Timer {
    id: pulse
    interval: 50
    repeat: true
    running: root.running && root.visible
    onRunningChanged: if (!running) root.phase = 0
    onTriggered: root.phase = (root.phase + interval) % root.cycleMs
  }
}
