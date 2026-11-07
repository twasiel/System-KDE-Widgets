import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "Format.js" as Fmt

ColumnLayout {
    id: sec
    property var disk: null
    property var histRead: []
    property var histWrite: []
    property bool showGraph: true
    property bool warnColors: true
    property color accent: Kirigami.Theme.neutralTextColor
    property color accent2: Kirigami.Theme.highlightColor
    property bool graphFills: false

    readonly property var d: disk || ({})
    spacing: Kirigami.Units.smallSpacing

    SectionHeader {
        icon: "drive-harddisk"
        title: "Storage"
        subtitle: (sec.d.drives || []).map(x => x.model + " (" + Fmt.bytes(x.size, 0) + ")").join(", ")
    }

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents3.Label { text: "Read"; opacity: 0.7 }
        PlasmaComponents3.Label { text: Fmt.rate(sec.d.read_bps); font.bold: true; color: sec.accent }
        Item { Layout.fillWidth: true }
        PlasmaComponents3.Label { text: "Write"; opacity: 0.7 }
        PlasmaComponents3.Label { text: Fmt.rate(sec.d.write_bps); font.bold: true; color: sec.accent2 }
    }

    Sparkline {
        visible: sec.showGraph
        Layout.fillWidth: true
        Layout.fillHeight: sec.graphFills
        Layout.minimumHeight: Kirigami.Units.gridUnit * 2.5
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
        values: sec.histRead
        values2: sec.histWrite
        color: sec.accent
        color2: sec.accent2
        maxValue: 0
    }

    Repeater {
        model: sec.d.mounts || []
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Math.round(Kirigami.Units.smallSpacing / 2)
            RowLayout {
                Layout.fillWidth: true
                PlasmaComponents3.Label {
                    text: modelData.mount
                    font.bold: true
                    elide: Text.ElideMiddle
                    Layout.fillWidth: true
                }
                PlasmaComponents3.Label {
                    text: Fmt.bytes(modelData.used) + " / " + Fmt.bytes(modelData.total) + " · " + modelData.fs
                    font: Kirigami.Theme.smallFont
                    opacity: 0.75
                }
            }
            UsageBar { Layout.fillWidth: true; value: modelData.usage; color: sec.accent; warnColors: sec.warnColors }
        }
    }
}
