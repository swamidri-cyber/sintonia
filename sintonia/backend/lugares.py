"""Carpetas de SINTONÍA para los scripts de datos.

La app las pasa por variables de entorno (ver sintonia/rutas.py); si un
script se corre a mano, se usan las mismas carpetas por defecto.
"""
import os
import sys
import tempfile

_WIN = sys.platform.startswith("win")
_HOME = os.path.expanduser("~")


def _defecto(clave):
    if _WIN:
        local = os.environ.get("LOCALAPPDATA") or os.path.join(_HOME, "AppData", "Local")
        roaming = os.environ.get("APPDATA") or os.path.join(_HOME, "AppData", "Roaming")
        return {"config": os.path.join(roaming, "Sintonia"),
                "state": os.path.join(local, "Sintonia", "estado"),
                "cache": os.path.join(local, "Sintonia", "cache"),
                "runtime": os.path.join(tempfile.gettempdir(), "sintonia-" + os.environ.get("USERNAME", "usuario"))}[clave]
    xdg = {"config": ("XDG_CONFIG_HOME", ".config"), "state": ("XDG_STATE_HOME", ".local/state"),
           "cache": ("XDG_CACHE_HOME", ".cache")}
    if clave == "runtime":
        rt = os.environ.get("XDG_RUNTIME_DIR")
        return os.path.join(rt, "sintonia") if rt else os.path.join(tempfile.gettempdir(), f"sintonia-{os.getuid()}")
    var, rel = xdg[clave]
    return os.path.join(os.environ.get(var) or os.path.join(_HOME, rel), "sintonia")


CONFIG = os.environ.get("SINTONIA_CONFIG") or _defecto("config")
STATE = os.environ.get("SINTONIA_STATE") or _defecto("state")
CACHE = os.environ.get("SINTONIA_CACHE") or _defecto("cache")
RUNTIME = os.environ.get("SINTONIA_RUNTIME") or _defecto("runtime")
DATA = os.environ.get("SINTONIA_DATA") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FONTS = os.path.join(DATA, "fonts")
if _WIN:
    _du = os.path.join(os.environ.get("LOCALAPPDATA") or os.path.join(_HOME, "AppData", "Local"), "Sintonia", "datos")
else:
    _du = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(_HOME, ".local", "share"), "sintonia")
DATA_USER = os.environ.get("SINTONIA_DATA_USER") or _du     # cuentas del navegador, servidor de Stremio
for _d in (CONFIG, STATE, CACHE, RUNTIME, DATA_USER):
    os.makedirs(_d, exist_ok=True)


def python(script):
    """Cómo correr otro script de backend/ (en la app empaquetada, el mismo .exe)."""
    if not os.path.isabs(script):
        script = os.path.join(os.path.dirname(os.path.abspath(__file__)), script)
    if os.environ.get("SINTONIA_FROZEN") == "1":
        return [sys.executable, "--script", script]
    return [sys.executable, script]


def separado():
    """Argumentos de Popen para que un proceso siga aunque se cierre quien lo lanzó."""
    if _WIN:
        return {"creationflags": 0x00000008 | 0x00000200 | 0x08000000}   # DETACHED | NEW_GROUP | NO_WINDOW
    return {"start_new_session": True}
