#!/usr/bin/env python3
"""rice-cine — canal de YouTube del modo cine (etapa 4).

Usa yt-dlp con tu sesión de YouTube de Zen (cookies del navegador, se leen
en el momento; no se guardan en ningún lado). Siempre imprime UN JSON.

  youtube.py home                              tu inicio de YouTube con sus categorías (como la tele)
  youtube.py feed <subs|rec|later|history|liked>   suscripciones, historial…
  youtube.py search <texto>
  youtube.py meta <id>                         descripción, canal, fecha
  youtube.py continue                          lo que dejaste a medias (local)
  youtube.py progress <id> <s> <s total> <título> <canal>   guardar dónde quedaste
  youtube.py dismiss <id>                         quitar de "seguir viendo"

Cachés: ~/.cache/rice-cine (feeds 20 min, fichas 1 día). El progreso de
YouTube queda en ~/.local/state/rice-cine/youtube.json (no va a la cuenta).
"""
import glob
import hashlib
import json
import os
import subprocess
import sys
import time

import lugares  # carpetas de SINTONÍA
import cuentas

HOME = os.path.expanduser("~")
CACHE = lugares.CACHE
STATE = lugares.STATE
PROGRESS = os.path.join(STATE, "youtube.json")
def _ytdlp():
    """yt-dlp: el de la app (módulo de Python), o uno instalado."""
    import shutil
    try:
        import yt_dlp  # noqa: F401
        return lugares.python(os.path.join(os.path.dirname(os.path.abspath(__file__)), "ytdlp.py"))
    except ImportError:
        pass
    p = HOME + "/.local/bin/yt-dlp"
    return [p if os.path.exists(p) else (shutil.which("yt-dlp") or "yt-dlp")]


YTDLP_CMD = _ytdlp()
YTDLP = YTDLP_CMD[-1] if len(YTDLP_CMD) == 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "ytdlp.py")
FEEDS = {"subs": ":ytsubs", "rec": ":ytrec", "later": ":ytwatchlater", "history": ":ythistory",
         "liked": "https://www.youtube.com/playlist?list=LL"}


def cookie_args():
    return cuentas.args_ytdlp()


def out(obj):
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))


def ytdlp_json(args, key, ttl):
    path = os.path.join(CACHE, "yt-" + hashlib.sha1(key.encode()).hexdigest()[:16] + ".json")
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < ttl:
        return json.load(open(path))
    r = subprocess.run(YTDLP_CMD + ["-J", "--no-warnings"] + cookie_args() + args, capture_output=True, text=True, timeout=90)
    if r.returncode != 0 or not r.stdout.strip():
        if os.path.exists(path):
            return json.load(open(path))
        raise RuntimeError((r.stderr.strip().split("\n") or ["yt-dlp falló"])[-1][:160])
    data = json.loads(r.stdout)
    os.makedirs(CACHE, exist_ok=True)
    json.dump(data, open(path, "w"))
    return data


def fmt_dur(s):
    s = int(s or 0)
    if not s:
        return ""
    h, m = s // 3600, s // 60 % 60
    return f"{h} h {m:02d} min" if h else f"{m} min"


def norm(e):
    vid = e.get("id") or ""
    views = e.get("view_count")
    return {
        "id": "yt:" + vid,
        "type": "video",
        "name": e.get("title") or "",
        "channel": e.get("channel") or e.get("uploader") or "",
        "year": "",
        "runtime": fmt_dur(e.get("duration")),
        "durationS": e.get("duration") or 0,
        "rating": "",
        "views": views or 0,
        "genres": [],
        "description": e.get("description") or "",
        "poster": f"https://i.ytimg.com/vi/{vid}/hqdefault.jpg",
        "background": f"https://i.ytimg.com/vi/{vid}/maxresdefault.jpg",
        "logo": "",
    }


def entries(data):
    es = [e for e in data.get("entries") or [] if e and e.get("id") and len(e.get("id")) == 11
          and not (e.get("title") or "").startswith(("[Deleted", "[Private"))]
    # sin shorts ni directos en vivo
    return [e for e in es if not (e.get("duration") and e["duration"] < 70) and e.get("live_status") != "is_live"]


def cmd_feed(name):
    data = ytdlp_json(["--flat-playlist", "--playlist-end", "60", FEEDS[name]], "feed-" + name, 20 * 60)
    out({"metas": [norm(e) for e in entries(data)]})


