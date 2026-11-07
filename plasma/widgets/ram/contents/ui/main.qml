import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "Format.js" as Fmt

PlasmoidItem {
    id: root
    readonly property var cfg: Plasmoid.configuration
    readonly property var ram: backend.data ? backend.data.ram : null
    readonly property color accent: Kirigami.Theme.visitedLinkColor

    Backend {
        id: backend
        sections: ["ram"]
        clientId: Plasmoid.pluginName + "-" + Plasmoid.id
        interval: root.cfg.updateInterval
        historyLength: root.cfg.historyLength
    }
    MenuActions { id: menu; backend: backend }
    Plasmoid.contextualActions: menu.list
    Plasmoid.icon: "memory"

    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation
    toolTipMainText: ram && ram.summary ? Fmt.bytes(ram.summary.installed, 0) + " " + Fmt.or(ram.summary.text, "") : "Memory"
    toolTipSubText: ram ? Fmt.bytes(ram.used) + " of " + Fmt.bytes(ram.total) + " used (" + Fmt.pct(ram.usage) + ")"
                        + (ram.swap_total ? "\nSwap " + Fmt.bytes(ram.swap_used) + " of " + Fmt.bytes(ram.swap_total) : "")
                        : (backend.error || "Loading…")

    compactRepresentation: CompactView {
        label: "RAM"
        valueText: root.ram ? (root.cfg.ramCompactAbsolute ? Fmt.bytes(root.ram.used) : Fmt.pct(root.ram.usage)) : "–"
        hist: backend.hist.ram || []
        color: root.accent
        showLabel: root.cfg.compactShowLabel
        showGraph: root.cfg.compactShowGraph
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: FullView {
        error: backend.error
        hasData: !!root.ram
        RamSection {
            Layout.fillWidth: true
            Layout.fillHeight: true
            ram: root.ram
            hist: backend.hist.ram || []
            accent: root.accent
            graphFills: true
            showGraph: root.cfg.showGraph
            showModules: root.cfg.showRamModules
            warnColors: root.cfg.warnColors
        }
    }
}
