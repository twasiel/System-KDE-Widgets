import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "Format.js" as Fmt

ColumnLayout {
    id: sec
    property var ram: null
    property var hist: []
    property bool showGraph: true
    property bool showModules: true
    property bool warnColors: true
    property color accent: Kirigami.Theme.visitedLinkColor
    property bool graphFills: false

    readonly property var r: ram || ({})
    readonly property var sm: r.summary || null
    spacing: Kirigami.Units.smallSpacing

    SectionHeader {
        icon: "memory"
        title: "Memory"
        subtitle: sec.sm ? Fmt.bytes(sec.sm.installed, 0) + " " + Fmt.or(sec.sm.text, "") : Fmt.bytes(sec.r.total)
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Kirigami.Units.largeSpacing
        RingGauge {
            value: Fmt.or(sec.r.usage, 0)
            label: "used"
            color: sec.accent
            warnColors: sec.warnColors
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StatRow { label: "Used"; value: Fmt.bytes(sec.r.used) + " / " + Fmt.bytes(sec.r.total) }
            StatRow { label: "Available"; value: Fmt.bytes(sec.r.available) }
            StatRow { label: "Cached"; value: Fmt.bytes(sec.r.cached) }
            StatRow { label: "Shared"; value: Fmt.bytes(sec.r.shared) }
            StatRow { label: "Swap"; value: sec.r.swap_total ? Fmt.bytes(sec.r.swap_used) + " / " + Fmt.bytes(sec.r.swap_total) : "–" }
            StatRow { label: "Part number"; value: sec.sm && sec.sm.part_numbers.length ? sec.sm.part_numbers.join(", ") : "–" }
        }
    }

    RowLayout {
        visible: sec.r.swap_total > 0
        Layout.fillWidth: true
        PlasmaComponents3.Label { text: "Swap"; font: Kirigami.Theme.smallFont; opacity: 0.7 }
        UsageBar {
            Layout.fillWidth: true
            value: Fmt.or(sec.r.swap_usage, 0)
            color: sec.accent
            warnColors: sec.warnColors
        }
        PlasmaComponents3.Label { text: Fmt.pct(sec.r.swap_usage); font: Kirigami.Theme.smallFont }
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

    // Installed modules (from SMBIOS via udev)
    ColumnLayout {
        visible: sec.showModules && (sec.r.modules || []).length > 0
        Layout.fillWidth: true
        spacing: 0
        PlasmaComponents3.Label {
            text: (sec.r.modules || []).length + " module(s)" + (sec.sm && sec.sm.max_capacity ? ", max " + Fmt.bytes(sec.sm.max_capacity, 0) : "")
            font: Kirigami.Theme.smallFont
            opacity: 0.7
        }
        Repeater {
            model: (sec.r.modules || []).length <= 4 ? sec.r.modules : []
            StatRow {
                label: Fmt.or(modelData.slot, "Slot " + index)
                value: Fmt.bytes(modelData.size, 0) + " " + Fmt.or(modelData.type, "") + (modelData.speed_mts ? " " + modelData.speed_mts + " MT/s" : "")
                       + (modelData.manufacturer ? " · " + modelData.manufacturer : "")
            }
        }
    }
}
