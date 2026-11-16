#!/usr/bin/env python3
"""rice-cine — reproductor del modo cine (etapa 2).

  player.py '<json>'

json = { type, id, videoId, name, lang, subs (bool), start (s), streams: [...] }
(streams = las de "stremio.py streams" del idioma elegido, mejor primero)

1. Se asegura de que el servidor de Stremio esté andando (127.0.0.1:11470);
   si la app no está abierta, levanta solo el servidor del flatpak.
2. Prueba las fuentes en orden: abre el torrent, mira las pistas con ffprobe
   y elige el audio del idioma pedido (si la fuente no lo tiene, pasa a la
   siguiente) y los subtítulos en español (del archivo o de OpenSubtitles).
3. Abre mpv a pantalla completa (app-id rice-cine-player, sin controles
   propios: los dibuja rice-cine encima) y lo maneja por su socket.
4. Guarda el progreso en tu cuenta de Stremio cada minuto y al salir.

Por stdout manda una línea JSON por evento:
  {"ev":"status","msg":…}           mientras conecta / prueba fuentes
  {"ev":"stats","peers":…,"speed":…,"progress":…}
  {"ev":"playing","source":…}       arrancó mpv
  {"ev":"state","pos":…,"dur":…,"pause":…,"buffering":…,"cache":…,"subDelay":…}
  {"ev":"tracks","audio":[…],"subs":[…],"aid":…,"sid":…}
  {"ev":"ended","pos":…,"dur":…,"finished":bool}
  {"ev":"error","msg":…}
Por stdin recibe órdenes: pause | seek <s> | seekto <s> | aid <n> |
  sid <n|no> | subdelay <+-s> | subdelayset <s> | volume <+-n> | quit |
  pauseset <0|1> | hide (pausa y esconde mpv) | show (lo vuelve a mostrar)

  player.py --serve '<json>'   (lo usa player-link.py)
Modo sesión: corre aparte del cine (systemd-run) y en vez de stdin/stdout usa
el socket $XDG_RUNTIME_DIR/rice-cine-player.sock, así la película sigue viva
aunque el cine se cierre o se recargue. Al conectarse alguien le repite el
estado actual (evento "session" con el json del arranque, tracks, state…).
Como está en $XDG_RUNTIME_DIR, al reiniciar la PC no queda nada.
"""
import json
import queue
import re
import signal
import os
import socket
import subprocess
import sys
import threading
import time
import urllib.parse
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stremio  # noqa: E402
import subsync  # noqa: E402
import numpy as np  # noqa: E402

import lugares  # carpetas de SINTONÍA
import canal  # sockets locales (Linux y Windows)

SERVER = "http://127.0.0.1:11470"
RUNTIME = lugares.RUNTIME
SUBDIR = os.path.join(stremio.CACHE, "subs")
STATE = lugares.STATE
DELAYS = os.path.join(STATE, "subdelay.json")
# Refuerzo de volumen en la tele: la ganancia la aplica el ffmpeg de Stremio
# (~/.var/app/com.stremio.Stremio/rice-ffmpeg, puesto con FFMPEG_BIN) leyendo
# GAIN_FILE; cada tele recuerda su refuerzo en BOOSTS (uuid → 1.0-3.0).
GAIN_FILE = os.path.expanduser("~/.var/app/com.stremio.Stremio/rice-gain")
BOOSTS = os.path.join(STATE, "boost.json")


def set_gain(g):
    try:
        if g > 1.001:
            with open(GAIN_FILE, "w") as f:
                f.write(f"{g:.2f}\n")
        elif os.path.exists(GAIN_FILE):
            os.remove(GAIN_FILE)
    except OSError:
        pass      # ajustes a mano de cada archivo + subtítulo
VIDEO_EXT = (".mkv", ".mp4", ".avi", ".m4v", ".webm", ".mov", ".ts", ".wmv")

# códigos de idioma de las pistas (ISO 639-2) para cada idioma del menú
LANG_CODES = {
    "en": {"eng", "en"}, "ko": {"kor", "ko"}, "ja": {"jpn", "ja"}, "fr": {"fre", "fra", "fr"},
    "de": {"ger", "deu", "de"}, "it": {"ita", "it"}, "pt": {"por", "pt", "pob"}, "zh": {"chi", "zho", "zh", "cmn"},
    "hi": {"hin", "hi"}, "ru": {"rus", "ru"}, "da": {"dan", "da"}, "sv": {"swe", "sv"}, "no": {"nor", "nob", "no"},
    "fi": {"fin", "fi"}, "nl": {"dut", "nld", "nl"}, "pl": {"pol", "pl"}, "tr": {"tur", "tr"}, "fa": {"per", "fas"},
    "th": {"tha"}, "id": {"ind"}, "he": {"heb"}, "el": {"gre", "ell"}, "cs": {"cze", "ces"}, "hu": {"hun"},
    "ro": {"rum", "ron"}, "uk": {"ukr"}, "ar": {"ara"},
    "es-ES": {"spa", "es", "esp"}, "es-419": {"spa", "es", "esp", "spl"},
}
LATINO = ("latino", "latin", "lat", "mex", "méxico", "mexico", "419", "latinoam")
ESPANA = ("castellano", "españa", "espana", "spain", "castilian", "european", "es-es")

lock = threading.Lock()

# ── Sesión ─────────────────────────────────────────────────────────────────
#  serving: modo --serve. clients: conexiones del cine (puede no haber
#  ninguna mientras el cine está cerrado). replay: último evento de cada tipo,
#  para ponerse al día al reconectarse. cmds: órdenes que llegan del cine.
SES = {"serving": False, "clients": [], "replay": {}, "mpv": False}
REPLAY = ("session", "status", "stats", "playing", "tracks", "state")
cmds = queue.Queue()


def emit(**kw):
    line = (json.dumps(kw, ensure_ascii=False) + "\n").encode()
    with lock:
        if kw.get("ev") in REPLAY:
            SES["replay"][kw["ev"]] = line
        if not SES["serving"]:
            sys.stdout.buffer.write(line)
            sys.stdout.flush()
            return
        for c in list(SES["clients"]):
            try:
                c.sendall(line)
            except OSError:
                SES["clients"].remove(c)


def serve():
    """Escucha al cine en el canal "player". Un "quit" antes de que arranque mpv corta
    la búsqueda de fuentes; después, las órdenes van a la cola de mpv."""
    srv = canal.escuchar("player", 4)
    SES["serving"] = True

    def client(c):
        with lock:
            for ev in REPLAY:
                if ev in SES["replay"]:
                    try:
                        c.sendall(SES["replay"][ev])
                    except OSError:
                        return
            SES["clients"].append(c)
        buf = b""
        while True:
            try:
                chunk = c.recv(4096)
            except OSError:
                chunk = b""
            if not chunk:
                break
            buf += chunk
            while b"\n" in buf:
                line, buf = buf.split(b"\n", 1)
                line = line.decode(errors="replace").strip()
                if line == "quit" and not SES["mpv"]:
                    end_session()
                    os._exit(0)
                if line:
                    cmds.put(line)
        with lock:
            if c in SES["clients"]:
                SES["clients"].remove(c)

    def accept():
        while True:
            c, _ = srv.accept()
            threading.Thread(target=client, args=(c,), daemon=True).start()
    threading.Thread(target=accept, daemon=True).start()


def end_session():
    set_gain(1.0)                      # el refuerzo nunca queda puesto para otra cosa
    if not SES["serving"]:
        return
    canal.cerrar("player")
    with lock:
        for c in SES["clients"]:
            try:
                c.shutdown(socket.SHUT_RDWR)
                c.close()
            except OSError:
                pass
        SES["clients"].clear()


def commands():
    """Las órdenes del cine: de stdin (modo viejo) o del socket (sesión)."""
    if not SES["serving"]:
        yield from sys.stdin
        return
    while True:
        yield cmds.get()


def move_player(workspace):
    """(rice-cine movía la ventana de mpv con Hyprland; en SINTONÍA el video está
    adentro de la app, así que no hay nada que mover)"""


def http_json(url, data=None, timeout=10):
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"} if data else {})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.load(r)


# ── Servidor de Stremio ─────────────────────────────────────────────────────
def server_up():
    try:
        urllib.request.urlopen(SERVER + "/settings", timeout=2).read()
        return True
    except Exception:
        return False