def cmd_search(q):
    data = ytdlp_json(["--flat-playlist", "ytsearch30:" + q], "search-" + q, 3600)
    out({"metas": [norm(e) for e in entries(data)]})


def cmd_meta(id_):
    vid = id_.removeprefix("yt:")
    e = ytdlp_json(["--skip-download", "https://www.youtube.com/watch?v=" + vid], "meta-" + vid, 24 * 3600)
    r = norm(e)
    d = e.get("upload_date") or ""
    r["year"] = f"{d[6:8]}/{d[4:6]}/{d[:4]}" if len(d) == 8 else ""
    out(r)


def load_progress():
    try:
        return json.load(open(PROGRESS))
    except Exception:
        return {}


def cmd_subsrelated():
    """"Parecido a lo que seguís": relacionados de lo último de tus suscripciones."""
    path = os.path.join(CACHE, "yt-subsrel.json")
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < 30 * 60:
        return out(json.load(open(path)))
    from concurrent.futures import ThreadPoolExecutor
    ck = yt_cookies()
    subs = entries(ytdlp_json(["--flat-playlist", "--playlist-end", "60", FEEDS["subs"]], "feed-subs", 20 * 60))
    seen_ch, pick = set(), []
    for e in subs:                    # uno por canal, de los 6 primeros canales distintos
        if e.get("channel") not in seen_ch:
            seen_ch.add(e.get("channel")); pick.append(e["id"])
        if len(pick) >= 6:
            break
    with ThreadPoolExecutor(6) as ex:
        rel = [x for r in ex.map(lambda v: related(v, ck), pick) for x in r[:8]]
    sub_ids = {"yt:" + e["id"] for e in subs}
    res = {"metas": [x for x in dedup(rel) if x["id"] not in sub_ids]}
    os.makedirs(CACHE, exist_ok=True)
    json.dump(res, open(path, "w"))
    out(res)


def cmd_continue():
    p = load_progress()
    items = []
    for vid, v in sorted(p.items(), key=lambda kv: -kv[1].get("last", 0)):
        if v.get("pos", 0) < 30 or (v.get("dur") and v["pos"] / v["dur"] > 0.92):
            continue
        it = norm({"id": vid, "title": v.get("title"), "channel": v.get("channel"), "duration": v.get("dur")})
        it["offset"] = int(v["pos"] * 1000)
        it["duration"] = int((v.get("dur") or 0) * 1000)
        it["progress"] = round(v["pos"] / v["dur"], 4) if v.get("dur") else 0
        items.append(it)
    out({"metas": items[:30]})


def cmd_dismiss(id_):
    p = load_progress()
    p.pop(id_.removeprefix("yt:"), None)
    os.makedirs(STATE, exist_ok=True)
    json.dump(p, open(PROGRESS, "w"))
    out({"ok": True})


def cmd_progress(id_, pos, dur, title="", channel=""):
    vid = id_.removeprefix("yt:")
    p = load_progress()
    p[vid] = {"pos": float(pos), "dur": float(dur), "title": title, "channel": channel, "last": time.time()}
    os.makedirs(STATE, exist_ok=True)
    json.dump(p, open(PROGRESS, "w"))
    out({"ok": True})


# ── Inicio de YouTube (API interna, con tu sesión de Zen) ──────────────────
def yt_cookies():
    jar, _ua = cuentas.sesion_web("youtube", "youtube.com")
    if jar is None:
        raise RuntimeError("nologin")
    return {c.name: c.value for c in jar if c.domain.endswith("youtube.com")}


def browse(body, ck, endpoint="browse"):
    import urllib.request
    sap = ck.get("SAPISID") or ck.get("__Secure-3PAPISID") or ""
    ts = str(int(time.time()))
    h = hashlib.sha1(f"{ts} {sap} https://www.youtube.com".encode()).hexdigest()
    hdr = {"Cookie": "; ".join(f"{k}={v}" for k, v in ck.items()), "Authorization": f"SAPISIDHASH {ts}_{h}",
           "Origin": "https://www.youtube.com", "X-Origin": "https://www.youtube.com", "X-Goog-AuthUser": "0",
           "Content-Type": "application/json",
           "User-Agent": cuentas.sesion_web("youtube", "youtube.com")[1]}
    body = dict(body, context={"client": {"clientName": "WEB", "clientVersion": "2.20260901.00.00", "hl": "es-419", "gl": "AR"}})
    req = urllib.request.Request(f"https://www.youtube.com/youtubei/v1/{endpoint}?prettyPrint=false",
                                 data=json.dumps(body).encode(), headers=hdr)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def txt(o):
    if isinstance(o, dict):
        return o.get("content") or o.get("simpleText") or "".join(r.get("text", "") for r in o.get("runs", []))
    return str(o or "")


