import QtQuick
import QtQuick.Layouts
import org.kde.kirigami as Kirigami
import org.kde.plasma.components as PlasmaComponents3
import "Format.js" as Fmt

ColumnLayout {
    id: sec
    property var system: null
    readonly property var s: system || ({})
    readonly property var bat: s.battery || null
    spacing: Kirigami.Units.smallSpacing

    SectionHeader {
        icon: "computer"
        title: Fmt.or(sec.s.hostname, "System")
        subtitle: [sec.s.vendor, sec.s.product].filter(x => !!x).join(" ")
        trailing: Fmt.duration(sec.s.uptime)
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StatRow { label: "OS"; value: Fmt.or(sec.s.os, "–") }
        StatRow { label: "Kernel"; value: Fmt.or(sec.s.kernel, "–") + (sec.s.arch ? " (" + sec.s.arch + ")" : "") }
        StatRow { label: "Desktop"; value: sec.s.plasma ? "KDE Plasma " + sec.s.plasma + (sec.s.session ? " · " + sec.s.session : "") : Fmt.or(sec.s.desktop, "–") }
        StatRow { label: "Uptime"; value: Fmt.duration(sec.s.uptime) }
        StatRow {
            label: "Battery"
            value: sec.bat ? sec.bat.capacity + "% · " + sec.bat.status + (sec.bat.power_w ? " · " + Fmt.watts(sec.bat.power_w) : "") : "–"
            valueColor: sec.bat && sec.bat.capacity <= 15 && sec.bat.status !== "Charging" ? Kirigami.Theme.negativeTextColor : Kirigami.Theme.textColor
        }
        StatRow { label: "Battery health"; value: sec.bat && sec.bat.health ? Fmt.pct(sec.bat.health) : "–" }
    }
}
