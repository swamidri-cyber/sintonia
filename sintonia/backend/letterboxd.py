#!/usr/bin/env python3
"""rice-cine — reseñas en Letterboxd (etapa 5).

Letterboxd no da su API a proyectos personales: esto usa TU sesión de
Letterboxd en Zen (las cookies se leen en el momento de una copia temporal que
se borra enseguida; no se guardan) y carga la entrada de diario igual que el
formulario "Log" de la web.

  letterboxd.py check <tt…>        quién sos y qué película es (no publica nada)
  letterboxd.py log <tt…> <estrellas 0-10> <like 0|1> <volví a verla 0|1> <spoilers 0|1> [reseña]
      fecha = hoy. PUBLICA en tu perfil.

Siempre imprime UN JSON.
"""
import datetime
import glob
import http.cookiejar
import json
import os
import re
import shutil
import sqlite3
import sys
import tempfile
import urllib.parse
import urllib.request

import lugares  # carpetas de SINTONÍA

HOME = os.path.expanduser("~")
BASE = "https://letterboxd.com"


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))


def zen_ua():
    """El mismo navegador que tus cookies (Cloudflare mira que coincida)."""
    ver = "156.0"
    for ini in glob.glob("/opt/zen*/platform.ini") + glob.glob("/usr/lib/zen*/platform.ini"):
        m = re.search(r"^Milestone=(\d+)", open(ini).read(), re.M)
        if m:
            ver = m.group(1) + ".0"
    return f"Mozilla/5.0 (X11; Linux x86_64; rv:{ver}) Gecko/20100101 Firefox/{ver}"


def opener():
    profs = glob.glob(HOME + "/.config/zen/*/cookies.sqlite") + glob.glob(HOME + "/.zen/*/cookies.sqlite")
    if not profs:
        raise RuntimeError("no encontré el perfil de Zen")
    src = max(profs, key=os.path.getsize)
    jar = http.cookiejar.CookieJar()
    with tempfile.TemporaryDirectory(dir=lugares.RUNTIME) as tmp:
        dst = os.path.join(tmp, "c.sqlite")
        shutil.copy(src, dst)
        for ext in ("-wal", "-shm"):
            if os.path.exists(src + ext):
                shutil.copy(src + ext, dst + ext)
        db = sqlite3.connect(dst)
        rows = db.execute("select name, value, host, path, isSecure, expiry from moz_cookies "
                          "where host like '%letterboxd.com'").fetchall()
        db.close()
    for name, value, host, path, secure, expiry in rows:
        exp = int(expiry) if expiry else None
        if exp and exp > 10 ** 11:
            exp //= 1000
        jar.set_cookie(http.cookiejar.Cookie(0, name, value, None, False, host, True, host.startswith("."),
                                             path or "/", True, bool(secure), exp, False, None, None, {}))
    op = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(jar))
    op.addheaders = [("User-Agent", zen_ua()), ("Accept-Language", "es-AR,es;q=0.9,en;q=0.7")]
    return op, jar


def film(op, imdb):
    with op.open(f"{BASE}/imdb/{imdb}/", timeout=25) as r:
        html = r.read().decode("utf-8", "replace")
        url = r.geturl()
    user = re.search(r'person\.username\s*=\s*"([^"]*)"', html)
    uid = re.search(r"data\.viewingable\.uid\s*=\s*'(film:\d+)'", html)
    csrf = re.search(r"supermodelCSRF\s*=\s*['\"]([^'\"]+)", html) or re.search(r'name="__csrf"\s+value="([^"]+)"', html)
    name = re.search(r'data-item-full-display-name="([^"]+)"', html)
    if not uid:
        raise RuntimeError("Letterboxd no tiene esa película")
    return {"user": user.group(1) if user and user.group(1) else None, "uid": uid.group(1), "url": url,
            "name": name.group(1) if name else "", "csrf": csrf.group(1) if csrf else ""}


def cmd_check(imdb):
    op, _ = opener()
    f = film(op, imdb)
    if not f["user"]:
        return out({"error": "nologin"})
    out({"user": f["user"], "film": f["name"], "url": f["url"]})


def cmd_log(imdb, rating, liked, rewatch, spoilers, review=""):
    review = review.strip()
    op, jar = opener()
    f = film(op, imdb)
    if not f["user"]:
        return out({"error": "nologin"})
    # el token tiene que coincidir con la cookie que Letterboxd acaba de dar
    csrf = next((c.value for c in jar if c.name == "com.xk72.webparts.csrf"), f["csrf"])
    form = [("__csrf", csrf), ("json", "true"), ("viewingId", ""), ("viewingableUid", f["uid"]),
            ("specifiedDate", "true"), ("viewingDateStr", datetime.date.today().isoformat()),
            ("review", review), ("tags", ""), ("rating", str(max(0, min(10, int(rating)))))]
    if liked == "1":
        form.append(("liked", "true"))
    if rewatch == "1":
        form.append(("rewatch", "true"))
    if spoilers == "1":
        form.append(("containsSpoilers", "true"))
    req = urllib.request.Request(f"{BASE}/s/save-diary-entry", data=urllib.parse.urlencode(form).encode(),
                                 headers={"Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
                                          "X-Requested-With": "XMLHttpRequest", "Origin": BASE, "Referer": f["url"],
                                          "Accept": "application/json, text/javascript, */*; q=0.01"})
    with op.open(req, timeout=25) as r:
        body = r.read().decode("utf-8", "replace")
    try:
        res = json.loads(body)
    except Exception:
        return out({"error": "respuesta rara de Letterboxd", "body": body[:200]})
    if res.get("result") is False or res.get("errorCodes") or res.get("messages") and not res.get("result"):
        return out({"error": "; ".join(res.get("messages") or res.get("errorCodes") or ["no se pudo"])})
    out({"ok": True, "user": f["user"], "film": f["name"], "url": f["url"]})


if __name__ == "__main__":
    a = sys.argv[1:]
    try:
        {"check": cmd_check, "log": cmd_log}[a[0]](*a[1:])
    except urllib.error.HTTPError as e:
        out({"error": f"Letterboxd respondió {e.code}"})
    except Exception as e:
        out({"error": str(e)[:200]})
