// Panel representation: label + value with an optional history graph behind.
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

Item {
    id: compact
    property string label: ""
    property string valueText: "–"
    property string valueText2: ""
    property var hist: []
    property var hist2: []
    property real maxValue: 100
    property color color: Kirigami.Theme.highlightColor
    property color color2: Kirigami.Theme.positiveTextColor
    property bool showGraph: true
    property bool showLabel: true
    signal clicked()

    readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property bool stacked: vertical || height >= (labelText.visible ? labelText.implicitHeight : 0) + valueText.implicitHeight * (valueText2 !== "" ? 2 : 1)
    readonly property real contentWidth: grid.implicitWidth + Kirigami.Units.smallSpacing * 2

    Layout.minimumWidth: vertical ? Kirigami.Units.gridUnit : contentWidth
    Layout.preferredWidth: vertical ? -1 : Math.max(contentWidth, showGraph ? height * 1.6 : 0)
    Layout.minimumHeight: vertical ? grid.implicitHeight + Kirigami.Units.smallSpacing : Kirigami.Units.gridUnit
    Layout.preferredHeight: Layout.minimumHeight

    Sparkline {
        anchors.fill: parent
        visible: compact.showGraph
        values: compact.hist
        values2: compact.hist2
        maxValue: compact.maxValue
        color: compact.color
        color2: compact.color2
        showGrid: false
        lineWidth: 1
        opacity: 0.85
    }

    GridLayout {
        id: grid
        anchors.centerIn: parent
        columns: compact.stacked ? 1 : 3
        rowSpacing: 0
        columnSpacing: Kirigami.Units.smallSpacing

        PlasmaComponents3.Label {
            id: labelText
            Layout.alignment: Qt.AlignHCenter
            visible: compact.showLabel && compact.label !== ""
            text: compact.label
            font.pixelSize: Kirigami.Theme.smallFont.pixelSize
            opacity: 0.8
        }
        PlasmaComponents3.Label {
            id: valueText
            Layout.alignment: Qt.AlignHCenter
            text: compact.valueText
            font.bold: true
            font.pixelSize: compact.vertical ? Kirigami.Theme.smallFont.pixelSize : Kirigami.Theme.defaultFont.pixelSize
        }
        PlasmaComponents3.Label {
            Layout.alignment: Qt.AlignHCenter
            visible: compact.valueText2 !== ""
            text: compact.valueText2
            font.bold: true
            font.pixelSize: valueText.font.pixelSize
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: compact.clicked()
    }
}
