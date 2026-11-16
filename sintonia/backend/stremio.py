#!/usr/bin/env python3
"""rice-cine — datos de Stremio para el modo cine (Quickshell rice-cine).

Usa tu cuenta de Stremio (la que conectás en SINTONÍA) y habla con la API de Stremio y
con los addons del usuario. Siempre imprime UN JSON por stdout.

  stremio.py library                         seguir viendo / ver de nuevo / mi lista
  stremio.py catalog <plataforma> <movie|series> [skip] [genero]
  stremio.py search <texto>
  stremio.py meta <movie|series> <id>        ficha completa (con episodios)
  stremio.py mylist <add|remove> <movie|series> <id> [nombre]
  stremio.py streams <movie|series> <id> <videoId>   fuentes agrupadas por idioma
  stremio.py subs <movie|series> <videoId> [archivo] [tamaño]   subtítulos en español
  stremio.py progress <movie|series> <id> <videoId> <ms> <ms total> [visto 0|1]

Cachés en ~/.cache/rice-cine (catálogos 6 h, fichas 1 día). Si no hay red se
devuelve lo último que haya en caché.
"""
import glob
import math
import re
import hashlib
import json
import os
import sqlite3
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

import lugares  # carpetas de SINTONÍA
import cuentas

HOME = os.path.expanduser("~")
CACHE = lugares.CACHE
STORAGE = HOME + "/.var/app/com.stremio.Stremio/data/stremio/storage/*/*/LocalStorage/localstorage.sqlite3"
API = "https://api.strem.io/api/"
CINEMETA = "https://v3-cinemeta.strem.io"
STREAMING = "https://7a82163c306e-stremio-netflix-catalog-addon.baby-beamup.club"
TOPSTREAM = "https://top-streaming.stream/username=temporary_username"
UA = {"User-Agent": "Mozilla/5.0 Sintonia"}

# plataforma → (addon, id del catálogo)
PLATFORMS = {
    "stremio": (CINEMETA, "top"),
    "netflix": (STREAMING, "nfx"),
    "disney":  (STREAMING, "dnp"),
    "max":     (STREAMING, "hbm"),
    "prime":   (STREAMING, "amp"),
    "crunchyroll": (STREAMING, "cru"),
    # fuentes extra para los carruseles
    "stremio-new":  (CINEMETA, "year"),          # estrenos (género = año)
    "stremio-best": (CINEMETA, "imdbRating"),    # destacadas
    "top10":        (TOPSTREAM, "popular-{type}-global"),   # top 10 mundial
}


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))
    sys.stdout.flush()


# ── Sesión de Stremio ──────────────────────────────────────────────────────
#  1. la cuenta conectada en SINTONÍA (cuentas/stremio.json, con sus addons)
#  2. si no, la de la app de Stremio instalada (flatpak), como hacía rice-cine
#  3. si no, sin cuenta: los addons de catálogo y subtítulos de abajo (ninguno
#     de fuentes: para ver películas hace falta tu cuenta con tus addons)
DEFAULT_ADDONS = [CINEMETA + "/manifest.json", STREAMING + "/manifest.json", TOPSTREAM + "/manifest.json",
                  "https://hispasubs.ak-forge.workers.dev/manifest.json"]
ADDONS_TTL = 6 * 3600


def stremio_app_profile():
    for path in glob.glob(STORAGE):
        db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
        try:
            row = db.execute("select value from ItemTable where key='profile'").fetchone()
        finally:
            db.close()
        if row:
            v = row[0]
            return json.loads(v.decode("utf-16-le") if isinstance(v, bytes) else v)
    return {}


def default_addons():
    res = []
    for url in DEFAULT_ADDONS:
        try:
            res.append({"transportUrl": url, "manifest": get_json(url, 7 * 86400)})
        except Exception:
            pass
    return res


