#!/usr/bin/env python3
"""rice-cine — puente entre el cine y la sesión del reproductor.

  player-link.py start '<json>'   arranca una película nueva (cierra la anterior)
  player-link.py attach           se engancha a la que esté andando, si hay
  player-link.py send <orden>     le manda una orden suelta (si hay sesión)

La película corre en player.py --serve, en un proceso aparte, así que la
búsqueda de fuentes no se corta si se recarga la interfaz: lo único que
muere es este puente. Hace de stdin/stdout de la sesión, igual que antes player.py.
Si no hay sesión, "attach" contesta {"ev":"none"} y termina.
"""
import os
import socket
import subprocess
import sys
import threading
import time

import lugares  # carpetas de SINTONÍA
import canal

HERE = os.path.dirname(os.path.abspath(__file__))
RUNTIME = lugares.RUNTIME


def connect():
    return canal.conectar("player", timeout=3)


def start(job):
    # había otra película andando: cerrarla (guarda su progreso al salir)
    try:
        old = connect()
        old.sendall(b"quit\n")
        old.settimeout(15)
        while old.recv(65536):
            pass
        old.close()
    except OSError:
        pass
    canal.cerrar("player")
    log = open(os.path.join(RUNTIME, "player.log"), "ab")
    subprocess.Popen(lugares.python("player.py") + ["--serve", job], stdout=log, stderr=log,
                     stdin=subprocess.DEVNULL, **lugares.separado())
    for _ in range(150):
        try:
            return connect()
        except OSError:
            time.sleep(0.1)
    print('{"ev":"error","msg":"No arrancó el reproductor"}', flush=True)
    sys.exit(1)


def bridge(s):
    def up():
        for line in sys.stdin:
            try:
                s.sendall(line.encode())
            except OSError:
                break
    threading.Thread(target=up, daemon=True).start()
    while True:
        try:
            chunk = s.recv(65536)
        except OSError:
            break
        if not chunk:
            break
        sys.stdout.buffer.write(chunk)
        sys.stdout.flush()


if __name__ == "__main__":
    if sys.argv[1] == "send":
        try:
            s = connect()
            s.sendall((" ".join(sys.argv[2:]) + "\n").encode())
            time.sleep(0.2)
            s.close()
        except OSError:
            pass
        sys.exit(0)
    if sys.argv[1] == "attach":
        try:
            s = connect()
        except OSError:
            print('{"ev":"none"}', flush=True)
            sys.exit(0)
    else:
        s = start(sys.argv[2])
    bridge(s)
