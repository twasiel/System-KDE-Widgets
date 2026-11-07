import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "Format.js" as Fmt

PlasmoidItem {
    id: root
    readonly property var cfg: Plasmoid.configuration
    readonly property var net: backend.data ? backend.data.net : null

    Backend {
        id: backend
        sections: ["net"]
        clientId: Plasmoid.pluginName + "-" + Plasmoid.id
        interval: root.cfg.updateInterval
        historyLength: root.cfg.historyLength
    }
    MenuActions { id: menu; backend: backend }
    Plasmoid.contextualActions: menu.list
    Plasmoid.icon: "network-wired"

    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation
    toolTipMainText: net && net.default ? "Network · " + net.default : "Network"
    toolTipSubText: net ? "↓ " + Fmt.rate(net.rx_bps) + "   ↑ " + Fmt.rate(net.tx_bps) : (backend.error || "Loading…")

    compactRepresentation: CompactView {
        label: ""
        valueText: "↓ " + Fmt.rate(root.net ? root.net.rx_bps : null)
        valueText2: "↑ " + Fmt.rate(root.net ? root.net.tx_bps : null)
        hist: backend.hist.rx || []
        hist2: backend.hist.tx || []
        maxValue: 0
        color: Kirigami.Theme.linkColor
        color2: Kirigami.Theme.positiveTextColor
        showLabel: false
        showGraph: root.cfg.compactShowGraph
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: FullView {
        error: backend.error
        hasData: !!root.net
        NetSection {
            Layout.fillWidth: true
            Layout.fillHeight: true
            net: root.net
            histRx: backend.hist.rx || []
            histTx: backend.hist.tx || []
            graphFills: true
            showGraph: root.cfg.showGraph
            showVirtual: root.cfg.showVirtualInterfaces
        }
    }
}
