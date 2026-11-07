// Runs the bundled Python backend (contents/code/sysmanager.py) periodically
// and exposes the parsed JSON plus a short history for graphs.
import QtQuick
import org.kde.plasma.plasma5support as P5Support

Item {
    id: backend

    property var sections: ["cpu"]
    property string clientId: "default"
    property int interval: 2000
    property int historyLength: 60
    property bool active: true

    property var data: null
    property string error: ""
    property var hist: ({})          // key -> array of numbers
    signal updated()

    readonly property string script: Qt.resolvedUrl("../code/sysmanager.py").toString().replace(/^file:\/\//, "")
    readonly property string command: "python3 '" + script + "' json " + sections.join(" ")
                                      + " --client '" + clientId.replace(/[^A-Za-z0-9_.-]/g, "_") + "'"

    function refresh() {
        if (exec.connectedSources.indexOf(command) === -1)
            exec.connectSource(command);
    }

    function run(cmd) {          // fire-and-forget helper for context-menu actions
        launcher.connectSource(cmd);
    }

    function record(newHist, key, value) {
        if (value === null || value === undefined || isNaN(value))
            return;
        var arr = (hist[key] || []).slice(-(historyLength - 1));
        arr.push(Number(value));
        newHist[key] = arr;
    }

    function ingest(d) {
        var h = Object.assign({}, hist);
        if (d.cpu) record(h, "cpu", d.cpu.usage);
        if (d.ram) { record(h, "ram", d.ram.usage); record(h, "swap", d.ram.swap_usage); }
        if (d.gpu) for (var i = 0; i < d.gpu.length; i++) {
            record(h, "gpu" + i, d.gpu[i].usage);
            record(h, "gpumem" + i, d.gpu[i].mem_usage);
        }
        if (d.net) { record(h, "rx", d.net.rx_bps); record(h, "tx", d.net.tx_bps); }
        if (d.disk) { record(h, "read", d.disk.read_bps); record(h, "write", d.disk.write_bps); }
        hist = h;
        data = d;
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName, d) => {
            disconnectSource(sourceName);
            if (d["exit code"] !== 0 && !d.stdout) {
                backend.error = d.stderr || ("exit code " + d["exit code"]);
                return;
            }
            try {
                backend.ingest(JSON.parse(d.stdout));
                backend.error = "";
                backend.updated();
            } catch (e) {
                backend.error = "Bad backend output: " + e;
            }
        }
    }

    P5Support.DataSource {
        id: launcher
        engine: "executable"
        connectedSources: []
        onNewData: (sourceName) => disconnectSource(sourceName)
    }

    onCommandChanged: refresh()

    Timer {
        interval: Math.max(500, backend.interval)
        running: backend.active
        repeat: true
        triggeredOnStart: true
        onTriggered: backend.refresh()
    }
}
