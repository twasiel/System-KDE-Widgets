import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.kirigami as Kirigami
import "Format.js" as Fmt

PlasmoidItem {
    id: root
    readonly property var cfg: Plasmoid.configuration
    readonly property var gpus: backend.data && backend.data.gpu ? backend.data.gpu : []
    readonly property int idx: Math.max(0, Math.min(cfg.gpuIndex, gpus.length - 1))
    readonly property var gpu: gpus.length ? gpus[idx] : null
    readonly property color accent: Kirigami.Theme.positiveTextColor

    Backend {
        id: backend
        sections: ["gpu"]
        clientId: Plasmoid.pluginName + "-" + Plasmoid.id
        interval: root.cfg.updateInterval
        historyLength: root.cfg.historyLength
    }
    MenuActions { id: menu; backend: backend }
    Plasmoid.contextualActions: menu.list
    Plasmoid.icon: "video-card-inactive"

    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation
    toolTipMainText: gpu ? gpu.name : "GPU"
    toolTipSubText: gpu ? "Usage " + Fmt.pct(gpu.usage) + " · " + Fmt.mhz(gpu.freq_mhz) + (gpu.temp_c ? " · " + Fmt.temp(gpu.temp_c) : "")
                        : (backend.error || (backend.data ? "No GPU detected" : "Loading…"))

    compactRepresentation: CompactView {
        label: "GPU"
        valueText: Fmt.pct(root.gpu ? root.gpu.usage : null)
        hist: backend.hist["gpu" + root.idx] || []
        color: root.accent
        showLabel: root.cfg.compactShowLabel
        showGraph: root.cfg.compactShowGraph
        onClicked: root.expanded = !root.expanded
    }

    fullRepresentation: FullView {
        error: backend.error
        hasData: !!root.gpu
        GpuSection {
            Layout.fillWidth: true
            Layout.fillHeight: true
            gpu: root.gpu
            hist: backend.hist["gpu" + root.idx] || []
            accent: root.accent
            graphFills: true
            showGraph: root.cfg.showGraph
            showEngines: root.cfg.showGpuEngines
            warnColors: root.cfg.warnColors
        }
    }
}
