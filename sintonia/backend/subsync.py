#!/usr/bin/env python3
"""rice-cine — sincroniza subtítulos (etapa 3, versión 2).

Busca la transformación  tiempo_real = tiempo_subtítulo × r + d  que mejor
calza los subtítulos bajados con una REFERENCIA de un tramo de la película:

  · si el archivo trae subtítulos propios (cualquier idioma, ya sincronizados):
    se comparan subtítulo contra subtítulo — lo más preciso;
  · si no: las voces del audio (energía en la banda de la voz).

r cubre el caso típico de subtítulos hechos para otra velocidad de cuadro
(25 vs 23,976…): se van corriendo de a poco a lo largo de la película.
En mpv: sub-speed = r, sub-delay = d.

  subsync.py <url> <subtítulo.srt> <desde s> [duración s] [pista de subtítulos del archivo | -]
      → {"delay": d, "speed": r, "conf": z, "ref": "subs"|"voz"}
"""
import json
import re
import subprocess
import sys

import glob
import os

import numpy as np

# el detector de WebRTC vive en un venv propio (sin tocar el Python del sistema)
for _sp in glob.glob(os.path.expanduser("~/.local/share/rice-cine/venv/lib/python3*/site-packages")):
    if _sp not in sys.path:
        sys.path.append(_sp)

RATE = 16000
HOP = 0.02                 # 20 ms por cuadro
MAX_OFF = 25.0             # ±25 s de corrimiento
# 25↔23,976 y 25↔24 (≈4 %) se notan en un solo tramo; 24↔23,976 (0,1 %) no:
# se confunde con el corrimiento, eso lo saca la recta de varios tramos (player.py)
RATIOS = [1.0, 25 / 23.976, 23.976 / 25, 25 / 24, 24 / 25]


def parse_srt_text(text):
    out = []
    for m in re.finditer(r"(\d+):(\d+):(\d+)[,.](\d+)\s*-->\s*(\d+):(\d+):(\d+)[,.](\d+)", text.replace("\r", "")):
        g = [int(x) for x in m.groups()]
        a = g[0] * 3600 + g[1] * 60 + g[2] + g[3] / (1000 if len(m.group(4)) == 3 else 100)
        b = g[4] * 3600 + g[5] * 60 + g[6] + g[7] / (1000 if len(m.group(8)) == 3 else 100)
        if b > a:
            out.append((a, b))
    return out


def parse_srt(path):
    with open(path, encoding="utf-8", errors="replace") as f:
        return parse_srt_text(f.read())


# ── Referencias ─────────────────────────────────────────────────────────────
def ref_subs(url, t0, dur, track):
    """Subtítulos del propio archivo en [t0, t0+dur] (tiempos absolutos)."""
    # -copyts + -to: tiempos absolutos (con -t se cortaba enseguida sin nada)
    import servidor
    r = subprocess.run([servidor.ffmpeg("ffmpeg"), "-nostdin", "-v", "error", "-copyts", "-ss", f"{t0:.2f}", "-i", url,
                        "-to", f"{t0 + dur:.2f}", "-map", f"0:s:{track}", "-f", "srt", "-"],
                       capture_output=True, text=True, timeout=dur * 3 + 90)
    subs = parse_srt_text(r.stdout)
    return [(a, b) for a, b in subs if t0 - 5 <= a <= t0 + dur + 5]


def audio(url, t0, dur):
    import servidor
    r = subprocess.run([servidor.ffmpeg("ffmpeg"), "-nostdin", "-v", "error", "-ss", f"{t0:.2f}", "-t", f"{dur:.2f}", "-i", url,
                        "-vn", "-ac", "1", "-ar", str(RATE), "-f", "s16le", "-"],
                       capture_output=True, timeout=dur * 3 + 90)
    return np.frombuffer(r.stdout, dtype=np.int16).astype(np.float32) / 32768.0


