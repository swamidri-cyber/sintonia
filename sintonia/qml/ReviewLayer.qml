// Pantalla de reseña (etapa 5): al terminar una película, estrellas, me
// gustó, texto y spoilers → se publica en tu diario de Letterboxd con la fecha
// de hoy (siempre pide confirmación). El estado vive en shell.qml (cine).
import QtQuick

Item {
    id: rv
    required property var cine
    readonly property var th: cine.theme
    readonly property alias textEdit: edit
    visible: cine.review !== null

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.9)
        MouseArea { anchors.fill: parent }
    }

    Column {
        anchors.centerIn: parent
        width: 1000
        spacing: 22

        Text {
            text: "LETTERBOXD" + (rv.cine.rvUser ? "  ·  " + rv.cine.rvUser : "")
            font.family: rv.cine.mono; font.pixelSize: 16; font.letterSpacing: 4
            color: rv.th.dim
        }
        EvaText {
            text: "¿QUÉ TE PARECIÓ?"
            size: 84
            color: rv.th.hi
        }
        Text {
            text: (rv.cine.review?.name ?? "") + (rv.cine.review?.rewatch ? "   ·   la volviste a ver" : "")
            font.family: rv.cine.sans; font.pixelSize: 24; font.weight: Font.Medium
            color: rv.th.fg
        }

        // 0 · estrellas (de a media)
        Rectangle {
            width: parent.width; height: 92; radius: 14
            color: rv.cine.rvRow === 0 && !rv.cine.rvConfirm ? Qt.rgba(1, 1, 1, 0.07) : "transparent"
            border.color: rv.cine.rvRow === 0 && !rv.cine.rvConfirm ? rv.th.hi : "transparent"; border.width: 2
            Row {
                anchors { left: parent.left; leftMargin: 26; verticalCenter: parent.verticalCenter }
                spacing: 10
                Repeater {
                    model: 5
                    Text {
                        required property int index
                        readonly property int v: rv.cine.rvStars - index * 2      // 2 = llena, 1 = media
                        text: v >= 2 ? "\u{f04ce}" : v === 1 ? "\u{f04d0}" : "\u{f04d2}"
                        font.family: rv.cine.mono; font.pixelSize: 58
                        color: v > 0 ? rv.th.hi : rv.th.line
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            // mitad izquierda = media estrella
                            onClicked: (m) => { rv.cine.rvRow = 0; rv.cine.rvStars = index * 2 + (m.x < width / 2 ? 1 : 2); }
                        }
                    }
                }
            }
            Text {
                anchors { right: parent.right; rightMargin: 26; verticalCenter: parent.verticalCenter }
                text: rv.cine.rvStars === 0 ? "◀ ▶ ESTRELLAS" : (rv.cine.rvStars / 2).toString().replace(".", ",") + " / 5"
                font.family: rv.cine.mono; font.pixelSize: 20
                color: rv.th.dim
            }
        }

        // 1 · me gustó   ·   3 · spoilers
        Row {
            spacing: 18
            Repeater {
                model: [{ row: 1, on: rv.cine.rvLiked, glyph: rv.cine.rvLiked ? "\u{f02d1}" : "\u{f02d5}", label: "ME GUSTÓ" },
                        { row: 3, on: rv.cine.rvSpoilers, glyph: rv.cine.rvSpoilers ? "\u{f0132}" : "\u{f0131}", label: "TIENE SPOILERS" }]
                Rectangle {
                    required property var modelData
                    readonly property bool sel: rv.cine.rvRow === modelData.row && !rv.cine.rvConfirm
                    width: lk.implicitWidth + 50; height: 62; radius: 31
                    color: modelData.on ? rv.th.hi : Qt.rgba(1, 1, 1, 0.06)
                    border.color: sel ? rv.th.hi : rv.th.line; border.width: sel ? 3 : 1
                    Text {
                        id: lk
                        anchors.centerIn: parent
                        text: parent.modelData.glyph + "  " + parent.modelData.label
                        font.family: rv.cine.sans; font.pixelSize: 20; font.weight: Font.Bold
                        color: parent.modelData.on ? rv.th.bg : rv.th.fg
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { rv.cine.rvRow = parent.modelData.row; rv.cine.button("a"); }
                    }
                }
            }
        }

        // 2 · reseña
        Rectangle {
            width: parent.width; height: 190; radius: 14
            readonly property bool sel: rv.cine.rvRow === 2 && !rv.cine.rvConfirm
            color: Qt.rgba(1, 1, 1, 0.05)
            border.color: edit.activeFocus ? rv.th.hi : sel ? rv.th.fg : rv.th.line
            border.width: edit.activeFocus || sel ? 2 : 1
            Flickable {
                id: flick
                anchors { fill: parent; margins: 20 }
                contentHeight: edit.contentHeight
                clip: true
                TextEdit {
                    id: edit
                    width: flick.width
                    wrapMode: TextEdit.Wrap
                    font.family: rv.cine.sans; font.pixelSize: 21
                    color: "white"
                    selectionColor: rv.th.dim
                    onCursorRectangleChanged: if (cursorRectangle.y + cursorRectangle.height > flick.contentY + flick.height) flick.contentY = cursorRectangle.y + cursorRectangle.height - flick.height
                    // Esc o Ctrl+Enter: terminar de escribir (Enter solo = renglón nuevo)
                    Keys.onPressed: (e) => {
                        if (e.key === Qt.Key_Escape || ((e.key === Qt.Key_Return || e.key === Qt.Key_Enter) && (e.modifiers & Qt.ControlModifier))) {
                            rv.cine.endEditing(); e.accepted = true;
                        }
                    }
                }
            }
            Text {
                anchors { left: parent.left; top: parent.top; margins: 20 }
                visible: edit.text === "" && !edit.activeFocus
                text: "Escribí tu reseña (opcional)…   A para escribir · Esc para terminar"
                font.family: rv.cine.sans; font.pixelSize: 20
                color: rv.th.dim
            }
            MouseArea {
                anchors.fill: parent
                visible: !edit.activeFocus
                cursorShape: Qt.IBeamCursor
                onClicked: { rv.cine.rvRow = 2; rv.cine.rvEditing = true; edit.forceActiveFocus(); }
            }
        }

        // 4 · botones
        Row {
            spacing: 18
            Repeater {
                model: ["\u{f0552}  PUBLICAR EN LETTERBOXD", "AHORA NO"]
                Rectangle {
                    required property string modelData
                    required property int index
                    readonly property bool on: rv.cine.rvRow === 4 && rv.cine.rvButton === index && !rv.cine.rvConfirm
                    width: bl.implicitWidth + 56; height: 66; radius: 33
                    color: on ? rv.th.hi : Qt.rgba(1, 1, 1, 0.06)
                    border.color: on ? rv.th.hi : rv.th.line; border.width: 2
                    Text {
                        id: bl
                        anchors.centerIn: parent
                        text: parent.modelData
                        font.family: rv.cine.sans; font.pixelSize: 20; font.weight: Font.Bold
                        color: parent.on ? rv.th.bg : rv.th.fg
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { rv.cine.rvRow = 4; rv.cine.rvButton = parent.index; rv.cine.button("a"); }
                    }
                }
            }
        }

        Text {
            width: parent.width
            wrapMode: Text.WordWrap
            visible: text !== ""
            text: rv.cine.rvState === "checking" ? "▒▒▒  CONECTANDO CON LETTERBOXD…"
                : rv.cine.rvState === "posting" ? "▒▒▒  PUBLICANDO…"
                : rv.cine.rvMsg
            font.family: rv.cine.rvState === "checking" || rv.cine.rvState === "posting" ? rv.cine.mono : rv.cine.sans
            font.pixelSize: 19
            color: rv.cine.rvState === "error" ? rv.th.warn : rv.th.fg
        }
        Text {
            text: "▲ ▼ MOVER   ◀ ▶ ESTRELLAS   A ELEGIR   B AHORA NO"
            font.family: rv.cine.mono; font.pixelSize: 14
            color: rv.th.line
        }
    }

    // ¿Publicar? (queda público en tu perfil)
    Rectangle {
        anchors.fill: parent
        visible: rv.cine.rvConfirm
        color: Qt.rgba(0, 0, 0, 0.7)
        Rectangle {
            anchors.centerIn: parent
            width: 820; height: 290; radius: 18
            color: rv.th.deep
            border.color: rv.th.warn; border.width: 2
            Column {
                anchors { fill: parent; margins: 34 }
                spacing: 16
                Text {
                    text: "¿PUBLICAR EN LETTERBOXD?"
                    font.family: rv.cine.mono; font.pixelSize: 22
                    color: rv.th.warn
                }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "Va a quedar en el diario de " + rv.cine.rvUser + " con fecha de hoy, a la vista de todos: "
                          + (rv.cine.rvStars ? (rv.cine.rvStars / 2).toString().replace(".", ",") + " estrellas" : "sin estrellas")
                          + (rv.cine.rvLiked ? ", me gustó" : "") + (edit.text.trim() ? ", con reseña" : "") + "."
                    font.family: rv.cine.sans; font.pixelSize: 20
                    color: rv.th.fg
                }
                Row {
                    spacing: 18
                    Repeater {
                        model: ["PUBLICAR", "CANCELAR"]
                        Rectangle {
                            required property string modelData
                            required property int index
                            readonly property bool on: rv.cine.rvButton === index
                            width: cb.implicitWidth + 50; height: 58; radius: 29
                            color: on ? (index === 0 ? rv.th.warn : rv.th.hi) : "transparent"
                            border.color: index === 0 ? rv.th.warn : rv.th.line; border.width: 2
                            Text {
                                id: cb
                                anchors.centerIn: parent
                                text: parent.modelData
                                font.family: rv.cine.sans; font.pixelSize: 20; font.weight: Font.Bold
                                color: parent.on ? rv.th.bg : (parent.index === 0 ? rv.th.warn : rv.th.fg)
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: { rv.cine.rvButton = parent.index; rv.cine.button("a"); }
                            }
                        }
                    }
                }
            }
        }
    }
}
