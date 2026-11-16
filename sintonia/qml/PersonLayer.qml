// Perfil de una PERSONA del modo cine (director, actor, fotógrafo…): se abre
// eligiendo un nombre en la pestaña de la película. Foto, quién es (Wikipedia
// en español / Wikidata) y su filmografía por rol, con pósters: elegir una
// película abre su pestaña (B vuelve acá, al mismo lugar).
// Datos: ~/.config/rice-cine/about.py person <nombre> <ruta de Letterboxd>.
import QtQuick

Item {
    id: pl
    required property var cine
    readonly property var th: cine.theme
    readonly property var it: cine.aboutItem
    readonly property var d: cine.personData
    readonly property var roles: cine.personRoles
    visible: cine.aboutOpen && !cine.playFull && cine.personView

    Rectangle { anchors.fill: parent; color: "black" }
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (m) => { if (m.button === Qt.RightButton) pl.cine.mouseBack(); }
        onWheel: (w) => {}
    }

    // ── Fondo: el flyer de la película elegida, muy apagado ───────────
    Image {
        id: bg
        anchors.fill: parent
        readonly property var cur: pl.roles[pl.cine.personRow]?.items?.[pl.cine.personCol]
        source: cur?.id ? "https://images.metahub.space/background/medium/" + cur.id + "/img" : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 1280
        opacity: status === Image.Ready ? 0.28 : 0
        Behavior on opacity { NumberAnimation { duration: 500 } }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0;  color: Qt.rgba(0, 0, 0, 0.55) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.8) }
            GradientStop { position: 1.0;  color: "black" }
        }
    }

    // ── Cabecera: foto + quién es ─────────────────────────────────────
    Text {
        id: back
        x: 110; y: 70
        text: pl.cine.aboutStack.length ? "◀ B  VOLVER A " + (pl.cine.aboutStack[pl.cine.aboutStack.length - 1].name ?? "").toUpperCase() : "PERFIL"
        font.family: pl.cine.mono; font.pixelSize: 14; font.letterSpacing: 3
        color: pl.th.dim
    }
    Rectangle {
        id: photo
        x: 110; y: 110
        width: 250; height: 330; radius: 10
        color: Qt.rgba(1, 1, 1, 0.06)
        border.color: pl.th.line; border.width: 2
        clip: true
        Image {
            id: ph
            anchors { fill: parent; margins: 2 }
            source: pl.d?.photo || pl.it?.photo || ""
            fillMode: Image.PreserveAspectCrop
            verticalAlignment: Image.AlignTop
            asynchronous: true
            sourceSize.width: 500
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 400 } }
        }
        Text {
            anchors.centerIn: parent
            visible: ph.status !== Image.Ready
            text: (pl.it?.name || "?").charAt(0)
            font.family: pl.cine.sans; font.pixelSize: 110; font.weight: Font.Bold
            color: pl.th.line
        }
    }
    Column {
        id: head
        anchors { left: photo.right; leftMargin: 48; top: photo.top; right: parent.right; rightMargin: 110 }
        spacing: 12
        EvaText {
            text: (pl.d?.name || pl.it?.name || "").toUpperCase()
            size: 64
            maxWidth: head.width
            color: pl.th.hi
        }
        Text {
            visible: !!pl.d?.description
            text: pl.d?.description ?? ""
            font.family: pl.cine.sans; font.pixelSize: 20; font.italic: true
            color: pl.th.fg
        }
        Repeater {
            model: pl.d?.facts ?? []
            Row {
                required property var modelData
                spacing: 16
                Text {
                    width: 140
                    text: modelData[0]
                    font.family: pl.cine.mono; font.pixelSize: 14; font.letterSpacing: 2
                    color: pl.th.dim
                    topPadding: 3
                }
                Text {
                    text: modelData[1]
                    font.family: pl.cine.sans; font.pixelSize: 19; font.weight: Font.DemiBold
                    color: "white"
                }
            }
        }
        Item { width: 1; height: 2 }
        Text {
            width: head.width
            text: !pl.d ? "▒▒▒  BUSCANDO…"
                 : (pl.d.bio || (pl.d.error ? "No encontré datos de esta persona." : "No hay biografía en español."))
            wrapMode: Text.WordWrap
            maximumLineCount: pl.d ? 7 : 1
            elide: Text.ElideRight
            font.family: pl.d ? pl.cine.sans : pl.cine.mono
            font.pixelSize: pl.d ? 19 : 17
            color: pl.d ? Qt.rgba(1, 1, 1, 0.86) : pl.th.dim
            lineHeight: 1.2
        }
    }

    // ── Filmografía: una fila por rol ─────────────────────────────────
    ListView {
        id: rowsView
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 40 }
        height: 2 * 282
        clip: true
        interactive: false
        model: pl.roles
        currentIndex: pl.cine.personRow
        highlightMoveDuration: 220
        preferredHighlightBegin: 0; preferredHighlightEnd: 282
        highlightRangeMode: ListView.StrictlyEnforceRange
        delegate: Item {
            id: rowD
            required property var modelData
            required property int index
            readonly property bool rowOn: index === pl.cine.personRow
            width: rowsView.width; height: 282
            opacity: rowOn ? 1 : 0.55
            Behavior on opacity { NumberAnimation { duration: 160 } }
            Text {
                id: rl
                x: 110
                text: rowD.modelData.label.toUpperCase()
                font.family: pl.cine.mono; font.pixelSize: 15; font.letterSpacing: 2
                color: rowD.rowOn ? pl.th.hi : pl.th.dim
            }
            ListView {
                id: films
                anchors { left: parent.left; right: parent.right; top: rl.bottom; topMargin: 14; bottom: parent.bottom }
                leftMargin: 110; rightMargin: 110
                orientation: ListView.Horizontal
                spacing: 20
                interactive: false
                model: rowD.modelData.items
                currentIndex: pl.cine.personCols[rowD.index] ?? 0
                highlightMoveDuration: 200
                preferredHighlightBegin: 110; preferredHighlightEnd: width - 260
                highlightRangeMode: ListView.ApplyRange
                delegate: Item {
                    id: fc
                    required property var modelData
                    required property int index
                    readonly property bool on: rowD.rowOn && index === (pl.cine.personCols[rowD.index] ?? 0)
                    readonly property bool hov: pl.cine.mouseMode && fMa.containsMouse
                    width: 124; height: films.height
                    Rectangle {
                        id: post
                        width: 124; height: 186
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.color: fc.on || fc.hov ? pl.th.hi : "transparent"; border.width: 3
                        scale: fc.on ? 1.07 : 1
                        transformOrigin: Item.Bottom
                        Behavior on scale { NumberAnimation { duration: 140 } }
                        Image {
                            id: pimg
                            anchors { fill: parent; margins: 3 }
                            source: fc.modelData.poster ?? ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 260
                        }
                        Text {     // sin póster: el título sobre la tarjeta
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
                            visible: pimg.status !== Image.Ready
                            text: fc.modelData.name
                            wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight
                            font.family: pl.cine.sans; font.pixelSize: 15; font.weight: Font.Bold
                            color: "white"
                        }
                    }
                    Text {
                        anchors { top: post.bottom; topMargin: 9 }
                        width: 124
                        text: fc.modelData.name
                        elide: Text.ElideRight
                        font.family: pl.cine.sans; font.pixelSize: 14; font.weight: Font.Bold
                        color: fc.on ? pl.th.hi : "white"
                    }
                    Text {
                        anchors { top: post.bottom; topMargin: 28 }
                        text: fc.modelData.year || ""
                        font.family: pl.cine.mono; font.pixelSize: 12
                        color: pl.th.dim
                    }
                    MouseArea {
                        id: fMa
                        anchors.fill: post
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            pl.cine.personRow = rowD.index;
                            pl.cine.setPersonCol(fc.index);
                            pl.cine.aboutButton("a");
                        }
                    }
                }
            }
        }
    }
    // rueda del mouse: subir/bajar entre roles
    MouseArea {
        anchors.fill: rowsView
        acceptedButtons: Qt.NoButton
        onWheel: (w) => pl.cine.navigate(w.angleDelta.y > 0 ? "up" : "down")
    }
    Text {
        anchors { right: parent.right; rightMargin: 110; bottom: parent.bottom; bottomMargin: 14 }
        visible: !!pl.cine.personMsg
        text: pl.cine.personMsg
        font.family: pl.cine.mono; font.pixelSize: 13; font.letterSpacing: 2
        color: pl.cine.personMsg ? pl.th.hi : pl.th.dim
    }
}
