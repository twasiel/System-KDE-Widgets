import QtQuick
import QtQuick.Controls as QQC2
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.kcmutils as KCM

KCM.SimpleKCM {
    property alias cfg_showSystem: sSystem.checked
    property alias cfg_showCpu: sCpu.checked
    property alias cfg_showRam: sRam.checked
    property alias cfg_showGpu: sGpu.checked
    property alias cfg_showDisk: sDisk.checked
    property alias cfg_showNet: sNet.checked
    property alias cfg_showProcs: sProcs.checked
    property string cfg_compactItems

    readonly property var allItems: [["cpu", "CPU"], ["ram", "Memory"], ["gpu", "GPU"], ["disk", "Disk I/O"], ["net", "Network"]]

    function toggleItem(key, on) {
        var list = cfg_compactItems.split(",").filter(x => x !== "" && x !== key);
        if (on) list.push(key);
        // keep a stable order
        cfg_compactItems = allItems.map(a => a[0]).filter(k => list.indexOf(k) !== -1).join(",");
    }

    Kirigami.FormLayout {
        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Sections in the full view" }
        QQC2.CheckBox { id: sSystem; text: "System (OS, uptime, battery)" }
        QQC2.CheckBox { id: sCpu; text: "CPU" }
        QQC2.CheckBox { id: sRam; text: "Memory" }
        QQC2.CheckBox { id: sGpu; text: "GPU" }
        QQC2.CheckBox { id: sDisk; text: "Storage" }
        QQC2.CheckBox { id: sNet; text: "Network" }
        QQC2.CheckBox { id: sProcs; text: "Top processes" }

        Item { Kirigami.FormData.isSection: true; Kirigami.FormData.label: "Shown in the panel" }
        Repeater {
            model: allItems
            QQC2.CheckBox {
                text: modelData[1]
                checked: cfg_compactItems.split(",").indexOf(modelData[0]) !== -1
                onToggled: toggleItem(modelData[0], checked)
            }
        }
    }
}
