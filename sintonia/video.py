"""SINTONÍA — el reproductor ADENTRO de la ventana.

mpv corre como librería (libmpv) dentro de la app y dibuja cada cuadro en un
elemento de la interfaz (MpvVideo, abajo de todo: los controles van encima).

player.py no sabe nada de esto: se conecta al canal "mpv" (backend/canal.py),
manda una línea {"open": [argumentos de mpv como en la terminal]} y desde ahí
habla el mismo idioma que el socket JSON de mpv (command/observe_property →
eventos property-change). Cuando mpv termina (quit, error, fin) se corta la
conexión, que para player.py es "mpv se cerró".
"""
from __future__ import annotations

import ctypes
import json
import os
import socket
import sys
import threading

from PySide6.QtCore import QObject, Property, Qt, Signal, Slot
from PySide6.QtGui import QOpenGLContext
from PySide6.QtOpenGL import QOpenGLFramebufferObject, QOpenGLFramebufferObjectFormat
from PySide6.QtQml import QmlElement
from PySide6.QtQuick import QQuickFramebufferObject

from . import rutas

sys.path.insert(0, rutas.BACKEND)
import canal  # noqa: E402

if sys.platform.startswith("win"):
    # libmpv-2.dll va al lado del ejecutable (o en la carpeta de la app)
    for d in (os.path.dirname(sys.executable), rutas.DATOS, os.path.dirname(rutas.DATOS)):
        if os.path.exists(os.path.join(d, "libmpv-2.dll")):
            os.add_dll_directory(d)
            os.environ["PATH"] = d + os.pathsep + os.environ.get("PATH", "")
else:
    # empaquetada: la libmpv que viene adentro (python-mpv la busca con find_library)
    _propia = [os.path.join(d, n) for d in (getattr(sys, "_MEIPASS", ""), os.path.dirname(sys.executable))
               for n in ("libmpv.so.2", "libmpv.so")]
    _propia = next((x for x in _propia if os.path.exists(x)), None)
    if _propia:
        import ctypes.util as _cu
        _buscar = _cu.find_library
        _cu.find_library = lambda n: _propia if n == "mpv" else _buscar(n)
import mpv as _mpv  # noqa: E402

QML_IMPORT_NAME = "Sintonia"
QML_IMPORT_MAJOR_VERSION = 1

# opciones de la línea de comandos que acá no corresponden (ventana propia, socket propio)
SIN_EFECTO = {"fs", "fullscreen", "wayland-app-id", "title", "input-ipc-server", "cursor-autohide",
              "x11-name", "force-window"}


# nombres que cambiaron entre versiones de mpv (nuevo → viejo)
VIEJAS = {"sub-outline-color": "sub-border-color", "sub-outline-size": "sub-border-size",
          "sub-border-color": "sub-outline-color", "sub-border-size": "sub-outline-size"}


# atajos de la línea de comandos que libmpv no conoce con ese nombre
ALIAS = {"sub-file": "sub-files", "audio-file": "audio-files", "external-file": "external-files"}


def opciones(args):
    """["url", "--k=v", "--no-osc", …] → (url, {k: v})"""
    url, opts = None, {}
    for a in args:
        if not a.startswith("--"):
            if url is None and a != "mpv":
                url = a
            continue
        k, _, v = a[2:].partition("=")
        if not _:
            if k.startswith("no-"):
                k, v = k[3:], "no"
            else:
                v = "yes"
        k = ALIAS.get(k, k)
        if k not in SIN_EFECTO:
            opts[k] = v
    return url, opts


def _a_json(v):
    if isinstance(v, bytes):
        return v.decode("utf-8", "replace")
    if isinstance(v, (list, tuple)):
        return [_a_json(x) for x in v]
    if isinstance(v, dict):
        return {str(k): _a_json(x) for k, x in v.items()}
    if isinstance(v, (str, int, float, bool)) or v is None:
        return v
    return str(v)


