"""Reemplazo de las piezas de Quickshell que usa la interfaz del cine.

La interfaz nació como una configuración de Quickshell (solo Linux/Wayland).
Para que la misma QML ande como app en Linux y Windows, acá se imitan, con la
misma forma, los tipos que usa:

  import Quickshell      → Quickshell (env, execDetached, screens)
  import Quickshell.Io   → Process, StdioCollector, SplitParser, FileView, IpcHandler
  import Sintonia        → App (carpetas, escribir archivos, plataforma)

Los comandos que terminan en .py se corren con el Python de la app (o con el
mismo ejecutable empaquetado, ver __main__.py), así andan igual en Windows.
Los comandos propios del rice (hyprctl, qs, systemctl, …) se ignoran.
"""
from __future__ import annotations

import json
import os
import sys

from enum import IntEnum

from PySide6.QtCore import (Q_ARG, Q_RETURN_ARG, Property, QDateTime, QMetaObject, Qt, QEnum, QFileSystemWatcher, QMetaMethod, QObject, QProcess,
                            QProcessEnvironment, QTimer, Signal, Slot, QUrl)
from PySide6.QtGui import QGuiApplication
from PySide6.QtNetwork import QLocalServer, QLocalSocket
from PySide6.QtQml import QmlElement, QmlSingleton, QJSValue

from . import rutas

# comandos del rice que en la app no tienen sentido
IGNORADOS = {"hyprctl", "qs", "systemctl", "notify-send", "xdg-open"}


def _lista(v) -> list[str]:
    if isinstance(v, QJSValue):
        v = v.toVariant()
    return [str(x) for x in (v or [])]


def preparar_comando(argv: list[str]) -> list[str] | None:
    """Traduce un comando de la interfaz a uno que se pueda correr acá.
    None = no correr nada."""
    if not argv:
        return None
    prog = os.path.basename(argv[0])
    if prog in IGNORADOS or prog.endswith(".sh"):
        return None
    if prog == "sh" and any(x in " ".join(argv) for x in ("hyprctl", "qs ", "systemctl")):
        return None
    if argv[0].endswith(".py"):
        return rutas.comando_python(argv[0]) + argv[1:]
    return argv


# ── import Quickshell ───────────────────────────────────────────────────────
QML_IMPORT_NAME = "Quickshell"
QML_IMPORT_MAJOR_VERSION = 1


@QmlElement
@QmlSingleton
class Quickshell(QObject):
    @Slot(str, result=str)
    def env(self, nombre):
        return rutas.entorno().get(nombre, "")

    @Slot("QVariant")
    def execDetached(self, argv):
        cmd = preparar_comando(_lista(argv))
        if cmd:
            QProcess.startDetached(cmd[0], cmd[1:], "", )

    @Property("QVariantList", constant=True)
    def screens(self):
        return list(QGuiApplication.screens())


@QmlElement
class SystemClock(QObject):
    """Reloj que avisa cada segundo/minuto/hora (property date)."""
    @QEnum
    class Precision(IntEnum):
        Hours = 0
        Minutes = 1
        Seconds = 2

    dateChanged = Signal()
    precisionChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._prec = 2
        self._t = QTimer(self)
        self._t.setSingleShot(True)
        self._t.timeout.connect(self._tic)
        self._tic()

    def _tic(self):
        self.dateChanged.emit()
        ahora = QDateTime.currentDateTime()
        paso = {0: 3600, 1: 60, 2: 1}[self._prec]
        seg = ahora.time().msecsSinceStartOfDay() // 1000
        falta = (paso - seg % paso) * 1000 - ahora.time().msec()
        self._t.start(max(50, falta))

    @Property(QDateTime, notify=dateChanged)
    def date(self):
        return QDateTime.currentDateTime()

    def _get_prec(self):
        return self._prec

    def _set_prec(self, v):
        self._prec = int(v)
        self.precisionChanged.emit()
        self._tic()

    precision = Property(int, _get_prec, _set_prec, notify=precisionChanged)


# ── import Quickshell.Io ────────────────────────────────────────────────────
QML_IMPORT_NAME = "Quickshell.Io"


