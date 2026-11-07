import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "Format.js" as Fmt

PlasmoidItem {
    id: root
    readonly property var cfg: Plasmoid.configuration
    readonly property var cpu: backend.data ? backend.data.cpu : null
    readonly property color accent: Kirigami.Theme.highlightColor

    Backend {
        id: backend
        sections: ["cpu"]
        clientId: Plasmoid.pluginName + "-" + Plasmoid.id
        interval: root.cfg.updateInterval
        historyLength: root.cfg.historyLength
    }
    MenuActions { id: menu; backend: backend }
    Plasmoid.contextualActions: menu.list
    Plasmoid.icon: "cpu"

    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation
    toolTipMainText: cpu ? cpu.model : "CPU"
    toolTipSubText: cpu ? "Usage " + Fmt.pct(cpu.usage) + " · " + Fmt.mhz(cpu.freq_mhz) + (cpu.temp_c ? " · " + Fmt.temp(cpu.temp_c) : "")
                        : (backend.error || "Loading…")

    compactRepresentation: CompactView {
        label: "CPU"
        valueText: Fmt.pct(root.cpu ? root.cpu.usage : null)
        hist: backend.hist.cpu || []
        color: root.accent
        showLabel: root.cfg.compactShowLabel
        showGraph: root.cfg.compactShowGraph
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: FullView {
        error: backend.error
        hasData: !!root.cpu
        CpuSection {
            Layout.fillWidth: true
            Layout.fillHeight: true
            cpu: root.cpu
            hist: backend.hist.cpu || []
            accent: root.accent
            graphFills: true
            showGraph: root.cfg.showGraph
            showPerCore: root.cfg.showPerCore
            warnColors: root.cfg.warnColors
        }
    }
}
