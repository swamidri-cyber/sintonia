#!/usr/bin/env python3
"""rice-cine — la app del teléfono (etapa C).

  phone.py newpin    → código de 4 números para vincular un teléfono (dura 10 min)
  phone.py forget    → desvincula todos los teléfonos

web.py le pasa los pedidos de /app y /api (handle()). Un teléfono queda
vinculado con un token (va en una cookie) que se consigue con el código.
"""
import json
import os
import secrets
import sys
import time

STATE = lugares.STATE
PHONES = os.path.join(STATE, "phones.json")
PIN = os.path.join(STATE, "phone-pin.json")


def load(path, default):
    try:
        return json.load(open(path))
    except Exception:
        return default


def save(path, data):
    os.makedirs(STATE, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, path)


def new_pin():
    pin = f"{secrets.randbelow(10000):04d}"
    save(PIN, {"pin": pin, "until": time.time() + 600, "tries": 0})
    return pin


def pair(pin, name):
    """→ token o None. Cinco intentos fallidos y el código deja de servir."""
    p = load(PIN, {})
    if not p or time.time() > p.get("until", 0) or p.get("tries", 0) >= 5:
        return None
    if not secrets.compare_digest(str(pin), p["pin"]):
        p["tries"] = p.get("tries", 0) + 1
        save(PIN, p)
        return None
    tok = secrets.token_urlsafe(24)
    ph = load(PHONES, {})
    ph[tok] = {"name": (name or "Teléfono")[:60], "since": int(time.time())}
    save(PHONES, ph)
    save(PIN, {})                       # cada código sirve una sola vez
    return tok


def valid(tok):
    return bool(tok) and tok in load(PHONES, {})


# ── Servidor (lo llama web.py) ───────────────────────────────────────────────
import socket  # noqa: E402
import subprocess  # noqa: E402
import threading  # noqa: E402
import urllib.parse  # noqa: E402
from datetime import datetime  # noqa: E402

import lugares  # carpetas de SINTONÍA

HERE = os.path.dirname(os.path.abspath(__file__))
APP = os.path.join(HERE, "phone-app")
RUNTIME = lugares.RUNTIME
import canal
FONTS = {"mono.otf": os.path.join(lugares.FONTS, "DepartureMonoNerdFont-Regular.otf"),
         "serif.ttf": os.path.join(lugares.FONTS, "LiberationSerif-Bold.ttf"),
         "sans.ttf": os.path.join(lugares.FONTS, "Inter.ttf")}
CTYPES = {".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8",
          ".webmanifest": "application/manifest+json", ".png": "image/png", ".svg": "image/svg+xml",
          ".otf": "font/otf", ".ttf": "font/ttf"}
THIS_YEAR = datetime.now().year
# los mismos canales que el cine (colores de shell.qml)
CHANNELS = [
    {"id": "stremio", "ch": "01", "name": "STREMIO", "kana": "初号機", "bg": "#07020c", "deep": "#14072a", "line": "#3d2260", "dim": "#9a74c8", "fg": "#e2ceff", "hi": "#f6eeff", "warn": "#ff8a3d"},
    {"id": "netflix", "ch": "02", "name": "NETFLIX", "kana": "赤", "bg": "#0b0202", "deep": "#200606", "line": "#5a1616", "dim": "#c0605a", "fg": "#ffd0ca", "hi": "#fff2ee", "warn": "#ffd25a"},
    {"id": "disney", "ch": "03", "name": "DISNEY+", "kana": "零号機", "bg": "#02060d", "deep": "#07152c", "line": "#1d3a66", "dim": "#6b9ad2", "fg": "#cde1ff", "hi": "#f0f6ff", "warn": "#ffb35a"},
    {"id": "max", "ch": "04", "name": "MAX", "kana": "白", "bg": "#050505", "deep": "#141416", "line": "#3a3a3e", "dim": "#9a9aa0", "fg": "#ececE8", "hi": "#ffffff", "warn": "#ff6a5a"},
    {"id": "prime", "ch": "05", "name": "PRIME VIDEO", "kana": "青", "bg": "#010a0b", "deep": "#051d20", "line": "#145055", "dim": "#5bbcc0", "fg": "#c8f9f5", "hi": "#effffd", "warn": "#ffb35a"},
    {"id": "crunchyroll", "ch": "06", "name": "CRUNCHYROLL", "kana": "アニメ", "bg": "#0c0601", "deep": "#241204", "line": "#6a3410", "dim": "#d08a4a", "fg": "#ffdcbc", "hi": "#fff3e8", "warn": "#ff5a8a"},
]
STREMIO_HOME = [
    ("TOP 10 EN EL MUNDO · PELÍCULAS", "top10", "movie", ""), ("TOP 10 EN EL MUNDO · SERIES", "top10", "series", ""),
    ("PELÍCULAS POPULARES", "stremio", "movie", ""), ("ESTRENOS", "stremio-new", "movie", str(THIS_YEAR)),
    ("SERIES POPULARES", "stremio", "series", ""), ("SERIES NUEVAS", "stremio-new", "series", str(THIS_YEAR)),
    ("DESTACADAS", "stremio-best", "movie", ""), ("PARA REÍRSE", "stremio", "movie", "Comedy"),
    ("PARA NO DORMIR", "stremio", "movie", "Horror"), ("ADRENALINA", "stremio", "movie", "Action"),
    ("OTROS MUNDOS", "stremio", "movie", "Sci-Fi"), ("SERIES DE CRIMEN Y MISTERIO", "stremio", "series", "Crime"),
    ("ANIMACIÓN", "stremio", "movie", "Animation"), ("HISTORIAS REALES", "stremio", "movie", "Documentary"),
    ("PARA ENAMORARSE", "stremio", "movie", "Romance")]
