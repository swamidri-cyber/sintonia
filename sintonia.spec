# PyInstaller — SINTONÍA (Linux y Windows).  pyinstaller --noconfirm sintonia.spec
# Sale en dist/Sintonia/ (una carpeta con el ejecutable "Sintonia").
import ast
import glob
import os
import sys

from PyInstaller.utils.hooks import collect_all

ES_WIN = sys.platform.startswith("win")
RAIZ = os.path.abspath(os.getcwd())
APP = os.path.join(RAIZ, "sintonia")

datas = [(os.path.join(APP, d), "sintonia/" + d) for d in ("qml", "shaders", "sfx", "fonts", "backend")]
datas += [(os.path.join(APP, "icono.png"), "sintonia"), (os.path.join(APP, "icono.svg"), "sintonia")]
binaries = []
hidden = ["mpv", "PySide6.QtWebEngineQuick", "PySide6.QtWebEngineCore", "PySide6.QtMultimedia",
          "PySide6.QtQuick", "PySide6.QtOpenGL", "PySide6.QtNetwork", "PySide6.QtQml"]

# los scripts de backend/ corren con el Python de la app (--script): que viaje
# todo lo que importan (la biblioteca estándar y los paquetes de terceros)
locales = {os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(APP, "backend", "*.py"))}
for p in glob.glob(os.path.join(APP, "backend", "*.py")):
    try:
        arbol = ast.parse(open(p, encoding="utf-8").read())
    except SyntaxError:
        continue
    for n in ast.walk(arbol):
        if isinstance(n, ast.Import):
            nombres = [a.name for a in n.names]
        elif isinstance(n, ast.ImportFrom) and n.module and not n.level:
            nombres = [n.module]
        else:
            continue
        solo_otro = {"fcntl", "termios"} if ES_WIN else {"msvcrt", "winreg"}
        for m in nombres:
            base = m.split(".")[0]
            if base not in locales and base not in solo_otro:
                hidden.append(m)

for paquete in ("pychromecast", "zeroconf", "casttube", "yt_dlp", "segno", "sdl2", "sdl2dll", "webrtcvad", "numpy"):
    try:
        d, b, h = collect_all(paquete)
        datas += d
        binaries += b
        hidden += h
    except Exception as e:      # noqa: BLE001
        print("sin", paquete, e)

# libmpv: en Linux la del sistema donde se arma; en Windows libmpv-2.dll al lado del .spec
if ES_WIN:
    for dll in glob.glob(os.path.join(RAIZ, "libmpv-2.dll")):
        binaries.append((dll, "."))
else:
    for so in ("/usr/lib/x86_64-linux-gnu/libmpv.so.2", "/usr/lib/libmpv.so.2", "/usr/lib64/libmpv.so.2"):
        if os.path.exists(so):
            binaries.append((so, "."))
            break

a = Analysis(
    [os.path.join(RAIZ, "lanzador.py")],
    pathex=[RAIZ],
    binaries=binaries,
    datas=datas,
    hiddenimports=sorted(set(hidden)),
    excludes=["tkinter", "PySide6.Qt3DCore", "PySide6.QtCharts", "PySide6.QtDataVisualization",
              "PySide6.QtGraphs", "PySide6.QtQuick3D", "PySide6.QtDesigner", "PySide6.QtPdf"],
    noarchive=False,
)
pyz = PYZ(a.pure)
exe = EXE(
    pyz, a.scripts, [],
    exclude_binaries=True,
    name="Sintonia",
    console=False,
    icon=os.path.join(APP, "icono.ico") if ES_WIN else None,
)
coll = COLLECT(exe, a.binaries, a.datas, strip=False, upx=False, name="Sintonia")