def voice(x):
    """Voz por cuadro (HOP): el detector de WebRTC (el de ffsubsync) si está
    instalado (venv ~/.local/share/rice-cine/venv), si no uno casero."""
    try:
        import webrtcvad
    except ImportError:
        return voice_home(x)
    vad = webrtcvad.Vad(2)
    pcm = (np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes()
    step = int(RATE * HOP) * 2
    v = np.array([1.0 if vad.is_speech(pcm[i:i + step], RATE) else 0.0
                  for i in range(0, len(pcm) - step + 1, step)])
    return np.convolve(v, np.ones(5) / 5, mode="same")


def voice_home(x):
    """Probabilidad de voz por cuadro (HOP): energía 300-3400 Hz vs. el resto."""
    hop, win = int(RATE * HOP), 1024
    n = (len(x) - win) // hop
    if n <= 0:
        return np.zeros(0)
    idx = np.arange(win)[None, :] + hop * np.arange(n)[:, None]
    spec = np.abs(np.fft.rfft(x[idx] * np.hanning(win)[None, :], axis=1)) ** 2
    f = np.fft.rfftfreq(win, 1 / RATE)
    band = spec[:, (f >= 300) & (f <= 3400)].sum(1)
    low = spec[:, f < 200].sum(1)
    e = np.log10(band + 1e-9)
    lo, hi = np.percentile(e, 25), np.percentile(e, 97)
    p = np.clip((e - lo) / max(hi - lo, 1e-3), 0, 1)
    p *= np.clip(band / (band + low + 1e-9) * 1.4, 0, 1)        # música grave / golpes: menos
    return np.convolve(p, np.ones(8) / 8, mode="same")


def mask(intervals, base, n):
    m = np.zeros(n)
    for a, b in intervals:
        i, j = int((a - base) / HOP), int((b - base) / HOP)
        if j > 0 and i < n:
            m[max(0, i):min(n, j)] = 1.0
    return m


# ── Búsqueda ────────────────────────────────────────────────────────────────
def search(ref, t0, dur, subs):
    """ref: señal de referencia sobre [t0, t0+dur]. Prueba cada r y cada d."""
    n = len(ref)
    m = int(MAX_OFF / HOP)
    refc = ref - ref.mean()
    best = None
    for r in RATIOS:
        # intervalos transformados por r; d se busca con la correlación
        tr = [(a * r, b * r) for a, b in subs if t0 - 3 * MAX_OFF < a * r < t0 + dur + 3 * MAX_OFF]
        lines = sum(1 for a, _ in tr if t0 - MAX_OFF <= a <= t0 + dur + MAX_OFF)
        if lines < 6:
            continue
        mk = mask(tr, t0 - MAX_OFF, n + 2 * m)
        corr = np.correlate(mk, refc, mode="valid")          # largo 2m+1
        k = int(np.argmax(corr))
        z = (corr[k] - corr.mean()) / (corr.std() + 1e-9)
        far = np.abs(np.arange(len(corr)) - k) > int(1.5 / HOP)
        second = corr[far].max() if far.any() else corr.min()
        sharp = (corr[k] - second) / (abs(corr[k]) + 1e-9)
        d = (m - k) * HOP
        cand = {"delay": round(float(d), 2), "speed": round(r, 6), "conf": round(float(z), 2),
                "sharp": round(float(sharp), 3), "lines": lines}
        if best is None or z > best["conf"]:
            best = cand
    return best


def sync(url, srt, t0, dur=150.0, track=None):
    subs = parse_srt(srt)
    t0 = max(0.0, t0)
    n = int(dur / HOP)
    res = None
    if track is not None:
        ref = ref_subs(url, t0, dur, track)
        if len(ref) >= 8:
            res = search(mask(ref, t0, n), t0, dur, subs)
            if res:
                res["ref"] = "subs"
    if res is None:
        x = audio(url, t0, dur)
        if len(x) < RATE * 30:
            return {"error": "no llegó el audio"}
        v = voice(x)
        res = search(v[:n] if len(v) >= n else np.pad(v, (0, n - len(v))), t0, dur, subs)
        if res:
            res["ref"] = "voz"
    return res or {"error": "pocos subtítulos en ese tramo"}


def confident(r):
    """¿Vale la pena aplicarlo? (contra subtítulos es mucho más fiable)"""
    if not r or "delay" not in r:
        return False
    # medido contra los subtítulos del archivo (la verdad): con WebRTC el error
    # quedó en 0,05-0,25 s; estos umbrales descartan los tramos sin diálogo claro
    if r["ref"] == "subs":
        return r["conf"] >= 3.0 and r["sharp"] >= 0.1
    return r["conf"] >= 2.0 and r["sharp"] >= 0.14


def offset_at(r, t):
    """Corrimiento local (s) que implica el resultado r en el instante t."""
    return (r["speed"] - 1.0) * t + r["delay"]


if __name__ == "__main__":
    try:
        tr = sys.argv[5] if len(sys.argv) > 5 else "-"
        out = sync(sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]) if len(sys.argv) > 4 else 150.0,
                   None if tr == "-" else int(tr))
    except Exception as e:
        out = {"error": str(e)[:200]}
    print(json.dumps(out))
