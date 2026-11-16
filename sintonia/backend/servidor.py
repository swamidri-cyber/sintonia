#!/usr/bin/env python3
"""SINTONÍA — el servidor de Stremio (el que convierte torrents en video).

No viene adentro de la app: la primera vez que se reproduce algo se baja,
igual que hace la app oficial de Stremio:
  · Node.js (nodejs.org, versión LTS, verificado con su SHA-256)
  · server.js (dl.strem.io)
Quedan en <datos>/stremio/ y se usan siempre desde ahí.

  servidor.py instalar      baja lo que falte (imprime el progreso)
  servidor.py estado        {"node": bool, "server": bool}
"""
import hashlib
import io
import json
import os
import platform
import shutil
import sys
import tarfile
import tempfile
import urllib.request
import zipfile

import lugares

DIR = os.path.join(lugares.DATA_USER, "stremio")
NODE_VER = "v20.18.1"
SERVER_VERS = ["v4.20.19", "v4.20.18", "v4.20.17", "v4.20.12"]
ES_WIN = os.name == "nt"
NODE = os.path.join(DIR, "node.exe" if ES_WIN else "node")
SERVER = os.path.join(DIR, "server.js")
UA = {"User-Agent": "Mozilla/5.0 Sintonia"}


def _bajar(url, aviso=None, timeout=60):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        total = int(r.headers.get("Content-Length") or 0)
        buf = io.BytesIO()
        hecho = 0
        while True:
            b = r.read(1 << 16)
            if not b:
                break
            buf.write(b)
            hecho += len(b)
            if aviso and total:
                aviso(hecho, total)
        return buf.getvalue()


def _arch():
    m = platform.machine().lower()
    return "arm64" if m in ("arm64", "aarch64") else "x64"


def instalar_node(aviso=None):
    if os.path.exists(NODE):
        return True
    os.makedirs(DIR, exist_ok=True)
    nombre = f"node-{NODE_VER}-{'win' if ES_WIN else 'linux'}-{_arch()}"
    arch = nombre + (".zip" if ES_WIN else ".tar.xz")
    base = f"https://nodejs.org/dist/{NODE_VER}/"
    sumas = _bajar(base + "SHASUMS256.txt").decode()
    esperado = next((l.split()[0] for l in sumas.splitlines() if l.endswith("  " + arch)), None)
    datos = _bajar(base + arch, aviso)
    if not esperado or hashlib.sha256(datos).hexdigest() != esperado:
        raise RuntimeError("Node.js bajó mal (no coincide la firma)")
    tmp = NODE + ".tmp"
    if ES_WIN:
        with zipfile.ZipFile(io.BytesIO(datos)) as z, open(tmp, "wb") as f:
            f.write(z.read(f"{nombre}/node.exe"))
    else:
        with tarfile.open(fileobj=io.BytesIO(datos), mode="r:xz") as t, open(tmp, "wb") as f:
            f.write(t.extractfile(f"{nombre}/bin/node").read())
        os.chmod(tmp, 0o755)
    os.replace(tmp, NODE)
    return True


def instalar_server(aviso=None):
    if os.path.exists(SERVER):
        return True
    os.makedirs(DIR, exist_ok=True)
    ultimo = None
    for v in SERVER_VERS:
        try:
            datos = _bajar(f"https://dl.strem.io/server/{v}/desktop/server.js", aviso)
        except Exception as e:
            ultimo = e
            continue
        if len(datos) > 1_000_000 and b"webpack" in datos[:2000]:
            tmp = SERVER + ".tmp"
            with open(tmp, "wb") as f:
                f.write(datos)
            os.replace(tmp, SERVER)
            with open(os.path.join(DIR, "version.txt"), "w") as f:
                f.write(v)
            return True
    raise RuntimeError(f"no pude bajar el servidor de Stremio ({ultimo})")


def instalar(avisar=print):
    def aviso(qué):
        ult = [-1]

        def f(h, t):
            p = int(h * 100 / t)
            if p // 10 != ult[0] // 10:
                ult[0] = p
                avisar(f"{qué}… {p} %")
        return f
    instalar_node(aviso("BAJANDO NODE.JS"))
    instalar_server(aviso("BAJANDO EL SERVIDOR DE STREMIO"))
    return [NODE, SERVER]


# ── ffmpeg / ffprobe (mirar las pistas, sincronizar subtítulos, la tele) ────
FF_DIR = os.path.join(lugares.DATA_USER, "ffmpeg")
FF_URL = ("https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/"
          + ("ffmpeg-master-latest-win64-gpl.zip" if ES_WIN else "ffmpeg-master-latest-linux64-gpl.tar.xz"))


def ffmpeg(nombre="ffmpeg", avisar=None):
    """Ruta de ffmpeg o ffprobe: el del sistema si hay; si no, el que baja la app."""
    sis = shutil.which(nombre)
    if sis:
        return sis
    exe = os.path.join(FF_DIR, nombre + (".exe" if ES_WIN else ""))
    if os.path.exists(exe):
        return exe
    os.makedirs(FF_DIR, exist_ok=True)
    if avisar:
        avisar("BAJANDO FFMPEG (SOLO LA PRIMERA VEZ)…")
    datos = _bajar(FF_URL, timeout=120)
    quiero = {"ffmpeg", "ffprobe"}
    if ES_WIN:
        with zipfile.ZipFile(io.BytesIO(datos)) as z:
            for n in z.namelist():
                b = os.path.basename(n)
                if b in ("ffmpeg.exe", "ffprobe.exe"):
                    with open(os.path.join(FF_DIR, b), "wb") as f:
                        f.write(z.read(n))
    else:
        with tarfile.open(fileobj=io.BytesIO(datos), mode="r:xz") as t:
            for m in t.getmembers():
                b = os.path.basename(m.name)
                if b in quiero and m.isfile():
                    dst = os.path.join(FF_DIR, b)
                    with open(dst, "wb") as f:
                        f.write(t.extractfile(m).read())
                    os.chmod(dst, 0o755)
    if not os.path.exists(exe):
        raise RuntimeError("no pude bajar " + nombre)
    return exe


def listo():
    return os.path.exists(NODE) and os.path.exists(SERVER)


if __name__ == "__main__":
    a = sys.argv[1:] or ["estado"]
    if a[0] == "instalar":
        instalar()
        print("listo")
    else:
        print(json.dumps({"node": os.path.exists(NODE), "server": os.path.exists(SERVER)}))