@QmlElement
class StdioCollector(QObject):
    """Junta toda la salida; al terminar el proceso avisa con streamFinished."""
    textChanged = Signal()
    streamFinished = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._buf = bytearray()

    def _empezar(self):
        self._buf.clear()

    def _datos(self, b: bytes):
        self._buf += b

    def _fin(self):
        self.textChanged.emit()
        self.streamFinished.emit()

    @Property(str, notify=textChanged)
    def text(self):
        return self._buf.decode("utf-8", "replace")


@QmlElement
class SplitParser(QObject):
    """Avisa cada línea que llega con read(data)."""
    read = Signal(str, arguments=["data"])

    def __init__(self, parent=None):
        super().__init__(parent)
        self._resto = bytearray()

    def _empezar(self):
        self._resto.clear()

    def _datos(self, b: bytes):
        self._resto += b
        while True:
            i = self._resto.find(b"\n")
            if i < 0:
                break
            linea = bytes(self._resto[:i]).decode("utf-8", "replace")
            del self._resto[: i + 1]
            self.read.emit(linea)

    def _fin(self):
        if self._resto:
            self.read.emit(bytes(self._resto).decode("utf-8", "replace"))
            self._resto.clear()


@QmlElement
class Process(QObject):
    commandChanged = Signal()
    runningChanged = Signal()
    stdoutChanged = Signal()
    stdinEnabledChanged = Signal()
    environmentChanged = Signal()
    started = Signal()
    exited = Signal(int, int, arguments=["exitCode", "exitStatus"])

    def __init__(self, parent=None):
        super().__init__(parent)
        self._command: list[str] = []
        self._stdout = None
        self._stdin = False
        self._env: dict = {}
        self._p: QProcess | None = None

    # command
    def _get_command(self):
        return self._command

    def _set_command(self, v):
        v = _lista(v)
        if v != self._command:
            self._command = v
            self.commandChanged.emit()

    command = Property("QVariant", _get_command, _set_command, notify=commandChanged)

    def _get_stdout(self):
        return self._stdout

    def _set_stdout(self, v):
        self._stdout = v
        self.stdoutChanged.emit()

    stdout = Property(QObject, _get_stdout, _set_stdout, notify=stdoutChanged)

    def _get_stdin(self):
        return self._stdin

    def _set_stdin(self, v):
        self._stdin = bool(v)
        self.stdinEnabledChanged.emit()

    stdinEnabled = Property(bool, _get_stdin, _set_stdin, notify=stdinEnabledChanged)

    def _get_env(self):
        return self._env

    def _set_env(self, v):
        self._env = v.toVariant() if isinstance(v, QJSValue) else (v or {})
        self.environmentChanged.emit()

    environment = Property("QVariant", _get_env, _set_env, notify=environmentChanged)

    # running
    def _get_running(self):
        return self._p is not None

    def _set_running(self, v):
        if v and self._p is None:
            QTimer.singleShot(0, self._arrancar)   # como Quickshell: cuando terminen de ponerse las propiedades
        elif not v and self._p is not None:
            self._p.kill()

    running = Property(bool, _get_running, _set_running, notify=runningChanged)

    def _arrancar(self):
        if self._p is not None:
            return
        cmd = preparar_comando(self._command)
        if not cmd:
            self.exited.emit(0, 0)
            return
        p = QProcess(self)
        env = QProcessEnvironment.systemEnvironment()
        for k, v in rutas.entorno_backend().items():
            env.insert(k, v)
        for k, v in (self._env or {}).items():
            env.insert(str(k), str(v))
        p.setProcessEnvironment(env)
        p.setProcessChannelMode(QProcess.SeparateChannels)
        out = self._stdout
        if out is not None and hasattr(out, "_empezar"):
            out._empezar()
        p.readyReadStandardOutput.connect(lambda: out._datos(bytes(p.readAllStandardOutput())) if out is not None and hasattr(out, "_datos") else p.readAllStandardOutput())
        p.readyReadStandardError.connect(lambda: sys.stderr.write(bytes(p.readAllStandardError()).decode("utf-8", "replace")))
        p.finished.connect(lambda code, st: self._termino(p, code, st))
        p.errorOccurred.connect(lambda e: self._fallo(p, e))
        self._p = p
        p.start(cmd[0], cmd[1:])
        self.runningChanged.emit()
        self.started.emit()

    def _fallo(self, p, e):
        if e == QProcess.FailedToStart and self._p is p:
            sys.stderr.write(f"[sintonia] no arrancó: {self._command}\n")
            self._termino(p, -1, 1)

    def _termino(self, p, code, st):
        if self._p is not p:
            return
        rest = bytes(p.readAllStandardOutput())
        out = self._stdout
        if out is not None and hasattr(out, "_datos"):
            if rest:
                out._datos(rest)
            out._fin()
        self._p = None
        p.deleteLater()
        self.runningChanged.emit()
        self.exited.emit(int(code), st.value if hasattr(st, "value") else int(st))

    @Slot(str)
    def write(self, texto):
        if self._p is not None:
            self._p.write(texto.encode())

    @Slot(int)
    def signal(self, _n):
        if self._p is not None:
            self._p.terminate()


