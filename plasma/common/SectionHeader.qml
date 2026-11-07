import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3

RowLayout {
    id: header
    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string trailing: ""
    Layout.fillWidth: true
    spacing: Kirigami.Units.smallSpacing * 2

    Kirigami.Icon {
        source: header.icon
        Layout.preferredWidth: Kirigami.Units.iconSizes.medium
        Layout.preferredHeight: Kirigami.Units.iconSizes.medium
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        Kirigami.Heading {
            Layout.fillWidth: true
            level: 4
            text: header.title
            elide: Text.ElideRight
        }
        PlasmaComponents3.Label {
            Layout.fillWidth: true
            visible: text !== ""
            text: header.subtitle
            opacity: 0.75
            elide: Text.ElideRight
            font: Kirigami.Theme.smallFont
        }
    }
    PlasmaComponents3.Label {
        visible: text !== ""
        text: header.trailing
        font.bold: true
    }
}
