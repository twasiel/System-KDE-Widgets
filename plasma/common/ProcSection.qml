import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "Format.js" as Fmt

ColumnLayout {
    id: sec
    property var procs: null
    property int limit: 6
    readonly property var rows: procs ? procs.top_cpu.slice(0, limit) : []
    spacing: Math.round(Kirigami.Units.smallSpacing / 2)

    SectionHeader {
        icon: "view-process-system"
        title: "Top processes"
        subtitle: sec.procs && sec.procs.count ? sec.procs.count + " running" : ""
    }

    RowLayout {
        Layout.fillWidth: true
        opacity: 0.6
        PlasmaComponents3.Label { text: "Name"; font: Kirigami.Theme.smallFont; Layout.fillWidth: true }
        PlasmaComponents3.Label { text: "CPU"; font: Kirigami.Theme.smallFont; Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5; horizontalAlignment: Text.AlignRight }
        PlasmaComponents3.Label { text: "Memory"; font: Kirigami.Theme.smallFont; Layout.preferredWidth: Kirigami.Units.gridUnit * 4; horizontalAlignment: Text.AlignRight }
    }

    Repeater {
        model: sec.rows
        RowLayout {
            Layout.fillWidth: true
            PlasmaComponents3.Label { text: modelData.name; elide: Text.ElideRight; Layout.fillWidth: true }
            PlasmaComponents3.Label { text: modelData.cpu.toFixed(1) + "%"; Layout.preferredWidth: Kirigami.Units.gridUnit * 2.5; horizontalAlignment: Text.AlignRight }
            PlasmaComponents3.Label { text: Fmt.bytes(modelData.rss); Layout.preferredWidth: Kirigami.Units.gridUnit * 4; horizontalAlignment: Text.AlignRight; opacity: 0.8 }
        }
    }
}