@QmlElement
class FileView(QObject):
    pathChanged = Signal()
    loaded = Signal()
    loadFailed = Signal(int, arguments=["error"])
    fileChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._path = ""
        self._texto = ""
        self._watch = False
        self._print = True
        self._w: QFileSystemWatcher | None = None

    def _get_path(self):
        return self._path

    def _set_path(self, v):
        v = str(v or "")
        if v.startswith("file://"):
            v = QUrl(v).toLocalFile()
        if v != self._path:
            self._path = v
            self.pathChanged.emit()
            self._vigilar()
            QTimer.singleShot(0, self.reload)

    path = Property(str, _get_path, _set_path, notify=pathChanged)

    def _get_watch(self):
        return self._watch

    def _set_watch(self, v):
        self._watch = bool(v)
        self._vigilar()

    watchChanges = Property(bool, _get_watch, _set_watch)

    def _get_print(self):
        return self._print

    def _set_print(self, v):
        self._print = bool(v)

    printErrors = Property(bool, _get_print, _set_print)

    def _vigilar(self):
        if self._w:
            self._w.deleteLater()
            self._w = None
        if self._watch and self._path:
            self._w = QFileSystemWatcher(self)
            d = os.path.dirname(self._path)
            if os.path.exists(self._path):
                self._w.addPath(self._path)
            if os.path.isdir(d):
                self._w.addPath(d)        # si se reemplaza el archivo (escritura atómica)
            self._w.fileChanged.connect(self._cambio)
            self._w.directoryChanged.connect(self._cambio_dir)

    def _cambio(self, _p):
        if self._w and os.path.exists(self._path) and self._path not in self._w.files():
            self._w.addPath(self._path)
        self.fileChanged.emit()

    def _cambio_dir(self, _d):
        if self._w and os.path.exists(self._path) and self._path not in self._w.files():
            self._w.addPath(self._path)
            self.fileChanged.emit()

    @Slot()
    def reload(self):
        if not self._path:
            return
        try:
            with open(self._path, encoding="utf-8") as f:
                self._texto = f.read()
        except OSError:
            if self._print:
                sys.stderr.write(f"[sintonia] no se pudo leer {self._path}\n")
            self.loadFailed.emit(1)
            return
        self.loaded.emit()

    @Slot(result=str)
    def text(self):
        return self._texto

    @Slot(str)
    def setText(self, t):
        rutas.escribir(self._path, t)
        self._texto = t


# IPC: `sintonia ipc <target> <función> [args…]` llama a una función del
# IpcHandler de la interfaz (sirve para las pruebas y para el teléfono).
_HANDLERS: dict[str, QObject] = {}


@QmlElement
class IpcHandler(QObject):
    targetChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._target = ""

    def _get_target(self):
        return self._target

    def _set_target(self, v):
        if self._target in _HANDLERS:
            _HANDLERS.pop(self._target, None)
        self._target = v
        _HANDLERS[v] = self
        self.targetChanged.emit()

    target = Property(str, _get_target, _set_target, notify=targetChanged)

    enabled = Property(bool, lambda self: True, lambda self, v: None)


