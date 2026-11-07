// Circular percentage gauge with the value in the middle.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "Format.js" as Fmt

Item {
    id: gauge
    property real value: 0
    property string label: ""
    property string valueText: Fmt.pct(value)
    property color color: Kirigami.Theme.highlightColor
    property bool warnColors: true

    implicitWidth: Kirigami.Units.gridUnit * 4.5
    implicitHeight: implicitWidth
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    readonly property real v: Math.max(0, Math.min(100, isNaN(value) ? 0 : value))
    readonly property color arcColor: warnColors && v >= 90 ? Kirigami.Theme.negativeTextColor
                                    : warnColors && v >= 75 ? Kirigami.Theme.neutralTextColor : color
    property real animated: v
    Behavior on animated { NumberAnimation { duration: Kirigami.Units.longDuration; easing.type: Easing.OutCubic } }

    onAnimatedChanged: ring.requestPaint()
    onArcColorChanged: ring.requestPaint()

    Canvas {
        id: ring
        anchors.fill: parent
        onWidthChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d");
            ctx.reset();
            var lw = Math.max(3, width * 0.09);
            var r = Math.min(width, height) / 2 - lw / 2 - 1;
            var cx = width / 2, cy = height / 2;
            var startA = Math.PI * 0.75, span = Math.PI * 1.5;
            var t = Kirigami.Theme.textColor;
            ctx.lineCap = "round";
            ctx.lineWidth = lw;
            ctx.strokeStyle = Qt.rgba(t.r, t.g, t.b, 0.12);
            ctx.beginPath(); ctx.arc(cx, cy, r, startA, startA + span); ctx.stroke();
            if (gauge.animated > 0.5) {
                ctx.strokeStyle = gauge.arcColor;
                ctx.beginPath(); ctx.arc(cx, cy, r, startA, startA + span * gauge.animated / 100); ctx.stroke();
            }
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 0
        PlasmaComponents3.Label {
            Layout.alignment: Qt.AlignHCenter
            text: gauge.valueText
            font.pixelSize: Math.round(gauge.height * 0.22)
            font.bold: true
        }
        PlasmaComponents3.Label {
            Layout.alignment: Qt.AlignHCenter
            visible: gauge.label !== ""
            text: gauge.label
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
    }
}
