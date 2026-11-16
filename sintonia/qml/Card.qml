// Tarjeta apaisada (tipo Netflix): imagen de fondo del título con su logo
// encima, barra de progreso si quedó a medias, temporada/episodio y SERIE.
import QtQuick
import QtQuick.Effects

Item {
    id: card
    required property var item
    property bool selected: false
    property bool hover: false                // mouse encima: solo el marco, sin elegirla
    property bool rowFocused: true            // la fila de la tarjeta es la elegida
    property var  theme

    scale: selected ? 1.08 : 1.0
    z: selected ? 2 : 1
    opacity: rowFocused ? 1 : 0.55
    Behavior on scale { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 200 } }

    // Brillo alrededor de la elegida
    Rectangle {
        anchors.fill: frame
        anchors.margins: -4
        radius: 8
        color: "transparent"
        border.width: 3
        border.color: card.theme.hi
        opacity: card.selected || card.hover ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 140 } }
        layer.enabled: card.selected || card.hover
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: card.theme.glow; shadowBlur: 1.0; blurMax: 40; shadowHorizontalOffset: 0; shadowVerticalOffset: 0 }
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: 6
        color: card.theme.deep
        border.width: 1
        border.color: card.selected || card.hover ? card.theme.hi : card.theme.line
        clip: true

        // Imagen de fondo; si no hay, el póster recortado
        Image {
            id: bg
            anchors.fill: parent
            anchors.margins: 1
            source: card.item.background || card.item.poster || ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: 520
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 240 } }
            onStatusChanged: if (status === Image.Error && source != card.item.poster && card.item.poster) source = card.item.poster
        }
        // Oscurece abajo para el logo (más fuerte si va texto: los videos traen letras en la miniatura)
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: logo.visible ? 0.35 : 0.2; color: "transparent" }
                GradientStop { position: logo.visible ? 0.75 : 0.55; color: Qt.rgba(0, 0, 0, logo.visible ? 0.45 : 0.72) }
                GradientStop { position: 1.0;  color: Qt.rgba(0, 0, 0, logo.visible ? 0.85 : 0.94) }
            }
        }
        Image {
            id: logo
            anchors { left: parent.left; bottom: parent.bottom; leftMargin: 16; bottomMargin: (card.item.offset ?? 0) > 0 ? 24 : 14 }
            source: card.item.logo ?? ""
            visible: status === Image.Ready
            height: 64
            width: Math.min(parent.width * 0.72, implicitWidth * height / Math.max(1, implicitHeight))
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            asynchronous: true
            sourceSize.height: 128
        }
        Text {
            visible: !logo.visible
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 16; rightMargin: 16; bottomMargin: (card.item.offset ?? 0) > 0 ? 24 : 14 }
            text: (card.item.name ?? "").toUpperCase()
            wrapMode: Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
            font.family: card.theme.font
            font.pixelSize: 24
            color: card.theme.hi
            style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.8)
        }

        // Quedó a medias: barra abajo (y el episodio, si es serie)
        Text {
            visible: (card.item.season ?? 0) > 0 && (card.item.offset ?? 0) > 0
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 14; bottomMargin: 14 }
            text: "T" + card.item.season + " · E" + card.item.episode
            font.family: card.theme.font
            font.pixelSize: 16
            color: card.theme.hi
            style: Text.Outline; styleColor: "#000"
        }
        Rectangle {
            visible: (card.item.offset ?? 0) > 0
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 6
            color: Qt.rgba(0, 0, 0, 0.7)
            Rectangle {
                height: parent.height
                width: parent.width * Math.max(0.03, Math.min(1, card.item.progress ?? 0))
                color: card.theme.hi
            }
        }
    }

    // Video: la duración arriba a la derecha (como en YouTube)
    Rectangle {
        visible: card.item.type === "video" && !!card.item.runtime
        anchors { top: frame.top; right: frame.right; margins: 8 }
        width: durTxt.implicitWidth + 14
        height: 24
        radius: 3
        color: Qt.rgba(0, 0, 0, 0.8)
        Text {
            id: durTxt
            anchors.centerIn: parent
            text: card.item.runtime ?? ""
            font.family: card.theme.font
            font.pixelSize: 14
            color: "#f2f2f2"
        }
    }

    // Serie: arriba a la derecha
    Rectangle {
        visible: card.item.type === "series"
        anchors { top: frame.top; right: frame.right; margins: 8 }
        width: badge.implicitWidth + 12
        height: 24
        radius: 3
        color: Qt.rgba(0, 0, 0, 0.75)
        border.width: 1
        border.color: card.theme.line
        Text {
            id: badge
            anchors.centerIn: parent
            text: "SERIE"
            font.family: card.theme.font
            font.pixelSize: 13
            color: card.theme.fg
        }
    }
}
