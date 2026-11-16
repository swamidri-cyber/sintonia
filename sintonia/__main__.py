"""SINTONÍA 同調 — arranque.

  python -m sintonia                     abre la app (si ya está abierta, la trae)
  python -m sintonia ipc <target> <fn> [args…]   llama a la interfaz (pruebas)
  sintonia --script <archivo.py> [args…] (empaquetada) corre un script de backend/
"""
from __future__ import annotations

import json
import os
import runpy
import sys


def correr_script(argv: list[str]) -> None:
    script = argv[0]
    sys.argv = argv
    sys.path.insert(0, os.path.dirname(script))
    runpy.run_path(script, run_name="__main__")


def nombre_ipc() -> str:
    usuario = os.environ.get("USER") or os.environ.get("USERNAME") or "usuario"
    return f"sintonia-{usuario}"


def cliente_ipc(target: str, fn: str, args: list[str]) -> int:
    from PySide6.QtCore import QCoreApplication
    from PySide6.QtNetwork import QLocalSocket

    QCoreApplication.instance() or QCoreApplication([])
    s = QLocalSocket()
    s.connectToServer(nombre_ipc())
    if not s.waitForConnected(1500):
        print("error: SINTONÍA no está abierta", file=sys.stderr)
        return 1
    s.write((json.dumps({"target": target, "fn": fn, "args": args}) + "\n").encode())
    s.flush()
    s.waitForReadyRead(5000)
    print(json.loads(bytes(s.readLine()).decode() or '{"r": ""}')["r"])
    return 0


def elegir_audio() -> None:
    """Qt Multimedia (6.12) se cae entero si usa PipeWire y no hay un servidor de
    PipeWire andando. En ese caso, en Linux se usa PulseAudio o ALSA."""
    if not sys.platform.startswith("linux") or os.environ.get("QT_AUDIO_BACKEND"):
        return
    rt = os.environ.get("XDG_RUNTIME_DIR", "")
    if rt and os.path.exists(os.path.join(rt, "pipewire-0")):
        return
    os.environ["QT_AUDIO_BACKEND"] = "pulseaudio" if rt and os.path.exists(os.path.join(rt, "pulse", "native")) else "alsa"


def abrir() -> int:
    elegir_audio()
    from PySide6.QtCore import QUrl, Qt
    from PySide6.QtGui import QFontDatabase, QGuiApplication, QIcon
    from PySide6.QtQml import QQmlApplicationEngine
    from PySide6.QtQuick import QQuickWindow, QSGRendererInterface

    from . import compat, rutas  # registra los tipos de QML  # noqa: F401
    # el video de mpv se dibuja con OpenGL (en Windows Qt usaría Direct3D)
    QQuickWindow.setGraphicsApi(QSGRendererInterface.GraphicsApi.OpenGL)
    try:   # el navegador para iniciar sesión (tiene que arrancar antes que la app)
        from PySide6.QtWebEngineQuick import QtWebEngineQuick
        QtWebEngineQuick.initialize()
    except ImportError:
        pass

    QGuiApplication.setApplicationName("Sintonía")
    QGuiApplication.setOrganizationName("Sintonia")
    QGuiApplication.setDesktopFileName("sintonia")
    QGuiApplication.setHighDpiScaleFactorRoundingPolicy(Qt.HighDpiScaleFactorRoundingPolicy.PassThrough)
    app = QGuiApplication(sys.argv)
    if ya_abierta():
        return 0   # ya estaba abierta: se le pidió que se muestre
    import locale
    locale.setlocale(locale.LC_NUMERIC, "C")   # libmpv lo pide
    from . import video  # noqa: F401  (MpvVideo + el canal "mpv")
    from . import navegador  # noqa: F401  (Navegador: inicio de sesión web)
    video.anfitrion()
    icono = os.path.join(rutas.DATOS, "icono.png")
    if os.path.exists(icono):
        app.setWindowIcon(QIcon(icono))

    carpeta = os.path.join(rutas.DATOS, "fonts")
    for f in sorted(os.listdir(carpeta)):
        QFontDatabase.addApplicationFont(os.path.join(carpeta, f))

    servidor = compat.ServidorIpc(nombre_ipc())  # noqa: F841
    app.aboutToQuit.connect(compat.matar_hijos)
    # cerrar bien también si la matan desde afuera (Ctrl+C, apagar la PC…)
    import signal
    from PySide6.QtCore import QTimer
    for sg in (signal.SIGINT, signal.SIGTERM) + ((signal.SIGHUP,) if hasattr(signal, "SIGHUP") else ()):
        signal.signal(sg, lambda *_: app.quit())
    latido = QTimer()            # (para que Python atienda las señales mientras corre Qt)
    latido.start(500)
    latido.timeout.connect(lambda: None)
    engine = QQmlApplicationEngine()
    engine.load(QUrl.fromLocalFile(os.path.join(rutas.DATOS, "qml", "Main.qml")))
    if not engine.rootObjects():
        return 1
    return app.exec()


def ya_abierta() -> bool:
    from PySide6.QtNetwork import QLocalSocket

    s = QLocalSocket()
    s.connectToServer(nombre_ipc())
    if not s.waitForConnected(300):
        return False
    s.write((json.dumps({"target": "cine", "fn": "show", "args": []}) + "\n").encode())
    s.flush()
    s.waitForReadyRead(2000)
    s.abort()
    return True


def main() -> int:
    a = sys.argv[1:]
    if a[:1] == ["--script"]:
        correr_script(a[1:])
        return 0
    if a[:1] == ["ipc"] and len(a) >= 3:
        return cliente_ipc(a[1], a[2], a[3:])
    return abrir()


if __name__ == "__main__":
    sys.exit(main())
