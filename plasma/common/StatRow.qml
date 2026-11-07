import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

RowLayout {
    property string label: ""
    property string value: ""
    property color valueColor: Kirigami.Theme.textColor
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing
    visible: value !== "" && value !== "–"

    PlasmaComponents3.Label {
        text: parent.label
        opacity: 0.7
        elide: Text.ElideRight
        Layout.fillWidth: true
        Layout.minimumWidth: Kirigami.Units.gridUnit * 3
    }
    PlasmaComponents3.Label {
        text: parent.value
        color: parent.valueColor
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideLeft
        Layout.maximumWidth: parent.width * 0.7
    }
}