def lockup(lv):
    """Un video del inicio nuevo de YouTube (lockupViewModel) → el formato del cine."""
    if lv.get("contentType") != "LOCKUP_CONTENT_TYPE_VIDEO":
        return None
    vid = lv.get("contentId") or ""
    md = lv.get("metadata", {}).get("lockupMetadataViewModel", {})
    rows = md.get("metadata", {}).get("contentMetadataViewModel", {}).get("metadataRows", [])
    parts = [txt(p.get("text")) for r in rows for p in r.get("metadataParts", [])]
    dur = ""
    for ov in lv.get("contentImage", {}).get("thumbnailViewModel", {}).get("overlays", []):
        for b in ov.get("thumbnailBottomOverlayViewModel", {}).get("badges", []):
            dur = b.get("thumbnailBadgeViewModel", {}).get("text", "") or dur
    it = norm({"id": vid, "title": txt(md.get("title"))})
    it["channel"] = parts[0] if parts else ""
    it["views"] = 0
    it["viewsText"] = parts[1] if len(parts) > 1 else ""
    it["year"] = parts[2] if len(parts) > 2 else ""
    it["runtime"] = dur
    return it


def grid_items(contents):
    out = []
    for c in contents:
        lv = c.get("richItemRenderer", {}).get("content", {}).get("lockupViewModel")
        if lv:
            it = lockup(lv)
            if it and it["name"]:
                out.append(it)
    return out


def find_lockups(o, out=None):
    """Todos los videos (lockupViewModel) que haya en cualquier parte de una respuesta."""
    out = [] if out is None else out
    if isinstance(o, dict):
        if "lockupViewModel" in o:
            it = lockup(o["lockupViewModel"])
            if it and it["name"]:
                out.append(it)
        else:
            for v in o.values():
                find_lockups(v, out)
    elif isinstance(o, list):
        for v in o:
            find_lockups(v, out)
    return out


def dedup(items):
    seen, out_ = set(), []
    for x in items:
        if x["id"] not in seen:
            seen.add(x["id"]); out_.append(x)
    return out_


def related(vid, ck):
    """Lo que YouTube propone al lado de un video ("a continuación")."""
    try:
        return dedup(find_lockups(browse({"videoId": vid}, ck, "next").get("contents", {})
                                  .get("twoColumnWatchNextResults", {}).get("secondaryResults", {})))
    except Exception:
        return []


