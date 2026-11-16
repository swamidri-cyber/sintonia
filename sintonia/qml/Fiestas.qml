// ─────────────────────────────────────────────────────────────────────────────
//  FIESTAS — unos días antes de cada fecha la interfaz se viste sola.
//  Va encima de los menús y abajo de CONFIGURACIÓN; nunca encima de una
//  película (ni de las portadas: todo va por los bordes y es transparente).
//
//    Navidad        21–25 dic   lucecitas de colores arriba, nieve
//    Año Nuevo      30 dic–1 ene fuegos artificiales y papelitos
//    San Valentín   10–14 feb   corazones que suben
//    Primavera      18–21 sep   guirnalda de flores y pétalos
//    Halloween      27–31 oct   telarañas, murciélagos y calabazas
//    Día de Muertos 1–2 nov     papel picado y pétalos de cempasúchil
//
//  CONFIGURACIÓN → FIESTAS: apagarlas o ver cómo queda cada una.
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Particles

Item {
    id: fx
    property bool on: true                      // CONFIGURACIÓN → FIESTAS
    property string preview: ""
    property bool hidden: false                 // viendo una película
    readonly property var list: [
        { id: "navidad",   nombre: "Navidad",        cuando: "del 21 al 25 de diciembre", desde: [12, 21], hasta: [12, 25] },
        { id: "anionuevo", nombre: "Año Nuevo",      cuando: "del 30 de diciembre al 1 de enero", desde: [12, 30], hasta: [1, 1] },
        { id: "valentin",  nombre: "San Valentín",   cuando: "del 10 al 14 de febrero", desde: [2, 10], hasta: [2, 14] },
        { id: "primavera", nombre: "Primavera",      cuando: "del 18 al 21 de septiembre", desde: [9, 18], hasta: [9, 21] },
        { id: "halloween", nombre: "Halloween",      cuando: "del 27 al 31 de octubre", desde: [10, 27], hasta: [10, 31] },
        { id: "muertos",   nombre: "Día de Muertos", cuando: "1 y 2 de noviembre", desde: [11, 1], hasta: [11, 2] }
    ]
    property date now: new Date()
    Timer { interval: 60 * 60 * 1000; repeat: true; running: true; onTriggered: fx.now = new Date() }
    function inRange(f, d) {
        const k = (d.getMonth() + 1) * 100 + d.getDate();
        const a = f.desde[0] * 100 + f.desde[1], b = f.hasta[0] * 100 + f.hasta[1];
        return a <= b ? (k >= a && k <= b) : (k >= a || k <= b);     // (la de Año Nuevo cruza el año)
    }
    readonly property string hoy: {
        // Año Nuevo gana el 30/31 (Navidad ya pasó)
        const order = ["anionuevo", "navidad", "valentin", "primavera", "halloween", "muertos"];
        for (const id of order) { const f = list.find(x => x.id === id); if (inRange(f, now)) return id; }
        return "";
    }
    readonly property string activa: preview !== "" ? preview : (on ? hoy : "")
    visible: activa !== "" && !hidden
    opacity: visible ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 400 } }

    // ── NAVIDAD: guirnalda de lucecitas + nieve ─────────────────────────────
    Item {
        anchors.fill: parent
        visible: fx.activa === "navidad"
        Repeater {
            model: 2                              // dos tiras que cuelgan, como en una vidriera
            Item {
                id: tira
                required property int index
                readonly property real sag: index === 0 ? 46 : 74
                readonly property real y0: index === 0 ? -6 : 10
                readonly property int n: index === 0 ? 26 : 22
                width: fx.width; height: 140
                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        const g = getContext("2d"); g.clearRect(0, 0, width, height);
                        g.strokeStyle = "#1b3a1f"; g.lineWidth = 3; g.beginPath();
                        const seg = 3;
                        for (let s = 0; s < seg; s++) {
                            const x0 = s * width / seg, x1 = (s + 1) * width / seg;
                            g.moveTo(x0, tira.y0);
                            g.quadraticCurveTo((x0 + x1) / 2, tira.y0 + tira.sag * 2, x1, tira.y0);
                        }
                        g.stroke();
                    }
                    onWidthChanged: requestPaint()
                }
                Repeater {
                    model: tira.n
                    Item {
                        required property int index
                        readonly property int seg: 3
                        readonly property real u: (index + 0.5) / tira.n
                        readonly property real sx: u * seg - Math.floor(u * seg)        // 0..1 dentro del tramo
                        x: u * fx.width - 7
                        y: tira.y0 + tira.sag * 2 * 2 * sx * (1 - sx) - 2
                        readonly property color c: ["#ff3b3b", "#ffd84a", "#3bd16f", "#46a6ff", "#ff7de9"][(index + tira.index * 2) % 5]
                        Rectangle { x: 4; y: -4; width: 6; height: 7; radius: 1; color: "#2a2a2a" }
                        Rectangle {
                            id: bulb
                            width: 14; height: 20; radius: 7
                            y: 2
                            color: parent.c
                            opacity: 0.35
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite
                                PauseAnimation { duration: (index * 137 + tira.index * 300) % 900 }
                                NumberAnimation { to: 1; duration: 260 }
                                PauseAnimation { duration: 500 + (index * 71) % 700 }
                                NumberAnimation { to: 0.35; duration: 380 }
                            }
                        }
                        Rectangle {        // el brillito alrededor
                            anchors.centerIn: bulb
                            width: 44; height: 44; radius: 22
                            color: parent.c
                            opacity: bulb.opacity * 0.22
                        }
                    }
                }
            }
        }
        ParticleSystem { id: nieve; running: fx.visible && fx.activa === "navidad" }
        ImageParticle {
            system: nieve
            source: "qrc:///particleresources/fuzzydot.png"
            color: "#ffffff"; colorVariation: 0.05; alpha: 0.85
        }
        Emitter {
            system: nieve
            width: parent.width; height: 1; y: -10
            emitRate: 26; lifeSpan: 14000
            size: 9; sizeVariation: 7
            velocity: AngleDirection { angle: 90; angleVariation: 12; magnitude: 70; magnitudeVariation: 30 }
            acceleration: PointDirection { xVariation: 8 }
        }
    }

    // ── AÑO NUEVO: fuegos artificiales y papelitos ──────────────────────────
    Item {
        anchors.fill: parent
        visible: fx.activa === "anionuevo"
        ParticleSystem { id: fuegos; running: fx.visible && fx.activa === "anionuevo" }
        ImageParticle {
            system: fuegos
            groups: ["chispa"]
            source: "qrc:///particleresources/glowdot.png"
            color: "#ffd25a"; colorVariation: 0.6; alpha: 0.9
            entryEffect: ImageParticle.Fade
        }
        Repeater {
            model: 4
            Emitter {
                id: estallido
                required property int index
                system: fuegos
                group: "chispa"
                x: fx.width * (0.12 + 0.25 * index + 0.06 * Math.sin(index * 7)); y: fx.height * (0.12 + 0.07 * (index % 2))
                width: 1; height: 1
                enabled: false
                lifeSpan: 1600; lifeSpanVariation: 400
                size: 12; sizeVariation: 6; endSize: 2
                velocity: AngleDirection { angleVariation: 360; magnitude: 170; magnitudeVariation: 60 }
                acceleration: PointDirection { y: 90 }
                Timer {
                    interval: 2300 + estallido.index * 700; repeat: true; running: fx.visible && fx.activa === "anionuevo"
                    onTriggered: { estallido.x = fx.width * (0.08 + Math.random() * 0.84); estallido.y = fx.height * (0.08 + Math.random() * 0.18); estallido.burst(110); }
                }
            }
        }
        ParticleSystem { id: papelitos; running: fx.visible && fx.activa === "anionuevo" }
        ItemParticle {
            system: papelitos
            delegate: Rectangle {
                width: 8; height: 14; radius: 1
                color: ["#ffd25a", "#ff5a7a", "#5ad1ff", "#9dff5a", "#ffffff"][Math.floor(Math.random() * 5)]
                rotation: Math.random() * 360
                opacity: 0.85
            }
        }
        Emitter {
            system: papelitos
            width: parent.width; height: 1; y: -20
            emitRate: 9; lifeSpan: 13000
            velocity: AngleDirection { angle: 90; angleVariation: 20; magnitude: 90; magnitudeVariation: 40 }
        }
    }

    // ── SAN VALENTÍN: corazones que suben ───────────────────────────────────
    Item {
        anchors.fill: parent
        visible: fx.activa === "valentin"
        ParticleSystem { id: corazones; running: fx.visible && fx.activa === "valentin" }
        ItemParticle {
            system: corazones
            delegate: Text {
                text: "♥"
                font.pixelSize: 22 + Math.random() * 30
                color: ["#ff4d6d", "#ff8fa3", "#ffccd5", "#c9184a"][Math.floor(Math.random() * 4)]
                opacity: 0.75
            }
        }
        Emitter {
            system: corazones
            width: parent.width; height: 1; y: parent.height + 20
            emitRate: 3; lifeSpan: 16000
            velocity: AngleDirection { angle: -90; angleVariation: 10; magnitude: 70; magnitudeVariation: 25 }
            acceleration: PointDirection { xVariation: 14 }
        }
        Rectangle {           // un rubor en los bordes
            anchors.fill: parent
            color: "transparent"
            border.width: 0
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 0.3, 0.45, 0.10) }
                GradientStop { position: 0.25; color: "transparent" }
                GradientStop { position: 0.8; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(1, 0.3, 0.45, 0.12) }
            }
        }
    }

    // ── PRIMAVERA: guirnalda de flores y pétalos ────────────────────────────
    Item {
        anchors.fill: parent
        visible: fx.activa === "primavera"
        Row {
            y: -14
            spacing: 6
            Repeater {
                model: Math.ceil(fx.width / 46) + 1
                Text {
                    required property int index
                    text: "✿"
                    font.pixelSize: 40
                    color: ["#ffb3c6", "#ffd166", "#caffbf", "#bdb2ff", "#ffffff"][index % 5]
                    rotation: (index * 37) % 360
                    opacity: 0.9
                    SequentialAnimation on rotation {
                        loops: Animation.Infinite
                        NumberAnimation { to: (index * 37) % 360 + 15; duration: 2400 + (index % 4) * 300; easing.type: Easing.InOutSine }
                        NumberAnimation { to: (index * 37) % 360 - 15; duration: 2400 + (index % 4) * 300; easing.type: Easing.InOutSine }
                    }
                }
            }
        }
        ParticleSystem { id: petalos; running: fx.visible && fx.activa === "primavera" }
        ItemParticle {
            system: petalos
            delegate: Rectangle {
                width: 12; height: 8; radius: 6
                color: ["#ffb3c6", "#ffc8dd", "#fff0f3"][Math.floor(Math.random() * 3)]
                rotation: Math.random() * 360
                opacity: 0.85
            }
        }
        Emitter {
            system: petalos
            width: parent.width; height: 1; y: -10
            emitRate: 7; lifeSpan: 15000
            velocity: AngleDirection { angle: 80; angleVariation: 25; magnitude: 55; magnitudeVariation: 25 }
            acceleration: PointDirection { x: 6; xVariation: 12 }
        }
    }

    // ── HALLOWEEN: telarañas, murciélagos y calabazas ───────────────────────
    Item {
        anchors.fill: parent
        visible: fx.activa === "halloween"
        Repeater {
            model: 2
            Canvas {           // telarañas en las esquinas de arriba
                required property int index
                width: 260; height: 260
                x: index === 0 ? 0 : fx.width - width
                transform: Scale { origin.x: 130; xScale: index === 0 ? 1 : -1 }
                onPaint: {
                    const g = getContext("2d"); g.clearRect(0, 0, width, height);
                    g.strokeStyle = "rgba(230,230,230,0.45)"; g.lineWidth = 1.4;
                    const rays = 7, R = 250;
                    for (let i = 0; i < rays; i++) {
                        const a = i / (rays - 1) * Math.PI / 2;
                        g.beginPath(); g.moveTo(0, 0); g.lineTo(Math.cos(a) * R, Math.sin(a) * R); g.stroke();
                    }
                    for (let r = 35; r < R; r += 38) {
                        g.beginPath();
                        for (let i = 0; i < rays; i++) {
                            const a = i / (rays - 1) * Math.PI / 2;
                            const x = Math.cos(a) * r, y = Math.sin(a) * r;
                            if (i === 0) g.moveTo(x, y);
                            else {
                                const am = (i - 0.5) / (rays - 1) * Math.PI / 2;
                                g.quadraticCurveTo(Math.cos(am) * r * 0.82, Math.sin(am) * r * 0.82, x, y);
                            }
                        }
                        g.stroke();
                    }
                }
            }
        }
        Repeater {
            model: 5
            Canvas {         // murciélagos que cruzan
                id: bat
                required property int index
                width: 64 + (index % 3) * 18; height: width * 0.5
                y: fx.height * (0.08 + 0.09 * index)
                property real ala: 0
                SequentialAnimation on ala {
                    loops: Animation.Infinite
                    running: fx.visible && fx.activa === "halloween"
                    NumberAnimation { to: 1; duration: 160 }
                    NumberAnimation { to: 0; duration: 160 }
                }
                onAlaChanged: requestPaint()
                onPaint: {
                    const g = getContext("2d"); g.clearRect(0, 0, width, height);
                    const w = width, h = height, cx = w / 2, up = (ala - 0.5) * h * 0.5;
                    g.fillStyle = "#14081c"; g.strokeStyle = "rgba(255,140,30,0.45)"; g.lineWidth = 1.2;
                    g.beginPath();
                    g.moveTo(cx, h * 0.45);
                    g.quadraticCurveTo(cx - w * 0.2, h * 0.2 - up, 0, h * 0.25 - up);
                    g.quadraticCurveTo(w * 0.12, h * 0.55, w * 0.18, h * 0.62);
                    g.quadraticCurveTo(w * 0.28, h * 0.5, cx - w * 0.06, h * 0.72);
                    g.lineTo(cx, h * 0.62);
                    g.lineTo(cx + w * 0.06, h * 0.72);
                    g.quadraticCurveTo(w * 0.72, h * 0.5, w * 0.82, h * 0.62);
                    g.quadraticCurveTo(w * 0.88, h * 0.55, w, h * 0.25 - up);
                    g.quadraticCurveTo(cx + w * 0.2, h * 0.2 - up, cx, h * 0.45);
                    g.fill(); g.stroke();
                    g.beginPath(); g.ellipse(cx - w * 0.06, h * 0.3, w * 0.12, h * 0.36); g.fill();
                }
                NumberAnimation on x {
                    loops: Animation.Infinite
                    running: fx.visible && fx.activa === "halloween"
                    from: -80 - bat.index * 260; to: fx.width + 80
                    duration: 14000 + bat.index * 2300
                }
                SequentialAnimation on y {
                    loops: Animation.Infinite
                    running: fx.visible && fx.activa === "halloween"
                    NumberAnimation { to: fx.height * (0.08 + 0.09 * bat.index) - 26; duration: 520; easing.type: Easing.InOutSine }
                    NumberAnimation { to: fx.height * (0.08 + 0.09 * bat.index) + 26; duration: 520; easing.type: Easing.InOutSine }
                }
            }
        }
        Repeater {
            model: 3
            Item {           // calabazas abajo, con la vela titilando
                required property int index
                width: 90; height: 76
                x: [40, fx.width - 150, fx.width - 260][index]
                y: fx.height - height - 18
                scale: [1.0, 1.15, 0.8][index]
                Canvas {
                    id: zapallo
                    anchors.fill: parent
                    property real luz: 0.8
                    SequentialAnimation on luz {
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.0; duration: 180 }
                        NumberAnimation { to: 0.65; duration: 240 }
                        NumberAnimation { to: 0.9; duration: 140 }
                    }
                    onLuzChanged: requestPaint()
                    onPaint: {
                        const g = getContext("2d"); g.clearRect(0, 0, width, height);
                        g.fillStyle = "#3d6b1f"; g.fillRect(width / 2 - 4, 2, 8, 14);
                        g.fillStyle = "#e86a10";
                        for (const [cx, rx] of [[width / 2 - 22, 22], [width / 2 + 22, 22], [width / 2, 26]]) {
                            g.beginPath(); g.ellipse(cx - rx, 12, rx * 2, height - 14); g.fill();
                        }
                        g.fillStyle = "rgba(255," + Math.round(200 * luz) + ",60," + luz + ")";
                        const tri = (x, y, s, up) => { g.beginPath(); g.moveTo(x - s, y + (up ? s : 0)); g.lineTo(x + s, y + (up ? s : 0)); g.lineTo(x, y + (up ? 0 : s)); g.closePath(); g.fill(); };
                        tri(width / 2 - 16, 30, 8, true); tri(width / 2 + 16, 30, 8, true);
                        g.beginPath(); g.moveTo(width / 2 - 24, 50); g.lineTo(width / 2 + 24, 50); g.lineTo(width / 2 + 14, 60);
                        g.lineTo(width / 2, 54); g.lineTo(width / 2 - 14, 60); g.closePath(); g.fill();
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 170; height: 120; radius: 60
                    color: "#ff7a1a"; opacity: 0.10 * zapallo.luz
                    z: -1
                }
            }
        }
    }

    // ── DÍA DE MUERTOS: papel picado y pétalos de cempasúchil ───────────────
    Item {
        anchors.fill: parent
        visible: fx.activa === "muertos"
        Rectangle { width: parent.width; height: 2; y: 6; color: "#5a3a1a" }
        Row {
            y: 7
            Repeater {
                model: Math.ceil(fx.width / 96) + 1
                Item {
                    id: bandera
                    required property int index
                    width: 96; height: 96
                    transformOrigin: Item.Top
                    SequentialAnimation on rotation {
                        loops: Animation.Infinite
                        NumberAnimation { to: 3; duration: 1600 + (bandera.index % 5) * 230; easing.type: Easing.InOutSine }
                        NumberAnimation { to: -3; duration: 1600 + (bandera.index % 5) * 230; easing.type: Easing.InOutSine }
                    }
                    Canvas {
                        anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                        readonly property color c: ["#ff2d8a", "#ff9f1c", "#2ec4b6", "#8338ec", "#ffd60a", "#3a86ff"][bandera.index % 6]
                        onPaint: {
                            const g = getContext("2d"); g.clearRect(0, 0, width, height);
                            g.fillStyle = c;
                            g.beginPath(); g.moveTo(0, 0); g.lineTo(width, 0); g.lineTo(width, height - 14);
                            for (let i = 0; i <= 6; i++) g.lineTo(width - i * width / 6, height - (i % 2 ? 0 : 14));
                            g.closePath(); g.fill();
                            // los calados: flores y rombos
                            g.globalCompositeOperation = "destination-out";
                            const cx = width / 2, cy = height / 2 - 6;
                            for (let k = 0; k < 6; k++) {
                                const a = k * Math.PI / 3;
                                g.beginPath(); g.ellipse(cx + Math.cos(a) * 12 - 6, cy + Math.sin(a) * 12 - 6, 12, 12); g.fill();
                            }
                            g.beginPath(); g.ellipse(cx - 5, cy - 5, 10, 10); g.fill();
                            for (const [x, y] of [[14, 14], [width - 14, 14], [14, height - 30], [width - 14, height - 30]]) {
                                g.beginPath(); g.moveTo(x, y - 6); g.lineTo(x + 5, y); g.lineTo(x, y + 6); g.lineTo(x - 5, y); g.closePath(); g.fill();
                            }
                            g.globalCompositeOperation = "source-over";
                        }
                    }
                }
            }
        }
        ParticleSystem { id: flores; running: fx.visible && fx.activa === "muertos" }
        ItemParticle {
            system: flores
            delegate: Rectangle {
                width: 10; height: 7; radius: 5
                color: ["#ff9f1c", "#ffbf00", "#ff7b00"][Math.floor(Math.random() * 3)]
                rotation: Math.random() * 360
                opacity: 0.9
            }
        }
        Emitter {
            system: flores
            width: parent.width; height: 1; y: 90
            emitRate: 6; lifeSpan: 14000
            velocity: AngleDirection { angle: 90; angleVariation: 18; magnitude: 60; magnitudeVariation: 25 }
            acceleration: PointDirection { xVariation: 10 }
        }
    }
}
