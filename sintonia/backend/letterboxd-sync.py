#!/usr/bin/env python3
"""rice-cine — tu watchlist de Letterboxd → Mi lista del cine (Stremio).

Corre cada 15 min (rice-cine-lbsync.timer) y al abrir el cine.
  · Lo nuevo en la watchlist se agrega a Mi lista.
  · Lo que sale de la watchlist (la sacaste o la marcaste vista) sale de Mi lista.
  · Lo que saques a mano de Mi lista no vuelve, salvo que lo vuelvas a agregar
    en Letterboxd (solo se mira lo que CAMBIA en la watchlist).
Si algo falla (sin internet, sin sesión, página rara) no toca nada.

  letterboxd-sync.py            sincronizar
  letterboxd-sync.py --seed     solo anotar la watchlist actual, sin tocar Mi lista
"""
import contextlib
import time
import html
import io
import json
import os
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import letterboxd as L  # noqa: E402
import stremio as S  # noqa: E402

import lugares  # carpetas de SINTONÍA

STATE = os.path.join(lugares.STATE, "letterboxd-sync.json")
# la watchlist tal cual, para la pestaña LETTERBOXD del cine (más nueva primero)
EXPORT = os.path.join(lugares.STATE, "letterboxd-watchlist.json")
USER = ""                   # el de tu sesión de Letterboxd (se averigua al arrancar)


def log(*a):
    print(*a, file=sys.stderr, flush=True)


def load_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except Exception:
        return None


def save_state(st):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    tmp = STATE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(st, f, ensure_ascii=False, indent=1)
    os.replace(tmp, STATE)


def watchlist(op):
    """Slugs de la watchlist, de la más nueva a la más vieja. None si algo salió raro."""
    slugs, p = [], 1
    names = {}
    while p < 100:
        h = op.open(f"{L.BASE}/{USER}/watchlist/page/{p}/", timeout=25).read().decode("utf-8", "replace")
        if p == 1 and "/watchlist/" not in h:
            return None
        for m in re.finditer(r'<div [^>]*data-item-slug="[^"]+"[^>]*>', h):
            n = re.search(r'data-item-name="([^"]*)"', m.group(0))
            sl = re.search(r'data-item-slug="([^"]+)"', m.group(0)).group(1)
            if n:
                names[sl] = html.unescape(n.group(1))
        s = [x for x in dict.fromkeys(re.findall(r'data-item-slug="([^"]+)"', h)) if x not in slugs]
        slugs += s
        if not s or f"/watchlist/page/{p + 1}/" not in h:
            break
        p += 1
    watchlist.names = names
    return slugs


def film_info(op, slug):
    h = op.open(f"{L.BASE}/film/{slug}/", timeout=25).read().decode("utf-8", "replace")
    tt = re.search(r"imdb\.com/title/(tt\d+)", h)
    name = re.search(r'<meta property="og:title" content="([^"]+)"', h)
    name = re.sub(r"\s*\(\d{4}\)$", "", html.unescape(name.group(1))) if name else slug
    return {"imdb": tt.group(1) if tt else None, "name": name}


def mylist(action, tt, name):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        S.cmd_mylist(action, "movie", tt, name)
    return '"ok": true' in buf.getvalue()


def export(slugs, films):
    """Lista para el cine: en el orden de Letterboxd (cuándo la agregaste, la más nueva primero)."""
    out = []
    for i, sl in enumerate(slugs):
        f = films.get(sl) or {}
        tt = f.get("imdb")
        out.append({"id": tt or "lb:" + sl, "type": "movie", "name": f.get("name") or sl,
                    "year": f.get("year", ""), "lbSlug": sl, "lbOrder": i + 1,
                    "poster": f"https://images.metahub.space/poster/medium/{tt}/img" if tt else ""})
    tmp = EXPORT + ".tmp"
    with open(tmp, "w") as fh:
        json.dump({"user": USER, "items": out}, fh, ensure_ascii=False)
    os.replace(tmp, EXPORT)


def main():
    seed = "--seed" in sys.argv
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    global USER
    lockp = STATE + ".lock"
    try:      # una sola a la vez (un archivo que se crea solo si no existe; vence a los 10 min)
        if os.path.exists(lockp) and time.time() - os.path.getmtime(lockp) > 600:
            os.unlink(lockp)
        fd = os.open(lockp, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
        os.close(fd)
    except OSError:
        return log("ya hay otra sincronización corriendo")
    try:
        _sync(seed)
    finally:
        try:
            os.unlink(lockp)
        except OSError:
            pass


def _sync(seed):
    global USER
    op, _ = L.opener()
    USER = L.usuario(op)
    if not USER:
        try:
            os.unlink(EXPORT)            # sin cuenta: nada de la lista de otro
        except OSError:
            pass
        return log("sin sesión de Letterboxd: no hay watchlist")
    st0 = load_state() or {}
    if st0.get("user") and st0["user"] != USER:
        save_state({"watchlist": [], "films": {}, "user": USER})   # cambió la cuenta: de cero
    slugs = watchlist(op)
    if not slugs:
        return log("no pude leer la watchlist: no toco nada")

    st = load_state() or {"watchlist": [], "films": {}}
    st["user"] = USER
    films = st["films"]                         # slug → {imdb, name}
    if not st["watchlist"]:
        seed = True                             # primera vez: no sé qué cambió

    new = [s for s in slugs if s not in st["watchlist"]]
    gone = [s for s in st["watchlist"] if s not in slugs]
    # si de golpe desaparece más de la mitad, seguro es la página que cambió
    if len(gone) > max(5, len(st["watchlist"]) // 2):
        log(f"desaparecieron {len(gone)} de golpe: no saco nada")
        gone = []

    with ThreadPoolExecutor(6) as ex:
        need = [s for s in new if s not in films]
        for s, info in zip(need, ex.map(lambda s: film_info(op, s), need)):
            films[s] = info

    changed = 0
    if not seed:
        for s in reversed(new):                 # la más nueva queda arriba
            f = films[s]
            if not f["imdb"]:
                log("sin IMDb, no se puede:", f["name"])
            elif mylist("add", f["imdb"], f["name"]):
                log("agregada:", f["name"]); changed += 1
        for s in gone:
            f = films.get(s) or {}
            if f.get("imdb") and mylist("remove", f["imdb"], f.get("name", "")):
                log("sacada:", f.get("name")); changed += 1

    st["watchlist"] = slugs
    for sl, full in getattr(watchlist, "names", {}).items():
        y = re.search(r"\((\d{4})\)$", full)
        if sl in films and y:
            films[sl]["year"] = y.group(1)
    save_state(st)
    export(slugs, films)
    log(f"watchlist {len(slugs)} · nuevas {len(new)} · salieron {len(gone)} · cambios {changed}")
    # (la app recarga Mi lista cuando esto termina)


if __name__ == "__main__":
    main()