def cmd_home():
    path = os.path.join(CACHE, "yt-home.json")
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < 20 * 60:
        return out(json.load(open(path)))
    from concurrent.futures import ThreadPoolExecutor
    ck = yt_cookies()
    d = browse({"browseId": "FEwhat_to_watch"}, ck)
    grid = d["contents"]["twoColumnBrowseResultsRenderer"]["tabs"][0]["tabRenderer"]["content"]["richGridRenderer"]
    chips = []
    for c in grid.get("header", {}).get("feedFilterChipBarRenderer", {}).get("contents", []):
        cc = c.get("chipCloudChipRenderer", {})
        tok = cc.get("navigationEndpoint", {}).get("continuationCommand", {}).get("token")
        if tok:
            chips.append((txt(cc.get("text")), tok))

    def chip(c):
        title, tok = c
        try:
            r = browse({"continuation": tok}, ck)
            items = []
            for a in r.get("onResponseReceivedActions", []):
                items += grid_items(a.get("reloadContinuationItemsCommand", {}).get("continuationItems", []))
            return {"title": title, "items": items}
        except Exception:
            return {"title": title, "items": []}
    # más páginas de "para vos" (la continuación del inicio)
    def more_for_you():
        items, tok = [], None
        for c in grid.get("contents", []):
            tok = c.get("continuationItemRenderer", {}).get("continuationEndpoint", {}).get("continuationCommand", {}).get("token") or tok
        for _ in range(2):
            if not tok:
                break
            r = browse({"continuation": tok}, ck)
            tok = None
            for a in r.get("onResponseReceivedActions", []):
                its = a.get("appendContinuationItemsAction", {}).get("continuationItems", [])
                items += grid_items(its)
                for c in its:
                    tok = c.get("continuationItemRenderer", {}).get("continuationEndpoint", {}).get("continuationCommand", {}).get("token") or tok
        return items

    # "porque viste…": relacionados de lo último que viste
    def because():
        try:
            hist = [h for h in dedup(find_lockups(browse({"browseId": "FEhistory"}, ck)))
                    if len(h["name"].replace("\u200b", "").strip()) >= 3][:5]
        except Exception:
            hist = []
        with ThreadPoolExecutor(5) as ex2:
            rel = list(ex2.map(lambda v: related(v["id"].removeprefix("yt:"), ck), hist))
        return [{"title": "Porque viste «" + h["name"][:40] + "»", "items": r[:20]} for h, r in zip(hist, rel) if len(r) >= 4]

    with ThreadPoolExecutor(10) as ex:
        f_more = ex.submit(more_for_you)
        f_because = ex.submit(because)
        shelves = list(ex.map(chip, chips[1:25]))         # [0] = "Todos" (es el "para vos")
        try:
            more = f_more.result()
        except Exception:
            more = []
        try:
            bec = f_because.result()
        except Exception:
            bec = []
    first = grid_items(grid.get("contents", []))
    more = [x for x in dedup(more) if x["id"] not in {y["id"] for y in first}]
    res = {"forYou": first, "more": more, "because": bec, "shelves": [s for s in shelves if len(s["items"]) >= 4]}
    os.makedirs(CACHE, exist_ok=True)
    json.dump(res, open(path, "w"))
    out(res)


def cmd_account():
    """Tu cuenta para el encabezado de YouTube: nombre, @, foto, suscriptores,
    videos y cuántos canales seguís (caché 6 h)."""
    import re
    path = os.path.join(CACHE, "yt-account.json")
    try:
        if time.time() - os.path.getmtime(path) < 6 * 3600:
            return out(json.load(open(path)))
    except OSError:
        pass
    ck = yt_cookies()
    h = browse({}, ck, "account/account_menu")["actions"][0]["openPopupAction"]["popup"]["multiPageMenuRenderer"]["header"]["activeAccountHeaderRenderer"]
    res = {"name": txt(h.get("accountName")), "handle": txt(h.get("channelHandle")),
           "avatar": re.sub(r"=s\d+", "=s240", (h.get("accountPhoto", {}).get("thumbnails") or [{}])[-1].get("url", "")),
           "subscribers": "", "videos": "", "following": 0}
    try:
        cid = browse({"url": "https://www.youtube.com/" + res["handle"]}, ck, "navigation/resolve_url")["endpoint"]["browseEndpoint"]["browseId"]
        hd = json.dumps(browse({"browseId": cid}, ck).get("header", {}), ensure_ascii=False)
        for t in re.findall(r'"content": ?"([^"]{1,60})"', hd):
            if "suscriptor" in t and not res["subscribers"]:
                res["subscribers"] = t
            elif re.match(r"^[\d.,]+ ?(k |mil )?videos?$", t) and not res["videos"]:
                res["videos"] = t
    except Exception:
        pass
    try:     # canales que seguís (solo la lista, no la barra lateral)
        s = json.dumps(browse({"browseId": "FEchannels"}, ck).get("contents", {}))
        res["following"] = s.count('"channelRenderer"')
    except Exception:
        pass
    os.makedirs(CACHE, exist_ok=True)
    json.dump(res, open(path, "w"))
    out(res)


if __name__ == "__main__":
    a = sys.argv[1:]
    try:
        {"home": cmd_home, "subsrelated": cmd_subsrelated, "feed": cmd_feed, "search": cmd_search, "meta": cmd_meta, "continue": cmd_continue, "dismiss": cmd_dismiss,
         "progress": cmd_progress, "account": cmd_account}[a[0]](*a[1:])
    except Exception as e:
        out({"error": str(e)[:200]})
