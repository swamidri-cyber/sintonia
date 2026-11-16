// Pestaña LETTERBOXD del modo cine: tu watchlist entera, como la BIBLIOTECA de
// la consola. Pósters en grilla, de la que agregaste último a la más vieja
// (el orden de Letterboxd, "When Added · Newest First"). A la izquierda la
// ficha de la elegida. X / F busca solo dentro de la lista.
// Los datos los arma letterboxd-sync.py → ~/.local/state/rice-cine/letterboxd-watchlist.json
import QtQuick
import QtQuick.Effects

Item {
    id: lb
    required property var cine
    readonly property var th: cine.theme
    readonly property int cols: Math.max(1, Math.floor(grid.width / grid.cellWidth))
    visible: cine.tab === "letterboxd" && !cine.searchActive && !cine.plat.external

    function show(i) { grid.positionViewAtIndex(i, GridView.Contain); }

    // ── Ficha de la elegida ─────────────────────────────────────────────
    Column {
        id: side
        anchors { left: parent.left; leftMargin: 90; top: parent.top; topMargin: 150 }
        width: Math.min(560, parent.width * 0.33)
        spacing: 16

        Text {
            text: "WATCHLIST DE LETTERBOXD"
            font.family: lb.cine.mono; font.pixelSize: 15; font.letterSpacing: 3
            color: lb.th.dim
        }
        Row {
            spacing: 14
            Text {
                text: lb.cine.lbItems.length
                font.family: lb.cine.sans; font.pixelSize: 54; font.weight: Font.Black
                color: lb.th.hi
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text { text: "PELÍCULAS"; font.family: lb.cine.sans; font.pixelSize: 18; font.weight: Font.Bold; font.letterSpacing: 2; color: lb.th.fg }
                Text { text: "de la última que agregaste a la más vieja"; font.family: lb.cine.sans; font.pixelSize: 15; color: lb.th.dim }
            }
        }
        Rectangle { width: 48; height: 3; color: lb.th.hi }
        Item { width: 1; height: 6 }

        Image {
            id: logo
            source: lb.cine.info?.logo ?? ""
            visible: status === Image.Ready
            height: 120
            width: Math.min(side.width, implicitWidth * height / Math.max(1, implicitHeight))
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            sourceSize.height: 240
            asynchronous: true
        }
        EvaText {
            visible: !logo.visible
            text: (lb.cine.info?.name ?? "").toUpperCase()
            size: 64
            maxWidth: side.width
            color: lb.th.hi
        }
        Text {
            width: side.width
            text: lb.cine.metaLine(lb.cine.info) || (lb.cine.info?.year ?? "")
            wrapMode: Text.WordWrap
            font.family: lb.cine.sans; font.pixelSize: 19; font.weight: Font.Medium
            color: lb.th.fg
        }
        Text {
            width: side.width
            text: lb.cine.info?.description ?? ""
            wrapMode: Text.WordWrap; maximumLineCount: 6; elide: Text.ElideRight
            font.family: lb.cine.sans; font.pixelSize: 18
            color: Qt.rgba(1, 1, 1, 0.82)
            lineHeight: 1.2
        }
        Rectangle {
            visible: !!lb.cine.info?.lbOrder
            width: orderTxt.implicitWidth + 24; height: 32; radius: 16
            color: Qt.rgba(1, 1, 1, 0.06)
            border.width: 1; border.color: lb.th.line
            Text {
                id: orderTxt
                anchors.centerIn: parent
                text: lb.cine.info?.lbOrder === 1 ? "◆ LA ÚLTIMA QUE AGREGASTE"
                    : "◆ AGREGADA  #" + (lb.cine.info?.lbOrder ?? "") + "  DE " + lb.cine.lbItems.length
                font.family: lb.cine.mono; font.pixelSize: 13; font.letterSpacing: 1
                color: lb.th.hi
            }
        }
        Text {
            visible: String(lb.cine.info?.id ?? "").startsWith("lb:")
            width: side.width; wrapMode: Text.WordWrap
            text: "Esta no tiene ficha en IMDb: no se puede buscar en Stremio."
            font.family: lb.cine.sans; font.pixelSize: 16
            color: lb.th.warn
        }
    }

    // ── Pósters ──────────────────────────────────────────────────────────
    GridView {
        id: grid
        anchors { left: side.right; leftMargin: 60; right: parent.right; rightMargin: 70; top: parent.top; topMargin: 130; bottom: parent.bottom; bottomMargin: 70 }
        cellWidth: 196; cellHeight: 318
        clip: true
        interactive: false
        model: lb.cine.lbItems
        currentIndex: lb.cine.lbIndex
        highlightRangeMode: GridView.ApplyRange
        preferredHighlightBegin: 30; preferredHighlightEnd: height - 30
        highlightMoveDuration: 200
        transform: Translate { x: lb.cine.bumpX; y: lb.cine.bumpY }
        delegate: Item {
            id: cell
            required property var modelData
            required property int index
            readonly property bool on: lb.cine.lbIndex === index
            readonly property bool hov: lb.cine.mouseMode && cellMa.containsMouse
            width: grid.cellWidth; height: grid.cellHeight
            Rectangle {
                id: frame
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 12 }
                width: 168; height: 252; radius: 8
                color: lb.th.deep
                border.color: cell.on || cell.hov ? lb.th.hi : "transparent"; border.width: 3
                scale: cell.on ? 1.07 : 1
                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                clip: true
                layer.enabled: cell.on
                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: lb.th.glow; shadowBlur: 1.0; blurMax: 32; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
                Image {
                    id: poster
                    anchors { fill: parent; margins: 3 }
                    source: cell.modelData.poster ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true; cache: true
                    sourceSize.width: 330
                }
                // sin póster: placa con el título
                Item {
                    visible: poster.status !== Image.Ready
                    anchors { fill: parent; margins: 3 }
                    Rectangle {
                        anchors.fill: parent
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: Qt.darker(lb.th.deep, 1.4) }
                            GradientStop { position: 1.0; color: lb.th.deep }
                        }
                    }
                    Column {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 14 }
                        spacing: 8
                        Rectangle { width: 36; height: 3; color: lb.th.hi }
                        Text {
                            width: parent.width; wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight
                            text: (cell.modelData.name ?? "").toUpperCase()
                            font.family: lb.cine.sans; font.pixelSize: 18; font.weight: Font.Black
                            lineHeight: 1.05
                            color: lb.th.hi
                        }
                        Text {
                            text: cell.modelData.year ?? ""
                            font.family: lb.cine.mono; font.pixelSize: 13
                            color: lb.th.dim
                        }
                    }
                }
                Rectangle {      // las 5 últimas que agregaste
                    visible: (cell.modelData.lbOrder ?? 99) <= 5
                    anchors { left: parent.left; top: parent.top; margins: 8 }
                    width: newTxt.implicitWidth + 14; height: 22; radius: 4
                    color: lb.th.hi
                    Text {
                        id: newTxt
                        anchors.centerIn: parent
                        text: "NUEVA"
                        font.family: lb.cine.mono; font.pixelSize: 11
                        color: lb.th.bg
                    }
                }
            }
            Text {
                anchors { left: frame.left; right: frame.right; top: frame.bottom; topMargin: 10 }
                elide: Text.ElideRight
                text: (cell.modelData.name ?? "") + (cell.modelData.year ? "  ·  " + cell.modelData.year : "")
                font.family: lb.cine.sans; font.pixelSize: 15; font.weight: cell.on ? Font.Bold : Font.Normal
                color: cell.on ? "white" : lb.th.dim
            }
            MouseArea {
                id: cellMa
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (m) => {
                    if (m.button === Qt.RightButton) { lb.cine.mouseBack(); return; }
                    lb.cine.lbIndex = cell.index; lb.cine.openSheet();
                }
            }
        }
        // ruedita: de a una fila de pósters
        MouseArea {
            anchors.fill: parent
            z: 5
            acceptedButtons: Qt.NoButton
            property real acc: 0
            onWheel: (w) => {
                acc += w.angleDelta.y;
                while (Math.abs(acc) >= 120) { lb.cine.navigate(acc > 0 ? "up" : "down"); acc -= Math.sign(acc) * 120; }
                lb.cine.mouseMode = false;
            }
        }
    }
    Text {
        anchors.centerIn: grid
        visible: lb.cine.lbItems.length === 0
        text: lb.cine.lbLoaded ? "Tu watchlist está vacía" : "Todavía no se leyó tu watchlist de Letterboxd"
        font.family: lb.cine.sans; font.pixelSize: 22
        color: lb.th.dim
    }
}
