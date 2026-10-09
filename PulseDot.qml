import QtQuick
import qs.Commons
import qs.Commons as Commons

// A solid dot with a ripple that grows and fades out on a loop. Marks
// sessions that are thinking or running tools. The ripple only animates
// while `running` and visible, so idle dots cost nothing.
Item {
  id: root

  property color tone: Commons.Color.accent
  property bool running: true
  property real size: Style.space(7)

  implicitWidth: size
  implicitHeight: size

  Rectangle {
    id: ripple
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: width / 2
    color: root.tone
    opacity: 0
  }

  Rectangle {
    anchors.centerIn: parent
    width: root.size
    height: root.size
    radius: width / 2
    color: root.tone
  }

  SequentialAnimation {
    running: root.running && root.visible
    loops: Animation.Infinite
    onRunningChanged: if (!running) { ripple.scale = 1; ripple.opacity = 0 }

    ParallelAnimation {
      NumberAnimation { target: ripple; property: "scale"; from: 1; to: 2.6; duration: 1100; easing.type: Easing.OutCubic }
      NumberAnimation { target: ripple; property: "opacity"; from: 0.55; to: 0; duration: 1100; easing.type: Easing.OutCubic }
    }
    PauseAnimation { duration: 350 }
  }
}