def _arg(v):
    if isinstance(v, bool):
        return "yes" if v else "no"
    return str(v)


# ── get_proc_address para el render de mpv ──────────────────────────────────
def _buscar_funcion_gl():
    """Fallback si Qt no da la dirección: la del sistema (GLX / EGL / WGL)."""
    if sys.platform.startswith("win"):
        gl = ctypes.WinDLL("opengl32")
        wgl = gl.wglGetProcAddress
        wgl.restype, wgl.argtypes = ctypes.c_void_p, [ctypes.c_char_p]
        k32 = ctypes.WinDLL("kernel32")
        k32.GetProcAddress.restype = ctypes.c_void_p
        k32.GetProcAddress.argtypes = [ctypes.c_void_p, ctypes.c_char_p]

        def f(nombre):
            p = wgl(nombre)
            if p in (None, 0, 1, 2, 3, -1):
                p = k32.GetProcAddress(gl._handle, nombre)
            return p or 0
        return f
    cands = []
    for lib, fn in (("libEGL.so.1", "eglGetProcAddress"), ("libGL.so.1", "glXGetProcAddressARB")):
        try:
            g = getattr(ctypes.CDLL(lib), fn)
            g.restype, g.argtypes = ctypes.c_void_p, [ctypes.c_char_p]
            cands.append((lib, g))
        except OSError:
            pass
    egl = os.environ.get("QT_QPA_PLATFORM", "").startswith("wayland") or (
        os.environ.get("WAYLAND_DISPLAY") and not os.environ.get("QT_QPA_PLATFORM"))
    cands.sort(key=lambda c: (c[0].startswith("libEGL")) != bool(egl))

    def f(nombre):
        for _, g in cands:
            p = g(nombre)
            if p:
                return p
        return 0
    return f


_sistema = None


def _proc_address(_ctx, nombre):
    global _sistema
    ctx = QOpenGLContext.currentContext()
    if ctx is not None:
        try:
            p = ctx.getProcAddress(nombre)
            p = int(p) if p is not None else 0
            if p:
                return p
        except Exception:
            pass
    if _sistema is None:
        _sistema = _buscar_funcion_gl()
    p = _sistema(nombre)
    if os.environ.get("SINTONIA_DEBUG_GL"):
        sys.stderr.write(f"gl {nombre!r} qt={ctx is not None} -> {p}\n")
    return p


_GPA = _mpv.MpvGlGetProcAddressFn(_proc_address)