def server_cmd():
    """Cómo prender el servidor de Stremio: el que viene con SINTONÍA, o el de
    una app de Stremio instalada (flatpak, paquete) con su node."""
    import shutil
    exe = ".exe" if os.name == "nt" else ""
    data = lugares.DATA
    for base in (os.path.join(data, "stremio"), os.path.join(os.path.dirname(data), "stremio")):
        js = os.path.join(base, "server.js")
        node = os.path.join(base, "node" + exe)
        if os.path.exists(js):
            if os.path.exists(node):
                return [node, js], base
            if shutil.which("node"):
                return [shutil.which("node"), js], base
    if os.name != "nt" and shutil.which("flatpak") and (os.path.isdir("/var/lib/flatpak/app/com.stremio.Stremio") or
                                                       os.path.isdir(os.path.expanduser("~/.local/share/flatpak/app/com.stremio.Stremio"))):
        return ["flatpak", "run", "--command=node", "com.stremio.Stremio", "/app/libexec/stremio/server.js"], None
    for js in ("/usr/share/stremio/server.js", "/opt/stremio/server.js", "/usr/lib/stremio/server.js",
               os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "LNV", "Stremio-4", "server.js")):
        if os.path.exists(js):
            node = os.path.join(os.path.dirname(js), "stremio-runtime" + exe)
            node = node if os.path.exists(node) else shutil.which("node")
            if node:
                return [node, js], os.path.dirname(js)
    return None, None


def ensure_server():
    if server_up():
        return True
    cmd, cwd = server_cmd()
    if not cmd:
        return False
    emit(ev="status", msg="PRENDIENDO EL SERVIDOR DE STREMIO…")
    env = dict(os.environ)
    env.setdefault("APP_PATH", os.path.join(lugares.DATA_USER, "stremio-server"))
    os.makedirs(env["APP_PATH"], exist_ok=True)
    env["NO_CORS"] = "1"
    kw = {"creationflags": 0x00000008 | 0x00000200 | 0x08000000} if os.name == "nt" else {"start_new_session": True}
    subprocess.Popen(cmd, cwd=cwd, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     stdin=subprocess.DEVNULL, **kw)
    for _ in range(60):
        time.sleep(0.5)
        if server_up():
            return True
    return False


# ── Una fuente: abrir el torrent, elegir el archivo, ver las pistas ────────
def open_torrent(s):
    """→ (url, nombre de archivo, tamaño en bytes)"""
    h = s["hash"].lower()
    info = http_json(f"{SERVER}/{h}/create", data=json.dumps({"torrent": {"infoHash": h}}).encode(), timeout=40)
    files = info.get("files") or []
    idx = s.get("fileIdx")
    if idx is None or idx < 0 or idx >= len(files):
        vids = [(i, f) for i, f in enumerate(files) if f.get("name", "").lower().endswith(VIDEO_EXT)]
        if not vids:
            raise RuntimeError("el torrent no tiene videos")
        idx = max(vids, key=lambda t: t[1].get("length", 0))[0]
    f = files[idx] if idx < len(files) else {}
    return f"{SERVER}/{h}/{idx}", f.get("name") or s.get("filename") or "", f.get("length") or 0


def stats_loop(h, idx, stop, alive):
    """Manda cómo viene la descarga; alive["peers"] = pares conectados."""
    while not stop.is_set():
        try:
            st = http_json(f"{SERVER}/{h}/{idx}/stats.json", timeout=3)
            alive["peers"] = max(alive["peers"], st.get("peers", 0) or 0)
            emit(ev="stats", peers=st.get("peers", 0), speed=round((st.get("downloadSpeed") or 0) / 1048576, 2),
                 progress=round(st.get("streamProgress") or 0, 4))
        except Exception:
            pass
        stop.wait(1.0)


def probe_watched(url, timeout, alive, dead_after=15):
    """ffprobe, pero si en dead_after segundos no apareció ningún par, se corta."""
    res = {}

    def run():
        try:
            res["ok"] = probe(url, timeout)
        except Exception as e:
            res["err"] = e
    t = threading.Thread(target=run, daemon=True)
    t.start()
    t0 = time.time()
    while t.is_alive():
        t.join(0.5)
        if alive["peers"] == 0 and time.time() - t0 > dead_after:
            raise RuntimeError("sin pares")
    if "err" in res:
        raise res["err"]
    return res["ok"]


def probe(url, timeout):
    r = subprocess.run(["ffprobe", "-v", "error", "-show_entries",
                        "stream=index,codec_type,codec_name:stream_tags=language,title:stream_disposition=forced,default",
                        "-of", "json", url], capture_output=True, text=True, timeout=timeout)
    streams = json.loads(r.stdout or "{}").get("streams") or []
    audio, subs = [], []
    for st in streams:
        tags = st.get("tags") or {}
        t = {"lang": (tags.get("language") or "").lower(), "title": tags.get("title") or "",
             "codec": st.get("codec_name") or "", "forced": bool((st.get("disposition") or {}).get("forced"))}
        if st.get("codec_type") == "audio":
            audio.append(t)
        elif st.get("codec_type") == "subtitle":
            subs.append(t)
    if not audio:
        raise RuntimeError("no se pudo leer el archivo")
    return audio, subs


def pick_audio(audio, lang, orig):
    """mpv numera las pistas de audio desde 1, en orden. None = no está."""
    codes = LANG_CODES.get(lang, {lang})

    def is_lang(t):
        if t["lang"] not in codes:
            return False
        title = t["title"].lower()
        if lang == "es-419":
            return any(k in title for k in LATINO) or not any(k in title for k in ESPANA)
        if lang == "es-ES":
            return not any(k in title for k in LATINO)
        return True

    exact = [i for i, t in enumerate(audio) if is_lang(t)]
    if lang == "es-419":   # preferir la que dice "latino" de verdad
        named = [i for i in exact if any(k in audio[i]["title"].lower() for k in LATINO)]
        exact = named or exact
    if exact:
        return exact[0] + 1
    if lang == orig and all(not t["lang"] or t["lang"] == "und" for t in audio):
        return 1          # sin etiquetas: el primero suele ser el original
    if lang == orig and len(audio) == 1:
        return 1          # una sola pista en una fuente "original"
    return None


def pick_sub(subs):
    """Subtítulos en español del archivo: latino primero; los de España solo si
    no hay otros. → (número de pista para mpv, ¿es de España?) o (None, False)"""
    es = [i for i, t in enumerate(subs) if t["lang"] in ("spa", "es", "esp", "spl")]
    full = [i for i in es if not subs[i]["forced"] and "forz" not in subs[i]["title"].lower()
            and "forced" not in subs[i]["title"].lower()]
    lst = full or es
    if not lst:
        return None, False
    lat = [i for i in lst if any(k in subs[i]["title"].lower() for k in LATINO)]
    if lat:
        return lat[0] + 1, False
    neutral = [i for i in lst if not any(k in subs[i]["title"].lower() for k in ESPANA)]
    if neutral:
        return neutral[0] + 1, False
    return lst[0] + 1, True


# Cuánto "suena a España" un subtítulo: vosotros, habéis/tenéis…, "os", vale,
# ordenador. España da ~0,03; latino, ~0
SPAIN = re.compile(r"\b(vosotr[oa]s|vuestr[oa]s?|os|vale|gilipollas|ordenador|coger(?=\s+el\s+coche))\b"
                   r"|\b\w+(?:[áé]is)\b", re.I)
LATAM = re.compile(r"\b(ustedes|computadora|carro|ahorita|plata|chévere|platicar|celular|pendejo|güey|boludo)\b", re.I)


