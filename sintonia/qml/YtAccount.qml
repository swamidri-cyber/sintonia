// Canal de YouTube: arriba, tu cuenta (foto, nombre, @ y números). Al bajar de
// la primera fila se va hacia arriba y las filas ocupan la pantalla
// (cine.ytCollapsed). Los datos vienen de youtube.py account (cine.ytAccount).
import QtQuick
import QtQuick.Effects

Item {
    id: ya
    required property var cine
    readonly property var th: cine.theme
    readonly property var acc: cine.ytAccount
    visible: cine.platform === "youtube" && !cine.playFull

    // fondo liso: rojo muy oscuro arriba → negro, sin nada que se mueva
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            GradientStop { position: 0.0; color: "#1a0303" }
            GradientStop { position: 0.55; color: "#090101" }
            GradientStop { position: 1.0; color: "#000000" }
        }
    }

    Item {
        id: head
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 90; rightMargin: 90; topMargin: 236 }
        height: 220
        opacity: ya.cine.ytCollapsed ? 0 : 1
        transform: Translate { y: ya.cine.ytCollapsed ? -60 : 0; Behavior on y { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } } }
        Behavior on opacity { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
        visible: opacity > 0

        // foto: círculo con aro del color del canal
        Rectangle {
            id: ring
            width: 196; height: 196; radius: 98
            anchors.verticalCenter: parent.verticalCenter
            color: "transparent"
            border.width: 3; border.color: ya.th.hi
            Rectangle {
                anchors.centerIn: parent
                width: 176; height: 176; radius: 88
                color: Qt.rgba(1, 1, 1, 0.06)
                clip: true
                layer.enabled: true
                Image {
                    id: photo
                    anchors.fill: parent
                    source: ya.acc?.avatar ?? ""
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: 240
                    asynchronous: true
                    visible: false
                }
                Rectangle {
                    id: roundMask
                    anchors.fill: parent; radius: width / 2
                    visible: false; layer.enabled: true
                }
                MultiEffect {   // recorte redondo de la foto
                    anchors.fill: parent
                    visible: photo.status === Image.Ready
                    source: photo
                    maskEnabled: true
                    maskSource: roundMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin: 1.0
                }
                Text {          // inicial mientras carga / sin foto
                    anchors.centerIn: parent
                    visible: photo.status !== Image.Ready
                    text: (ya.acc?.name ?? "?").charAt(0).toUpperCase()
                    font.family: ya.cine.sans; font.pixelSize: 80; font.weight: Font.Black
                    color: ya.th.dim
                }
            }
        }

        Column {
            anchors { left: ring.right; leftMargin: 44; verticalCenter: parent.verticalCenter; right: parent.right }
            spacing: 12
            Text {
                text: "TU CUENTA"
                font.family: ya.cine.mono; font.pixelSize: 16; font.letterSpacing: 4
                color: ya.th.dim
            }
            EvaText {
                text: (ya.acc?.name || "YOUTUBE").toUpperCase()
                size: 84
                maxWidth: parent.width
                color: ya.th.hi
            }
            Text {
                visible: !!ya.acc?.handle
                text: ya.acc?.handle ?? ""
                font.family: ya.cine.sans; font.pixelSize: 24; font.weight: Font.Medium
                color: ya.th.fg
            }
            Row {
                spacing: 14
                topPadding: 6
                Repeater {
                    model: [ya.acc?.subscribers ?? "", ya.acc?.videos ?? "",
                            ya.acc?.following ? "sigue " + ya.acc.following + " canales" : ""].filter(s => s)
                    Rectangle {
                        required property string modelData
                        height: 38; radius: 19
                        width: chip.implicitWidth + 36
                        color: Qt.rgba(1, 1, 1, 0.06)
                        border.width: 1; border.color: ya.th.line
                        Text {
                            id: chip
                            anchors.centerIn: parent
                            text: parent.modelData.toUpperCase()
                            font.family: ya.cine.mono; font.pixelSize: 16; font.letterSpacing: 2
                            color: ya.th.fg
                        }
                    }
                }
            }
        }
    }
}