GENRES = [("Action", "ACCIÓN"), ("Comedy", "COMEDIA"), ("Drama", "DRAMA"), ("Thriller", "SUSPENSO"), ("Horror", "TERROR"),
          ("Sci-Fi", "CIENCIA FICCIÓN"), ("Animation", "ANIMACIÓN"), ("Romance", "ROMANCE"), ("Crime", "POLICIALES"),
          ("Documentary", "DOCUMENTALES")]
PLAT_GENRES = [(["Comedy"], "PARA REÍRSE"), (["Horror"], "PARA NO DORMIR"), (["Action"], "ADRENALINA"), (["Drama"], "DRAMAS"),
               (["Sci-Fi", "Fantasy"], "OTROS MUNDOS"), (["Crime", "Mystery"], "CRIMEN Y MISTERIO"),
               (["Family", "Animation"], "EN FAMILIA"), (["Documentary", "Biography"], "HISTORIAS REALES"), (["Romance"], "PARA ENAMORARSE")]
ANIME_GENRES = [(["Action"], "PELEAS ÉPICAS"), (["Fantasy", "Adventure"], "MUNDOS FANTÁSTICOS"), (["Comedy"], "PARA REÍRSE"),
                (["Romance"], "ROMANCE"), (["Drama"], "DRAMAS"), (["Sci-Fi"], "CIENCIA FICCIÓN")]
_cache, _clock = {}, threading.Lock()


def tool(script, *args, ttl=600, timeout=90):
    """Corre stremio.py y guarda la respuesta un rato."""
    key = (script,) + args
    with _clock:
        hit = _cache.get(key)
    if hit and time.time() - hit[0] < ttl:
        return hit[1]
    try:
        r = subprocess.run([sys.executable, os.path.join(HERE, script)] + list(args), capture_output=True, text=True, timeout=timeout)
        data = json.loads(r.stdout or "null")
    except Exception as e:
        data = {"error": str(e)[:120]}
    if ttl and data is not None and not (isinstance(data, dict) and data.get("error")):
        with _clock:
            _cache[key] = (time.time(), data)
    return data


def lite(it):
    """Lo que el teléfono necesita de cada título (para no mandar de más)."""
    keys = ("id", "type", "name", "year", "rating", "genres", "runtime", "poster", "background", "logo", "offset",
            "duration", "progress", "videoId", "season", "episode", "channel", "description", "watched")
    return {k: it[k] for k in keys if k in it and it[k] not in (None, "")}


