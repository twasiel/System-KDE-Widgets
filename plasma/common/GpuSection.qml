import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "Format.js" as Fmt

ColumnLayout {
    id: sec
    property var gpu: null
    property var hist: []
    property bool showGraph: true
    property bool showEngines: true
    property bool warnColors: true
    property color accent: Kirigami.Theme.positiveTextColor
    property bool graphFills: false

    readonly property var g: gpu || ({})
    readonly property var engineList: {
        var e = g.engines || {};
        return Object.keys(e).map(k => ({ name: k, value: e[k] }));
    }
    spacing: Kirigami.Units.smallSpacing

    SectionHeader {
        icon: "video-card-inactive"
        title: "GPU" + (sec.g.integrated ? " (integrated)" : "")
        subtitle: sec.gpu ? sec.g.name + (sec.g.codename ? " · " + sec.g.codename : "") : "No GPU detected"
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing
        RingGauge {
            value: Fmt.or(sec.g.usage, 0)
            valueText: Fmt.pct(sec.g.usage)
            label: "usage"
            color: sec.accent
            warnColors: sec.warnColors
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StatRow { label: "Frequency"; value: (sec.g.freq_mhz === 0 ? "idle" : Fmt.mhz(sec.g.freq_mhz)) + (sec.g.freq_max_mhz ? " / " + Fmt.mhz(sec.g.freq_max_mhz) : "") }
            StatRow {
                label: Fmt.or(sec.g.mem_label, "VRAM")
                value: sec.g.mem_total ? Fmt.bytes(sec.g.mem_used) + " / " + Fmt.bytes(sec.g.mem_total) : Fmt.bytes(sec.g.mem_used)
            }
            StatRow { label: "Temperature"; value: Fmt.temp(sec.g.temp_c) }
            StatRow { label: "Power"; value: Fmt.watts(sec.g.power_w) }
            StatRow { label: "Idle (RC6)"; value: Fmt.pct(sec.g.rc6) }
            StatRow { label: "Driver"; value: sec.gpu ? Fmt.or(sec.g.driver, "?") + " · " + Fmt.or(sec.g.pci_id, "") : "–" }
        }
    }

    UsageBar {
        visible: !!sec.g.mem_total
        Layout.fillWidth: true
        value: Fmt.or(sec.g.mem_usage, 0)
        color: sec.accent
        warnColors: sec.warnColors
    }

    Sparkline {
        visible: sec.showGraph
        Layout.fillWidth: true
        Layout.fillHeight: sec.graphFills
        Layout.minimumHeight: Kirigami.Units.gridUnit * 2.5
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
        values: sec.hist
        color: sec.accent
    }

    GridLayout {
        visible: sec.showEngines && sec.engineList.length > 1
        Layout.fillWidth: true
        columns: 2
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Math.round(Kirigami.Units.smallSpacing / 2)
        Repeater {
            model: sec.engineList
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.Label {
                    text: modelData.name
                    font: Kirigami.Theme.smallFont
                    opacity: 0.7
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 4.5
                    elide: Text.ElideRight
                }
                UsageBar { Layout.fillWidth: true; value: modelData.value; color: sec.accent; warnColors: false }
                PlasmaComponents3.Label {
                    text: Math.round(modelData.value) + "%"
                    font: Kirigami.Theme.smallFont
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.8
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
