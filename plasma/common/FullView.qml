// Wrapper for a widget's expanded view: sizing hints + backend error message.
import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami

ColumnLayout {
    id: full
    property string error: ""
    property bool hasData: true
    default property alias content: body.data

    Layout.minimumWidth: Kirigami.Units.gridUnit * 16
    Layout.preferredWidth: Kirigami.Units.gridUnit * 21
    Layout.minimumHeight: implicitHeight
    Layout.preferredHeight: implicitHeight
    spacing: Kirigami.Units.smallSpacing

    Kirigami.InlineMessage {
        Layout.fillWidth: true
        visible: full.error !== ""
        type: Kirigami.MessageType.Error
        text: "Sys Manager backend failed: " + full.error
    }

    ColumnLayout {
        id: body
        Layout.fillWidth: true
        Layout.fillHeight: true
        opacity: full.hasData ? 1 : 0.5
    }
}