def rows_for(ch, tab):
    R = []
    add = lambda t, items, mn=1: R.append({"title": t, "items": [lite(x) for x in (items or [])[:40]]}) if items and len(items) >= mn else None
    lib = tool("stremio.py", "library", ttl=30) or {}
    if ch == "stremio":
        if tab == "home":
            keys = [f"{s}|{t}|{g}" for _, s, t, g in STREMIO_HOME]
            cats = tool("stremio.py", "catalogs", *keys, ttl=3600, timeout=120) or {}
            add("SEGUIR VIENDO", lib.get("continue"))
            add("MI LISTA", lib.get("list"))
            for (title, s, t, g), k in zip(STREMIO_HOME, keys):
                add(title, cats.get(k), 4)
            add("VER DE NUEVO", lib.get("again"))
        else:
            keys = [f"stremio|{tab}|"] + [f"stremio|{tab}|{g}" for g, _ in GENRES]
            cats = tool("stremio.py", "catalogs", *keys, ttl=3600, timeout=120) or {}
            add("POPULARES", cats.get(keys[0]))
            for (g, title), k in zip(GENRES, keys[1:]):
                add(title, cats.get(k), 4)
        return R
    km, ks = f"{ch}|movie|", f"{ch}|series|"
    cats = tool("stremio.py", "catalogs", km, ks, ttl=3600, timeout=120) or {}
    M, S = cats.get(km) or [], cats.get(ks) or []
    anime = ch == "crunchyroll"
    both = [x for pair in zip(M, S) for x in pair] + M[len(S):] + S[len(M):]
    has = lambda x, gs: any(g in (x.get("genres") or []) for g in gs)
    year = lambda x: int(str(x.get("year") or "0")[:4] or 0) if str(x.get("year") or "0")[:4].isdigit() else 0
    rating = lambda x: float(x.get("rating") or 0) if str(x.get("rating") or "").replace(".", "", 1).isdigit() else 0
    if tab == "movie":
        add("POPULARES", M)
        for gs, title in (ANIME_GENRES if anime else PLAT_GENRES):
            add(title, [x for x in M if has(x, gs)], 4)
    elif tab == "series":
        add("POPULARES", S)
        for gs, title in (ANIME_GENRES if anime else PLAT_GENRES):
            add(title, [x for x in S if has(x, gs)], 4)
    else:
        add("TOP 10 ANIME" if anime else "TOP 10 EN " + next(c["name"] for c in CHANNELS if c["id"] == ch), both[:10])
        add("ANIME POPULAR" if anime else "SERIES POPULARES", S)
        add("PELÍCULAS DE ANIME" if anime else "PELÍCULAS POPULARES", M)
        add("ESTRENOS", sorted([x for x in both if year(x) >= THIS_YEAR - 1], key=year, reverse=True))
        add("LAS MEJOR PUNTUADAS", sorted([x for x in both if rating(x) >= 7.3], key=rating, reverse=True))
        for gs, title in (ANIME_GENRES if anime else PLAT_GENRES):
            add(title, [x for x in both if has(x, gs)], 4)
    return R


def session_snapshot():
    """Cómo está la película en curso (lo que el reproductor repite al conectarse)."""
    try:
        s = canal.conectar("player", timeout=2)
        s.settimeout(0.6)
    except OSError:
        return {"active": False}
    buf = b""
    t0 = time.time()
    try:
        while time.time() - t0 < 0.5:
            chunk = s.recv(65536)
            if not chunk:
                break
            buf += chunk
            if b'"ev": "state"' in buf and buf.endswith(b"\n"):
                break
    except OSError:
        pass
    s.close()
    out = {"active": True}
    for line in buf.decode(errors="replace").splitlines():
        try:
            e = json.loads(line)
        except Exception:
            continue
        out[e.get("ev")] = e
    return out


def link_send(cmd):
    try:
        s = canal.conectar("player", timeout=2)
        s.sendall((cmd + "\n").encode())
        time.sleep(0.15)
        s.close()
        return True
    except OSError:
        return False


ALLOWED = {"pause", "pauseset", "seek", "seekto", "volume", "sid", "aid", "subdelay", "subdelayset", "resync", "quit"}