def _convertir(tipo: str, v: str):
    if tipo == "bool":
        return v.lower() in ("1", "true", "si", "sí", "yes")
    if tipo in ("double", "float", "qreal"):
        return float(v)
    if tipo == "int":
        return int(v)
    return v


def _texto(v) -> str:
    return v if isinstance(v, str) else bytes(v).decode()


def llamar_ipc(target: str, funcion: str, args: list[str]) -> str:
    obj = _HANDLERS.get(target)
    if obj is None:
        return f"error: no hay '{target}'"
    mo = obj.metaObject()
    for i in range(mo.methodCount()):
        m = mo.method(i)
        if _texto(m.name()) != funcion or m.methodType() not in (QMetaMethod.Method, QMetaMethod.Slot):
            continue
        tipos = [_texto(t) for t in m.parameterTypes()]
        if len(tipos) != len(args):
            return f"error: {funcion} espera {len(tipos)} argumentos"
        valores = [_convertir(t, a) for t, a in zip(tipos, args)]
        pytipo = {"bool": bool, "double": float, "float": float, "qreal": float, "int": int}
        qargs = [Q_ARG(pytipo.get(t, str), v) for t, v in zip(tipos, valores)]
        ret = _texto(m.typeName())
        try:
            if ret in ("", "void"):
                QMetaObject.invokeMethod(obj, funcion, Qt.DirectConnection, *qargs)
                return ""
            res = QMetaObject.invokeMethod(obj, funcion, Qt.DirectConnection,
                                           Q_RETURN_ARG(pytipo.get(ret, str)), *qargs)
        except Exception as e:  # noqa: BLE001
            return f"error: {e}"
        return "" if res is None else str(res)
    return f"error: no existe {target}.{funcion}"


class ServidorIpc(QObject):
    def __init__(self, nombre: str, parent=None):
        super().__init__(parent)
        QLocalServer.removeServer(nombre)
        self.s = QLocalServer(self)
        self.s.listen(nombre)
        self.s.newConnection.connect(self._nueva)

    def _nueva(self):
        c = self.s.nextPendingConnection()
        c.readyRead.connect(lambda: self._leer(c))

    def _leer(self, c: QLocalSocket):
        if not c.canReadLine():
            return
        try:
            pedido = json.loads(bytes(c.readLine()).decode())
            res = llamar_ipc(pedido["target"], pedido["fn"], pedido.get("args", []))
        except Exception as e:  # noqa: BLE001
            res = f"error: {e}"
        c.write((json.dumps({"r": res}) + "\n").encode())
        c.flush()
        c.disconnectFromServer()


# ── import Sintonia ─────────────────────────────────────────────────────────
QML_IMPORT_NAME = "Sintonia"


@QmlElement
@QmlSingleton
class App(QObject):
    """Carpetas y utilidades de la app, iguales en Linux y Windows."""

    @Property(str, constant=True)
    def dataDir(self):
        return rutas.DATOS

    @Property(str, constant=True)
    def dataUrl(self):
        return QUrl.fromLocalFile(rutas.DATOS).toString()

    @Property(str, constant=True)
    def backendDir(self):
        return rutas.BACKEND

    @Property(str, constant=True)
    def configDir(self):
        return rutas.CONFIG

    @Property(str, constant=True)
    def stateDir(self):
        return rutas.ESTADO

    @Property(str, constant=True)
    def cacheDir(self):
        return rutas.CACHE

    @Property(str, constant=True)
    def runtimeDir(self):
        return rutas.RUNTIME

    @Property(str, constant=True)
    def platform(self):
        return "windows" if sys.platform.startswith("win") else ("mac" if sys.platform == "darwin" else "linux")

    @Slot(str, result=str)
    def url(self, relativo):
        """URL de un archivo de la app (shaders, sonidos…)."""
        return QUrl.fromLocalFile(os.path.join(rutas.DATOS, relativo)).toString()

    @Slot(str, str)
    def writeFile(self, path, texto):
        rutas.escribir(path, texto)

    @Slot(str)
    def removeFile(self, path):
        try:
            os.remove(path)
        except OSError:
            pass

    @Slot()
    def quit(self):
        QGuiApplication.quit()
