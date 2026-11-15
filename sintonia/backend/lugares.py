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
for _d in (CONFIG, STATE, CACHE, RUNTIME):
    os.makedirs(_d, exist_ok=True)
