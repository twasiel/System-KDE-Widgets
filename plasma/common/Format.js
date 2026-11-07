.pragma library

function isNum(v) {
    return v !== null && v !== undefined && !isNaN(v);
}

function bytes(n, digits) {
    if (!isNum(n)) return "–";
    var units = ["B", "KiB", "MiB", "GiB", "TiB", "PiB"];
    var i = 0;
    n = Number(n);
    while (Math.abs(n) >= 1024 && i < units.length - 1) { n /= 1024; i++; }
    if (i === 0) return Math.round(n) + " B";
    var d = digits === undefined ? (n >= 100 ? 0 : 1) : digits;
    return n.toFixed(d) + " " + units[i];
}

function rate(n) {
    if (!isNum(n)) return "–";
    return bytes(n, n < 1024 * 1024 ? 0 : 1) + "/s";
}

function pct(v, digits) {
    if (!isNum(v)) return "–";
    return Number(v).toFixed(digits === undefined ? 0 : digits) + "%";
}

function mhz(v) {
    if (!isNum(v) || v <= 0) return "–";
    return v >= 1000 ? (v / 1000).toFixed(2) + " GHz" : Math.round(v) + " MHz";
}

function temp(v) {
    if (!isNum(v)) return "–";
    return Math.round(v) + " °C";
}

function watts(v) {
    if (!isNum(v)) return "–";
    return Number(v).toFixed(1) + " W";
}

function duration(sec) {
    if (!isNum(sec)) return "–";
    sec = Math.floor(sec);
    var d = Math.floor(sec / 86400); sec -= d * 86400;
    var h = Math.floor(sec / 3600); sec -= h * 3600;
    var m = Math.floor(sec / 60);
    if (d > 0) return d + "d " + h + "h " + m + "m";
    if (h > 0) return h + "h " + m + "m";
    return m + "m";
}

function or(v, fallback) {
    return (v === null || v === undefined || v === "") ? fallback : v;
}