def spainness(text):
    lines = max(1, text.count("\n") // 4)
    return (len(SPAIN.findall(text)) - 0.5 * len(LATAM.findall(text))) / lines


def download_subs(type_, video_id, filename, size):
    try:
        lst = stremio.get_json_subs(type_, video_id, filename, str(size or ""))
    except Exception:
        return None
    os.makedirs(SUBDIR, exist_ok=True)
    # OpenSubtitles no separa latino de España: se bajan varios y se elige el
    # que menos suena a España (en empate, el que mejor calza con el archivo)
    best = None
    for i, sub in enumerate(lst[:6]):
        path = os.path.join(SUBDIR, f"{video_id.replace(':', '_')}-{sub.get('id') or i}.srt")
        try:
            if not os.path.exists(path):
                with urllib.request.urlopen(urllib.request.Request(sub["url"], headers=stremio.UA), timeout=20) as r:
                    data = r.read()
                if len(data) < 200:
                    continue
                with open(path, "wb") as f:
                    f.write(data)
            with open(path, encoding="utf-8", errors="replace") as f:
                sc = spainness(f.read())
        except Exception:
            continue
        if best is None or sc < best[0] - 0.01:
            best = (sc, path)
        if sc < 0.01:
            break                  # ya es latino: no hace falta seguir bajando
    return best[1] if best else None


# ── mpv ─────────────────────────────────────────────────────────────────────
def settings():
    """settings.json (CONFIGURACIÓN): tipografía, tamaño y altura de los subtítulos…"""
    d = {"subFont": "Figtree SemiBold", "subSize": 34, "subMargin": 34, "subMarginControls": 140}
    for f in (os.path.join(os.path.dirname(os.path.abspath(__file__)), "settings.default.json"),
              os.path.join(lugares.CONFIG, "settings.json")):
        try:
            d.update(json.load(open(f, encoding="utf-8")))
        except Exception:
            pass
    return d


def sub_style():
    # tamaños en la escala de mpv (relativa a 720 de alto: ×1,5 en 1080p)
    c = settings()
    return [f"--sub-font={c['subFont']}", "--sub-bold=no", f"--sub-font-size={c['subSize']}",
            f"--sub-color={c.get('subColor', '#FFFFFF')}", "--sub-outline-color=#000000", f"--sub-outline-size={c.get('subOutline', 0)}",
            "--sub-shadow-color=#000000B4", f"--sub-shadow-offset={c.get('subShadow', 1.5)}", f"--sub-margin-y={c['subMargin']}",
            "--sub-fonts-dir=" + lugares.FONTS]


def audio_filter():
    """Modo noche (comprime los picos) y voces más claras (realza 1-4 kHz)."""
    c = settings()
    f = []
    if c.get("dialogBoost"):
        f.append("lavfi=[equalizer=f=2500:t=q:w=1.2:g=5,equalizer=f=120:t=q:w=1:g=-3]")
    if c.get("nightMode"):
        f.append("lavfi=[dynaudnorm=f=250:g=15:m=12:p=0.9]")
    return ",".join(f)


def apply_cfg(mpv):
    """Ajustes cambiados desde CONFIGURACIÓN con la película andando."""
    c = settings()
    for k, v in (("sub-font", c["subFont"]), ("sub-font-size", c["subSize"]), ("sub-color", c.get("subColor", "#FFFFFF")),
                 ("sub-outline-size", c.get("subOutline", 0)), ("sub-shadow-offset", c.get("subShadow", 1.5)),
                 ("sub-margin-y", c["subMargin"]), ("af", audio_filter())):
        mpv.cmd("set_property", k, v)


def order_streams(streams):
    """Calidad elegida en CONFIGURACIÓN. Liviana = el orden que ya viene
    (1080p más chico con seeds); equilibrada = 1080p más grande hasta 8 GB;
    máxima = lo de más resolución y peso, con algo de seeds."""
    q = settings().get("quality", "light")
    if q == "light" or not streams:
        return streams
    ok = [x for x in streams if (x.get("seeds") or 0) >= 3] or streams
    rest = [x for x in streams if x not in ok]
    if q == "balanced":
        key = lambda x: (x.get("res") == 1080 and (x.get("size") or 0) <= 8, x.get("size") or 0)
    else:
        key = lambda x: (x.get("res") or 0, x.get("size") or 0)
    return sorted(ok, key=key, reverse=True) + rest


def force_fullscreen():
    """El video ya está en la ventana de la app (pantalla completa): solo avisar."""
    emit(ev="fullscreen")


class Mpv:
    """mpv adentro de SINTONÍA (sintonia/video.py): canal "mpv" + el mismo
    JSON que el socket de mpv. La primera línea le pasa los argumentos."""

    def __init__(self, args):
        self.args = args
        self.sock = None
        self.buf = b""
        self.props = {}
        self.req = 0
        self.vivo = False

    def connect(self):
        for _ in range(100):
            try:
                s = canal.conectar("mpv", timeout=3)
                s.sendall((json.dumps({"open": self.args}) + "\n").encode())
                self.sock = s
                self.vivo = True
                return True
            except OSError:
                time.sleep(0.1)
        return False

    def poll(self):
        """como Popen.poll(): None mientras la película está abierta"""
        return None if self.vivo else 0

    def cmd(self, *args):
        self.req += 1
        try:
            self.sock.sendall((json.dumps({"command": list(args), "request_id": self.req}) + "\n").encode())
        except OSError:
            pass

    def read_events(self, on_event):
        while True:
            try:
                chunk = self.sock.recv(65536)
            except OSError:
                self.vivo = False
                return
            if not chunk:
                self.vivo = False
                return
            self.buf += chunk
            while b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                try:
                    on_event(json.loads(line))
                except Exception:
                    pass


def main():
    if sys.argv[1] == "--serve":
        job = json.loads(sys.argv[2])
        serve()
    else:
        job = json.loads(sys.argv[1])
    for sig in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(sig, on_signal)
    threading.Thread(target=flush_pending, daemon=True).start()
    # lo que el cine necesita para rearmar la pantalla al volver
    emit(ev="session", ui=job.get("ui"), type=job.get("type"), id=job.get("id"), videoId=job.get("videoId"))
    type_, video_id = job["type"], job["videoId"]
    lang, orig = job.get("lang") or "", job.get("original") or ""
    want_subs = bool(job.get("subs"))
    start = float(job.get("start") or 0)

    if job.get("type") == "video":
        youtube(job)
        return
    if job.get("type") == "archivo":      # un video de la compu: sin Stremio ni cuenta
        args = ["mpv", job["url"], "--keep-open=yes", "--no-osc", "--osd-level=0", "--save-position-on-quit=no",
                "--no-resume-playback"] + sub_style() + ([f"--af={audio_filter()}"] if audio_filter() else [])
        run_mpv(job, args, {"s": {"title": job.get("name", ""), "res": 0, "hash": ""}, "url": job["url"]}, None, "", 0)
        return
    if not ensure_server():
        emit(ev="error", msg="No arrancó el servidor de Stremio")
        return

    # Probar fuentes hasta encontrar una que ande y tenga el idioma
    chosen = None
    fallback = None
    job["streams"] = order_streams(job.get("streams") or [])
    total = len(job.get("streams") or [])
    for n, s in enumerate(job.get("streams") or []):
        if not s.get("hash"):
            continue
        emit(ev="status", msg=f"FUENTE {n + 1} DE {total}: {s['res']}p · {s['size']} GB · {s['seeds']} SEEDS",
             source=s.get("title", ""))
        stop = threading.Event()
        try:
            url, fname, fsize = open_torrent(s)
            h, idx = s["hash"].lower(), url.rsplit("/", 1)[1]
            alive = {"peers": 0}
            threading.Thread(target=stats_loop, args=(h, idx, stop, alive), daemon=True).start()
            audio, subs = probe_watched(url, 50 if n == 0 else 35, alive)
        except Exception as e:
            stop.set()
            emit(ev="status", msg=f"FUENTE {n + 1} SIN SEÑAL ({str(e)[:60]}) → PROBANDO OTRA")
            continue
        stop.set()
        aid = pick_audio(audio, lang, orig)
        cand = {"s": s, "url": url, "fname": fname, "fsize": fsize, "audio": audio, "subs": subs, "aid": aid}
        if aid:
            chosen = cand
            break
        fallback = fallback or cand
        emit(ev="status", msg=f"LA FUENTE {n + 1} NO TRAE ESE AUDIO → PROBANDO OTRA")
        if n >= 4:
            break
    if not chosen and fallback:
        chosen = fallback
        chosen["aid"] = 1
        emit(ev="status", msg="NO HABÍA ESE IDIOMA: VA CON EL AUDIO QUE TRAE EL ARCHIVO")
    if not chosen:
        emit(ev="error", msg="Ninguna fuente respondió. Probá de nuevo o con otro idioma.")
        return

    args = ["mpv", chosen["url"], "--fs", "--wayland-app-id=rice-cine-player", "--title=" + job.get("name", "Modo cine"),
            "--no-osc", "--osd-level=0", "--osd-playing-msg=", "--keep-open=yes",
            "--save-position-on-quit=no", "--no-resume-playback", "--cache=yes", "--demuxer-max-bytes=400MiB",
            "--demuxer-readahead-secs=60", "--cursor-autohide=always",
            f"--aid={chosen['aid']}",
            ] + sub_style() + ([f"--af={audio_filter()}"] if audio_filter() else [])
    if start > 5:
        args.append(f"--start={start:.0f}")
    sub_ext, sub_key = None, ""
    if want_subs:
        sid, spain = pick_sub(chosen["subs"])
        ext = None
        if spain:   # el archivo solo trae los de España: buscar latinos afuera
            emit(ev="status", msg="BUSCANDO SUBTÍTULOS LATINOS…")
            ext = download_subs(type_, video_id, chosen["fname"], chosen["fsize"])
            if ext and spainness(open(ext, encoding="utf-8", errors="replace").read()) > 0.015:
                ext = None
        if ext:
            args += [f"--sub-file={ext}", "--sid=auto"]
            sub_ext = ext
        elif sid:
            args.append(f"--sid={sid}")
            sub_key = f"sid{sid}"
        else:
            emit(ev="status", msg="BUSCANDO SUBTÍTULOS EN ESPAÑOL…")
            path = download_subs(type_, video_id, chosen["fname"], chosen["fsize"])
            if path:
                args += [f"--sub-file={path}", "--sid=auto"]
                sub_ext = path
            else:
                emit(ev="status", msg="NO HAY SUBTÍTULOS EN ESPAÑOL PARA ESTE ARCHIVO")
                args.append("--sid=no")
    else:
        args.append("--sid=no")

    # subtítulos de texto que trae el archivo (cualquier idioma): referencia exacta
    text_subs = [i for i, t in enumerate(chosen["subs"]) if t["codec"] in ("subrip", "ass", "ssa", "mov_text", "webvtt", "text")]
    chosen["refTrack"] = text_subs[0] if text_subs else None
    if job.get("target"):
        sid_inband = None
        if want_subs and not sub_ext:
            m = re.search(r"--sid=(\d+)", " ".join(args))
            sid_inband = int(m.group(1)) if m else None
        run_cast(job, chosen, sub_ext, sub_key, start, sid_inband)
        return
    run_mpv(job, args, chosen, sub_ext, sub_key, start)


# ── En la tele (etapa B) ─────────────────────────────────────────────────────
#  El Chromecast le pide el video al servidor de Stremio (que lo convierte a
#  HLS en H.264 si hace falta) y los subtítulos a web.py (puerto 20130).
#  cast.py (venv) habla con el Chromecast. Para el cine es igual que mpv:
#  mismos eventos (state, tracks, sync, ended) y mismas órdenes.
WEB_PORT = 20130
CAST_DIR = os.path.join(RUNTIME, "web", "cast")
CAST_PY = os.path.join(os.path.dirname(os.path.abspath(__file__)), "cast.py")
VENV_PY = os.path.expanduser("~/.local/share/rice-cine/venv/bin/python")


def lan_ip(host):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        s.connect((host, 8009))
        return s.getsockname()[0]
    finally:
        s.close()


def to_vtt(src, dst, speed, delay):
    """Subtítulos → WebVTT con el ajuste aplicado (como mpv: t·speed + delay)."""
    r = subprocess.run(["ffmpeg", "-v", "error", "-i", src, "-f", "webvtt", "-"], capture_output=True, timeout=60)
    text = r.stdout.decode("utf-8", errors="replace")

    def fix(m):
        h, mi, se, ms = m.group(1), m.group(2), m.group(3), m.group(4)
        t = (int(h or 0) * 3600 + int(mi) * 60 + int(se) + int(ms) / 1000) * speed + delay
        t = max(0.0, t)
        return f"{int(t // 3600):02d}:{int(t % 3600 // 60):02d}:{t % 60:06.3f}"
    text = re.sub(r"(?:(\d+):)?(\d{2}):(\d{2})\.(\d{3})", fix, text)
    with open(dst, "w", encoding="utf-8") as f:
        f.write(text)


def cast_master(url, ip, sess, aid, sid_inband):
    """La lista HLS de Stremio, con el audio elegido y (si van) los subtítulos
    del archivo; las direcciones quedan absolutas para que el Chromecast llegue."""
    q = "mediaURL=" + urllib.parse.quote(url, safe="") + "&videoCodecs=h264&audioCodecs=aac&audioCodecs=mp3&maxAudioChannels=2"
    base = f"http://{ip}:11470/hlsv2/{sess}/"
    text = urllib.request.urlopen(f"{SERVER}/hlsv2/{sess}/master.m3u8?{q}", timeout=60).read().decode()
    audios = re.findall(r'URI="(audio(\d+)\.m3u8[^"]*)"', text)
    keep_a = f"audio{max(0, (aid or 1) - 1)}.m3u8"
    if not any(a[0].startswith(keep_a) for a in audios):
        keep_a = audios[0][0].split("?")[0] if audios else ""
    keep_s = f"subtitle{sid_inband - 1}.m3u8" if sid_inband else None
    out = []
    for line in text.splitlines():
        if line.startswith("#EXT-X-MEDIA:TYPE=AUDIO") and keep_a not in line:
            continue
        if line.startswith("#EXT-X-MEDIA:TYPE=SUBTITLES"):
            if not keep_s or keep_s not in line:
                continue
            line = line.replace("AUTOSELECT=NO", "AUTOSELECT=YES").replace("DEFAULT=NO", "DEFAULT=YES")
        if line.startswith("#EXT-X-MEDIA:TYPE=AUDIO"):
            line = line.replace("DEFAULT=NO", "DEFAULT=YES")
        if line.startswith("#EXT-X-STREAM-INF") and not keep_s:
            line = re.sub(r',SUBTITLES="[^"]*"', "", line)
        line = re.sub(r'URI="([^"]+)"', lambda m: f'URI="{base}{m.group(1)}"', line)
        if line and not line.startswith("#"):
            line = base + line
        out.append(line)
    os.makedirs(CAST_DIR, exist_ok=True)
    name = f"{sess}.m3u8"
    with open(os.path.join(CAST_DIR, name), "w") as f:
        f.write("\n".join(out) + "\n")
    return f"http://{ip}:{WEB_PORT}/cast/{name}"


def sub_style_cast():
    """El estilo de settings.json traducido al del Chromecast."""
    cfg = settings()
    return {"backgroundColor": "#00000000", "foregroundColor": cfg.get("subColor", "#FFFFFF") + "FF", "edgeType": "DROP_SHADOW",
            "edgeColor": "#000000AA", "fontFamily": "Inter", "fontGenericFamily": "SANS_SERIF",
            "fontScale": round(float(cfg.get("subSize", 33)) / 40, 2), "fontStyle": "NORMAL"}


TEST_FLAG = os.path.join(RUNTIME, "sintonia-test")
TEST_TTL = 3 * 3600


def test_mode():
    """Modo prueba (qs -c rice-cine ipc call cine test true): no se guarda nada en la cuenta.
    Es SOLO el archivo (no job["nosave"]: el cine lo arrastraba de una prueba vieja y una
    peli entera en la tele quedó sin guardar) y vence a las 3 h para que no quede prendido."""
    try:
        if time.time() - os.path.getmtime(TEST_FLAG) < TEST_TTL:
            return True
        os.unlink(TEST_FLAG)
    except OSError:
        pass
    return False


# ── Progreso: se guarda pase lo que pase ────────────────────────────────────
#  Cada guardado se anota primero en PENDING y se borra cuando Stremio/YouTube
#  confirman; lo que quede (sin red, Stremio caído, PC apagada a mitad) se
#  reintenta en el próximo arranque del reproductor.
PENDING = os.path.join(STATE, "pending-progress.json")
save_lock = threading.Lock()
CUR = {}        # lo que se está viendo, para guardar al recibir SIGTERM/SIGHUP


def _pending(update):
    try:
        d = json.load(open(PENDING))
    except Exception:
        d = {}
    d[update["key"]] = update
    os.makedirs(STATE, exist_ok=True)
    tmp = PENDING + ".tmp"
    json.dump(d, open(tmp, "w"))
    os.replace(tmp, PENDING)
    return d


def _send_progress(rec):
    here = os.path.dirname(os.path.abspath(__file__))
    if rec["type"] == "video":
        cmd = [sys.executable, os.path.join(here, "youtube.py"), "progress", rec["id"], str(rec["pos"]),
               str(rec["dur"]), rec.get("name", ""), rec.get("channel", "")]
    else:
        cmd = [sys.executable, os.path.join(here, "stremio.py"), "progress", rec["type"], rec["id"], rec["videoId"],
               str(int(rec["pos"] * 1000)), str(int(rec["dur"] * 1000)), "1" if rec["finished"] else "0"]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=25)
        return r.returncode == 0 and '"error"' not in r.stdout
    except Exception:
        return False