# ── Anfitrión: una película por vez ─────────────────────────────────────────
class Anfitrion(QObject):
    """Atiende al canal "mpv" y maneja la instancia de libmpv."""
    cambio = Signal()          # hay que redibujar el video
    activoCambio = Signal()

    def __init__(self):
        super().__init__()
        self.m = None          # mpv.MPV
        self.ctx = None        # mpv.MpvRenderContext (vive en el hilo de dibujo)
        self.cerrando = False
        self.cliente = None
        self.lock = threading.Lock()
        self.item = None
        self._activo = False
        self.activoCambio.connect(lambda: None)
        threading.Thread(target=self._escuchar, daemon=True).start()

    # lo que ve la interfaz
    def activo(self):
        return self._activo

    def _set_activo(self, v):
        if v != self._activo:
            self._activo = v
            self.activoCambio.emit()

    # ── canal ───────────────────────────────────────────────────────────
    def _escuchar(self):
        srv = canal.escuchar("mpv")
        while True:
            c, _ = srv.accept()
            threading.Thread(target=self._atender, args=(c,), daemon=True).start()

    def _enviar(self, obj):
        c = self.cliente
        if not c:
            return
        try:
            c.sendall((json.dumps(obj, ensure_ascii=False) + "\n").encode())
        except OSError:
            pass

    def _atender(self, c):
        f = c.makefile("rb")
        primera = f.readline()
        try:
            pedido = json.loads(primera)
        except Exception:
            c.close()
            return
        self.terminar(esperar=True)          # una película por vez
        url, opts = opciones(pedido.get("open") or [])
        try:
            self._abrir(url, opts)
        except Exception as e:
            sys.stderr.write(f"mpv no arrancó: {e}\n")
            c.close()
            return
        self.cliente = c
        try:
            for linea in f:
                try:
                    pedido = json.loads(linea)
                except Exception:
                    continue
                self._orden(pedido)
                if self.m is None:
                    break
        except OSError:
            pass
        # se cortó player.py: no queda nadie para manejarla
        if self.cliente is c:
            self.terminar()

    def _abrir(self, url, opts):
        base = {"vo": "libmpv", "osc": "no", "input-default-bindings": "no", "input-vo-keyboard": "no",
                "osd-level": "0", "hwdec": "auto-safe", "ytdl": "yes", "keep-open": "yes",
                "terminal": "no", "config": "no"}
        base.update(opts)
        m = None
        for _ in range(12):
            try:
                m = _mpv.MPV(log_handler=_registro, loglevel="warn",
                             **{k.replace("-", "_"): v for k, v in base.items()})
                break
            except Exception as e:           # una mpv más vieja/nueva que no conoce alguna opción
                malo = next((a.decode() for a in (e.args[2] if len(e.args) > 2 else ())
                             if isinstance(a, bytes) and a.decode() in base), None)
                if not malo:
                    raise
                v = base.pop(malo)
                if malo in VIEJAS and VIEJAS[malo] not in base:
                    base[VIEJAS[malo]] = v
                sys.stderr.write(f"mpv: sin la opción {malo}\n")
        if m is None:
            raise RuntimeError("no se pudo configurar mpv")
        self.m = m
        self.cerrando = False

        @m.event_callback("shutdown")
        def _fin(_ev):
            threading.Thread(target=self.terminar, daemon=True).start()

        @m.event_callback("end-file")
        def _fin_archivo(ev):
            try:
                razon = ev.data.reason
            except Exception:
                razon = None
            sys.stderr.write(f"mpv: fin del archivo ({razon})\n")
            if razon == _mpv.MpvEventEndFile.ERROR:
                threading.Thread(target=self.terminar, daemon=True).start()

        # primero que exista el contexto de dibujo (lo crea el hilo de dibujo de Qt
        # cuando el video se hace visible); si mpv arranca antes, no tiene dónde dibujar
        self._ctx_listo = threading.Event()
        self._set_activo(True)
        self.cambio.emit()
        if not self._ctx_listo.wait(5):
            sys.stderr.write("mpv: el video no se dibujó a tiempo (¿ventana escondida?)\n")
        if url and self.m is m:
            m.play(url)

    def _orden(self, p):
        m = self.m
        args = p.get("command") or []
        if not m or not args:
            return
        nombre, resto = args[0], args[1:]
        try:
            if nombre == "observe_property":
                pid, prop = resto[0], resto[1]

                def aviso(name, value, pid=pid):
                    self._enviar({"event": "property-change", "id": pid, "name": name, "data": _a_json(value)})
                m.observe_property(prop, aviso)
            elif nombre == "set_property":
                k, v = resto[0], resto[1]
                m[k] = v
            elif nombre == "get_property":
                self._enviar({"request_id": p.get("request_id"), "error": "success", "data": _a_json(m[resto[0]])})
            elif nombre == "quit":
                self.terminar()
            else:
                m.command(nombre, *[_arg(a) for a in resto])
        except Exception as e:
            self._enviar({"request_id": p.get("request_id"), "error": str(e)[:120]})

    def terminar(self, esperar=False):
        """Cierra la película: primero el dibujo (en su hilo), después mpv."""
        with self.lock:
            m = self.m
            if m is None:
                return
            self.m = None
            self.cerrando = True
        if self.ctx is not None:
            hecho = threading.Event()
            self._al_soltar = hecho
            self.cambio.emit()                      # el hilo de dibujo suelta el contexto
            hecho.wait(3)
        self.ctx = None
        self._set_activo(False)                     # (recién ahora: escondido no se dibuja)
        try:
            m.terminate()
        except Exception:
            pass
        c, self.cliente = self.cliente, None
        if c:
            try:
                c.shutdown(socket.SHUT_RDWR)
                c.close()
            except OSError:
                pass

    # ── hilo de dibujo ──────────────────────────────────────────────────
    def dibujar(self, fbo, w, h):
        if self.cerrando and self.ctx is not None:
            try:
                self.ctx.free()
            except Exception:
                pass
            self.ctx = None
            ev = getattr(self, "_al_soltar", None)
            if ev:
                ev.set()
            return False
        m = self.m
        if m is None:
            return False
        if self.ctx is None:
            try:
                self.ctx = _mpv.MpvRenderContext(m, "opengl", opengl_init_params={"get_proc_address": _GPA})
            except Exception as e:           # (a veces el primer cuadro llega antes de tiempo)
                self._fallas = getattr(self, "_fallas", 0) + 1
                sys.stderr.write(f"render de mpv: {e} (intento {self._fallas})\n")
                if self._fallas < 20:
                    self.cambio.emit()
                return False
            self._fallas = 0
            self.ctx.update_cb = self.cambio.emit
            ev = getattr(self, "_ctx_listo", None)
            if ev:
                ev.set()
        self.ctx.render(flip_y=False, opengl_fbo={"w": w, "h": h, "fbo": fbo})
        return True


