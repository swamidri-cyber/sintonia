#!/usr/bin/env python3
"""SINTONÍA — lo que muestra CONFIGURACIÓN → SISTEMA / TELÉFONO.

  sistema.py estado          {"ip", "services": {stremio, web}, "casts": [...], "phones": n}
  sistema.py qr <texto> <archivo.svg>
"""
import json
import os
import socket
import sys
import urllib.request

import lugares


def ip():
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect(("10.255.255.255", 1))        # no manda nada: solo elige la placa de red
        return s.getsockname()[0]
    except OSError:
        return ""
    finally:
        s.close()


def up(url):
    try:
        urllib.request.urlopen(url, timeout=1.5)
        return True
    except Exception:
        return False


def leer(path, defecto):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return defecto


if __name__ == "__main__":
    c = sys.argv[1] if len(sys.argv) > 1 else "estado"
    if c == "estado":
        print(json.dumps({"ip": ip(),
                          "services": {"stremio": up("http://127.0.0.1:11470/settings"),
                                       "web": up("http://127.0.0.1:20130/")},
                          "casts": leer(os.path.join(lugares.CACHE, "casts.json"), []),
                          "phones": len(leer(os.path.join(lugares.STATE, "phones.json"), {}))}, ensure_ascii=False))
    elif c == "qr":
        import segno
        segno.make(sys.argv[2], error="m").save(sys.argv[3], kind="svg", scale=8, border=1, dark="#000", light="#fff")