def save_progress(job, pos, dur, start, finished):
    if test_mode() or job.get("type") == "archivo":
        return
    # menos de un minuto visto: no pisar dónde habías quedado (arranque en falso)
    if dur <= 0 or (not finished and pos - start < 60):
        return
    rec = {"key": f'{job["type"]}:{job["videoId"]}', "type": job["type"], "id": job["id"], "videoId": job["videoId"],
           "pos": dur if (finished and job["type"] == "video") else pos, "dur": dur, "finished": bool(finished),
           "name": job.get("name", ""), "channel": job.get("channel", ""), "ts": time.time()}
    with save_lock:
        try:
            _pending(rec)
        except Exception:
            pass
        for i in range(3):
            if _send_progress(rec):
                try:
                    with open(PENDING) as f:
                        d = json.load(f)
                    if d.get(rec["key"], {}).get("ts") == rec["ts"]:
                        d.pop(rec["key"])
                        tmp = PENDING + ".tmp"
                        json.dump(d, open(tmp, "w"))
                        os.replace(tmp, PENDING)
                except Exception:
                    pass
                return
            time.sleep(2 + 3 * i)


def flush_pending():
    """Lo que no se pudo guardar en sesiones anteriores."""
    if test_mode():
        return
    try:
        d = json.load(open(PENDING))
    except Exception:
        return
    for rec in sorted(d.values(), key=lambda r: r.get("ts", 0)):
        with save_lock:
            if _send_progress(rec):
                try:
                    cur = json.load(open(PENDING))
                    if cur.get(rec["key"], {}).get("ts") == rec["ts"]:
                        cur.pop(rec["key"])
                    json.dump(cur, open(PENDING + ".tmp", "w"))
                    os.replace(PENDING + ".tmp", PENDING)
                except Exception:
                    pass


