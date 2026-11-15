// Texto estilo placa de título de Evangelion: serif pesada, comprimida a lo
// ancho, apretada. El ancho que ocupa ya es el comprimido.
import QtQuick

Item {
    id: eva
    property alias text: t.text
    property alias color: t.color
    property real  size: 40
    property real  squeeze: 0.78               // compresión horizontal
    property int   maxWidth: 0                 // 0 = sin límite (si no, achica la letra)
    implicitWidth: t.implicitWidth * squeeze * fit
    implicitHeight: t.implicitHeight * fit
    width: implicitWidth; height: implicitHeight
    readonly property real fit: maxWidth > 0 && t.implicitWidth * squeeze > maxWidth ? maxWidth / (t.implicitWidth * squeeze) : 1

    Text {
        id: t
        font.family: "Liberation Serif"
        font.bold: true
        font.pixelSize: eva.size
        font.letterSpacing: -eva.size * 0.02
        color: "white"
        transform: Scale { xScale: eva.squeeze * eva.fit; yScale: eva.fit }
    }
}
