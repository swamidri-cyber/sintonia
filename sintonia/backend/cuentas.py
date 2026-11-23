"""SINTONÍA — las cuentas (Stremio, Letterboxd).

Todo vive en la carpeta de ajustes, solo para el usuario:

  cuentas/stremio.json        {"authKey", "email", "addons": [...], "addonsTs"}
  cuentas/letterboxd.txt      cookies
  cuentas/navegador.json      {"ua": …} el navegador de la app (Cloudflare mira que coincida)

Las cookies las escribe la ventana de inicio de sesión de la app (sintonia/
navegador.py). Si no hay, en Linux se usa la sesión de Zen/Firefox como antes.
"""
import glob
import http.cookiejar
import json
import os
import re
import shutil
import sqlite3
import tempfile

import lugares

DIR = os.path.join(lugares.CONFIG, "cuentas")
os.makedirs(DIR, exist_ok=True)
try:
    os.chmod(DIR, 0o700)
except OSError:
    pass
HOME = os.path.expanduser("~")
UA_CHROME = ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) "
             "Chrome/134.0.0.0 Safari/537.36")


def ruta(nombre):
    return os.path.join(DIR, nombre)


def leer_json(nombre, defecto=None):
    try:
        with open(ruta(nombre), encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return defecto


def escribir_json(nombre, obj):
    p = ruta(nombre)
    tmp = p + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(obj, f, ensure_ascii=False)
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.replace(tmp, p)


def borrar(nombre):
    try:
        os.unlink(ruta(nombre))
    except OSError:
        pass


# ── Navegador ───────────────────────────────────────────────────────────────
def ua():
    return (leer_json("navegador.json") or {}).get("ua") or UA_CHROME


def archivo_cookies(servicio):
    """Archivo de cookies de la app para el servicio, o None."""
    p = ruta(servicio + ".txt")
    return p if os.path.exists(p) and os.path.getsize(p) > 0 else None


def jar_app(servicio):
    p = archivo_cookies(servicio)
    if not p:
        return None
    jar = http.cookiejar.MozillaCookieJar()
    try:
        jar.load(p, ignore_discard=True, ignore_expires=True)
    except Exception:
        return None
    return jar


# ── Zen / Firefox (lo de antes, solo Linux) ────────────────────────────────
def perfil_firefox():
    profs = (glob.glob(HOME + "/.config/zen/*/cookies.sqlite") + glob.glob(HOME + "/.zen/*/cookies.sqlite")
             + glob.glob(HOME + "/.mozilla/firefox/*/cookies.sqlite"))
    if not profs:
        return None
    return max(profs, key=os.path.getsize)


def jar_firefox(dominio):
    src = perfil_firefox()
    if not src:
        return None
    jar = http.cookiejar.CookieJar()
    with tempfile.TemporaryDirectory(dir=lugares.RUNTIME) as tmp:
        dst = os.path.join(tmp, "c.sqlite")
        shutil.copy(src, dst)
        for ext in ("-wal", "-shm"):
            if os.path.exists(src + ext):
                shutil.copy(src + ext, dst + ext)
        db = sqlite3.connect(dst)
        rows = db.execute("select name, value, host, path, isSecure, expiry from moz_cookies "
                          "where host like ?", ("%" + dominio,)).fetchall()
        db.close()
    for name, value, host, path, secure, expiry in rows:
        exp = int(expiry) if expiry else None
        if exp and exp > 10 ** 11:
            exp //= 1000
        jar.set_cookie(http.cookiejar.Cookie(0, name, value, None, False, host, True, host.startswith("."),
                                             path or "/", True, bool(secure), exp, False, None, None, {}))
    return jar


def ua_firefox():
    ver = "150.0"
    for ini in glob.glob("/opt/zen*/platform.ini") + glob.glob("/usr/lib/zen*/platform.ini") + \
            glob.glob("/usr/lib/firefox/platform.ini"):
        m = re.search(r"^Milestone=(\d+)", open(ini).read(), re.M)
        if m:
            ver = m.group(1) + ".0"
    return f"Mozilla/5.0 (X11; Linux x86_64; rv:{ver}) Gecko/20100101 Firefox/{ver}"


def sesion_web(servicio, dominio):
    """→ (cookiejar, user-agent) de la app; si no hay, de Zen/Firefox; si no, (None, ua)."""
    jar = jar_app(servicio)
    if jar is not None:
        return jar, ua()
    if os.name != "nt" and os.environ.get("SINTONIA_SIN_FIREFOX") != "1":
        try:
            jar = jar_firefox(dominio)
        except Exception:
            jar = None
        if jar is not None and len(jar):
            return jar, ua_firefox()
    return None, ua()


def estado():
    """Para la pantalla de cuentas: quién está conectado en cada servicio."""
    st = leer_json("stremio.json") or {}
    nav = leer_json("navegador.json") or {}
    return {
        "stremio": {"ok": bool(st.get("authKey")), "user": st.get("email", "")},
        "letterboxd": {"ok": bool(archivo_cookies("letterboxd")), "user": (nav.get("usuarios") or {}).get("letterboxd", "")},
    }


if __name__ == "__main__":
    import sys
    a = sys.argv[1:]
    if a[:1] == ["estado"]:
        print(json.dumps(estado(), ensure_ascii=False))
    elif a[:1] == ["salir"] and len(a) > 1:
        if a[1] == "stremio":
            borrar("stremio.json")
        else:
            borrar(a[1] + ".txt")
            nav = leer_json("navegador.json") or {}
            (nav.get("usuarios") or {}).pop(a[1], None)
            escribir_json("navegador.json", nav)
        print(json.dumps(estado(), ensure_ascii=False))
