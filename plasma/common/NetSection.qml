import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "Format.js" as Fmt

ColumnLayout {
    id: sec
    property var net: null
    property var histRx: []
    property var histTx: []
    property bool showGraph: true
    property bool showVirtual: false
    property color accent: Kirigami.Theme.linkColor
    property color accent2: Kirigami.Theme.positiveTextColor
    property bool graphFills: false

    readonly property var n: net || ({})
    readonly property var shown: (n.interfaces || []).filter(i => (i.state === "up" || i.ipv4) && (showVirtual || !i.virtual))
    readonly property var primary: shown.length ? shown[0] : null
    spacing: Kirigami.Units.smallSpacing

    SectionHeader {
        icon: sec.primary && sec.primary.wireless ? "network-wireless" : "network-wired"
        title: "Network"
        subtitle: sec.primary ? sec.primary.name + (sec.primary.ipv4 ? " · " + sec.primary.ipv4 : "") : "Disconnected"
    }

    RowLayout {
        Layout.fillWidth: true
        PlasmaComponents3.Label { text: "↓"; font.bold: true; color: sec.accent }
        PlasmaComponents3.Label { text: Fmt.rate(sec.n.rx_bps); font.bold: true }
        Item { Layout.fillWidth: true }
        PlasmaComponents3.Label { text: "↑"; font.bold: true; color: sec.accent2 }
        PlasmaComponents3.Label { text: Fmt.rate(sec.n.tx_bps); font.bold: true }
    }

    Sparkline {
        visible: sec.showGraph
        Layout.fillWidth: true
        Layout.fillHeight: sec.graphFills
        Layout.minimumHeight: Kirigami.Units.gridUnit * 2.5
        Layout.preferredHeight: Kirigami.Units.gridUnit * 3
        values: sec.histRx
        values2: sec.histTx
        color: sec.accent
        color2: sec.accent2
        maxValue: 0
    }

    Repeater {
        model: sec.shown
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Kirigami.Icon {
                    source: modelData.wireless ? "network-wireless" : modelData.virtual || !modelData.physical ? "network-vpn" : "network-wired"
                    Layout.preferredWidth: Kirigami.Units.iconSizes.small
                    Layout.preferredHeight: Kirigami.Units.iconSizes.small
                }
                PlasmaComponents3.Label { text: modelData.name; font.bold: true; Layout.fillWidth: true; elide: Text.ElideRight }
                PlasmaComponents3.Label {
                    text: "↓ " + Fmt.rate(modelData.rx_bps) + "  ↑ " + Fmt.rate(modelData.tx_bps)
                    font: Kirigami.Theme.smallFont
                }
            }
            StatRow { label: "IPv4"; value: Fmt.or(modelData.ipv4, "–") }
            StatRow { label: "Signal"; value: modelData.wifi ? Math.round(modelData.wifi.signal_dbm) + " dBm (" + modelData.wifi.quality + "%)" : "–" }
            StatRow { label: "Link speed"; value: modelData.speed_mbps ? modelData.speed_mbps + " Mb/s" : "–" }
            StatRow { label: "Total ↓ / ↑"; value: Fmt.bytes(modelData.rx_total) + " / " + Fmt.bytes(modelData.tx_total) }
        }
    }
}