def profile():
    ses = cuentas.leer_json("stremio.json")
    if ses and ses.get("authKey"):
        if time.time() - ses.get("addonsTs", 0) > ADDONS_TTL or not ses.get("addons"):
            try:
                r = api("addonCollectionGet", {"type": "AddonCollectionGet", "authKey": ses["authKey"], "update": True})
                ses["addons"] = r.get("addons") or []
                ses["addonsTs"] = time.time()
                cuentas.escribir_json("stremio.json", ses)
            except Exception:
                pass
        return {"auth": {"key": ses["authKey"]}, "addons": ses.get("addons") or default_addons(),
                "user": {"email": ses.get("email", "")}}
    if os.environ.get("SINTONIA_SIN_STREMIO_APP") != "1":
        p = stremio_app_profile()
        if (p.get("auth") or {}).get("key"):
            return p
    return {"auth": None, "addons": default_addons()}


def auth_key():
    return ((profile().get("auth") or {}).get("key")) or None


def cmd_login(email):
    """La contraseña llega por stdin (no queda en la lista de procesos)."""
    pw = sys.stdin.readline().rstrip("\n")
    try:
        r = api("login", {"type": "Login", "email": email, "password": pw, "facebook": False})
    except Exception as e:
        msg = str(e)
        if "password" in msg.lower() or "wrong" in msg.lower() or "passphrase" in msg.lower():
            msg = "Mail o contraseña incorrectos"
        elif "user not found" in msg.lower():
            msg = "No hay una cuenta de Stremio con ese mail"
        return out({"error": msg[:160]})
    ses = {"authKey": r["authKey"], "email": (r.get("user") or {}).get("email", email)}
    cuentas.escribir_json("stremio.json", ses)
    profile()                          # baja tus addons ya
    out({"ok": True, "user": ses["email"]})


def cmd_logout():
    ses = cuentas.leer_json("stremio.json") or {}
    if ses.get("authKey"):
        try:
            api("logout", {"type": "Logout", "authKey": ses["authKey"]})
        except Exception:
            pass
    cuentas.borrar("stremio.json")
    out({"ok": True})


def cmd_whoami():
    p = profile()
    k = (p.get("auth") or {}).get("key")
    out({"user": (p.get("user") or {}).get("email", "") if k else "", "logged": bool(k),
         "addons": [a.get("manifest", {}).get("name", "?") for a in p.get("addons", [])]})


def _cache_path(key):
    return os.path.join(CACHE, hashlib.sha1(key.encode()).hexdigest()[:20] + ".json")


def get_json(url, ttl):
    path = _cache_path(url)
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < ttl:
        with open(path) as f:
            return json.load(f)
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=20) as r:
            data = json.load(r)
        os.makedirs(CACHE, exist_ok=True)
        with open(path + ".tmp", "w") as f:
            json.dump(data, f)
        os.replace(path + ".tmp", path)
        return data
    except Exception:
        if os.path.exists(path):            # sin red: lo último que haya
            with open(path) as f:
                return json.load(f)
        raise


