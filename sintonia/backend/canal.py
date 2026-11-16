"""SINTONÍA — canales locales entre las partes de la app (igual en Linux y Windows).

  escuchar("player")  → socket que acepta conexiones
  conectar("player")  → socket conectado (OSError si no hay nadie)
  cerrar("player")    → borra el rastro (al terminar)

En Linux es un socket de archivo en la carpeta de la sesión. Windows no tiene
de esos en Python: ahí es TCP en 127.0.0.1 con un puerto al azar, anotado en
un archivo de la misma carpeta (solo lo puede leer el usuario).
"""
import os
import socket

import lugares

ES_WINDOWS = os.name == "nt"


def _ruta(nombre):
    return os.path.join(lugares.RUNTIME, nombre + (".port" if ES_WINDOWS else ".sock"))


def escuchar(nombre, cola=8):
    ruta = _ruta(nombre)
    cerrar(nombre)
    if ES_WINDOWS:
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.bind(("127.0.0.1", 0))
        s.listen(cola)
        tmp = ruta + ".tmp"
        with open(tmp, "w") as f:
            f.write(str(s.getsockname()[1]))
        os.replace(tmp, ruta)
        return s
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(ruta)
    s.listen(cola)
    return s


def conectar(nombre, timeout=None):
    ruta = _ruta(nombre)
    if ES_WINDOWS:
        try:
            puerto = int(open(ruta).read().strip())
        except (OSError, ValueError):
            raise ConnectionRefusedError(nombre)
        s = socket.create_connection(("127.0.0.1", puerto), timeout=timeout or 5)
        s.settimeout(None)
        return s
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    if timeout:
        s.settimeout(timeout)
    s.connect(ruta)
    s.settimeout(None)
    return s


def cerrar(nombre):
    try:
        os.unlink(_ruta(nombre))
    except OSError:
        pass


def existe(nombre):
    return os.path.exists(_ruta(nombre))
