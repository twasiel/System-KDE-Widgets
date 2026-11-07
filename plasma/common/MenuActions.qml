// Context-menu actions shared by all Sys Manager widgets.
import QtQuick
import org.kde.plasma.core as PlasmaCore

QtObject {
    id: actions
    property var backend

    readonly property list<PlasmaCore.Action> list: [
        PlasmaCore.Action {
            text: "Open Terminal Monitor"
            icon.name: "utilities-terminal"
            onTriggered: actions.backend.run("konsole -e python3 '" + actions.backend.script + "' tui || xterm -e python3 '" + actions.backend.script + "' tui")
        },
        PlasmaCore.Action {
            text: "Open System Monitor"
            icon.name: "utilities-system-monitor"
            onTriggered: actions.backend.run("plasma-systemmonitor")
        },
        PlasmaCore.Action {
            text: "Refresh Now"
            icon.name: "view-refresh"
            onTriggered: actions.backend.refresh()
        }
    ]
}
