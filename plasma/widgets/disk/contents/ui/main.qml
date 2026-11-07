import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "Format.js" as Fmt

PlasmoidItem {
    id: root
    readonly property var cfg: Plasmoid.configuration
    readonly property var disk: backend.data ? backend.data.disk : null
    readonly property var rootMount: disk && disk.mounts.length ? disk.mounts[0] : null

    Backend {
        id: backend
        sections: ["disk"]
        clientId: Plasmoid.pluginName + "-" + Plasmoid.id
        interval: root.cfg.updateInterval
        historyLength: root.cfg.historyLength
    }
    MenuActions { id: menu; backend: backend }
    Plasmoid.contextualActions: menu.list
    Plasmoid.icon: "drive-harddisk"

    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation
    toolTipMainText: disk && disk.drives.length ? disk.drives[0].model : "Storage"
    toolTipSubText: disk ? (rootMount ? rootMount.mount + ": " + Fmt.bytes(rootMount.free) + " free of " + Fmt.bytes(rootMount.total) + "\n" : "")
                           + "Read " + Fmt.rate(disk.read_bps) + " · Write " + Fmt.rate(disk.write_bps)
                         : (backend.error || "Loading…")

    compactRepresentation: CompactView {
        label: root.rootMount ? root.rootMount.mount : "Disk"
        valueText: Fmt.pct(root.rootMount ? root.rootMount.usage : null)
        hist: backend.hist.read || []
        hist2: backend.hist.write || []
        maxValue: 0
        color: Kirigami.Theme.neutralTextColor
        color2: Kirigami.Theme.highlightColor
        showLabel: root.cfg.compactShowLabel
        showGraph: root.cfg.compactShowGraph
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: FullView {
        error: backend.error
        hasData: !!root.disk
        DiskSection {
            Layout.fillWidth: true
            Layout.fillHeight: true
            disk: root.disk
            histRead: backend.hist.read || []
            histWrite: backend.hist.write || []
            graphFills: true
            showGraph: root.cfg.showGraph
            warnColors: root.cfg.warnColors
        }
    }
}
