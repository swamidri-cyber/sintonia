"""Dónde guarda cada cosa SINTONÍA, en Linux y en Windows.

  CONFIG   ajustes del usuario (settings.json, sesiones de cuentas)
  ESTADO   lo que la app recuerda (búsquedas, origen de cada título, progreso pendiente)
  CACHE    catálogos, fichas e imágenes bajadas (se puede borrar)
  RUNTIME  sockets y archivos de la sesión actual (se borran al reiniciar)

Los scripts de backend/ reciben estas carpetas por variables de entorno
(SINTONIA_CONFIG, …), así no dependen de dónde esté instalada la app.
"""
from __future__ import annotations

import os
import sys
import tempfile

ES_WINDOWS = sys.platform.startswith("win")
EMPAQUETADA = bool(getattr(sys, "frozen", False))

if EMPAQUETADA:
    DATOS = os.path.join(getattr(sys, "_MEIPASS", os.path.dirname(sys.executable)), "sintonia")
else:
    DATOS = os.path.dirname(os.path.abspath(__file__))
BACKEND = os.path.join(DATOS, "backend")

HOME = os.path.expanduser("~")
if ES_WINDOWS:
    _roaming = os.environ.get("APPDATA") or os.path.join(HOME, "AppData", "Roaming")
    _local = os.environ.get("LOCALAPPDATA") or os.path.join(HOME, "AppData", "Local")
    CONFIG = os.path.join(_roaming, "Sintonia")
    ESTADO = os.path.join(_local, "Sintonia", "estado")
    CACHE = os.path.join(_local, "Sintonia", "cache")
    RUNTIME = os.path.join(tempfile.gettempdir(), "sintonia-" + os.environ.get("USERNAME", "usuario"))
    DATOS_USUARIO = os.path.join(_local, "Sintonia", "datos")
else:
    CONFIG = os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "sintonia")
    ESTADO = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state"), "sintonia")
    CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache"), "sintonia")
    _rt = os.environ.get("XDG_RUNTIME_DIR")
    RUNTIME = os.path.join(_rt, "sintonia") if _rt else os.path.join(tempfile.gettempdir(), f"sintonia-{os.getuid()}")
    DATOS_USUARIO = os.path.join(os.environ.get("XDG_DATA_HOME") or os.path.join(HOME, ".local", "share"), "sintonia")

for _d in (CONFIG, ESTADO, CACHE, RUNTIME, DATOS_USUARIO):
    os.makedirs(_d, exist_ok=True)
if not ES_WINDOWS:
    os.chmod(RUNTIME, 0o700)


def entorno() -> dict[str, str]:
    e = dict(os.environ)
    e.setdefault("HOME", HOME)
    e.setdefault("XDG_RUNTIME_DIR", RUNTIME)
    return e


def entorno_backend() -> dict[str, str]:
    return {
        "SINTONIA_CONFIG": CONFIG,
        "SINTONIA_STATE": ESTADO,
        "SINTONIA_CACHE": CACHE,
        "SINTONIA_RUNTIME": RUNTIME,
        "SINTONIA_DATA": DATOS,
        "SINTONIA_DATA_USER": DATOS_USUARIO,
        "PYTHONIOENCODING": "utf-8",
        "PYTHONUTF8": "1",
        "PYTHONUNBUFFERED": "1",
        "SINTONIA_FROZEN": "1" if EMPAQUETADA else "0",
    }


def comando_python(script: str) -> list[str]:
    """Cómo correr un script de backend/: con el Python de la app, o (empaquetada)
    con el mismo ejecutable en modo --script."""
    if not os.path.isabs(script):
        script = os.path.join(BACKEND, script)
    if EMPAQUETADA:
        return [sys.executable, "--script", script]
    return [sys.executable, script]


def escribir(path: str, texto: str) -> None:
    """Escribe de una (archivo temporal + reemplazo), creando las carpetas."""
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(texto)
    os.replace(tmp, path)