def api(method, body):
    req = urllib.request.Request(API + method, data=json.dumps(body).encode(),
                                 headers={**UA, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.load(r)
    if data.get("error"):
        raise RuntimeError(data["error"].get("message", "error de Stremio"))
    return data["result"]


# ── Formato común de un título ──────────────────────────────────────────────
def art(kind, id_, fallback=""):
    if id_.startswith("tt"):
        return f"https://images.metahub.space/{kind}/medium/{id_}/img"
    return fallback or ""


def norm_meta(m):
    id_ = m.get("imdb_id") or m.get("id") or ""
    runtime = m.get("runtime") or ""
    return {
        "id": id_,
        "type": m.get("type", "movie"),
        "name": m.get("name", ""),
        "year": str(m.get("releaseInfo") or m.get("year") or ""),
        "rating": str(m.get("imdbRating") or ""),
        "genres": m.get("genres") or m.get("genre") or [],
        "country": m.get("country") or "",
        "runtime": runtime,
        "description": m.get("description") or "",
        "poster": art("poster", id_, m.get("poster", "")),
        "background": art("background", id_, m.get("background", "")),
        "logo": art("logo", id_, m.get("logo", "")),
    }


def iso_ts(s):
    try:
        return int(datetime.fromisoformat(s.replace("Z", "+00:00")).timestamp())
    except Exception:
        return 0


def norm_item(it):
    st = it.get("state") or {}
    off, dur = st.get("timeOffset") or 0, st.get("duration") or 0
    id_ = it["_id"]
    return {
        "id": id_,
        "type": it.get("type", "movie"),
        "name": it.get("name", ""),
        "year": str(it.get("year") or ""),
        "poster": art("poster", id_, it.get("poster", "")),
        "background": art("background", id_, it.get("background", "")),
        "logo": art("logo", id_, it.get("logo", "")),
        "offset": off,
        "duration": dur,
        "progress": round(off / dur, 4) if dur else 0,
        "videoId": st.get("video_id") or "",
        "season": st.get("season") or 0,
        "episode": st.get("episode") or 0,
        "lastWatched": iso_ts(st.get("lastWatched") or it.get("_mtime") or ""),
        "watched": bool(st.get("timesWatched") or st.get("flaggedWatched")),
        "inList": not it.get("removed") and not it.get("temp"),
    }


# ── Comandos ────────────────────────────────────────────────────────────────
def cmd_library():
    key = auth_key()
    if not key:
        return out({"error": "nologin"})
    path = _cache_path("library")
    try:
        items = api("datastoreGet", {"authKey": key, "collection": "libraryItem", "ids": [], "all": True})
        os.makedirs(CACHE, exist_ok=True)
        with open(path, "w") as f:
            json.dump(items, f)
    except Exception:
        if not os.path.exists(path):
            return out({"error": "offline"})
        with open(path) as f:
            items = json.load(f)
    items = [i for i in items if i.get("type") in ("movie", "series")]
    n = [norm_item(i) for i in items]
    # géneros y país de cada título (fichas de Cinemeta en caché): para repartir
    # la biblioteca entre los canales (ej. Crunchyroll = anime)
    def enrich(x):
        try:
            m = get_json(f"{CINEMETA}/meta/{x['type']}/{x['id']}.json", 7 * 24 * 3600).get("meta") or {}
            x["genres"] = m.get("genres") or m.get("genre") or []
            x["country"] = m.get("country") or ""
            x["year"] = x["year"] or str(m.get("releaseInfo") or m.get("year") or "")
        except Exception:
            x["genres"], x["country"] = [], ""
    with ThreadPoolExecutor(8) as ex:
        list(ex.map(enrich, n))
    by_recent = lambda l: sorted(l, key=lambda x: -x["lastWatched"])
    # Como en Stremio: seguir viendo = con minuto guardado (aunque se haya sacado de la lista)
    cont = by_recent([x for x in n if x["offset"] > 0])
    again = by_recent([x for x in n if x["watched"] and x["offset"] == 0])
    mine = by_recent([x for x in n if x["inList"]])
    out({"continue": cont, "again": again, "list": mine})


def fetch_catalog(platform, type_, skip="0", genre=""):
    base, cat = PLATFORMS[platform]
    cat = cat.format(type=type_)
    extra = []
    if genre:
        extra.append("genre=" + urllib.parse.quote(genre))
    if skip and skip != "0":
        extra.append("skip=" + skip)
    url = f"{base}/catalog/{type_}/{cat}" + ("/" + "&".join(extra) if extra else "") + ".json"
    return [norm_meta(m) for m in get_json(url, 6 * 3600).get("metas", []) if m.get("name")]


PAGED = ("netflix", "disney", "max", "prime", "crunchyroll")


def cmd_catalogs(*keys):
    """Varios catálogos a la vez, en paralelo: claves "fuente|tipo|género".
    Las plataformas traen 3 páginas juntas (para las filas por género)."""
    jobs = []
    for k in keys:
        src, type_, genre = (k.split("|") + ["", ""])[:3]
        pages = ["0", "100", "200"] if src in PAGED and not genre else ["0"]
        jobs += [(k, src, type_, p, genre) for p in pages]

    def run(j):
        try:
            return j, fetch_catalog(j[1], j[2], j[3], j[4])
        except Exception:
            return j, []
    res = {k: [] for k in keys}
    with ThreadPoolExecutor(10) as ex:
        for j, metas in sorted(ex.map(run, jobs), key=lambda t: int(t[0][3])):
            seen = {m["id"] for m in res[j[0]]}
            res[j[0]] += [m for m in metas if m["id"] not in seen]
    out(res)


def cmd_catalog(platform, type_, skip="0", genre=""):
    base, cat = PLATFORMS[platform]
    cat = cat.format(type=type_)
    extra = []
    if genre:
        extra.append("genre=" + urllib.parse.quote(genre))
    if skip and skip != "0":
        extra.append("skip=" + skip)
    url = f"{base}/catalog/{type_}/{cat}" + ("/" + "&".join(extra) if extra else "") + ".json"
    data = get_json(url, 6 * 3600)
    out({"metas": [norm_meta(m) for m in data.get("metas", []) if m.get("name")]})


def cmd_search(q):
    qq = urllib.parse.quote(q)
    urls = [f"{CINEMETA}/catalog/{t}/top/search={qq}.json" for t in ("movie", "series")]
    with ThreadPoolExecutor(2) as ex:
        res = list(ex.map(lambda u: get_json(u, 3600).get("metas", []), urls))
    # intercalar películas y series, por relevancia
    mixed = [m for pair in zip(*res) for m in pair] + res[0][len(res[1]):] + res[1][len(res[0]):]
    out({"metas": [norm_meta(m) for m in mixed if m.get("name")]})


def cmd_meta(type_, id_):
    m = get_json(f"{CINEMETA}/meta/{type_}/{id_}.json", 24 * 3600).get("meta") or {}
    r = norm_meta(m)
    vids = []
    for v in m.get("videos") or []:
        if not v.get("season"):
            continue                          # especiales sin temporada: afuera
        vids.append({
            "id": v.get("id"),
            "season": v.get("season"),
            "episode": v.get("episode") or v.get("number"),
            "name": v.get("name") or v.get("title") or "",
            "overview": v.get("overview") or v.get("description") or "",
            "thumb": v.get("thumbnail") or "",
            "released": (v.get("released") or "")[:10],
        })
    vids.sort(key=lambda v: (v["season"], v["episode"] or 0))
    r["videos"] = vids
    r["cast"] = (m.get("cast") or [])[:4]
    r["director"] = (m.get("director") or [])[:2]
    out(r)


def cmd_mylist(action, type_, id_, name=""):
    key = auth_key()
    if not key:
        return out({"error": "nologin"})
    now = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    cur = api("datastoreGet", {"authKey": key, "collection": "libraryItem", "ids": [id_], "all": False})
    if cur:
        item = cur[0]
    else:
        item = {"_id": id_, "type": type_, "name": name, "poster": art("poster", id_),
                "posterShape": "poster", "background": "", "logo": "", "year": "",
                "_ctime": now, "state": {}}
    item["removed"] = action == "remove"
    item["temp"] = False
    item["_mtime"] = now
    api("datastorePut", {"authKey": key, "collection": "libraryItem", "changes": [item]})
    out({"ok": True})


# ── Fuentes (etapa 2) ───────────────────────────────────────────────────────
# Idioma original a partir del país (Cinemeta no trae el idioma)
COUNTRY_LANG = {
    "United States": "en", "United Kingdom": "en", "Canada": "en", "Australia": "en", "Ireland": "en",
    "New Zealand": "en", "South Korea": "ko", "Korea": "ko", "Japan": "ja", "France": "fr", "Belgium": "fr",
    "Spain": "es-ES", "Argentina": "es-419", "Mexico": "es-419", "Colombia": "es-419", "Chile": "es-419",
    "Uruguay": "es-419", "Peru": "es-419", "Venezuela": "es-419", "Cuba": "es-419", "Germany": "de",
    "Austria": "de", "Switzerland": "de", "Italy": "it", "Brazil": "pt", "Portugal": "pt", "China": "zh",
    "Taiwan": "zh", "Hong Kong": "zh", "India": "hi", "Russia": "ru", "Soviet Union": "ru", "Denmark": "da",
    "Sweden": "sv", "Norway": "no", "Finland": "fi", "Netherlands": "nl", "Poland": "pl", "Turkey": "tr",
    "Iran": "fa", "Thailand": "th", "Indonesia": "id", "Philippines": "tl", "Israel": "he", "Greece": "el",
    "Czech Republic": "cs", "Hungary": "hu", "Romania": "ro", "Ukraine": "uk", "Egypt": "ar",
}
LANG_NAME = {
    "en": "Inglés", "ko": "Coreano", "ja": "Japonés", "fr": "Francés", "es-ES": "Español España",
    "es-419": "Español latino", "de": "Alemán", "it": "Italiano", "pt": "Portugués", "zh": "Chino",
    "hi": "Hindi", "ru": "Ruso", "da": "Danés", "sv": "Sueco", "no": "Noruego", "fi": "Finlandés",
    "nl": "Neerlandés", "pl": "Polaco", "tr": "Turco", "fa": "Persa", "th": "Tailandés", "id": "Indonesio",
    "tl": "Filipino", "he": "Hebreo", "el": "Griego", "cs": "Checo", "hu": "Húngaro", "ro": "Rumano",
    "uk": "Ucraniano", "ar": "Árabe",
}
# Banderas que ponen los addons (Torrentio & cía.) para los audios extra
FLAG_LANG = {
    "🇬🇧": "en", "🇺🇸": "en", "🇪🇸": "es-ES", "🇲🇽": "es-419", "🇦🇷": "es-419", "🇫🇷": "fr", "🇩🇪": "de",
    "🇮🇹": "it", "🇵🇹": "pt", "🇧🇷": "pt", "🇯🇵": "ja", "🇰🇷": "ko", "🇨🇳": "zh", "🇹🇼": "zh", "🇮🇳": "hi",
    "🇷🇺": "ru", "🇺🇦": "uk", "🇵🇱": "pl", "🇳🇱": "nl", "🇩🇰": "da", "🇸🇪": "sv", "🇳🇴": "no", "🇫🇮": "fi",
    "🇹🇷": "tr", "🇬🇷": "el", "🇭🇺": "hu", "🇨🇿": "cs", "🇷🇴": "ro", "🇮🇱": "he", "🇸🇦": "ar", "🇹🇭": "th",
}
BAD = re.compile(r"\b(cam|camrip|hdcam|ts|telesync|hdts|tc|telecine|scr|screener)\b", re.I)


def stream_addons():
    out_ = []
    for a in profile().get("addons", []):
        m = a.get("manifest", {})
        res = [r if isinstance(r, str) else r.get("name") for r in m.get("resources", [])]
        if "stream" in res and a["transportUrl"].startswith("http") and "127.0.0.1" not in a["transportUrl"]:
            out_.append((m.get("name", "?"), a["transportUrl"].rsplit("/manifest.json", 1)[0]))
    return out_


def parse_stream(st, source):
    txt = " ".join(str(st.get(k) or "") for k in ("name", "title", "description"))
    first = (st.get("title") or st.get("description") or "").split("\n")[0]
    fname = (st.get("behaviorHints") or {}).get("filename") or first
    langs = {FLAG_LANG[f] for f in FLAG_LANG if f in txt}
    low = txt.lower()
    if re.search(r"\blat(ino|am)?\b|dual lat", low):
        langs.add("es-419")
    if re.search(r"castellano|\bcast\b|\bspa(nish)?\b", low) and "es-419" not in langs:
        langs.add("es-ES")
    res = 2160 if re.search(r"2160\s?px?|\b4k\b|uhd", low) else 1080 if re.search(r"1080\s?px?|fullhd|full hd", low) else 720 if re.search(r"720\s?px?", low) else 480
    m = re.search(r"💾\s*([\d.]+)\s*(gb|mb)", low)
    size = float(m.group(1)) * (1 if m.group(2) == "gb" else 1 / 1024) if m else 0.0
    m = re.search(r"👤\s*(\d+)", txt)
    seeds = int(m.group(1)) if m else 0
    return {
        "source": source, "title": first[:120], "filename": fname,
        "hash": st.get("infoHash") or "", "fileIdx": st.get("fileIdx"), "url": st.get("url") or "",
        "res": res, "size": round(size, 2), "seeds": seeds, "langs": sorted(langs),
        "multi": "multi" in low or "dual" in low,
        "bad": bool(BAD.search(first)), "dv": bool(re.search(r"\bdv\b|dolby.?vision", low)) and "hdr" not in low,
        "remux": "remux" in low,
    }


def score(s):
    """La más liviana que mantenga 1080p (y que tenga con quién bajar)."""
    if s["bad"] or (s["hash"] and s["seeds"] == 0):
        return -1
    base = {1080: 10.0, 720: 6.0, 2160: 4.0}.get(s["res"], 2.0)
    size = s["size"] or 4.0               # sin dato: como si fuera mediana
    seeds = min(math.log10(1 + s["seeds"]), 2.5) * 1.2
    if s["hash"] and s["seeds"] < 3:
        seeds -= 3.0                      # casi nadie la comparte: tarda una eternidad
    pen = 1.5 if s["dv"] else 0.0         # solo Dolby Vision: colores raros sin HDR de respaldo
    return base - size * 0.6 + seeds - pen


def cmd_streams(type_, id_, video_id):
    meta = get_json(f"{CINEMETA}/meta/{type_}/{id_}.json", 24 * 3600).get("meta") or {}
    country = (meta.get("country") or "").split(",")[0].strip()
    orig = COUNTRY_LANG.get(country, "en")
    vid = urllib.parse.quote(video_id, safe=":")

    def fetch(addon):
        name, base = addon
        try:
            with urllib.request.urlopen(urllib.request.Request(f"{base}/stream/{type_}/{vid}.json", headers=UA), timeout=14) as r:
                return [parse_stream(s, name) for s in json.load(r).get("streams", [])]
        except Exception:
            return []

    with ThreadPoolExecutor(8) as ex:
        allst = [s for lst in ex.map(fetch, stream_addons()) for s in lst]
    # solo lo que se puede reproducir sin cuenta paga: torrents (o links directos)
    allst = [s for s in allst if s["hash"] or s["url"].startswith("http")]
    seen, uniq = set(), []
    for s in sorted(allst, key=score, reverse=True):
        k = s["hash"] + str(s["fileIdx"]) if s["hash"] else s["url"]
        if k not in seen and score(s) >= 0:
            seen.add(k)
            uniq.append(s)

    def in_lang(s, lang):
        if lang == orig:                 # sin banderas = audio original
            return not s["langs"] or orig in s["langs"] or s["multi"]
        return lang in s["langs"]

    # inglés en pelis de otro idioma: suelen ser subtítulos, no audio. Español:
    # latino siempre que exista; el de España solo si no hay latino
    # Pedido del usuario (2026-11-14): nunca ofrecer el doblaje de España.
    # Solo aparece si ES el idioma original (película española).
    order = [orig] + (["es-419"] if orig != "es-419" else [])
    opts = []
    for lang in order:
        lst = [s for s in uniq if in_lang(s, lang)][:6]
        if lst:
            label = LANG_NAME.get(lang, lang) + (" (original)" if lang == orig else "")
            opts.append({"lang": lang, "label": label, "streams": lst})
    out({"original": orig, "originalName": LANG_NAME.get(orig, orig), "options": opts, "total": len(uniq)})


def cmd_subs(type_, video_id, filename="", size=""):
    es = get_json_subs(type_, video_id, filename, size)
    out({"subs": [{"id": x.get("id"), "url": x.get("url"), "lang": x.get("lang")} for x in es]})


def get_json_subs(type_, video_id, filename="", size=""):
    """Subtítulos en español de OpenSubtitles, los que mejor calzan con el archivo primero."""
    extra = []
    if filename:
        extra.append("filename=" + urllib.parse.quote(filename))
    if size:
        extra.append("videoSize=" + size)
    vid = urllib.parse.quote(video_id, safe=":")
    url = f"https://opensubtitles-v3.strem.io/subtitles/{type_}/{vid}" + ("/" + "&".join(extra) if extra else "") + ".json"
    subs = get_json(url, 6 * 3600).get("subtitles", [])
    return [x for x in subs if x.get("lang") in ("spa", "spn", "es", "esp", "ea")]


def cmd_progress(type_, id_, video_id, offset, duration, finished="0"):
    key = auth_key()
    if not key:
        return out({"error": "nologin"})
    offset, duration, finished = int(float(offset)), int(float(duration)), finished == "1"
    now = datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")
    cur = api("datastoreGet", {"authKey": key, "collection": "libraryItem", "ids": [id_], "all": False})
    if cur:
        item = cur[0]
    else:   # como hace Stremio con lo que ves sin agregarlo: en la biblioteca, pero oculto
        meta = get_json(f"{CINEMETA}/meta/{type_}/{id_}.json", 24 * 3600).get("meta") or {}
        item = {"_id": id_, "type": type_, "name": meta.get("name", ""), "poster": art("poster", id_),
                "posterShape": "poster", "background": "", "logo": "", "year": str(meta.get("year") or ""),
                "_ctime": now, "removed": True, "temp": True, "state": {}}
    st = item.setdefault("state", {})
    prev = st.get("timeOffset") or 0
    watched_now = max(0, offset - prev) if st.get("video_id") == video_id else offset
    st["timeWatched"] = (st.get("timeWatched") or 0) + watched_now
    st["overallTimeWatched"] = (st.get("overallTimeWatched") or 0) + watched_now
    st["video_id"] = video_id
    st["duration"] = duration
    st["lastWatched"] = now
    parts = video_id.split(":")
    st["season"] = int(parts[1]) if len(parts) == 3 else 0
    st["episode"] = int(parts[2]) if len(parts) == 3 else 0
    if finished:
        st["timeOffset"] = 0
        st["timesWatched"] = (st.get("timesWatched") or 0) + 1
        if type_ == "movie":
            st["flaggedWatched"] = 1
    else:
        st["timeOffset"] = offset
    item["_mtime"] = now
    api("datastorePut", {"authKey": key, "collection": "libraryItem", "changes": [item]})
    out({"ok": True})


def main():
    a = sys.argv[1:]
    try:
        if not a:
            raise SystemExit(__doc__)
        {"library": cmd_library, "catalog": cmd_catalog, "catalogs": cmd_catalogs, "search": cmd_search,
         "meta": cmd_meta, "mylist": cmd_mylist,
         "streams": cmd_streams, "subs": cmd_subs, "progress": cmd_progress,
         "login": cmd_login, "logout": cmd_logout, "whoami": cmd_whoami}[a[0]](*a[1:])
    except KeyError:
        out({"error": "comando desconocido"})
    except Exception as e:
        out({"error": str(e)[:200]})


if __name__ == "__main__":
    main()
