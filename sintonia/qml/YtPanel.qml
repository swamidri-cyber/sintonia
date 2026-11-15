// Canal de YouTube: en lugar de la portada grande, un panel de "transmisión
// entrante" con la estética de la PC (monitor de NERV/MAGI): los datos del
// video se escriben como en una terminal, un osciloscopio con la señal, una
// grilla roja que se mueve y 動画 de marca de agua. El estado vive en shell.qml.
import QtQuick

Item {
    id: yp
    required property var cine
    readonly property var th: cine.theme
    readonly property var it: cine.current
    visible: cine.platform === "youtube" && !cine.playFull
    property real t: 0
    FrameAnimation { running: yp.visible && yp.cine.open; onTriggered: yp.t += frameTime }

    // ── Fondo: negro rojizo, grilla que avanza, líneas de barrido ─────────
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#140202" }
            GradientStop { position: 0.6; color: "#080101" }
            GradientStop { position: 1.0; color: "#000000" }
        }
    }
    Canvas {
        id: grid
        anchors.fill: parent
        opacity: 0.55
        property real off: (yp.t * 18) % 60
        onOffChanged: requestPaint()
        onPaint: {
            const g = getContext("2d");
            g.reset();
            g.strokeStyle = "rgba(255, 40, 30, 0.10)";
            g.lineWidth = 1;
            for (let x = -60 + off; x < width; x += 60) { g.beginPath(); g.moveTo(x, 0); g.lineTo(x, height); g.stroke(); }
            for (let y = 0; y < height; y += 60) { g.beginPath(); g.moveTo(0, y); g.lineTo(width, y); g.stroke(); }
        }
    }
    Text {      // marca de agua
        anchors { right: parent.right; rightMargin: -40; verticalCenter: parent.verticalCenter; verticalCenterOffset: -140 }
        text: "動画"
        font.family: "Noto Sans CJK JP"; font.weight: Font.Black; font.pixelSize: 520
        color: Qt.rgba(1, 0.1, 0.08, 0.06)
    }

    // ── Transmisión: datos del video ──────────────────────────────────────
    Column {
        id: info
        anchors { left: parent.left; leftMargin: 90; top: parent.top; topMargin: 150 }
        width: parent.width * 0.5
        spacing: 14

        Row {
            spacing: 14
            Rectangle {   // franja de peligro
                width: 64; height: 14; anchors.verticalCenter: parent.verticalCenter
                clip: true; color: "#ffd25a"
                Item {
                    x: -((yp.t * 30) % 20)
                    Repeater { model: 8; Rectangle { required property int index; width: 10; height: 30; color: "#140202"; rotation: 35; x: index * 20; y: -8 } }
                }
            }
            Text {
                text: "▶ TRANSMISIÓN ENTRANTE  //  CH 07  動画"
                font.family: yp.cine.mono; font.pixelSize: 16; font.letterSpacing: 2
                color: "#ff5a4a"
                SequentialAnimation on opacity {
                    loops: Animation.Infinite; running: yp.visible
                    NumberAnimation { to: 0.45; duration: 800 }
                    NumberAnimation { to: 1.0; duration: 800 }
                }
            }
        }
        Text {
            width: parent.width
            text: yp.it?.name ?? ""
            wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
            font.family: yp.cine.sans; font.pixelSize: 44; font.weight: Font.Black
            color: "white"
            lineHeight: 1.05
        }
        // lectura tipo terminal, se escribe letra por letra al cambiar de video
        Item {
            width: parent.width; height: readout.implicitHeight
            property string full: {
                const v = yp.it;
                if (!v) return "";
                const row = (k, val) => val ? (k + " " + ".".repeat(Math.max(2, 14 - k.length)) + " " + val + "\n") : "";
                return row("CANAL", v.channel) + row("DURACIÓN", v.runtime) + row("VISTAS", v.viewsText)
                     + row("PUBLICADO", v.year) + (v.offset > 0 ? row("QUEDASTE EN", yp.cine.fmtClock(v.offset / 1000)) : "");
            }
            property int shown: 0
            onFullChanged: { shown = 0; typer.restart(); }
            Timer { id: typer; interval: 12; repeat: true; onTriggered: { if (parent.shown < parent.full.length) parent.shown += 3; else stop(); } }
            Text {
                id: readout
                text: parent.full.slice(0, parent.shown) + (parent.shown < parent.full.length ? "█" : "")
                font.family: yp.cine.mono; font.pixelSize: 19
                color: "#ffb4ab"
                lineHeight: 1.35
            }
        }
    }

    // ── Osciloscopio con la señal ──────────────────────────────────────────
    Item {
        id: scope
        anchors { right: parent.right; rightMargin: 120; top: parent.top; topMargin: 165 }
        width: 560; height: 260
        // esquinas de visor
        Repeater {
            model: 4
            Item {
                required property int index
                x: index % 2 ? scope.width - 28 : 0
                y: index < 2 ? 0 : scope.height - 28
                width: 28; height: 28
                Rectangle { width: 28; height: 2; color: "#ff5a4a"; y: parent.index < 2 ? 0 : 26 }
                Rectangle { width: 2; height: 28; color: "#ff5a4a"; x: parent.index % 2 ? 26 : 0 }
            }
        }
        Canvas {
            anchors { fill: parent; margins: 18 }
            property real tt: yp.t
            onTtChanged: requestPaint()
            onPaint: {
                const g = getContext("2d");
                g.reset();
                const h = height / 2, seed = (yp.it?.id ?? "").length;
                g.strokeStyle = "rgba(255, 70, 55, 0.25)"; g.lineWidth = 1;
                g.beginPath(); g.moveTo(0, h); g.lineTo(width, h); g.stroke();
                for (let k = 0; k < 2; k++) {
                    g.strokeStyle = k ? "rgba(255, 90, 74, 0.35)" : "#ff5a4a";
                    g.lineWidth = k ? 5 : 2;
                    g.beginPath();
                    for (let x = 0; x <= width; x += 4) {
                        const p = x / width;
                        const y = h + Math.sin(p * 14 + tt * 3 + seed) * h * 0.45 * Math.sin(p * 3.1416)
                                    + Math.sin(p * 47 - tt * 7) * h * 0.12 + Math.sin(p * 5 + tt * 1.3) * h * 0.15;
                        x === 0 ? g.moveTo(x, y) : g.lineTo(x, y);
                    }
                    g.stroke();
                }
            }
        }
        Text {
            anchors { left: parent.left; top: parent.bottom; topMargin: 10 }
            text: "SEÑAL  " + (80 + Math.round(Math.sin(yp.t * 2) * 12)) + "%   ·   " + Qt.formatDateTime(new Date(), "hh:mm") + "   ·   ENLACE MAGI-07"
            font.family: yp.cine.mono; font.pixelSize: 14
            color: "#b5544c"
        }
    }
}
