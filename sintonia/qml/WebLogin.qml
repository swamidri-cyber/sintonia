// Iniciar sesión en Letterboxd con el navegador de adentro de la app.
// Cuando aparecen las cookies de sesión del sitio, se guardan y se cierra sola.
// Esc (o B del joystick) cancela.
import QtQuick
import QtWebEngine
import Sintonia

Item {
    id: wl
    required property var cine
    readonly property var th: cine.theme
    property string servicio: ""            // "" = cerrada
    readonly property bool open: servicio !== ""
    readonly property string nombre: servicio === "letterboxd" ? "LETTERBOXD" : ""
    signal listo(string servicio, string usuario)
    visible: open

    function abrir(s) {
        servicio = s;
        hecho = false;
        view.url = Navegador.url(s);
        view.forceActiveFocus();
    }
    function cerrar() {
        servicio = "";
        view.url = "about:blank";
        cine.stageFocus();
    }
    property bool hecho: false
    function revisar() {
        if (!open || hecho || !Navegador.conectado(servicio)) return;
        hecho = true;
        if (servicio === "letterboxd") {
            // tu nombre de usuario, para mostrarlo en CUENTAS
            view.runJavaScript("(window.person && person.username) || ''", r => terminar(String(r || "")));
        } else terminar("");
    }
    function terminar(usuario) {
        const s = servicio;
        espera.restart();          // un toque más, para que lleguen todas las cookies
        pendiente = { s: s, u: usuario };
    }
    property var pendiente: null
    Timer {
        id: espera; interval: 1500
        onTriggered: {
            const p = wl.pendiente; wl.pendiente = null;
            if (!p) return;
            Navegador.guardar(p.s, p.u);
            wl.listo(p.s, p.u);
            wl.cerrar();
        }
    }
    Connections { target: Navegador; function onCambio() { wl.revisar(); } }

    Rectangle { anchors.fill: parent; color: wl.th.bg }
    MouseArea { anchors.fill: parent }

    // barra de arriba
    Rectangle {
        id: barra
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 84
        color: wl.th.deep
        Text {
            anchors { left: parent.left; leftMargin: 40; verticalCenter: parent.verticalCenter }
            text: "INICIÁ SESIÓN EN " + wl.nombre
            font.family: wl.cine.mono; font.pixelSize: 24; font.letterSpacing: 3
            color: wl.th.hi
        }
        Text {
            anchors { right: cancelar.left; rightMargin: 30; verticalCenter: parent.verticalCenter }
            text: view.loading ? "CARGANDO…" : "Cuando entres, se guarda y se cierra solo"
            font.family: wl.cine.sans; font.pixelSize: 19
            color: wl.th.dim
        }
        Rectangle {
            id: cancelar
            anchors { right: parent.right; rightMargin: 30; verticalCenter: parent.verticalCenter }
            width: ct.implicitWidth + 44; height: 50; radius: 25
            color: "transparent"; border.color: wl.th.line; border.width: 2
            Text { id: ct; anchors.centerIn: parent; text: "ESC  CANCELAR"; font.family: wl.cine.mono; font.pixelSize: 17; color: wl.th.fg }
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: wl.cerrar() }
        }
    }
    WebEngineView {
        id: view
        anchors { left: parent.left; right: parent.right; top: barra.bottom; bottom: parent.bottom }
        profile: Navegador.perfil
        visible: wl.open
        onLoadingChanged: wl.revisar()
        onUrlChanged: wl.revisar()
        // ventanas nuevas (por ej. "entrar con Google"): en la misma
        onNewWindowRequested: (req) => view.url = req.requestedUrl
        Keys.onEscapePressed: wl.cerrar()
    }
}
