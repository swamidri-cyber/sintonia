#!/usr/bin/env python3
"""rice-cine — puente entre el cine y la sesión del reproductor.

  player-link.py start '<json>'   arranca una película nueva (cierra la anterior)
  player-link.py attach           se engancha a la que esté andando, si hay
  player-link.py send <orden>     le manda una orden suelta (si hay sesión)

La película corre en player.py --serve, aparte del cine (systemd-run), así
que no se corta si el cine se cierra o se recarga: lo único que muere es
este puente. Hace de stdin/stdout de la sesión, igual que antes player.py.
Si no hay sesión, "attach" contesta {"ev":"none"} y termina.
"""
import os
import socket
import subprocess
import sys
import threading
import time

import lugares  # carpetas de SINTONÍA

HERE = os.path.dirname(os.path.abspath(__file__))
RUNTIME = lugares.RUNTIME
LINK = os.path.join(RUNTIME, "player.sock")
# lo que mpv y hyprctl necesitan del entorno gráfico
ENV = ("WAYLAND_DISPLAY", "DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "XDG_RUNTIME_DIR", "PATH",
       "XDG_CURRENT_DESKTOP", "DBUS_SESSION_BUS_ADDRESS")


def connect():
    s = socket.socket(socket.AF_UNIX)
    s.connect(LINK)
    return s


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
    cmd = ["systemd-run", "--user", "--quiet", "--collect", "-p", "KillMode=process",
           f"--unit=rice-cine-player-{int(time.time() * 1000)}"]
    cmd += [f"--setenv={k}={os.environ[k]}" for k in ENV if k in os.environ]
    cmd += [sys.executable, os.path.join(HERE, "player.py"), "--serve", job]
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for _ in range(100):
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
