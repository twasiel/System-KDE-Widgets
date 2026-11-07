// Small history graph. values (and optional values2) are arrays of numbers.
import QtQuick
import org.kde.kirigami as Kirigami

Canvas {
    id: canvas

    property var values: []
    property var values2: []
    property color color: Kirigami.Theme.highlightColor
    property color color2: Kirigami.Theme.positiveTextColor
    property real maxValue: 100          // <= 0 means auto-scale
    property int capacity: 60
    property bool showGrid: true
    property bool showFill: true
    property real lineWidth: 1.5

    readonly property real effectiveMax: {
        if (maxValue > 0) return maxValue;
        var m = 1;
        var all = (values || []).concat(values2 || []);
        for (var i = 0; i < all.length; i++) m = Math.max(m, all[i]);
        return m * 1.15;
    }

    onValuesChanged: requestPaint()
    onValues2Changed: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onColorChanged: requestPaint()

    function drawSeries(ctx, arr, col) {
        if (!arr || arr.length < 2) return;
        var step = width / Math.max(1, capacity - 1);
        var n = Math.min(arr.length, capacity);
        var start = arr.length - n;
        var x0 = width - (n - 1) * step;
        var max = effectiveMax;
        function yOf(v) { return height - Math.max(0, Math.min(1, v / max)) * (height - lineWidth) - lineWidth / 2; }

        ctx.beginPath();
        ctx.moveTo(x0, yOf(arr[start]));
        for (var i = 1; i < n; i++) ctx.lineTo(x0 + i * step, yOf(arr[start + i]));
        if (showFill) {
            ctx.save();
            ctx.lineTo(width, height);
            ctx.lineTo(x0, height);
            ctx.closePath();
            var g = ctx.createLinearGradient(0, 0, 0, height);
            g.addColorStop(0, Qt.rgba(col.r, col.g, col.b, 0.35));
            g.addColorStop(1, Qt.rgba(col.r, col.g, col.b, 0.05));
            ctx.fillStyle = g;
            ctx.fill();
            ctx.restore();
            ctx.beginPath();
            ctx.moveTo(x0, yOf(arr[start]));
            for (var j = 1; j < n; j++) ctx.lineTo(x0 + j * step, yOf(arr[start + j]));
        }
        ctx.lineWidth = lineWidth;
        ctx.lineJoin = "round";
        ctx.strokeStyle = col;
        ctx.stroke();
    }

    onPaint: {
        var ctx = getContext("2d");
        ctx.reset();
        if (showGrid) {
            var t = Kirigami.Theme.textColor;
            ctx.strokeStyle = Qt.rgba(t.r, t.g, t.b, 0.08);
            ctx.lineWidth = 1;
            for (var k = 1; k < 4; k++) {
                var y = Math.round(height * k / 4) + 0.5;
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke();
            }
        }
        drawSeries(ctx, values2, color2);
        drawSeries(ctx, values, color);
    }
}