def _registro(nivel, modulo, texto):
    sys.stderr.write(f"mpv [{modulo}] {nivel}: {texto.rstrip()}\n")


ANFITRION: Anfitrion | None = None


def anfitrion() -> Anfitrion:
    global ANFITRION
    if ANFITRION is None:
        ANFITRION = Anfitrion()
    return ANFITRION


_FBOS = []


class _Dibujante(QQuickFramebufferObject.Renderer):
    def __init__(self):
        super().__init__()

    def createFramebufferObject(self, size):
        fmt = QOpenGLFramebufferObjectFormat()
        fmt.setAttachment(QOpenGLFramebufferObject.Attachment.CombinedDepthStencil)
        fbo = QOpenGLFramebufferObject(size, fmt)
        # Qt la borra cuando cambia el tamaño; Python no tiene que borrarla nunca
        # (si no, la libera antes de tiempo y se cae). Solo cambia al redimensionar.
        _FBOS.append(fbo)
        return fbo

    def render(self):
        fbo = self.framebufferObject()
        dibujo = anfitrion().dibujar(fbo.handle(), fbo.width(), fbo.height())
        if not dibujo:
            ctx = QOpenGLContext.currentContext()
            if ctx:
                gl = ctx.functions()
                gl.glClearColor(0, 0, 0, 1)
                gl.glClear(0x00004000)
        try:
            from PySide6.QtQuick import QQuickOpenGLUtils
            QQuickOpenGLUtils.resetOpenGLState()
        except Exception:
            pass


@QmlElement
class MpvVideo(QQuickFramebufferObject):
    """El video. Va abajo de todo; `activo` dice si hay una película cargada."""
    activoChanged = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        a = anfitrion()
        a.cambio.connect(self.update, Qt.ConnectionType.QueuedConnection)
        a.activoCambio.connect(self.activoChanged, Qt.ConnectionType.QueuedConnection)

    def createRenderer(self):
        # (que Python no lo borre: lo usa el hilo de dibujo de Qt)
        self._dibujante = _Dibujante()
        return self._dibujante

    @Property(bool, notify=activoChanged)
    def activo(self):
        return anfitrion().activo()

    @Slot()
    def detener(self):
        threading.Thread(target=anfitrion().terminar, daemon=True).start()
