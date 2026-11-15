// Capa del reproductor del modo cine (etapa 2): el menú de antes de
// reproducir (idioma y subtítulos), la pantalla de "sintonizando" y los
// controles encima de la película (mpv va debajo, a pantalla completa).
// Todo el estado vive en shell.qml (cine).
import QtQuick
import Sintonia
import QtQuick.Effects
import Quickshell

Item {
    id: pl
    required property var cine
    readonly property var th: cine.theme
    visible: cine.playStep !== "" || cine.nextEp !== null

    // ── Menú: idioma → subtítulos ──────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: pl.cine.playStep === "lang" || pl.cine.playStep === "subs" || pl.cine.playStep === "dest"
        color: Qt.rgba(0, 0, 0, 0.85)
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (m) => { if (m.button === Qt.RightButton) pl.cine.button("b"); }
        }

        Column {
            anchors.centerIn: parent
            width: 860
            spacing: 14
            EvaText {
                text: (pl.cine.play?.item.name ?? "").toUpperCase()
                size: 70
                maxWidth: parent.width
                color: pl.th.hi
            }
            Text {
                visible: (pl.cine.play?.epName ?? "") !== ""
                text: pl.cine.play?.epName ?? ""
                font.family: pl.cine.sans; font.pixelSize: 20
                color: pl.th.fg
            }
            Item { width: 1; height: 16 }
            Text {
                text: pl.cine.playStep === "lang" ? "¿EN QUÉ IDIOMA?" : pl.cine.playStep === "dest" ? (pl.cine.destTvOnly ? "¿EN QUÉ TELE?" : "¿DÓNDE LO VES?") : "¿SUBTÍTULOS EN ESPAÑOL?"
                font.family: pl.cine.mono; font.pixelSize: 18; font.letterSpacing: 4
                color: pl.th.dim
            }
            // buscando fuentes
            Text {
                visible: pl.cine.playStep === "lang" && !pl.cine.playOpts && pl.cine.playErr === ""
                text: "▒▒▒  BUSCANDO FUENTES EN TUS ADDONS…"
                font.family: pl.cine.mono; font.pixelSize: 20
                color: pl.th.fg
                SequentialAnimation on opacity {
                    loops: Animation.Infinite; running: parent.visible
                    NumberAnimation { to: 0.4; duration: 600 }
                    NumberAnimation { to: 1.0; duration: 600 }
                }
            }
            Text {
                visible: pl.cine.playErr !== ""
                width: parent.width
                wrapMode: Text.WordWrap
                text: "⚠  " + pl.cine.playErr
                font.family: pl.cine.sans; font.pixelSize: 20
                color: pl.th.warn
            }
            Repeater {
                model: pl.cine.playStep === "lang" ? (pl.cine.playOpts?.options ?? [])
                     : pl.cine.playStep === "subs" ? [{ label: "Sí, en español" }, { label: "No, sin subtítulos" }]
                     : pl.cine.playStep === "dest" ? pl.cine.destOptions() : []
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool on: index === pl.cine.playIndex
                    width: 860; height: 78; radius: 39
                    color: on ? pl.th.hi : Qt.rgba(1, 1, 1, 0.05)
                    border.color: on ? pl.th.hi : pl.th.line
                    border.width: 2
                    scale: on ? 1.03 : 1
                    Behavior on scale { NumberAnimation { duration: 140 } }
                    Text {
                        anchors { left: parent.left; leftMargin: 36; verticalCenter: parent.verticalCenter }
                        text: parent.modelData.label
                        font.family: pl.cine.sans; font.pixelSize: 26; font.weight: Font.Bold
                        color: parent.on ? pl.th.bg : pl.th.fg
                    }
                    Text {   // PC / CHROMECAST
                        visible: pl.cine.playStep === "dest"
                        anchors { right: parent.right; rightMargin: 36; verticalCenter: parent.verticalCenter }
                        text: (parent.modelData.note ?? "") + ((pl.cine.destTvOnly ? parent.modelData.target?.uuid === pl.cine.lastTv : parent.index === pl.cine.lastDest) ? "  ·  LA ÚLTIMA VEZ" : "")
                        font.family: pl.cine.mono; font.pixelSize: 15
                        color: parent.on ? pl.th.deep : pl.th.dim
                    }
                    Text {   // la mejor fuente de ese idioma
                        visible: pl.cine.playStep === "lang"
                        anchors { right: parent.right; rightMargin: 36; verticalCenter: parent.verticalCenter }
                        text: {
                            const s = parent.modelData.streams?.[0];
                            return s ? s.res + "p · " + s.size + " GB · " + s.seeds + " seeds" : "";
                        }
                        font.family: pl.cine.mono; font.pixelSize: 15
                        color: parent.on ? pl.th.deep : pl.th.dim
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: if (pl.cine.mouseMode) pl.cine.playIndex = parent.index
                        onClicked: { pl.cine.playIndex = parent.index; pl.cine.button("a"); }
                    }
                }
            }
            Item { width: 1; height: 10 }
            Text {
                text: "A ELEGIR   B VOLVER"
                font.family: pl.cine.mono; font.pixelSize: 14
                color: pl.th.line
            }
        }
    }

    // ── Sintonizando: negro con nieve, el título y cómo viene la señal ────
    Rectangle {
        anchors.fill: parent
        visible: pl.cine.playStep === "load"
        color: "black"
        ShaderEffect {
            anchors.fill: parent
            property real time: pl.cine.fxTime
            property real noise: 0.22
            property real bars: 0
            property size res: Qt.size(width, height)
            fragmentShader: App.url("shaders/tvstatic.frag.qsb")
            FrameAnimation { running: parent.visible; onTriggered: pl.cine.fxTime += frameTime }
        }
        Column {
            anchors { left: parent.left; leftMargin: parent.width * 0.1; verticalCenter: parent.verticalCenter }
            spacing: 12
            Text {
                text: "CH " + pl.cine.plat.ch + "  ·  " + pl.cine.plat.name
                font.family: pl.cine.mono; font.pixelSize: 20
                color: "white"
            }
            EvaText {
                text: (pl.cine.play?.item.name ?? "").toUpperCase()
                size: 110
                maxWidth: pl.width * 0.8
                color: "white"
            }
            Text {
                visible: (pl.cine.play?.epName ?? "") !== ""
                text: pl.cine.play?.epName ?? ""
                font.family: pl.cine.sans; font.pixelSize: 24
                color: "white"
            }
            Item { width: 1; height: 24 }
            Text {
                text: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[Math.floor(pl.cine.fxTime * 12) % 10] + "  " + pl.cine.playMsg
                font.family: pl.cine.mono; font.pixelSize: 22
                color: "white"
            }
            Text {
                text: "PARES " + (pl.cine.playStats.peers ?? 0) + "   ·   " + (pl.cine.playStats.speed ?? 0) + " MB/s"
                font.family: pl.cine.mono; font.pixelSize: 17
                color: Qt.rgba(1, 1, 1, 0.6)
            }
            Text {
                text: (pl.cine.playLang?.label ?? "") + (pl.cine.playSubs ? "  ·  subtítulos en español" : "  ·  sin subtítulos")
                font.family: pl.cine.sans; font.pixelSize: 17
                color: Qt.rgba(1, 1, 1, 0.6)
            }
            Item { width: 1; height: 20 }
            Text {
                text: "B CANCELAR"
                font.family: pl.cine.mono; font.pixelSize: 14
                color: Qt.rgba(1, 1, 1, 0.4)
            }
        }
    }

    // ── En la tele: la PC muestra qué se está viendo y hace de control ────
    Rectangle {
        anchors.fill: parent
        visible: pl.cine.playStep === "on" && pl.cine.casting
        color: "black"
        Image {
            anchors.fill: parent
            source: pl.cine.play?.item.background ?? pl.cine.play?.item.poster ?? ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            opacity: 0.35
        }
        Rectangle { anchors.fill: parent; color: Qt.rgba(0, 0, 0, 0.35) }
        // ondas de transmisión
        Item {
            id: waves
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: -150 }
            width: 1; height: 1
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    readonly property real k: ((pl.cine.fxTime * 0.5 + index / 3) % 1)
                    anchors.centerIn: parent
                    width: 90 + k * 260; height: width; radius: width / 2
                    color: "transparent"
                    border.width: 3
                    border.color: pl.th.hi
                    opacity: (1 - k) * (pl.cine.pst.pause ? 0.25 : 0.8)
                }
            }
            Text {
                anchors.centerIn: parent
                text: "\u{f0118}"
                font.family: pl.cine.mono; font.pixelSize: 64
                color: pl.th.hi
            }
            FrameAnimation { running: parent.visible; onTriggered: pl.cine.fxTime += frameTime }
        }
        Column {
            anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: parent.verticalCenter; verticalCenterOffset: 60 }
            spacing: 14
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "TRANSMITIENDO A  ·  " + pl.cine.castName.toUpperCase()
                font.family: pl.cine.mono; font.pixelSize: 22; font.letterSpacing: 4
                color: pl.th.hi
            }
            EvaText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: (pl.cine.play?.item.name ?? "").toUpperCase()
                size: 96
                maxWidth: pl.width * 0.8
                color: "white"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: (pl.cine.play?.epName ?? "") !== ""
                text: pl.cine.play?.epName ?? ""
                font.family: pl.cine.sans; font.pixelSize: 24
                color: "white"
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: pl.cine.pst.buffering ? "CARGANDO EN LA TELE…" : pl.cine.pst.pause ? "EN PAUSA" : "EN LA TELE  ·  EL JOYSTICK ES EL CONTROL REMOTO"
                font.family: pl.cine.mono; font.pixelSize: 16
                color: Qt.rgba(1, 1, 1, 0.6)
            }
        }
    }

    // ── Viendo: controles encima de la película ────────────────────────────
    Item {
        id: osd
        anchors.fill: parent
        visible: pl.cine.playStep === "on"
        opacity: pl.cine.ctrlVisible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 260 } }

        // sombra arriba y abajo para que se lea sobre la imagen
        Rectangle {
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: 200
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.75) }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 380
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.88) }
            }
        }

        // arriba: en el aire + canal, y la hora
        Row {
            anchors { left: parent.left; top: parent.top; leftMargin: 90; topMargin: 50 }
            spacing: 14
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 12; height: 12; radius: 6
                color: pl.th.warn
            }
            Text {
                text: "EN EL AIRE   ·   CH " + pl.cine.plat.ch + "  " + pl.cine.plat.name
                font.family: pl.cine.mono; font.pixelSize: 16
                color: "white"
            }
        }
        Text {
            anchors { right: parent.right; top: parent.top; rightMargin: 90; topMargin: 44 }
            text: Qt.formatDateTime(osdClock.date, "hh:mm")
            SystemClock { id: osdClock; precision: SystemClock.Minutes }
            font.family: pl.cine.mono; font.pixelSize: 26
            color: "white"
        }

        // abajo: título, barra de tiempo y botones
        Column {
            id: bottom
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 90; rightMargin: 90; bottomMargin: 50 }
            spacing: 18
            Row {
                spacing: 20
                EvaText {
                    text: (pl.cine.play?.item.name ?? "").toUpperCase()
                    size: 54
                    color: "white"
                }
                Text {
                    anchors.bottom: parent.bottom; anchors.bottomMargin: 8
                    text: pl.cine.play?.epName ?? ""
                    font.family: pl.cine.sans; font.pixelSize: 20
                    color: Qt.rgba(1, 1, 1, 0.8)
                }
            }
            // barra
            Row {
                width: parent.width
                spacing: 22
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: pl.cine.fmtClock(pl.cine.pst.pos)
                    font.family: pl.cine.mono; font.pixelSize: 18
                    color: "white"
                }
                Item {
                    id: bar
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 260; height: 26
                    readonly property real frac: pl.cine.pst.dur > 0 ? Math.min(1, pl.cine.pst.pos / pl.cine.pst.dur) : 0
                    readonly property bool focused: pl.cine.ctrlFocus === 0 && pl.cine.trackMenu === ""
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                        height: bar.focused ? 8 : 5; radius: height / 2
                        color: Qt.rgba(1, 1, 1, 0.22)
                        Rectangle { height: parent.height; radius: parent.radius; width: parent.width * bar.frac; color: pl.th.hi }
                    }
                    Rectangle {
                        x: parent.width * bar.frac - width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        width: bar.focused ? 24 : 14; height: width; radius: width / 2
                        color: pl.th.hi
                        layer.enabled: bar.focused
                        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: pl.th.glow; shadowBlur: 1.0; blurMax: 24; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -10
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (m) => { if (pl.cine.pst.dur > 0) pl.cine.playerCmd("seekto " + (m.x - 10) / bar.width * pl.cine.pst.dur); }
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "-" + pl.cine.fmtClock(pl.cine.pst.dur - pl.cine.pst.pos)
                    font.family: pl.cine.mono; font.pixelSize: 18
                    color: Qt.rgba(1, 1, 1, 0.7)
                }
            }
            // botones
            Row {
                spacing: 16
                Repeater {
                    model: pl.cine.ctrlButtons()
                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool on: pl.cine.ctrlFocus === 1 && index === pl.cine.ctrlIndex
                        width: bt.implicitWidth + 44; height: 56; radius: 28
                        color: on ? pl.th.hi : Qt.rgba(1, 1, 1, 0.08)
                        border.color: on ? pl.th.hi : Qt.rgba(1, 1, 1, 0.25)
                        border.width: 2
                        Row {   // ícono aparte, con la fuente de íconos y ancho fijo
                            id: bt
                            anchors.centerIn: parent
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 22; horizontalAlignment: Text.AlignHCenter
                                text: parent.parent.modelData.glyph
                                font.family: pl.cine.mono; font.pixelSize: 21
                                color: parent.parent.on ? pl.th.bg : "white"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.parent.modelData.label
                                font.family: pl.cine.sans; font.pixelSize: 18; font.weight: Font.Bold
                                color: parent.parent.on ? pl.th.bg : "white"
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { pl.cine.ctrlFocus = 1; pl.cine.ctrlIndex = parent.index; pl.cine.ctrlAction(parent.modelData.id); }
                        }
                    }
                }
            }
        }

        // Lista de pistas (audio / subtítulos)
        Rectangle {
            visible: pl.cine.trackMenu === "audio" || pl.cine.trackMenu === "subs"
            anchors { right: parent.right; bottom: bottom.top; rightMargin: 90; bottomMargin: 20 }
            width: 520; height: trackCol.implicitHeight + 40; radius: 14
            color: Qt.rgba(0, 0, 0, 0.9)
            border.color: pl.th.line; border.width: 2
            Column {
                id: trackCol
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 20 }
                spacing: 6
                Text {
                    text: pl.cine.trackMenu === "audio" ? "AUDIO" : "SUBTÍTULOS"
                    font.family: pl.cine.mono; font.pixelSize: 15; font.letterSpacing: 3
                    color: pl.th.dim
                }
                Repeater {
                    model: pl.cine.trackList()
                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool on: index === pl.cine.trackIndex
                        width: trackCol.width; height: 48; radius: 8
                        color: on ? pl.th.hi : "transparent"
                        Text {
                            anchors { left: parent.left; leftMargin: 16; right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                            elide: Text.ElideRight
                            text: (parent.modelData.on ? "●  " : "     ") + parent.modelData.label
                            font.family: pl.cine.sans; font.pixelSize: 19
                            color: parent.on ? pl.th.bg : "white"
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { pl.cine.trackIndex = parent.index; pl.cine.button("a"); }
                        }
                    }
                }
            }
        }
    }

    // Sincronizar subtítulos a mano
    Rectangle {
        visible: pl.cine.playStep === "on" && pl.cine.trackMenu === "sync"
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 220 }
        width: 760; height: 230; radius: 16
        color: Qt.rgba(0, 0, 0, 0.9)
        border.color: pl.th.hi; border.width: 2
        Column {
            anchors.centerIn: parent
            spacing: 12
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SINCRONIZAR SUBTÍTULOS"
                font.family: pl.cine.mono; font.pixelSize: 16; font.letterSpacing: 3
                color: pl.th.dim
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 36
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "◀ ANTES"
                    font.family: pl.cine.mono; font.pixelSize: 20
                    color: "white"
                    MouseArea { anchors.fill: parent; anchors.margins: -10; cursorShape: Qt.PointingHandCursor; onClicked: pl.cine.nudgeSubs(-0.1) }
                }
                Text {
                    text: pl.cine.fmtDelay(pl.cine.pst.subDelay)
                    font.family: pl.cine.mono; font.pixelSize: 56
                    color: pl.th.hi
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "DESPUÉS ▶"
                    font.family: pl.cine.mono; font.pixelSize: 20
                    color: "white"
                    MouseArea { anchors.fill: parent; anchors.margins: -10; cursorShape: Qt.PointingHandCursor; onClicked: pl.cine.nudgeSubs(0.1) }
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "◀ ▶ 0,1 s    ▲ ▼ 0,5 s    X AUTOMÁTICO    A LISTO"
                font.family: pl.cine.mono; font.pixelSize: 14
                color: pl.th.line
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Si el texto aparece antes que la voz: DESPUÉS. Si aparece tarde: ANTES."
                font.family: pl.cine.sans; font.pixelSize: 15
                color: Qt.rgba(1, 1, 1, 0.6)
            }
        }
    }

    // Volumen (y refuerzo en la tele): panel con el botón VOLUMEN, pastilla con la ruedita
    Rectangle {
        id: volBox
        readonly property bool panel: pl.cine.trackMenu === "vol"
        readonly property int  lv: pl.cine.pst.volume ?? 0
        readonly property int  mx: pl.cine.volMax()
        readonly property bool boosting: pl.cine.casting && lv > 100
        readonly property color warm: "#ff9a3c"
        visible: pl.cine.playStep === "on" && (panel || pl.cine.volFlash) && pl.cine.trackMenu !== "sync"
        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: panel ? 220 : 120 }
        width: 760; height: panel ? 250 : 120; radius: 16
        color: Qt.rgba(0, 0, 0, 0.9)
        border.color: boosting ? warm : pl.th.hi; border.width: 2
        Column {
            anchors.centerIn: parent
            spacing: 12
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: volBox.panel
                text: "VOLUMEN  ·  " + (pl.cine.casting ? pl.cine.castName.trim().toUpperCase() : "PC")
                font.family: pl.cine.mono; font.pixelSize: 16; font.letterSpacing: 3
                color: pl.th.dim
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 24
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: volBox.lv === 0 ? "\u{f0581}" : volBox.lv < 50 ? "\u{f057f}" : "\u{f057e}"
                    font.family: pl.cine.mono; font.pixelSize: 34
                    color: volBox.boosting ? volBox.warm : pl.th.hi
                }
                // barra: hasta la marca del 100 % es la tele; después, el refuerzo
                Item {
                    id: vbar
                    anchors.verticalCenter: parent.verticalCenter
                    width: 480; height: 34
                    readonly property real mark: 100 / volBox.mx
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: 12; radius: 6; color: Qt.rgba(1, 1, 1, 0.15) }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width * Math.min(volBox.lv, 100) / volBox.mx; height: 12; radius: 6
                        color: pl.th.hi
                    }
                    Rectangle {
                        visible: volBox.lv > 100
                        anchors.verticalCenter: parent.verticalCenter
                        x: parent.width * vbar.mark - 6
                        width: parent.width * (volBox.lv - 100) / volBox.mx + 6; height: 12; radius: 6
                        color: pl.cine.casting ? volBox.warm : pl.th.hi
                    }
                    Rectangle {
                        visible: volBox.mx > 100
                        x: parent.width * vbar.mark - 1; width: 2; height: parent.height
                        color: "white"; opacity: 0.7
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (m) => pl.cine.playerCmd("volset " + Math.round(Math.max(0, Math.min(1, m.x / width)) * volBox.mx / 5) * 5)
                    }
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 130
                    text: volBox.lv + "%"
                    font.family: pl.cine.mono; font.pixelSize: 44
                    color: volBox.boosting ? volBox.warm : pl.th.hi
                }
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: volBox.panel || volBox.boosting
                text: volBox.boosting ? "REFUERZO ×" + (volBox.lv / 100).toFixed(1).replace(".", ",") + "  ·  LA TELE RECARGA UNOS SEGUNDOS AL CAMBIARLO"
                    : pl.cine.casting && volBox.mx > 100 ? "PASANDO EL 100 % SE ACTIVA EL REFUERZO" : ""
                font.family: pl.cine.sans; font.pixelSize: 15
                color: Qt.rgba(1, 1, 1, 0.6)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                visible: volBox.panel
                text: "◀ ▶ 5 %    ▲ ▼ 25 %    A LISTO"
                font.family: pl.cine.mono; font.pixelSize: 14
                color: pl.th.line
            }
        }
    }

    // Aviso de los subtítulos (sincronizados solos, ajuste a mano…)
    Rectangle {
        visible: pl.cine.playStep === "on" && pl.cine.syncNote !== ""
        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 110 }
        width: syncTxt.implicitWidth + 50; height: 48; radius: 24
        color: Qt.rgba(0, 0, 0, 0.82)
        border.color: pl.th.line; border.width: 1
        Text {
            id: syncTxt
            anchors.centerIn: parent
            text: pl.cine.syncNote
            font.family: pl.cine.mono; font.pixelSize: 17
            color: "white"
        }
    }

    // Cargando en medio de la película (señal débil): siempre visible
    Row {
        visible: pl.cine.playStep === "on" && pl.cine.pst.buffering && !pl.cine.casting
        anchors.centerIn: parent
        spacing: 14
        Text {
            text: "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[Math.floor(Date.now() / 80) % 10]
            font.family: pl.cine.mono; font.pixelSize: 30
            color: "white"
            Timer { interval: 80; repeat: true; running: parent.visible; onTriggered: parent.text = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"[Math.floor(Date.now() / 80) % 10] }
        }
        Text {
            text: "SEÑAL DÉBIL · CARGANDO " + Math.round(pl.cine.pst.cache ?? 0) + "%"
            font.family: pl.cine.mono; font.pixelSize: 24
            color: "white"
            style: Text.Outline; styleColor: "black"
        }
    }

    // Pausa: cartel grande, como en una tele vieja
    Text {
        visible: pl.cine.playStep === "on" && pl.cine.pst.pause && !pl.cine.pst.buffering
        anchors { right: parent.right; top: parent.top; rightMargin: 90; topMargin: 110 }
        text: "❚❚ PAUSA"
        font.family: pl.cine.mono; font.pixelSize: 48
        color: "white"
        style: Text.Outline; styleColor: "black"
    }

    // Mouse: sin flecha cuando los controles no están
    MouseArea {
        anchors.fill: parent
        visible: pl.cine.playStep === "on"
        z: -1
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: pl.cine.ctrlVisible ? Qt.ArrowCursor : Qt.BlankCursor
        onPositionChanged: pl.cine.showCtrl()
        onClicked: (m) => {
            if (m.button === Qt.RightButton) { pl.cine.button("b"); return; }
            pl.cine.playerCmd("pause"); pl.cine.showCtrl();
        }
        onWheel: (w) => pl.cine.playerCmd("volume " + (w.angleDelta.y > 0 ? 5 : -5))
    }

    // ── Siguiente episodio (cuenta regresiva) ──────────────────────────────
    Rectangle {
        visible: pl.cine.nextEp !== null
        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 90; bottomMargin: 90 }
        width: 560; height: 170; radius: 16
        color: Qt.rgba(0, 0, 0, 0.92)
        border.color: pl.th.hi; border.width: 2
        Column {
            anchors { fill: parent; margins: 24 }
            spacing: 8
            Text {
                text: "SIGUIENTE EPISODIO EN " + pl.cine.nextCount
                font.family: pl.cine.mono; font.pixelSize: 16; font.letterSpacing: 2
                color: pl.th.dim
            }
            Text {
                width: parent.width; elide: Text.ElideRight
                text: pl.cine.nextEp ? "T" + pl.cine.nextEp.video.season + " · E" + pl.cine.nextEp.video.episode + "  " + (pl.cine.nextEp.video.name || "") : ""
                font.family: pl.cine.sans; font.pixelSize: 24; font.weight: Font.Bold
                color: pl.th.hi
            }
            Text {
                text: "A VER AHORA   B CANCELAR"
                font.family: pl.cine.mono; font.pixelSize: 14
                color: pl.th.line
            }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: pl.cine.playNext() }
    }
}
