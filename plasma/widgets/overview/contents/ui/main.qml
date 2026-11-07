import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami
import "Format.js" as Fmt

PlasmoidItem {
    id: root
    readonly property var cfg: Plasmoid.configuration
    readonly property var d: backend.data || ({})
    readonly property var compactKeys: cfg.compactItems.split(",").filter(k => k !== "")

    readonly property var sectionList: {
        var s = [];
        if (cfg.showSystem) s.push("system");
        if (cfg.showCpu) s.push("cpu");
        if (cfg.showRam) s.push("ram");
        if (cfg.showGpu) s.push("gpu");
        if (cfg.showDisk) s.push("disk");
        if (cfg.showNet) s.push("net");
        if (cfg.showProcs) s.push("procs");
        compactKeys.forEach(k => { if (s.indexOf(k) === -1) s.push(k); });
        return s.length ? s : ["cpu"];
    }

    Backend {
        id: backend
        sections: root.sectionList
        clientId: Plasmoid.pluginName + "-" + Plasmoid.id
        interval: root.cfg.updateInterval
        historyLength: root.cfg.historyLength
    }
    MenuActions { id: menu; backend: backend }
    Plasmoid.contextualActions: menu.list
    Plasmoid.icon: "utilities-system-monitor"

    // Describes one item of the compact (panel) view
    function itemInfo(key, data, hist) {
        switch (key) {
        case "cpu":  return { label: "CPU", value: Fmt.pct(data.cpu ? data.cpu.usage : null), value2: "", hist: hist.cpu || [], hist2: [], max: 100, color: Kirigami.Theme.highlightColor, color2: Kirigami.Theme.highlightColor };
        case "ram":  return { label: "RAM", value: data.ram ? (cfg.ramCompactAbsolute ? Fmt.bytes(data.ram.used) : Fmt.pct(data.ram.usage)) : "–", value2: "", hist: hist.ram || [], hist2: [], max: 100, color: Kirigami.Theme.visitedLinkColor, color2: Kirigami.Theme.visitedLinkColor };
        case "gpu":  return { label: "GPU", value: Fmt.pct(data.gpu && data.gpu.length ? data.gpu[0].usage : null), value2: "", hist: hist.gpu0 || [], hist2: [], max: 100, color: Kirigami.Theme.positiveTextColor, color2: Kirigami.Theme.positiveTextColor };
        case "disk": return { label: "Disk", value: "R " + Fmt.rate(data.disk ? data.disk.read_bps : null), value2: "W " + Fmt.rate(data.disk ? data.disk.write_bps : null), hist: hist.read || [], hist2: hist.write || [], max: 0, color: Kirigami.Theme.neutralTextColor, color2: Kirigami.Theme.highlightColor };
        case "net":  return { label: "", value: "↓ " + Fmt.rate(data.net ? data.net.rx_bps : null), value2: "↑ " + Fmt.rate(data.net ? data.net.tx_bps : null), hist: hist.rx || [], hist2: hist.tx || [], max: 0, color: Kirigami.Theme.linkColor, color2: Kirigami.Theme.positiveTextColor };
        }
        return { label: key, value: "?", value2: "", hist: [], hist2: [], max: 100, color: Kirigami.Theme.textColor, color2: Kirigami.Theme.textColor };
    }

    preferredRepresentation: Plasmoid.formFactor === PlasmaCore.Types.Planar ? fullRepresentation : compactRepresentation
    toolTipMainText: d.system ? d.system.hostname : "System Overview"
    toolTipSubText: {
        var parts = [];
        if (d.cpu) parts.push("CPU " + Fmt.pct(d.cpu.usage));
        if (d.ram) parts.push("RAM " + Fmt.pct(d.ram.usage));
        if (d.gpu && d.gpu.length) parts.push("GPU " + Fmt.pct(d.gpu[0].usage));
        return parts.length ? parts.join(" · ") : (backend.error || "Loading…");
    }

    compactRepresentation: Item {
        readonly property bool vertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
        Layout.minimumWidth: vertical ? -1 : row.implicitWidth
        Layout.preferredWidth: Layout.minimumWidth
        Layout.minimumHeight: vertical ? row.implicitHeight : -1
        Layout.preferredHeight: Layout.minimumHeight

        GridLayout {
            id: row
            anchors.fill: parent
            flow: parent.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
            rows: parent.vertical ? -1 : 1
            columns: parent.vertical ? 1 : -1
            rowSpacing: Kirigami.Units.smallSpacing
            columnSpacing: Kirigami.Units.smallSpacing
            Repeater {
                model: root.compactKeys
                CompactView {
                    readonly property var info: root.itemInfo(modelData, root.d, backend.hist)
                    Layout.fillHeight: !parent.parent.vertical
                    Layout.fillWidth: parent.parent.vertical
                    label: info.label
                    valueText: info.value
                    valueText2: info.value2
                    hist: info.hist
                    hist2: info.hist2
                    maxValue: info.max
                    color: info.color
                    color2: info.color2
                    showLabel: root.cfg.compactShowLabel
                    showGraph: root.cfg.compactShowGraph
                    onClicked: root.expanded = !root.expanded
                }
            }
        }
    }

    fullRepresentation: PlasmaComponents3.ScrollView {
        id: scroll
        Layout.minimumWidth: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 24
        Layout.minimumHeight: Kirigami.Units.gridUnit * 12
        Layout.preferredHeight: Math.min(content.implicitHeight + Kirigami.Units.largeSpacing, Kirigami.Units.gridUnit * 40)
        contentWidth: availableWidth
        PlasmaComponents3.ScrollBar.horizontal.policy: PlasmaComponents3.ScrollBar.AlwaysOff

        ColumnLayout {
            id: content
            width: scroll.availableWidth
            spacing: Kirigami.Units.largeSpacing

            Kirigami.InlineMessage {
                Layout.fillWidth: true
                visible: backend.error !== ""
                type: Kirigami.MessageType.Error
                text: "Sys Manager backend failed: " + backend.error
            }

            SystemSection {
                visible: root.cfg.showSystem
                Layout.fillWidth: true
                system: root.d.system || null
            }
            Kirigami.Separator { Layout.fillWidth: true; visible: root.cfg.showSystem && root.cfg.showCpu }
            CpuSection {
                visible: root.cfg.showCpu
                Layout.fillWidth: true
                cpu: root.d.cpu || null
                hist: backend.hist.cpu || []
                showGraph: root.cfg.showGraph
                showPerCore: root.cfg.showPerCore
                warnColors: root.cfg.warnColors
            }
            Kirigami.Separator { Layout.fillWidth: true; visible: root.cfg.showRam }
            RamSection {
                visible: root.cfg.showRam
                Layout.fillWidth: true
                ram: root.d.ram || null
                hist: backend.hist.ram || []
                showGraph: root.cfg.showGraph
                showModules: root.cfg.showRamModules
                warnColors: root.cfg.warnColors
            }
            Repeater {
                model: root.cfg.showGpu && root.d.gpu ? root.d.gpu : []
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Kirigami.Units.largeSpacing
                    Kirigami.Separator { Layout.fillWidth: true }
                    GpuSection {
                        Layout.fillWidth: true
                        gpu: modelData
                        hist: backend.hist["gpu" + index] || []
                        showGraph: root.cfg.showGraph
                        showEngines: root.cfg.showGpuEngines
                        warnColors: root.cfg.warnColors
                    }
                }
            }
            Kirigami.Separator { Layout.fillWidth: true; visible: root.cfg.showDisk }
            DiskSection {
                visible: root.cfg.showDisk
                Layout.fillWidth: true
                disk: root.d.disk || null
                histRead: backend.hist.read || []
                histWrite: backend.hist.write || []
                showGraph: root.cfg.showGraph
                warnColors: root.cfg.warnColors
            }
            Kirigami.Separator { Layout.fillWidth: true; visible: root.cfg.showNet }
            NetSection {
                visible: root.cfg.showNet
                Layout.fillWidth: true
                net: root.d.net || null
                histRx: backend.hist.rx || []
                histTx: backend.hist.tx || []
                showGraph: root.cfg.showGraph
                showVirtual: root.cfg.showVirtualInterfaces
            }
            Kirigami.Separator { Layout.fillWidth: true; visible: root.cfg.showProcs }
            ProcSection {
                visible: root.cfg.showProcs
                Layout.fillWidth: true
                procs: root.d.procs || null
            }
        }
    }
}
