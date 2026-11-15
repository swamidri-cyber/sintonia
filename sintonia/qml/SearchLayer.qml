// Buscador del modo cine: a la izquierda lo que escribís (grande) y un teclado
// en pantalla para el joystick; a la derecha los resultados en pósters. Con el
// teclado de verdad se escribe directo. El estado vive en shell.qml (cine).
import QtQuick
import QtQuick.Effects

Item {
    id: sl
    required property var cine
    readonly property var th: cine.theme
    readonly property int resCols: Math.max(1, Math.floor(resGrid.width / resGrid.cellWidth))
    readonly property alias grid: resGrid           // para las zonas sin filtro (los pósters)
    visible: cine.searchActive
    readonly property bool wide: cine.platform === "youtube"     // miniaturas apaisadas

    function focusField() { field.forceActiveFocus(); }
    function setField(q) { if (field.text !== q) field.text = q; }

    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.985) }
            GradientStop { position: 0.45; color: Qt.rgba(0, 0, 0, 0.97) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.94) }
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: (m) => { if (m.button === Qt.RightButton) sl.cine.button("b"); }
            onWheel: (w) => sl.cine.navigate(w.angleDelta.y > 0 ? "up" : "down")
        }
    }

    // Teclado de verdad: escribe en este campo invisible; flechas/Enter/Esc navegan
    TextInput {
        id: field
        width: 1; height: 1; opacity: 0
        onTextEdited: sl.cine.queryTyped(text)
        Keys.onPressed: (e) => {
            const k = e.key;
            if (k === Qt.Key_Left)       sl.cine.navigate("left");
            else if (k === Qt.Key_Right) sl.cine.navigate("right");
            else if (k === Qt.Key_Up)    sl.cine.navigate("up");
            else if (k === Qt.Key_Down)  sl.cine.navigate("down");
            else if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                // con el foco en el teclado y algo escrito, Enter salta a los resultados
                if (sl.cine.sFocus === "keys" && sl.cine.searchResults.length) { sl.cine.sFocus = "results"; sl.cine.resIndex = 0; }
                else sl.cine.button("a");
            }
            else if (k === Qt.Key_Escape) sl.cine.button("b");
            else return;
            e.accepted = true;
        }
    }

    // ── Izquierda: lo escrito + teclado en pantalla ───────────────────────
    Column {
        id: left
        anchors { left: parent.left; leftMargin: 90; top: parent.top; topMargin: 130 }
        width: 640
        spacing: 26

        Text {
            text: sl.cine.tab === "letterboxd" && sl.cine.platform !== "youtube" ? "BUSCAR  ·  EN TU WATCHLIST DE LETTERBOXD"
                : "BUSCAR" + (sl.cine.platform !== "stremio" ? "  ·  EN " + sl.cine.plat.name + " Y TODO STREMIO" : "")
            font.family: sl.cine.mono; font.pixelSize: 15; font.letterSpacing: 4
            color: sl.th.dim
        }
        Item {
            width: parent.width; height: 74
            Text {
                id: qtxt
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                elide: Text.ElideLeft
                text: sl.cine.query === "" ? "¿Qué querés ver?" : sl.cine.query
                font.family: sl.cine.sans; font.pixelSize: 50; font.weight: Font.Bold
                color: sl.cine.query === "" ? sl.th.line : "white"
            }
            Rectangle {      // cursor que titila
                visible: sl.cine.query !== ""
                x: Math.min(qtxt.contentWidth, parent.width) + 6
                anchors.verticalCenter: parent.verticalCenter
                width: 4; height: 54; color: sl.th.hi
                SequentialAnimation on opacity {
                    loops: Animation.Infinite; running: sl.visible
                    NumberAnimation { to: 0; duration: 500 }
                    NumberAnimation { to: 1; duration: 500 }
                }
            }
            Rectangle { anchors { left: parent.left; right: parent.right; bottom: parent.bottom } height: 2; color: sl.th.line }
        }
        Grid {
            columns: sl.cine.keyCols
            spacing: 8
            Repeater {
                model: sl.cine.keyboard
                Rectangle {
                    required property string modelData
                    required property int index
                    readonly property bool on: sl.cine.sFocus === "keys" && sl.cine.keyIndex === index
                    width: 72; height: 64; radius: 10
                    color: on ? sl.th.hi : Qt.rgba(1, 1, 1, 0.06)
                    border.color: on ? sl.th.hi : Qt.rgba(1, 1, 1, 0.1); border.width: 1
                    scale: on ? 1.08 : 1
                    Behavior on scale { NumberAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: parent.modelData === "ESPACIO" ? "␣" : parent.modelData === "BORRAR" ? "✕" : parent.modelData
                        font.family: sl.cine.sans; font.pixelSize: parent.modelData.length > 1 ? 26 : 24; font.weight: Font.Bold
                        color: parent.on ? sl.th.bg : "white"
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { sl.cine.sFocus = "keys"; sl.cine.keyIndex = parent.index; sl.cine.typeKey(parent.modelData); sl.focusField(); }
                    }
                }
            }
        }
        Text {
            text: "A ESCRIBIR / ELEGIR    X BORRAR    Y ESPACIO    B CERRAR\nTambién podés escribir con el teclado."
            font.family: sl.cine.mono; font.pixelSize: 14
            color: sl.th.dim
            lineHeight: 1.4
        }
    }

    // ── Derecha: resultados ────────────────────────────────────────────────
    Item {
        anchors { left: left.right; leftMargin: 70; right: parent.right; rightMargin: 90; top: parent.top; topMargin: 130; bottom: parent.bottom; bottomMargin: 60 }

        Text {
            id: resHead
            text: sl.cine.query.trim() === "" ? (sl.cine.recents.length ? "BÚSQUEDAS RECIENTES" : "")
                : sl.cine.searching && sl.cine.searchResults.length === 0 ? "▒▒▒  BUSCANDO…"
                : sl.cine.searchResults.length + (sl.cine.searchResults.length === 1 ? " RESULTADO" : " RESULTADOS")
            font.family: sl.cine.mono; font.pixelSize: 15; font.letterSpacing: 3
            color: sl.th.dim
        }
        Text {
            anchors.centerIn: parent
            visible: sl.cine.query.trim() !== "" && !sl.cine.searching && sl.cine.searchResults.length === 0
            text: "Nada con “" + sl.cine.query + "”"
            font.family: sl.cine.sans; font.pixelSize: 26
            color: sl.th.dim
        }
        Text {
            anchors.centerIn: parent
            visible: sl.cine.query.trim() === "" && sl.cine.recents.length === 0
            horizontalAlignment: Text.AlignHCenter
            text: "Buscá por título: películas, series, anime…"
            font.family: sl.cine.sans; font.pixelSize: 24
            color: sl.th.line
        }

        GridView {
            id: resGrid
            anchors { left: parent.left; right: parent.right; top: resHead.bottom; topMargin: 24; bottom: parent.bottom }
            cellWidth: sl.wide ? 300 : 200
            cellHeight: sl.cine.query.trim() === "" ? 76 : sl.wide ? 230 : 340
            clip: true
            interactive: false
            model: sl.cine.searchResults
            currentIndex: sl.cine.resIndex
            highlightRangeMode: GridView.ApplyRange
            preferredHighlightBegin: 30; preferredHighlightEnd: height - 30
            highlightMoveDuration: 200
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                readonly property bool on: sl.cine.sFocus === "results" && sl.cine.resIndex === index
                width: resGrid.cellWidth; height: resGrid.cellHeight

                // búsqueda reciente: una pastilla
                Rectangle {
                    visible: !!cell.modelData.recent
                    anchors { left: parent.left; right: parent.right; margins: 6; verticalCenter: parent.verticalCenter }
                    height: 56; radius: 28
                    color: cell.on ? sl.th.hi : Qt.rgba(1, 1, 1, 0.07)
                    Text {
                        anchors.centerIn: parent
                        width: parent.width - 24; elide: Text.ElideRight; horizontalAlignment: Text.AlignHCenter
                        text: "↺  " + cell.modelData.name
                        font.family: sl.cine.sans; font.pixelSize: 18; font.weight: Font.Medium
                        color: cell.on ? sl.th.bg : "white"
                    }
                }
                // resultado: póster
                Item {
                    visible: !cell.modelData.recent
                    anchors.fill: parent
                    Rectangle {
                        id: frame
                        objectName: "poster"
                        anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 8 }
                        width: sl.wide ? 280 : 176; height: sl.wide ? 158 : 264; radius: 8
                        color: sl.th.deep
                        border.color: cell.on ? sl.th.hi : "transparent"; border.width: 3
                        scale: cell.on ? 1.07 : 1
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                        clip: true
                        layer.enabled: cell.on
                        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: sl.th.glow; shadowBlur: 1.0; blurMax: 32; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
                        Image {
                            id: poster
                            anchors { fill: parent; margins: 3 }
                            source: sl.wide ? (cell.modelData.background || cell.modelData.poster || "") : (cell.modelData.poster ?? "")
                            onStatusChanged: if (status === Image.Error && sl.wide && source != cell.modelData.poster) source = cell.modelData.poster
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true; cache: true
                            sourceSize.width: 340
                        }
                        // sin póster: placa con el título (rayas del color del canal + nombre grande)
                        Item {
                            visible: poster.status !== Image.Ready
                            anchors { fill: parent; margins: 3 }
                            Rectangle {
                                anchors.fill: parent
                                gradient: Gradient {
                                    GradientStop { position: 0.0; color: Qt.darker(sl.th.deep, 1.4) }
                                    GradientStop { position: 1.0; color: sl.th.deep }
                                }
                            }
                            Column {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                                spacing: 8
                                Rectangle { width: 36; height: 3; color: sl.th.hi }
                                Text {
                                    width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight
                                    text: (cell.modelData.name ?? "").toUpperCase()
                                    font.family: sl.cine.sans; font.pixelSize: 19; font.weight: Font.Black
                                    lineHeight: 1.05
                                    color: sl.th.hi
                                }
                                Text {
                                    visible: !!cell.modelData.year
                                    text: cell.modelData.year ?? ""
                                    font.family: sl.cine.mono; font.pixelSize: 13
                                    color: sl.th.dim
                                }
                            }
                        }
                        Rectangle {      // está en este canal
                            visible: !!cell.modelData.here
                            anchors { left: parent.left; top: parent.top; margins: 8 }
                            width: hereTxt.implicitWidth + 14; height: 24; radius: 4
                            color: sl.th.hi
                            Text {
                                id: hereTxt
                                anchors.centerIn: parent
                                text: "◆ " + sl.cine.plat.name
                                font.family: sl.cine.mono; font.pixelSize: 11
                                color: sl.th.bg
                            }
                        }
                    }
                    Text {
                        anchors { left: frame.left; right: frame.right; top: frame.bottom; topMargin: 10 }
                        elide: Text.ElideRight
                        text: (cell.modelData.name ?? "") + (cell.modelData.year ? "  ·  " + cell.modelData.year : "")
                        font.family: sl.cine.sans; font.pixelSize: 15; font.weight: cell.on ? Font.Bold : Font.Normal
                        color: cell.on ? "white" : sl.th.dim
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: if (sl.cine.mouseMode) { sl.cine.sFocus = "results"; sl.cine.resIndex = cell.index; }
                    onClicked: { sl.cine.sFocus = "results"; sl.cine.resIndex = cell.index; sl.cine.searchButton("a"); }
                }
            }
        }
    }
}