def start_play(b):
    """Igual que el cine al reproducir (launchPlayer / launchVideo)."""
    it = b["item"]
    target = None
    if b.get("target") and b["target"] != "pc":
        target = next((c for c in (load(os.path.join(lugares.CACHE, "casts.json"), [])) if c["uuid"] == b["target"]), None)
    start = float(b.get("start") or 0) / 1000
    if it.get("type") == "video":
        job = {"type": "video", "id": it["id"], "videoId": it["id"], "name": it.get("name", ""), "channel": it.get("channel", ""),
               "start": start}
        lang = {"lang": "", "label": "Tráiler"}
    else:
        lang = {"lang": b.get("lang", ""), "label": b.get("langLabel", "")}
        job = {"type": it["type"], "id": it["id"], "videoId": b.get("videoId") or it["id"], "name": it.get("name", ""),
               "lang": b.get("lang", ""), "original": b.get("original", ""), "subs": bool(b.get("subs")), "start": start,
               "streams": b.get("streams") or []}
    job["ui"] = {"play": {"item": it, "videoId": job["videoId"], "start": b.get("start") or 0, "seenBefore": bool(it.get("watched")),
                          "epName": b.get("epName", "")},
                 "lastChoice": {"lang": lang["lang"], "subs": bool(b.get("subs")), "auto": False, "target": target},
                 "playLang": lang, "playSubs": bool(b.get("subs")), "platform": b.get("channel", "stremio"), "testMode": False,
                 "target": target, "fromPhone": True}
    if target:
        job["target"] = {"uuid": target["uuid"], "host": target["host"], "name": target["name"]}
    subprocess.Popen([sys.executable, os.path.join(HERE, "player-link.py"), "start", json.dumps(job)],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    # en la PC: que el cine muestre sus controles (y si está abierto con la tele, que se entere)

    def tell_cine():
        time.sleep(1.2)
        subprocess.run(["qs", "-c", "rice-cine", "ipc", "call", "cine", "attach", "false" if target else "true"],
                       capture_output=True, timeout=10)
    threading.Thread(target=tell_cine, daemon=True).start()
    return {"ok": True}


def token_of(req):
    for part in (req.headers.get("Cookie") or "").split(";"):
        k, _, v = part.strip().partition("=")
        if k == "rc":
            return v
    return ""


def send_json(req, data, code=200, cookie=None):
    body = json.dumps(data, ensure_ascii=False).encode()
    extra = {"Set-Cookie": f"rc={cookie}; Max-Age=315360000; Path=/; SameSite=Lax; HttpOnly"} if cookie else None
    req.send_bytes(code, body, "application/json; charset=utf-8", extra)


def handle(req, method):
    url = urllib.parse.urlparse(req.path)
    path, q = url.path, {k: v[0] for k, v in urllib.parse.parse_qs(url.query).items()}
    if not path.startswith("/api/"):
        if path in ("/", "/app", "/app/"):
            path = "/index.html"
        if path.startswith("/font/"):
            f = FONTS.get(os.path.basename(path))
        else:
            f = os.path.join(APP, os.path.basename(path))
        if not f or not os.path.isfile(f):
            return req.send_bytes(404, b"no", "text/plain")
        return req.send_bytes(200, open(f, "rb").read(), CTYPES.get(os.path.splitext(f)[1], "application/octet-stream"),
                              {"Cache-Control": "max-age=86400"} if path.startswith("/font/") else None)
    body = {}
    if method == "POST":
        n = int(req.headers.get("Content-Length") or 0)
        try:
            body = json.loads(req.rfile.read(n) or b"{}") if n else {}
        except Exception:
            body = {}
    api = path[5:]
    if api == "hello":
        return send_json(req, {"paired": valid(token_of(req))})
    if api == "pair":
        tok = pair(str(body.get("pin", "")).strip(), body.get("name", ""))
        return send_json(req, {"ok": bool(tok)}, cookie=tok) if tok else send_json(req, {"ok": False}, 403)
    if not valid(token_of(req)):
        return send_json(req, {"error": "sin vincular"}, 401)
    if api == "channels":
        prefs = load(os.path.join(HERE, "settings.json"), {})
        return send_json(req, {"channels": CHANNELS, "casts": load(os.path.join(lugares.CACHE, "casts.json"), []),
                               "prefs": {k: prefs.get(k) for k in ("prefAudio", "prefSubs", "dest")}})
    if api == "rows":
        return send_json(req, {"rows": rows_for(q.get("ch", "stremio"), q.get("tab", "home"))})
    if api == "search":
        r = tool("stremio.py", "search", q.get("q", ""))
        items = r if isinstance(r, list) else ((r or {}).get("metas") or (r or {}).get("items") or [])
        return send_json(req, {"items": [lite(x) for x in items[:40]]})
    if api == "meta":
        return send_json(req, tool("stremio.py", "meta", q.get("type", "movie"), q.get("id", ""), ttl=3600))
    if api == "streams":
        return send_json(req, tool("stremio.py", "streams", q.get("type", "movie"), q.get("id", ""), q.get("vid") or q.get("id", ""), ttl=600, timeout=120))
    if api == "play":
        return send_json(req, start_play(body))
    if api == "now":
        return send_json(req, session_snapshot())
    if api == "cmd":
        c = str(body.get("c", "")).strip()
        if c.split(" ")[0] not in ALLOWED:
            return send_json(req, {"ok": False}, 400)
        return send_json(req, {"ok": link_send(c)})
    send_json(req, {"error": "no existe"}, 404)


if __name__ == "__main__":
    if sys.argv[1] == "newpin":
        print(new_pin())
    elif sys.argv[1] == "forget":
        save(PHONES, {})
