import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "Format.js" as Fmt

ColumnLayout {
    id: sec
    property var cpu: null
    property var hist: []
    property bool showPerCore: true
    property bool showGraph: true
    property bool warnColors: true
    property color accent: Kirigami.Theme.highlightColor
    property bool graphFills: false

    readonly property var c: cpu || ({})
    readonly property string coresText: {
        if (!c.cores) return "–";
        var s = c.cores + " cores / " + c.threads + " threads";
        if (c.hybrid) s += " (" + c.hybrid.p_cores + "P + " + c.hybrid.e_cores + "E)";
        return s;
    }
    spacing: Kirigami.Units.smallSpacing

    SectionHeader {
        icon: "cpu"
        title: "CPU"
        subtitle: Fmt.or(sec.c.model, "…")
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing
        RingGauge {
            value: Fmt.or(sec.c.usage, 0)
            label: "usage"
            color: sec.accent
            warnColors: sec.warnColors
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StatRow { label: "Frequency"; value: Fmt.mhz(sec.c.freq_mhz) + (sec.c.freq_max_mhz ? " / " + Fmt.mhz(sec.c.freq_max_mhz) : "") }
            StatRow { label: "Temperature"; value: Fmt.temp(sec.c.temp_c)
                      valueColor: sec.c.temp_c >= 90 ? Kirigami.Theme.negativeTextColor : sec.c.temp_c >= 75 ? Kirigami.Theme.neutralTextColor : Kirigami.Theme.textColor }
            StatRow { label: "Cores"; value: sec.coresText }
            StatRow { label: "Load avg"; value: sec.c.load ? sec.c.load.map(x => x.toFixed(2)).join("  ") : "–" }
            StatRow { label: "User / System"; value: sec.c.breakdown && sec.c.breakdown.user !== undefined ? Fmt.pct(sec.c.breakdown.user) + " / " + Fmt.pct(sec.c.breakdown.system) : "–" }
            StatRow { label: "Processes"; value: Fmt.or(sec.c.processes, "–") + "" }
            StatRow { label: "Governor"; value: Fmt.or(sec.c.governor, "–") + (sec.c.epp ? " (" + sec.c.epp + ")" : "") }
        }
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
        visible: sec.showPerCore && (sec.c.per_core || []).length > 0
        Layout.fillWidth: true
        columns: sec.width > Kirigami.Units.gridUnit * 22 ? 4 : 2
        columnSpacing: Kirigami.Units.largeSpacing
        rowSpacing: Math.round(Kirigami.Units.smallSpacing / 2)
        Repeater {
            model: sec.c.per_core || []
            RowLayout {
                Layout.fillWidth: true
                spacing: Kirigami.Units.smallSpacing
                PlasmaComponents3.Label {
                    text: index
                    font: Kirigami.Theme.smallFont
                    opacity: 0.6
                    Layout.preferredWidth: Kirigami.Units.gridUnit
                    horizontalAlignment: Text.AlignRight
                }
                UsageBar { Layout.fillWidth: true; value: modelData; color: sec.accent; warnColors: sec.warnColors }
                PlasmaComponents3.Label {
                    text: Math.round(modelData) + "%"
                    font: Kirigami.Theme.smallFont
                    Layout.preferredWidth: Kirigami.Units.gridUnit * 1.8
                    horizontalAlignment: Text.AlignRight
                }
            }
        }
    }
}
