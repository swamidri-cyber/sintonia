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
import urllib.error
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


def film_json(op, url):
    """Ficha de la película (lid, uid, csrf), la misma que pide el formulario de la web."""
    req = urllib.request.Request(url.rstrip("/") + "/json/", headers={
        "X-Requested-With": "XMLHttpRequest", "Accept": "application/json", "Referer": url})
    with op.open(req, timeout=25) as r:
        return json.loads(r.read().decode("utf-8", "replace"))


def cmd_log(imdb, rating, liked, rewatch, spoilers, review=""):
    # Desde 2026 la web guarda el diario por su API (/api/v0/production-log-entries);
    # la vieja /s/save-diary-entry devuelve 404.
    review = review.strip()
    op, jar = opener()
    f = film(op, imdb)
    if not f["user"]:
        return out({"error": "nologin"})
    fj = film_json(op, f["url"])
    csrf = fj.get("csrf") or f["csrf"]
    stars = max(0, min(10, int(rating)))
    body = {"productionId": fj["lid"],
            "diaryDetails": {"diaryDate": datetime.date.today().isoformat(), "rewatch": rewatch == "1"},
            "tags": [], "like": liked == "1"}
    if review:
        body["review"] = {"text": review, "containsSpoilers": spoilers == "1"}
    if stars:
        body["rating"] = stars / 2
    req = urllib.request.Request(f"{BASE}/api/v0/production-log-entries", data=json.dumps(body).encode(),
                                 method="POST",
                                 headers={"Content-Type": "application/json; charset=UTF-8",
                                          "Accept": "application/json", "X-CSRF-TOKEN": csrf,
                                          "Origin": BASE, "Referer": f["url"]})
    try:
        with op.open(req, timeout=25) as r:
            text = r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        text = e.read().decode("utf-8", "replace")
        try:
            res = json.loads(text)
        except Exception:
            return out({"error": f"Letterboxd respondió {e.code}"})
        msgs = [m.get("title") or m.get("message") or m.get("code") for m in res.get("messages", []) if isinstance(m, dict)]
        return out({"error": "; ".join(x for x in msgs if x) or res.get("message") or f"Letterboxd respondió {e.code}"})
    try:
        res = json.loads(text)
    except Exception:
        return out({"error": "respuesta rara de Letterboxd", "body": text[:200]})
    errs = [m for m in res.get("messages", []) if isinstance(m, dict) and m.get("type") == "Error"]
    if errs or not res.get("logEntry"):
        return out({"error": "; ".join(m.get("title") or m.get("code") or "" for m in errs) or "no se pudo"})
    out({"ok": True, "user": f["user"], "film": f["name"], "url": f["url"]})


if __name__ == "__main__":
    a = sys.argv[1:]
    try:
        {"check": cmd_check, "log": cmd_log}[a[0]](*a[1:])
    except urllib.error.HTTPError as e:
        out({"error": f"Letterboxd respondió {e.code}"})
    except Exception as e:
        out({"error": str(e)[:200]})
