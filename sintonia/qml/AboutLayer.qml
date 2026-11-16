// Pestaña SOBRE LA PELÍCULA del modo cine: se abre desde la ficha (ABRIR) y es
// el ÚNICO camino para reproducir. Flyer de fondo, sinopsis en español, equipo,
// reparto, tráiler y "PARECIDAS EN ESTILO" (fotografía / forma de contar, no trama).
// Datos: ~/.config/rice-cine/about.py about|similar (con caché).
import QtQuick

Item {
    id: ab
    required property var cine
    readonly property var th: cine.theme
    readonly property var it: cine.aboutInfo
    readonly property var d: cine.aboutData
    visible: cine.aboutOpen && !cine.playFull && !cine.personView

    // tapa todo lo de atrás (filas, ficha, clics)
    Rectangle { anchors.fill: parent; color: "black" }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => { if (m.button === Qt.RightButton) ab.cine.mouseBack(); }
        onWheel: (w) => {}
    }

    // ── Flyer de fondo ──────────────────────────────────────────────────
    Image {
        id: bg
        anchors.fill: parent
        source: ab.d?.background || ab.it?.background || ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 1920
        opacity: status === Image.Ready ? 0.75 : 0
        Behavior on opacity { NumberAnimation { duration: 600 } }
        NumberAnimation on scale { from: 1.0; to: 1.06; duration: 60000; loops: Animation.Infinite; easing.type: Easing.InOutSine; running: ab.visible }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0;  color: Qt.rgba(0, 0, 0, 0.95) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.75) }
            GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, 0.35) }
        }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(0, 0, 0, 0.5) }
            GradientStop { position: 0.2;  color: "transparent" }
            GradientStop { position: 0.58; color: Qt.rgba(0, 0, 0, 0.55) }
            GradientStop { position: 0.72; color: Qt.rgba(0, 0, 0, 0.92) }
            GradientStop { position: 1.0;  color: "black" }
        }
    }

    // ── Columna principal ──────────────────────────────────────────────
    Column {
        id: main
        anchors { left: parent.left; leftMargin: 110; top: parent.top; topMargin: 96 }
        width: Math.min(980, parent.width * 0.52)
        spacing: 14

        Text {
            text: ab.cine.aboutStack.length ? "◀ B  VOLVER A " + (ab.cine.aboutStack[ab.cine.aboutStack.length - 1].name ?? "").toUpperCase() : "SOBRE " + (ab.it?.type === "series" ? "LA SERIE" : "LA PELÍCULA")
            font.family: ab.cine.mono; font.pixelSize: 14; font.letterSpacing: 3
            color: ab.th.dim
            elide: Text.ElideRight; width: parent.width
        }
        Image {
            id: logo
            source: ab.it?.logo ?? ""
            visible: status === Image.Ready
            height: 120
            width: Math.min(620, implicitWidth * height / Math.max(1, implicitHeight))
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            sourceSize.height: 240
            asynchronous: true
        }
        EvaText {
            visible: !logo.visible
            text: (ab.d?.nameEs || ab.it?.name || "").toUpperCase()
            size: 78
            maxWidth: main.width
            color: ab.th.hi
        }
        Text {   // título en español si es distinto
            visible: !!ab.d?.nameEs && ab.d.nameEs !== ab.it?.name
            text: ab.d?.nameEs ?? ""
            font.family: ab.cine.sans; font.pixelSize: 20; font.italic: true
            color: ab.th.fg
        }
        // año · duración · géneros · puntajes
        Row {
            spacing: 18
            Repeater {
                model: ab.facts()
                Text {
                    required property var modelData
                    text: modelData
                    font.family: ab.cine.sans; font.pixelSize: 20; font.weight: Font.Medium
                    color: ab.th.fg
                }
            }
        }
        Text {
            width: parent.width
            text: ab.d ? (ab.d.description || ab.it?.description || "Sin sinopsis.") : (ab.it?.description || "▒▒ SINTONIZANDO…")
            wrapMode: Text.WordWrap
            maximumLineCount: 6
            elide: Text.ElideRight
            font.family: ab.cine.sans; font.pixelSize: 21
            color: Qt.rgba(1, 1, 1, 0.88)
            lineHeight: 1.22
        }
        // progreso (si la venías viendo)
        Row {
            visible: (ab.it?.offset ?? 0) > 0
            spacing: 16
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 300; height: 6; radius: 3; color: Qt.rgba(1, 1, 1, 0.18)
                Rectangle { height: parent.height; radius: 3; width: parent.width * Math.max(0.02, ab.it?.progress ?? 0); color: ab.th.hi }
            }
            Text {
                text: (ab.it?.season > 0 ? "T" + ab.it.season + " · E" + ab.it.episode + "    " : "")
                      + "quedan " + ab.cine.fmtTime(Math.max(0, (ab.it?.duration ?? 0) - (ab.it?.offset ?? 0)))
                font.family: ab.cine.sans; font.pixelSize: 17
                color: ab.th.fg
            }
        }
        Item { width: 1; height: 6 }
        Text {
            visible: String(ab.it?.id ?? "").startsWith("tmdb:")
            text: "No hay dónde verla."
            font.family: ab.cine.sans; font.pixelSize: 20
            color: ab.th.warn
        }
        // botones: reproducir / continuar / tele / episodios / tráiler
        Row {
            spacing: 18
            Repeater {
                model: ab.cine.aboutActions(ab.it)
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool on: ab.cine.aboutFocus === "act" && index === ab.cine.aboutIndex
                    width: Math.max(190, act.implicitWidth + 50); height: 70; radius: 35
                    color: on ? ab.th.hi : Qt.rgba(1, 1, 1, 0.07)
                    border.color: on ? ab.th.hi : ab.th.line
                    border.width: 2
                    scale: on ? 1.05 : 1
                    Behavior on scale { NumberAnimation { duration: 140 } }
                    Column {
                        id: act
                        anchors.centerIn: parent
                        spacing: 2
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 26; horizontalAlignment: Text.AlignHCenter
                                text: modelData.glyph
                                font.family: ab.cine.mono; font.pixelSize: 24
                                color: on ? ab.th.bg : ab.th.fg
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.family: ab.cine.sans; font.pixelSize: 20; font.weight: Font.Bold
                                color: on ? ab.th.bg : ab.th.fg
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: !!modelData.note
                            text: modelData.note ?? ""
                            font.family: ab.cine.sans; font.pixelSize: 13
                            color: on ? ab.th.deep : ab.th.dim
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { ab.cine.aboutFocus = "act"; ab.cine.aboutIndex = index; ab.cine.aboutButton("a"); }
                    }
                }
            }
        }
    }

    // ── Equipo y reparto (derecha) ─────────────────────────────────────
    Column {
        anchors { right: parent.right; rightMargin: 110; top: parent.top; topMargin: 120 }
        width: Math.min(640, parent.width * 0.32)
        spacing: 12
        visible: !!ab.d
        // equipo: cada nombre se elige (joystick/clic) y abre su perfil
        Repeater {
            model: ab.crewLines()
            Row {
                required property var modelData
                spacing: 16
                Text {
                    width: 150
                    text: modelData.label
                    font.family: ab.cine.mono; font.pixelSize: 14; font.letterSpacing: 2
                    color: ab.th.dim
                    topPadding: 7
                }
                Flow {
                    width: 470
                    spacing: 0
                    Repeater {
                        model: modelData.people
                        Rectangle {
                            required property var modelData
                            readonly property bool on: ab.cine.aboutFocus === "ppl" && ab.cine.aboutPplIndex === modelData.idx
                            width: nm.implicitWidth + (modelData.last ? 20 : 14); height: 34; radius: 17
                            color: on ? ab.th.hi : (hov.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent")
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                id: nm
                                x: 10; anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name + (modelData.last ? "" : ",")
                                font.family: ab.cine.sans; font.pixelSize: 19; font.weight: Font.DemiBold
                                color: parent.on ? ab.th.bg : "white"
                            }
                            HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { ab.cine.aboutFocus = "ppl"; ab.cine.aboutPplIndex = modelData.idx; ab.cine.aboutButton("a"); }
                            }
                        }
                    }
                }
            }
        }
        Repeater {
            model: ab.extraRows()
            Row {
                required property var modelData
                spacing: 16
                Text {
                    width: 150
                    text: modelData[0]
                    font.family: ab.cine.mono; font.pixelSize: 14; font.letterSpacing: 2
                    color: ab.th.dim
                    topPadding: 3
                }
                Text {
                    width: 470
                    leftPadding: 10
                    text: modelData[1]
                    wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                    font.family: ab.cine.sans; font.pixelSize: 19; font.weight: Font.DemiBold
                    color: "white"
                }
            }
        }
        Item { width: 1; height: 8 }
        Text {
            visible: ab.castPeople().length > 0
            text: "REPARTO"
            font.family: ab.cine.mono; font.pixelSize: 14; font.letterSpacing: 2
            color: ab.th.dim
        }
        Grid {
            columns: 3
            columnSpacing: 8; rowSpacing: 6
            Repeater {
                model: ab.castPeople()
                Rectangle {
                    id: cp
                    required property var modelData
                    readonly property bool on: ab.cine.aboutFocus === "ppl" && ab.cine.aboutPplIndex === modelData.idx
                    width: 206; height: 66; radius: 33
                    color: on ? ab.th.hi : (chov.hovered ? Qt.rgba(1, 1, 1, 0.1) : "transparent")
                    Behavior on color { ColorAnimation { duration: 120 } }
                    HoverHandler { id: chov; cursorShape: Qt.PointingHandCursor }
                    Row {
                        anchors { left: parent.left; leftMargin: 6; verticalCenter: parent.verticalCenter }
                        spacing: 10
                        Rectangle {
                            width: 54; height: 54; radius: 27
                            color: Qt.rgba(1, 1, 1, 0.1)
                            clip: true
                            Image {
                                anchors.fill: parent
                                source: cp.modelData.photo
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 108
                                visible: status === Image.Ready
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !cp.modelData.photo
                                text: (cp.modelData.name || "?").charAt(0)
                                font.family: ab.cine.sans; font.pixelSize: 22; font.weight: Font.Bold
                                color: ab.th.dim
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 128
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: cp.modelData.name
                                font.family: ab.cine.sans; font.pixelSize: 15; font.weight: Font.Bold
                                color: cp.on ? ab.th.bg : "white"
                            }
                            Text {
                                width: parent.width; elide: Text.ElideRight
                                text: cp.modelData.character
                                font.family: ab.cine.sans; font.pixelSize: 13
                                color: cp.on ? ab.th.deep : ab.th.dim
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { ab.cine.aboutFocus = "ppl"; ab.cine.aboutPplIndex = cp.modelData.idx; ab.cine.aboutButton("a"); }
                    }
                }
            }
        }
    }

    // ── Parecidas en estilo ────────────────────────────────────────────
    Item {
        id: simBox
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 70 }
        height: 330
        Text {
            id: simTitle
            x: 110
            text: "PARECIDAS"
            font.family: ab.cine.mono; font.pixelSize: 15; font.letterSpacing: 2
            color: ab.cine.aboutFocus === "sim" ? ab.th.hi : ab.th.dim
        }
        Text {
            x: 110; y: 60
            visible: ab.cine.aboutSim === null || !(ab.cine.aboutSim?.length)
            text: ab.cine.aboutSim === null ? "▒▒▒  BUSCANDO PARECIDAS…" : "No encontré recomendaciones."
            font.family: ab.cine.mono; font.pixelSize: 17
            color: ab.th.dim
        }
        ListView {
            id: simList
            anchors { left: parent.left; right: parent.right; top: simTitle.bottom; topMargin: 16; bottom: parent.bottom }
            leftMargin: 110; rightMargin: 110
            orientation: ListView.Horizontal
            spacing: 26
            clip: false
            model: ab.cine.aboutSim ?? []
            currentIndex: ab.cine.aboutSimIndex
            highlightMoveDuration: 200
            preferredHighlightBegin: 110; preferredHighlightEnd: width - 300
            highlightRangeMode: ListView.ApplyRange
            delegate: Item {
                id: sc
                required property var modelData
                required property int index
                readonly property bool on: ab.cine.aboutFocus === "sim" && index === ab.cine.aboutSimIndex
                readonly property bool hov: ab.cine.mouseMode && simMa.containsMouse
                width: 160; height: simList.height
                Rectangle {
                    id: post
                    width: 160; height: 240
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.color: sc.on || sc.hov ? ab.th.hi : "transparent"; border.width: 3
                    scale: sc.on ? 1.06 : 1
                    transformOrigin: Item.Bottom
                    Behavior on scale { NumberAnimation { duration: 140 } }
                    Image {
                        anchors { fill: parent; margins: 3 }
                        source: sc.modelData.poster
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 340
                    }
                    Text {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
                        visible: !sc.modelData.poster
                        text: sc.modelData.name
                        wrapMode: Text.WordWrap
                        font.family: ab.cine.sans; font.pixelSize: 16; font.weight: Font.Bold
                        color: "white"
                    }
                }
                Text {
                    anchors { top: post.bottom; topMargin: 10 }
                    width: 160
                    text: sc.modelData.name + (sc.modelData.year ? "  " + sc.modelData.year : "")
                    elide: Text.ElideRight
                    font.family: ab.cine.sans; font.pixelSize: 15; font.weight: Font.Bold
                    color: sc.on ? ab.th.hi : "white"
                }
                MouseArea {
                    id: simMa
                    anchors.fill: post
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: { ab.cine.aboutFocus = "sim"; ab.cine.aboutSimIndex = sc.index; ab.cine.aboutButton("a"); }
                }
            }
        }
    }

    // ── Textos ─────────────────────────────────────────────────────────
    readonly property var genreEs: ({ "Action": "Acción", "Adventure": "Aventura", "Animation": "Animación", "Biography": "Biografía",
        "Comedy": "Comedia", "Crime": "Crimen", "Documentary": "Documental", "Drama": "Drama", "Family": "Familia",
        "Fantasy": "Fantasía", "History": "Historia", "Horror": "Terror", "Music": "Música", "Musical": "Musical",
        "Mystery": "Misterio", "Romance": "Romance", "Sci-Fi": "Ciencia ficción", "Sport": "Deporte", "Thriller": "Suspenso",
        "War": "Bélica", "Western": "Western" })
    function facts() {
        if (!it) return [];
        const f = [];
        const date = d?.released ? d.released.split("-").reverse().join("/") : (it.year || "");
        if (date) f.push(date);
        const rt = d?.runtime || it.runtime;
        if (rt) f.push(String(rt).replace(" min", " min"));
        if (it.type === "series" && d?.seasons) f.push(d.seasons + (d.seasons === 1 ? " temporada" : " temporadas"));
        const g = d?.genresEs?.length ? d.genresEs : (d?.genres ?? it.genres ?? []).map(x => genreEs[x] ?? x);
        if (g.length) f.push(g.slice(0, 3).join(" · "));
        const imdb = d?.rating || it.rating;
        if (imdb) f.push("IMDb " + imdb);
        if (d?.lbRating) f.push("Letterboxd ★ " + Number(d.lbRating).toFixed(1));
        return f;
    }
    readonly property var roleLabel: ({ director: "DIRECCIÓN", creator: "CREACIÓN", writer: "GUION", cinematography: "FOTOGRAFÍA",
                                        editor: "MONTAJE", composer: "MÚSICA" })
    function crewLines() {
        const P = cine.aboutPeople, out = [];
        P.forEach((x, i) => {
            if (x.kind === "actor") return;
            let l = out.find(o => o.line === x.line);
            if (!l) { l = { line: x.line, label: roleLabel[x.kind] ?? x.kind.toUpperCase(), people: [] }; out.push(l); }
            l.people.push(Object.assign({}, x, { idx: i }));
        });
        out.forEach(l => l.people.forEach((x, k) => x.last = k === l.people.length - 1));
        return out;
    }
    function castPeople() {
        const cast = d?.castFull ?? [];
        return cine.aboutPeople.map((x, i) => Object.assign({}, x, { idx: i })).filter(x => x.kind === "actor")
            .map(x => Object.assign(x, { character: (cast.find(c => c.name === x.name)?.character) ?? "" }));
    }
    function extraRows() {
        if (!d) return [];
        const r = [];
        if (d.country) r.push(["PAÍS", d.country]);
        if (d.awards) r.push(["PREMIOS", d.awards]);
        return r;
    }
    function credits() {
        if (!d) return [];
        const r = [];
        const add = (k, v) => { if (v && v.length) r.push([k, v.slice(0, 3).join(", ")]); };
        add(it?.type === "series" ? "CREACIÓN" : "DIRECCIÓN", d.director);
        add("GUION", d.writer);
        add("FOTOGRAFÍA", d.dop);
        add("MONTAJE", d.editing);
        add("MÚSICA", d.music);
        if (d.country) r.push(["PAÍS", d.country]);
        if (d.awards) r.push(["PREMIOS", d.awards]);
        return r;
    }
}