def watch_progress(job, st, start, alive):
    """Guarda cada 30 s si la posición cambió (también en pausa, una vez).
    alive() = sigue la sesión; st tiene pos/dur."""
    CUR.update(job=job, st=st, start=start)
    last = None
    while alive():
        time.sleep(1)
        if time.time() - CUR.get("t", 0) < 30:
            continue
        pos = st.get("pos") or 0
        if last is None or abs(pos - last) >= 2:
            CUR["t"] = time.time()
            last = pos
            threading.Thread(target=save_progress, args=(job, pos, st.get("dur") or 0, start, False), daemon=True).start()


def on_signal(signum, frame):
    """Apagar la PC / reiniciar / matar la unidad: guardar ANTES de irse."""
    try:
        if CUR.get("st") and not CUR.get("done"):
            st = CUR["st"]
            dur = st.get("dur") or 0
            fin = bool(dur and (st.get("pos") or 0) / dur > 0.92)
            save_progress(CUR["job"], st.get("pos") or 0, dur, CUR["start"], fin)
    finally:
        end_session()
        os._exit(0)


def run_cast(job, chosen, sub_ext, sub_key, start, sid_inband):
    tg = job["target"]
    emit(ev="status", msg=f"CONECTANDO CON {tg['name'].upper()}…")
    try:
        ip = lan_ip(tg["host"])
    except OSError:
        emit(ev="error", msg="No encuentro la red de la tele")
        return
    cp = subprocess.Popen([VENV_PY, CAST_PY, "run", tg["uuid"], tg["host"], tg["name"]], stdin=subprocess.PIPE,
                          stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
    SES["mpv"] = True
    lock_c = threading.Lock()

    def send(**kw):
        with lock_c:
            try:
                cp.stdin.write(json.dumps(kw) + "\n")
                cp.stdin.flush()
            except Exception:
                pass

    yt = job.get("type") == "video"
    sess = f"rc{int(time.time())}"
    try:
        b = json.load(open(BOOSTS)).get(tg["uuid"]) or {}
        # se recuerda solo por 3 horas: a la noche siguiente la tele arranca normal
        boost = 1.0 if yt or time.time() - b.get("t", 0) > 3 * 3600 else min(3.0, max(1.0, float(b.get("b", 1.0))))
    except Exception:
        boost = 1.0
    vol = {"boost": boost, "cast": 1.0 if boost > 1 else None, "gen": 0}
    set_gain(boost)
    media, vtt_n = None, [0]
    sub = {"speed": 1.0, "delay": 0.0, "manual": False, "key": "", "on": bool(sub_ext or sid_inband)}
    if sub_ext or sub_key:
        sub["key"] = f'{chosen["s"]["hash"]}:{chosen["url"].rsplit("/", 1)[1]}:{os.path.basename(sub_ext) if sub_ext else sub_key}'
    try:
        saved = json.load(open(DELAYS)).get(sub["key"]) if sub["key"] else None
    except Exception:
        saved = None
    if saved is not None and sub_ext:
        sub["manual"], sub["delay"] = True, float(saved)

    def vtt_url():
        vtt_n[0] += 1
        name = f"{sess}-{vtt_n[0]}.vtt"
        to_vtt(sub_ext, os.path.join(CAST_DIR, name), sub["speed"], sub["delay"])
        return f"http://{ip}:{WEB_PORT}/cast/{name}"

    def load(at):
        nonlocal media
        if vol.get("remaster"):
            # refuerzo nuevo: sesión HLS nueva para que Stremio arranque otro ffmpeg
            vol["remaster"] = False
            media = cast_master(chosen["url"], ip, f"{sess}b{vol['gen']}", chosen.get("aid"), sid_inband)
        if yt:
            send(cmd="youtube", id=job["id"].removeprefix("yt:"), start=at)
            return
        send(cmd="load", url=media, hls=True, title=job.get("name", ""), image=(job.get("ui") or {}).get("play", {}).get("item", {}).get("background"),
             start=at, subs=vtt_url() if (sub_ext and sub["on"]) else None, subsInband=bool(sid_inband and sub["on"]),
             style=sub_style_cast())

    if not yt:
        emit(ev="status", msg="PREPARANDO EL VIDEO PARA LA TELE…")
        try:
            media = cast_master(chosen["url"], ip, sess, chosen.get("aid"), sid_inband)
        except Exception as e:
            emit(ev="error", msg="Stremio no pudo preparar el video: " + str(e)[:80])
            send(cmd="stop")
            return
    st = {"pos": start, "dur": 0.0, "pause": False, "buffering": True, "cache": 100, "subDelay": sub["delay"],
          "volume": round(boost * 100) if boost > 1 else 50, "boost": boost > 1, "eof": False, "state": "", "seen_play": False, "gone": False,
          "net": "", "dead": False}
    net = {"down_at": 0.0, "we_paused": False, "dead_since": 0.0}
    ready = threading.Event()

    def reader():
        for line in cp.stdout:
            try:
                e = json.loads(line)
            except Exception:
                continue
            if e.get("ev") == "castReady":
                ready.set()
            elif e.get("ev") == "castError":
                emit(ev="error" if not st["seen_play"] else "status", msg=e.get("msg", "Error del Chromecast"))
                if not st["seen_play"]:
                    st["gone"] = True
            elif e.get("ev") == "cast":
                stt = e.get("state") or ""
                st["state"] = stt
                if stt in ("PLAYING", "PAUSED", "BUFFERING"):
                    if not st["seen_play"]:
                        st["seen_play"] = True
                        emit(ev="casting", name=tg["name"])
                    st["pos"], st["dur"] = e.get("time") or st["pos"], e.get("dur") or st["dur"]
                    st["pause"], st["buffering"] = stt == "PAUSED", stt == "BUFFERING"
                    vol["cast"] = e.get("volume") or 0
                    st["volume"] = round(vol["boost"] * 100) if vol["boost"] > 1 else round(vol["cast"] * 100)
                    st["boost"] = vol["boost"] > 1
                    emit(ev="state", **{k: st[k] for k in ("pos", "dur", "pause", "buffering", "cache", "subDelay", "volume", "boost", "net")})
                elif stt == "IDLE" and st["seen_play"] and not st.get("reloading"):
                    why = e.get("idle") or ""
                    if why == "FINISHED":
                        st["eof"] = True
                        st["gone"] = True
                    elif st.get("quit"):
                        st["gone"] = True
                    elif why == "ERROR" or st["net"] or time.time() - net["down_at"] < 180:
                        # se cortó (internet / la fuente): la tele quedó en espera.
                        # No se termina: net_loop la vuelve a cargar en el mismo punto.
                        if not st["dead"]:
                            st["dead"], net["dead_since"] = True, time.time()
                            st["net"] = st["net"] or "retry"
                            emit_net()
                    else:
                        st["gone"] = True       # la cortaste desde la tele (u otra app la pisó)
        st["gone"] = True
    threading.Thread(target=reader, daemon=True).start()
    if not ready.wait(30):
        emit(ev="error", msg=f"No pude conectar con {tg['name']}")
        cp.kill()
        return
    emit(ev="playing", source=chosen["s"].get("title", ""), res=chosen["s"]["res"], target=tg["name"])
    if boost > 1:
        send(cmd="volume", v=1.0)      # con refuerzo, la tele va al máximo
    load(start)

    # ── Cortes de internet ─────────────────────────────────────────────────
    #  Se corta → pausa en la tele (no se gasta lo que tiene cargado).
    #  Vuelve → espera a que el torrent tenga pares y sigue sola. Si el
    #  Chromecast ya se había rendido (pantalla de espera), la vuelve a cargar
    #  en el mismo punto, con sesión HLS nueva. Se rinde recién a los 60 min.
    def emit_net():
        emit(ev="state", **{k: st[k] for k in ("pos", "dur", "pause", "buffering", "cache", "subDelay", "volume", "boost", "net")})

    def net_ok():
        for h, port in (("1.1.1.1", 443), ("8.8.8.8", 53), ("9.9.9.9", 443)):
            try:
                socket.create_connection((h, port), timeout=2).close()
                return True
            except OSError:
                pass
        return False

    def source_ready(limit=30):
        """Después del corte: hasta que el torrent vuelva a tener pares."""
        if yt or not chosen.get("url"):
            time.sleep(3)
            return
        t0 = time.time()
        while time.time() - t0 < limit and not st["gone"]:
            try:
                if (http_json(chosen["url"] + "/stats.json", timeout=3).get("peers") or 0) > 0:
                    time.sleep(2)
                    return
            except Exception:
                pass
            time.sleep(2)

    def revive():
        """La tele quedó en espera: cargar de nuevo un poco antes de donde iba."""
        st["reloading"] = True
        st["state"] = ""
        vol["gen"] += 1
        vol["remaster"] = not yt
        try:
            load(max(0.0, st["pos"] - 5))
        except Exception:
            pass
        t0 = time.time()
        while time.time() - t0 < 45 and st["state"] not in ("PLAYING", "PAUSED", "BUFFERING") and not st["gone"]:
            time.sleep(0.5)
        ok = st["state"] in ("PLAYING", "PAUSED", "BUFFERING")
        time.sleep(3)                   # que no cuente el IDLE de la carga vieja
        st["reloading"] = False
        return ok

    def net_loop():
        fails, wait, next_try = 0, 10, 0.0
        while not st["gone"] and not st.get("quit"):
            time.sleep(2)
            ok = net_ok()
            fails = 0 if ok else fails + 1
            if fails >= 2 and st["net"] != "down":
                st["net"], net["down_at"] = "down", time.time()
                if st["seen_play"] and not st["dead"] and not st["pause"]:
                    send(cmd="pause")
                    net["we_paused"] = True
                emit_net()
                continue
            if not ok:
                if st["net"] == "down":
                    net["down_at"] = time.time()
                continue
            if st["net"] == "down":                 # volvió
                st["net"] = "retry"
                emit_net()
                source_ready()
                if not st["dead"]:
                    if net["we_paused"]:
                        send(cmd="play")
                        # tras una pausa larga la tele a veces cierra el reproductor
                        # sin avisar: si no arranca, se carga de nuevo
                        t0 = time.time()
                        while time.time() - t0 < 15 and st["state"] not in ("PLAYING", "BUFFERING") and not st["dead"]:
                            time.sleep(0.5)
                        if st["state"] not in ("PLAYING", "BUFFERING") and not st["dead"]:
                            st["dead"], net["dead_since"] = True, time.time()
                    net["we_paused"] = False
                    if not st["dead"]:
                        st["net"] = ""
                        emit_net()
                        continue
                next_try = 0.0
            if st["dead"]:
                if time.time() - net["dead_since"] > 3600:
                    st["gone"] = True               # una hora sin poder: se cierra (queda guardado dónde ibas)
                    break
                if time.time() < next_try:
                    continue
                st["net"] = "retry"
                emit_net()
                if revive():
                    st["dead"], st["net"], wait = False, "", 10
                    net["we_paused"] = False
                    emit_net()
                else:
                    next_try = time.time() + wait
                    wait = min(60, wait * 2)
    threading.Thread(target=net_loop, daemon=True).start()

    def tracks():
        a = chosen.get("audio") or []
        cur = (chosen.get("aid") or 1) - 1
        audio = [{"id": i + 1, "lang": t.get("lang", ""), "title": t.get("title", ""), "selected": i == cur}
                 for i, t in enumerate(a)] if a else []
        subs = [{"id": 1, "lang": "spa", "title": "Español", "selected": sub["on"]}] if (sub_ext or sid_inband) else []
        emit(ev="tracks", audio=audio[cur:cur + 1] if audio else [], subs=subs)
    tracks()

    def reload_subs():
        """El Chromecast no deja cambiar el archivo de subtítulos en vivo:
        recarga en el mismo punto (rebobina un segundo)."""
        st["reloading"] = True
        load(max(0.0, st["pos"] - 1))
        time.sleep(4)
        st["reloading"] = False

    nudge = {"t": 0.0}

    def apply_boost(gen):
        """El refuerzo se aplica recargando en el mismo punto (Stremio tiene que
        volver a armar el audio); espera a que dejes de tocar la barra."""
        time.sleep(1.5)
        if gen != vol["gen"] or st.get("quit"):
            return
        try:
            d = json.load(open(BOOSTS))
        except Exception:
            d = {}
        d[tg["uuid"]] = {"b": vol["boost"], "t": time.time()}
        try:
            os.makedirs(STATE, exist_ok=True)
            json.dump(d, open(BOOSTS, "w"))
        except OSError:
            pass
        set_gain(vol["boost"])
        st["reloading"] = True
        vol["remaster"] = True
        try:
            load(max(0.0, st["pos"] - 1))
        except Exception as e:
            emit(ev="status", msg="No pude aplicar el refuerzo: " + str(e)[:60])
        time.sleep(4)
        st["reloading"] = False

    def set_level(lv):
        """0-100 = volumen de la tele; 101-300 = tele al máximo + refuerzo."""
        lv = max(0, min(100 if yt else 300, round(lv)))
        old = vol["boost"]
        if lv <= 100:
            vol["boost"] = 1.0
            vol["cast"] = lv / 100
            send(cmd="volume", v=lv / 100)
        else:
            vol["boost"] = lv / 100
            if (vol["cast"] or 0) < 0.999:
                vol["cast"] = 1.0
                send(cmd="volume", v=1.0)
        st["volume"], st["boost"] = lv, vol["boost"] > 1
        emit(ev="state", **{k: st[k] for k in ("pos", "dur", "pause", "buffering", "cache", "subDelay", "volume", "boost", "net")})
        if abs(vol["boost"] - old) > 0.001:
            vol["gen"] += 1
            threading.Thread(target=apply_boost, args=(vol["gen"],), daemon=True).start()

    def commands_loop():
        for line in commands():
            p = line.split()
            if not p:
                continue
            c = p[0]
            if c == "pause":
                send(cmd="toggle")
            elif c == "pauseset":
                send(cmd="pause" if p[1] == "1" else "play")
            elif c == "seek":
                send(cmd="seek", t=st["pos"] + float(p[1]))
            elif c == "seekto":
                send(cmd="seek", t=float(p[1]))
            elif c == "volume":
                set_level(st["volume"] + float(p[1]))
            elif c == "volset":
                set_level(float(p[1]))
            elif c == "sid":
                sub["on"] = p[1] != "no"
                if sid_inband:
                    send(cmd="subs", on=sub["on"])
                else:
                    threading.Thread(target=reload_subs, daemon=True).start()
                tracks()
            elif c in ("subdelay", "subdelayset") and sub_ext:
                sub["manual"] = True
                sub["delay"] = (sub["delay"] + float(p[1])) if c == "subdelay" else float(p[1])
                st["subDelay"] = round(sub["delay"] + (sub["speed"] - 1) * st["pos"], 2)
                emit(ev="state", **{k: st[k] for k in ("pos", "dur", "pause", "buffering", "cache", "subDelay", "volume", "boost", "net")})
                nudge["t"] = time.time()
            elif c == "resync" and sub_ext:
                sub["manual"] = False
                try:
                    d = json.load(open(DELAYS)); d.pop(sub["key"], None); json.dump(d, open(DELAYS, "w"))
                except Exception:
                    pass
                threading.Thread(target=auto_sync, args=(True,), daemon=True).start()
            elif c == "show":
                if st["seen_play"]:
                    emit(ev="casting", name=tg["name"])
            elif c == "quit":
                st["quit"] = True
                send(cmd="stop")
    threading.Thread(target=commands_loop, daemon=True).start()

    def auto_sync(first):
        """Igual que en la PC, pero aplicar = recargar con el .vtt corregido."""
        if not sub_ext or sub["manual"]:
            return
        if first:
            emit(ev="sync", state="working")
        p0 = st["pos"]
        t0 = p0 - 160 if p0 > 200 else p0 + 2
        try:
            r = subsync.sync(chosen["url"], sub_ext, max(0.0, t0), 150, chosen.get("refTrack"))
        except Exception as e:
            r = {"error": str(e)[:80]}
        if sub["manual"]:
            return
        if not subsync.confident(r):
            if first:
                emit(ev="sync", state="unsure")
            return
        tm = t0 + 75
        speed = r["speed"] if abs(r["speed"] - 1) > 0.02 else 1.0
        delay = r["delay"] if speed != 1.0 else subsync.offset_at(r, tm)
        new = (speed - 1) * st["pos"] + delay
        cur = (sub["speed"] - 1) * st["pos"] + sub["delay"]
        if abs(new - cur) > 0.25 or abs(speed - sub["speed"]) > 1e-4:
            sub["speed"], sub["delay"] = speed, delay
            st["subDelay"] = round(new, 2)
            emit(ev="sync", state="auto", delay=round(new, 2), ref=r.get("ref"))
            if sub["on"]:
                reload_subs()
        elif first:
            emit(ev="sync", state="auto", delay=round(cur, 2), ref=r.get("ref"))

    def sync_loop():
        while not st["gone"] and not st["seen_play"]:
            time.sleep(0.5)
        auto_sync(True)
        last = time.time()
        while not st["gone"]:
            time.sleep(1)
            # ajuste a mano: espera a que dejes de tocar y recarga una vez
            if nudge["t"] and time.time() - nudge["t"] > 1.8:
                nudge["t"] = 0.0
                if sub["on"]:
                    reload_subs()
            if time.time() - last > 300 and not st["pause"] and st["pos"] > 200:
                last = time.time()
                auto_sync(False)
    if sub_ext:
        threading.Thread(target=sync_loop, daemon=True).start()

    threading.Thread(target=watch_progress, args=(job, st, start, lambda: not st["gone"] and cp.poll() is None),
                     daemon=True).start()
    while not st["gone"] and cp.poll() is None:
        time.sleep(0.5)
    CUR["done"] = True      # de acá en adelante guarda el final (no el SIGTERM)
    send(cmd="stop")
    try:
        cp.wait(8)
    except Exception:
        cp.kill()
    finished = st["eof"] or (st["dur"] > 0 and st["pos"] / st["dur"] > 0.92)
    if sub["manual"] and sub["key"]:
        try:
            os.makedirs(STATE, exist_ok=True)
            try:
                d = json.load(open(DELAYS))
            except Exception:
                d = {}
            d[sub["key"]] = sub["delay"]
            json.dump(d, open(DELAYS, "w"))
        except Exception:
            pass
    save_progress(job, st["pos"], st["dur"], start, finished)
    for f in os.listdir(CAST_DIR) if os.path.isdir(CAST_DIR) else []:
        if f.startswith(sess):
            try:
                os.unlink(os.path.join(CAST_DIR, f))
            except OSError:
                pass
    emit(ev="ended", pos=st["pos"], dur=st["dur"], finished=finished)


def youtube(job):
    """YouTube: mpv abre el video con yt-dlp (con tu sesión de Zen), hasta 1080p."""
    import youtube as yt
    vid = job["id"].removeprefix("yt:")
    emit(ev="status", msg="SINTONIZANDO YOUTUBE…")
    if job.get("target"):
        run_cast(job, {"s": {"title": "YouTube", "res": 1080, "hash": ""}, "url": ""}, None, "", float(job.get("start") or 0), None)
        return
    # sin la sesión: con las cookies de Zen YouTube contesta "The page needs to
    # be reloaded" y no deja bajar el video (la sesión solo sirve para las listas)
    args = ["mpv", "https://www.youtube.com/watch?v=" + vid,
            "--ytdl-format=bv*[height<=1080][vcodec!*=av01]+ba/bv*[height<=1080]+ba/b",
            f"--script-opts=ytdl_hook-ytdl_path={yt.YTDLP}",
            "--fs", "--wayland-app-id=rice-cine-player", "--title=" + job.get("name", "YouTube"),
            "--no-osc", "--osd-level=0", "--osd-playing-msg=", "--keep-open=yes",
            "--save-position-on-quit=no", "--no-resume-playback", "--cursor-autohide=always", "--sid=no"]
    start = float(job.get("start") or 0)
    if start > 5:
        args.append(f"--start={start:.0f}")
    run_mpv(job, args, {"s": {"title": "YouTube", "res": 1080, "hash": ""}, "url": ""}, None, "", start)


def run_mpv(job, args, chosen, sub_ext, sub_key, start):
    mpv = Mpv(args)
    proc = mpv
    SES["mpv"] = True
    if not mpv.connect():
        emit(ev="error", msg="mpv no arrancó")
        return
    emit(ev="playing", source=chosen["s"].get("title", ""), res=chosen["s"]["res"])
    threading.Thread(target=force_fullscreen, daemon=True).start()

    st = {"pos": start, "dur": 0.0, "pause": False, "buffering": False, "cache": 100, "subDelay": 0.0, "eof": False}
    tracks = {"list": None}
    for i, p in enumerate(["time-pos", "duration", "pause", "paused-for-cache", "cache-buffering-state",
                           "sub-delay", "eof-reached", "track-list", "aid", "sid", "volume"]):
        mpv.cmd("observe_property", i + 1, p)

    last_emit = [0.0]

    def on_event(e):
        if e.get("event") != "property-change":
            return
        name, val = e.get("name"), e.get("data")
        if name == "time-pos" and val is not None:
            st["pos"] = val
        elif name == "duration" and val:
            st["dur"] = val
        elif name == "pause":
            st["pause"] = bool(val)
        elif name == "paused-for-cache":
            st["buffering"] = bool(val)
        elif name == "cache-buffering-state" and val is not None:
            st["cache"] = val
        elif name == "sub-delay" and val is not None:
            st["subDelay"] = round(val, 2)
        elif name == "eof-reached":
            st["eof"] = bool(val)
        elif name == "volume" and val is not None:
            st["volume"] = round(val)
        elif name in ("track-list", "aid", "sid"):
            if name == "track-list":
                tracks["list"] = val or []
            tl = tracks["list"] or []
            emit(ev="tracks",
                 audio=[{"id": t["id"], "lang": t.get("lang", ""), "title": t.get("title", ""), "selected": t.get("selected", False)}
                        for t in tl if t.get("type") == "audio"],
                 subs=[{"id": t["id"], "lang": t.get("lang", ""), "title": t.get("title", "") or ("archivo" if t.get("external") else ""),
                        "selected": t.get("selected", False)} for t in tl if t.get("type") == "sub"])
            return
        now = time.time()
        if name != "time-pos" or now - last_emit[0] > 0.25:
            last_emit[0] = now
            emit(ev="state", **st)

    threading.Thread(target=mpv.read_events, args=(on_event,), daemon=True).start()

    # Órdenes de la interfaz
    def stdin_loop():
        for line in commands():
            p = line.split()
            if not p:
                continue
            c = p[0]
            if c == "pause":
                mpv.cmd("cycle", "pause")
            elif c == "seek":
                mpv.cmd("seek", float(p[1]), "relative+exact")
            elif c == "seekto":
                mpv.cmd("seek", float(p[1]), "absolute+exact")
            elif c == "aid":
                mpv.cmd("set_property", "aid", int(p[1]))
            elif c == "sid":
                mpv.cmd("set_property", "sid", p[1] if p[1] == "no" else int(p[1]))
            elif c == "subdelay":
                sync["manual"] = True
                mpv.cmd("add", "sub-delay", float(p[1]))
            elif c == "subdelayset":
                sync["manual"] = True
                mpv.cmd("set_property", "sub-delay", float(p[1]))
            elif c == "resync":           # volver a automático
                sync["manual"] = False
                sync["auto"] = None
                sync["speed"] = 1.0
                mpv.cmd("set_property", "sub-speed", 1.0)
                if sync["key"]:
                    try:
                        d = json.load(open(DELAYS))
                        d.pop(sync["key"], None)
                        json.dump(d, open(DELAYS, "w"))
                    except Exception:
                        pass
                if sub_ext:
                    sync["resync"] = True
                else:
                    mpv.cmd("set_property", "sub-delay", 0)
                    emit(ev="sync", state="reset")
            elif c == "submargin":   # subtítulos más arriba mientras se ven los controles
                cfg = settings()
                mpv.cmd("set_property", "sub-margin-y", int(cfg["subMarginControls"] if p[1] == "controls" else cfg["subMargin"]))
            elif c == "volume":
                mpv.cmd("add", "volume", float(p[1]))
            elif c == "volset":
                mpv.cmd("set", "volume", float(p[1]))
            elif c == "pauseset":
                mpv.cmd("set_property", "pause", p[1] == "1")
            elif c == "reloadcfg":
                apply_cfg(mpv)
            elif c == "hide":            # la ventana se escondió: pausa
                mpv.cmd("set_property", "pause", True)
            elif c == "show":
                pass
            elif c == "quit":
                mpv.cmd("quit")
    threading.Thread(target=stdin_loop, daemon=True).start()

    # ── Subtítulos: ajuste guardado, automático y a mano ──────────────────
    #  Los que vienen dentro del archivo ya están sincronizados: solo a mano.
    #  Los bajados de OpenSubtitles: subsync.py escucha el audio al arrancar
    #  y cada 5 minutos (también corrige los que se van corriendo de a poco).
    #  Si los movés a mano, manda lo tuyo (y queda guardado para ese archivo).
    sync = {"manual": False, "auto": None, "busy": False, "key": "", "points": [], "speed": 1.0}
    if sub_ext or sub_key:
        sync["key"] = f'{chosen["s"]["hash"]}:{chosen["url"].rsplit("/", 1)[1]}:{os.path.basename(sub_ext) if sub_ext else sub_key}'
    try:
        saved = json.load(open(DELAYS)).get(sync["key"]) if sync["key"] else None
    except Exception:
        saved = None
    if saved is not None:
        sync["manual"] = True
        mpv.cmd("set_property", "sub-delay", float(saved))
        emit(ev="sync", state="saved", delay=saved)

    def run_sync(t0, dur, first):
        """Mide un tramo y, con todo lo medido hasta ahora, decide speed + delay.
        Una sola medición: corrimiento fijo. Varias separadas: la recta que
        cierra con todas (subtítulos que se van corriendo de a poco)."""
        if sync["busy"] or not sub_ext:
            return
        sync["busy"] = True
        if first:
            emit(ev="sync", state="working")
        try:
            r = subsync.sync(chosen["url"], sub_ext, max(0.0, t0), dur, chosen.get("refTrack"))
        except Exception as e:
            r = {"error": str(e)[:80]}
        sync["busy"] = False
        if sync["manual"]:
            return
        if not subsync.confident(r):
            if first and not sync["points"]:
                emit(ev="sync", state="unsure")
            return
        tm = t0 + dur / 2
        if abs(r["speed"] - 1) > 0.02:              # otra velocidad de cuadro (≈4 %): va directo
            speed, delay = r["speed"], r["delay"]
            sync["points"] = []
        else:
            sync["points"].append((tm, subsync.offset_at(r, tm)))
            pts = sync["points"][-8:]
            ts = np.array([p[0] for p in pts]); os_ = np.array([p[1] for p in pts])
            speed, delay = 1.0, float(np.median(os_[-3:]))
            if len(pts) >= 3 and ts.max() - ts.min() >= 900:
                slope, icpt = np.polyfit(ts, os_, 1)
                resid = np.abs(os_ - (slope * ts + icpt)).max()
                if abs(slope) > 0.0004 and resid < 0.35:   # se va corriendo de verdad
                    speed, delay = 1.0 + float(slope), float(icpt)
        cur = (sync["speed"] - 1) * st["pos"] + st["subDelay"]
        new = (speed - 1) * st["pos"] + delay
        if sync["auto"] is None or abs(new - cur) > 0.2 or abs(speed - sync["speed"]) > 1e-4:
            sync["auto"], sync["speed"] = delay, speed
            mpv.cmd("set_property", "sub-speed", speed)
            mpv.cmd("set_property", "sub-delay", round(delay, 2))
            emit(ev="sync", state="auto", delay=round(new, 2), ref=r.get("ref"))

    def sync_loop():
        while proc.poll() is None and (st["dur"] <= 0 or st["buffering"]):
            time.sleep(0.5)
        if not sync["manual"]:
            p0 = st["pos"]
            # al principio no hay nada atrás: lo que viene (mpv lo está bajando igual)
            run_sync(p0 - 160 if p0 > 200 else p0 + 2, 150, True)
        last = time.time()
        while proc.poll() is None:
            time.sleep(2)
            if sync["resync"]:
                sync["resync"] = False
                sync["points"] = []
                p0 = st["pos"]
                run_sync(p0 - 160 if p0 > 200 else p0 + 2, 150, True)
                last = time.time()
            elif time.time() - last > 240 and not st["pause"] and not sync["manual"] and st["pos"] > 200:
                last = time.time()
                run_sync(st["pos"] - 170, 160, False)      # lo ya visto: está en caché, sale al toque
    sync["resync"] = False
    if sub_ext:
        threading.Thread(target=sync_loop, daemon=True).start()

    def save_delay():
        if not sync["key"] or not sync["manual"]:
            return
        try:
            os.makedirs(STATE, exist_ok=True)
            try:
                d = json.load(open(DELAYS))
            except Exception:
                d = {}
            d[sync["key"]] = st["subDelay"]
            json.dump(d, open(DELAYS, "w"))
        except Exception:
            pass

    # Progreso: cada 30 s si cambió, al cerrar, y al apagar/matar (on_signal)
    threading.Thread(target=watch_progress, args=(job, st, start, lambda: proc.poll() is None), daemon=True).start()
    while proc.poll() is None:
        time.sleep(0.5)
        if st["eof"]:
            mpv.cmd("quit")
    CUR["done"] = True
    finished = st["eof"] or (st["dur"] > 0 and st["pos"] / st["dur"] > 0.92)
    save_delay()
    save_progress(job, st["pos"], st["dur"], start, finished)
    emit(ev="ended", pos=st["pos"], dur=st["dur"], finished=finished)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        emit(ev="error", msg=str(e)[:200])
    finally:
        end_session()
