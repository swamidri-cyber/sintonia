#!/usr/bin/env python3
"""rice-cine — control del Chromecast (etapa B).

  cast.py discover                  → [{"name","uuid","host","model"}] (y lo guarda en caché)
  cast.py run <uuid> <host> <name>  → controla ese Chromecast por stdin/stdout

En "run" recibe por stdin una orden JSON por línea:
  {"cmd":"load","url":…,"type":…,"title":…,"image":…,"start":s,
   "subs":url|null,"subsInband":bool,"style":{…}}
  {"cmd":"toggle"} {"cmd":"pause"} {"cmd":"play"} {"cmd":"seek","t":s}
  {"cmd":"volume","d":±0.05} {"cmd":"subs","on":bool} {"cmd":"stop"}
y manda por stdout:
  {"ev":"cast","state":"PLAYING|PAUSED|BUFFERING|IDLE","time":s,"dur":s,
   "idle":"FINISHED|…","volume":0-1,"texts":[ids de pistas de texto],"sub":bool}
  {"ev":"castError","msg":…}
Corre con el venv del cine (ahí está pychromecast).
"""
import json
import os
import re
import sys
import threading
import time
from uuid import UUID

import pychromecast
from pychromecast.discovery import discover_chromecasts

import lugares  # carpetas de SINTONÍA

CACHE = os.path.join(lugares.CACHE, "casts.json")
# todas las teles que se vieron alguna vez (no se borra): algunas Android TV dejan
# de anunciarse por mDNS aunque sigan prendidas y contestando en 8009
SEEN = os.path.join(lugares.STATE, "casts-seen.json")
lock = threading.Lock()


def out(**kw):
    with lock:
        sys.stdout.write(json.dumps(kw, ensure_ascii=False) + "\n")
        sys.stdout.flush()


def alive(host, port=8009):
    import socket
    try:
        socket.create_connection((host, port), timeout=1.5).close()
        return True
    except OSError:
        return False


def avahi():
    """Plan B: el mismo buscador que usa el sistema (anda aunque falle el de Python)."""
    import subprocess
    try:
        out = subprocess.run(["avahi-browse", "-rtp", "_googlecast._tcp"], capture_output=True, text=True, timeout=8).stdout
    except Exception:
        return []
    found = {}
    for line in out.splitlines():
        f = line.split(";")
        if len(f) < 10 or f[0] != "=" or f[2] != "IPv4":
            continue
        txt = dict(re.findall(r'"(\w+)=([^"]*)"', f[9]))
        if txt.get("id") and txt.get("fn"):
            u = txt["id"]
            uuid = f"{u[0:8]}-{u[8:12]}-{u[12:16]}-{u[16:20]}-{u[20:32]}"
            found[uuid] = {"name": txt["fn"], "uuid": uuid, "host": f[7], "model": txt.get("md", "")}
    return list(found.values())


def discover():
    found = []
    try:
        infos, browser = discover_chromecasts(timeout=5)
        browser.stop_discovery()
        found = [{"name": i.friendly_name, "uuid": str(i.uuid), "host": i.host, "model": i.model_name or ""}
                 for i in infos if i.cast_type in (None, "cast")]
    except Exception:
        pass
    if not found:
        found = avahi()
    # los que ya conocíamos (alguna vez) y siguen contestando no se olvidan
    old = []
    for f in (CACHE, SEEN):
        try:
            old += json.load(open(f))
        except Exception:
            pass
    have = {d["uuid"] for d in found}
    for d in old:
        if d["uuid"] not in have and alive(d["host"]):
            found.append(d); have.add(d["uuid"])
    # anotar en el registro permanente (con la IP más nueva)
    seen = {d["uuid"]: d for d in old}
    seen.update({d["uuid"]: d for d in found})
    os.makedirs(os.path.dirname(SEEN), exist_ok=True)
    json.dump(list(seen.values()), open(SEEN, "w"), ensure_ascii=False)
    os.makedirs(os.path.dirname(CACHE), exist_ok=True)
    json.dump(found, open(CACHE, "w"), ensure_ascii=False)
    print(json.dumps(found, ensure_ascii=False))


