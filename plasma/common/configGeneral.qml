import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_updateInterval: intervalSpin.value
    property alias cfg_historyLength: historySpin.value
    property alias cfg_showGraph: showGraph.checked
    property alias cfg_compactShowLabel: compactLabel.checked
    property alias cfg_compactShowGraph: compactGraph.checked
    property alias cfg_warnColors: warnColors.checked
    property alias cfg_showPerCore: perCore.checked
    property alias cfg_showRamModules: ramModules.checked
    property alias cfg_showGpuEngines: gpuEngines.checked
    property alias cfg_showVirtualInterfaces: virtualIfaces.checked
    property alias cfg_gpuIndex: gpuIndex.value
    property alias cfg_ramCompactAbsolute: ramAbs.checked

    Kirigami.FormLayout {
        QQC2.SpinBox {
            id: intervalSpin
            Kirigami.FormData.label: "Update interval:"
            from: 500; to: 60000; stepSize: 500
            editable: true
            textFromValue: (v) => (v / 1000).toFixed(1) + " s"
            valueFromText: (t) => Math.round(parseFloat(t) * 1000)
        }
        QQC2.SpinBox {
            id: historySpin
            Kirigami.FormData.label: "Graph history (samples):"
            from: 10; to: 600; stepSize: 10
            editable: true
        }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Panel" }
        QQC2.CheckBox { id: compactLabel; text: "Show label (CPU, RAM, …)" }
        QQC2.CheckBox { id: compactGraph; text: "Show graph behind the value" }
        QQC2.CheckBox { id: ramAbs; text: "Memory: show used amount instead of percent" }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Details" }
        QQC2.CheckBox { id: showGraph; text: "Show history graphs" }
        QQC2.CheckBox { id: warnColors; text: "Warning colors when usage is high" }
        QQC2.CheckBox { id: perCore; text: "CPU: per-core usage" }
        QQC2.CheckBox { id: ramModules; text: "Memory: list installed modules" }
        QQC2.CheckBox { id: gpuEngines; text: "GPU: per-engine usage" }
        QQC2.CheckBox { id: virtualIfaces; text: "Network: include virtual interfaces" }
        QQC2.SpinBox {
            id: gpuIndex
            Kirigami.FormData.label: "GPU (multi-GPU systems):"
            from: 0; to: 7
        }
    }
}
