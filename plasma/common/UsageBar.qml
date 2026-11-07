import QtQuick
import org.kde.kirigami as Kirigami

Item {
    id: bar
    property real value: 0               // 0..100
    property color color: Kirigami.Theme.highlightColor
    property bool warnColors: true

    readonly property real clamped: Math.max(0, Math.min(100, isNaN(value) ? 0 : value))
    implicitHeight: Math.round(Kirigami.Units.gridUnit * 0.4)
    implicitWidth: Kirigami.Units.gridUnit * 4

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Kirigami.Theme.textColor
        opacity: 0.12
    }
    Rectangle {
        height: parent.height
        radius: height / 2
        width: Math.max(height, parent.width * bar.clamped / 100)
        visible: bar.clamped > 0
        color: bar.warnColors && bar.clamped >= 90 ? Kirigami.Theme.negativeTextColor
             : bar.warnColors && bar.clamped >= 75 ? Kirigami.Theme.neutralTextColor
             : bar.color
        Behavior on width { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }
    }
}