def run(uuid, host, name):
    cc = pychromecast.get_chromecast_from_host((host, 8009, UUID(uuid), None, name), tries=3, timeout=10)
    cc.wait(timeout=20)
    mc = cc.media_controller
    st = {"sub": False, "inband": False, "texts": [], "loaded": False}

    class L:
        def new_media_status(self, s):
            pass

        def load_media_failed(self, item, code):
            out(ev="castError", msg=f"El Chromecast no pudo abrir el video (error {code})")

    mc.register_status_listener(L())

    def text_ids():
        tr = getattr(mc.status, "subtitle_tracks", None)
        return [t["trackId"] for t in (tr or []) if t.get("type") == "TEXT"]

    def report():
        while True:
            time.sleep(0.5)
            s = mc.status
            if not st["loaded"]:
                continue
            try:
                texts = text_ids()
                # subtítulos del archivo (vienen en el HLS): aparecen recién al cargar
                if st["inband"] and st["sub"] and texts and not s.current_subtitle_tracks:
                    mc.enable_subtitle(texts[0])
                out(ev="cast", state=s.player_state, time=round(s.adjusted_current_time or 0, 2), dur=s.duration or 0,
                    idle=s.idle_reason or "", volume=round(cc.status.volume_level if cc.status else 0, 2),
                    texts=texts, sub=bool(s.current_subtitle_tracks))
            except Exception:
                pass
    threading.Thread(target=report, daemon=True).start()

    out(ev="castReady", name=cc.cast_info.friendly_name)
    for line in sys.stdin:
        try:
            c = json.loads(line)
        except Exception:
            continue
        k = c.get("cmd")
        try:
            if k == "load":
                st["inband"] = bool(c.get("subsInband"))
                st["sub"] = bool(c.get("subs")) or st["inband"]
                extra = {}
                if c.get("hls"):
                    extra["hlsSegmentFormat"] = "fmp4"
                    extra["hlsVideoSegmentFormat"] = "fmp4"
                if c.get("style"):
                    extra["textTrackStyle"] = c["style"]
                if c.get("subs"):
                    extra["tracks"] = [{"trackId": 1, "type": "TEXT", "subtype": "SUBTITLES", "language": "es",
                                        "name": "Español", "trackContentId": c["subs"], "trackContentType": "text/vtt"}]
                st["loaded"] = False
                mc.play_media(c["url"], c.get("type") or "application/x-mpegurl", title=c.get("title", ""),
                              thumb=c.get("image") or None, current_time=float(c.get("start") or 0),
                              stream_type="BUFFERED", media_info=extra)
                mc.block_until_active(timeout=30)
                st["loaded"] = True
                if c.get("subs"):
                    time.sleep(1)
                    mc.enable_subtitle(1)
            elif k == "youtube":           # YouTube: la app oficial de la tele
                from pychromecast.quick_play import quick_play
                st["loaded"] = False
                quick_play(cc, "youtube", {"media_id": c["id"]})
                time.sleep(2)
                if float(c.get("start") or 0) > 5:
                    try:
                        mc.block_until_active(timeout=15)
                        time.sleep(2)
                        mc.seek(float(c["start"]))
                    except Exception:
                        pass
                st["loaded"] = True
            elif k == "toggle":
                mc.pause() if mc.status.player_state == "PLAYING" else mc.play()
            elif k == "pause":
                mc.pause()
            elif k == "play":
                mc.play()
            elif k == "seek":
                mc.seek(max(0.0, float(c["t"])))
            elif k == "volume":
                v = cc.status.volume_level if cc.status else 0.5
                v = float(c["v"]) if "v" in c else v + float(c["d"])
                cc.set_volume(min(1.0, max(0.0, v)))
            elif k == "subs":
                st["sub"] = bool(c["on"])
                if c["on"]:
                    ids = text_ids()
                    if ids:
                        mc.enable_subtitle(ids[0])
                else:
                    mc.disable_subtitle()
            elif k == "stop":
                try:
                    cc.quit_app()
                except Exception:
                    pass
                time.sleep(0.5)
                break
        except Exception as e:
            out(ev="castError", msg=str(e)[:150])
    cc.disconnect(timeout=3)


if __name__ == "__main__":
    if sys.argv[1] == "discover":
        discover()
    else:
        try:
            run(*sys.argv[2:5])
        except Exception as e:
            out(ev="castError", msg="No pude conectar con el Chromecast: " + str(e)[:120])
