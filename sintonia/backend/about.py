#!/usr/bin/env python3
"""rice-cine — pestaña SOBRE LA PELÍCULA.

  about.py about <movie|series> <id>     ficha en español (sinopsis, equipo, tráiler…)
  about.py similar <movie|series> <id>   parecidas por ESTILO (fotografía, forma de contar), no por trama
  about.py person <nombre> [/rol/slug/]  perfil (Wikipedia/Wikidata + filmografía de Letterboxd por rol)
  about.py lbfilm <slug>                 película de Letterboxd → id de IMDb

Fuentes: Cinemeta (dirección, duración, tráiler), addon de TMDB en es-MX
(sinopsis, géneros y elenco con personajes y fotos), Letterboxd con las cookies de Zen
(fotografía, puntaje, "similares" = lo que ve la misma gente) y una IA por
OmniRoute que elige por estilo. Todo queda en caché (~/.cache/rice-cine/about).
Siempre imprime UN JSON.
"""
import html
import importlib.util
import json
import os
import re
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import stremio as S  # noqa: E402

CACHE = os.path.join(S.CACHE, "about")
OMNI = "http://127.0.0.1:20128/v1/chat/completions"
OMNI_KEY = os.path.expanduser("~/.config/omniroute/api.key")
MODELS = ["auto/best-free"]


def out(o):
    print(json.dumps(o, ensure_ascii=False))


def cached(name, ttl, fn):
    path = os.path.join(CACHE, name + ".json")
    if os.path.exists(path) and time.time() - os.path.getmtime(path) < ttl:
        try:
            return json.load(open(path))
        except Exception:
            pass
    try:
        data = fn()
    except Exception:
        data = None
    if data:
        os.makedirs(CACHE, exist_ok=True)
        json.dump(data, open(path, "w"), ensure_ascii=False)
        return data
    if os.path.exists(path):                       # sin red: lo último que haya
        return json.load(open(path))
    return None


def text(s):
    return html.unescape(re.sub(r"<[^>]+>", " ", s or "")).strip()


# ── TMDB en español (addon público de TMDB para Stremio, ElfHosted) ──────────
TMDB_ADDON = "https://tmdb.elfhosted.com/" + urllib.parse.quote('{"language":"es-MX"}')


def tmdb_es(type_, id_):
    m = S.get_json(f"{TMDB_ADDON}/meta/{type_}/{id_}.json", 3 * 24 * 3600).get("meta") or {}
    r = {}
    if m.get("description"):
        r["description"] = m["description"]
    if m.get("name"):
        r["nameEs"] = m["name"]
    if m.get("genres"):
        r["genresEs"] = m["genres"]
    cast = (m.get("app_extras") or {}).get("cast") or []
    r["castFull"] = [{"name": c.get("name", ""), "character": c.get("character") or "", "photo": c.get("photo") or ""}
                     for c in cast if "(uncredited)" not in (c.get("character") or "")][:10]
    tr = [t.get("ytId") for t in (m.get("trailerStreams") or []) if t.get("ytId")]
    if tr:
        r["trailer"] = tr[0]
    return r


# ── Letterboxd (cookies de Zen) ─────────────────────────────────────────────
def lb_module():
    spec = importlib.util.spec_from_file_location("lbx", os.path.join(HERE, "letterboxd.py"))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def crew(h, role):
    i = h.find(">" + role + "<")
    if i < 0:
        return []
    seg = h[i:i + 3000]
    seg = seg[:seg.find("</div>")] if "</div>" in seg else seg
    return [text(x) for x in re.findall(r'<a [^>]*href="/[^"]+/"[^>]*>(.*?)</a>', seg)][:4]


def letterboxd(imdb):
    op, _ = lb_module().opener()
    with op.open(f"https://letterboxd.com/imdb/{imdb}/", timeout=25) as r:
        h = r.read().decode("utf-8", "replace")
        url = r.geturl()
    i = h.find("Similar Films")
    seg = h[i:i + 20000] if i >= 0 else ""
    sim = [{"name": html.unescape(n)} for n in re.findall(r'data-item-name="([^"]+)"', seg)][:8]
    rating = re.search(r'name="twitter:data2" content="([\d.]+) out of 5"', h)
    people = {}
    for path, name in re.findall(r'<a [^>]*href="(/(?:director|actor|writer|cinematography|editor|composer|producer|co-director|creator)/[^"/]+/)"[^>]*>(.*?)</a>', h):
        n = text(name)
        if n and len(n) < 60:
            people.setdefault(n.lower(), path)
    return {"lbUrl": url, "people": people, "dop": crew(h, "Cinematography"), "editing": crew(h, "Editor"),
            "music": crew(h, "Composer"), "lbRating": rating.group(1) if rating else "", "lbSimilar": sim}


# ── Ficha ───────────────────────────────────────────────────────────────────
def build_about(type_, id_):
    meta = S.get_json(f"{S.CINEMETA}/meta/{type_}/{id_}.json", 24 * 3600).get("meta") or {}
    base = S.norm_meta(meta) if meta else {"id": id_, "type": type_}
    base["type"] = type_
    tr = [t.get("ytId") for t in (meta.get("trailerStreams") or []) if t.get("ytId")]
    rel = meta.get("released") or ""
    base.update({
        "director": meta.get("director") or [],
        "writer": meta.get("writer") or [],
        "cast": (meta.get("cast") or [])[:8],
        "released": rel[:10],
        "awards": meta.get("awards") or "",
        "trailer": tr[0] if tr else "",
        "descriptionEn": meta.get("description") or "",
    })
    if type_ == "series":
        vids = meta.get("videos") or []
        base["seasons"] = len({v.get("season") for v in vids if v.get("season")})
    jobs = {"tmdb": lambda: tmdb_es(type_, id_)}
    if id_.startswith("tt") and type_ == "movie":
        jobs["lb"] = lambda: letterboxd(id_)

    def run(k):
        try:
            return k, jobs[k]()
        except Exception:
            return k, {}
    with ThreadPoolExecutor(2) as ex:
        res = dict(ex.map(run, jobs))
    t = res.get("tmdb") or {}
    if t.get("description"):
        base["description"] = t["description"]
    elif base.get("descriptionEn"):
        base["description"] = translate(base["descriptionEn"])
    for k in ("nameEs", "genresEs", "castFull"):
        if t.get(k):
            base[k] = t[k]
    if t.get("trailer"):
        base["trailer"] = t["trailer"]           # el de TMDB en español (si hay)
    if not base.get("castFull"):
        base["castFull"] = [{"name": n, "character": "", "photo": ""} for n in base["cast"]]
    base.update(res.get("lb") or {})
    base["country"] = ", ".join(COUNTRY_ES.get(c.strip(), c.strip()) for c in (base.get("country") or "").split(",") if c.strip())
    base["awards"] = awards_es(base.get("awards"))
    return base


COUNTRY_ES = {"United States": "Estados Unidos", "United States of America": "Estados Unidos", "United Kingdom": "Reino Unido",
              "France": "Francia", "Germany": "Alemania", "Italy": "Italia", "Spain": "España", "Japan": "Japón",
              "South Korea": "Corea del Sur", "Korea": "Corea del Sur", "China": "China", "Canada": "Canadá",
              "Australia": "Australia", "Ireland": "Irlanda", "Mexico": "México", "Argentina": "Argentina",
              "Brazil": "Brasil", "Sweden": "Suecia", "Denmark": "Dinamarca", "Norway": "Noruega", "Belgium": "Bélgica",
              "Netherlands": "Países Bajos", "Austria": "Austria", "Switzerland": "Suiza", "Poland": "Polonia",
              "India": "India", "Hong Kong": "Hong Kong", "Taiwan": "Taiwán", "Russia": "Rusia", "New Zealand": "Nueva Zelanda",
              "Chile": "Chile", "Colombia": "Colombia", "Portugal": "Portugal", "Finland": "Finlandia", "Greece": "Grecia",
              "Turkey": "Turquía", "Iran": "Irán", "Israel": "Israel", "Thailand": "Tailandia", "Hungary": "Hungría",
              "Czech Republic": "República Checa", "Romania": "Rumania", "Soviet Union": "Unión Soviética"}


def awards_es(s):
    if not s:
        return ""
    s = re.sub(r"Won (\d+) Oscars?", lambda m: f"Ganó {m.group(1)} Óscar" + ("s" if m.group(1) != "1" else ""), s)
    s = re.sub(r"Nominated for (\d+) Oscars?", lambda m: f"Nominada a {m.group(1)} Óscar" + ("s" if m.group(1) != "1" else ""), s)
    s = re.sub(r"(\d+) wins?", lambda m: m.group(1) + (" premio" if m.group(1) == "1" else " premios"), s)
    s = re.sub(r"(\d+) nominations?( total)?", lambda m: m.group(1) + (" nominación" if m.group(1) == "1" else " nominaciones"), s)
    return s.replace(" & ", " y ").replace("Another ", "Además, ").rstrip(".")


def cmd_about(type_, id_):
    d = cached("about-" + id_, 3 * 24 * 3600, lambda: build_about(type_, id_))
    out(d or {"error": "sin datos"})


# ── Parecidas por estilo ────────────────────────────────────────────────────
def parse_list(txt):
    txt = re.sub(r"```(?:json)?", "", txt or "")
    for m in re.finditer(r"\[", txt):           # el primer "[" que arranque un JSON válido
        try:
            v, _ = json.JSONDecoder().raw_decode(txt[m.start():])
            if isinstance(v, list) and v and isinstance(v[0], dict):
                return v
        except ValueError:
            continue
    return []


def ask_ai(prompt):
    if not os.path.exists(OMNI_KEY):              # sin IA (otra compu): las de Letterboxd
        return []
    key = open(OMNI_KEY).read().strip()
    for model in MODELS * 3:                       # la ruta gratis a veces falla: reintentar
        try:
            body = json.dumps({"model": model, "max_tokens": 4000, "temperature": 0.4,
                               "messages": [{"role": "user", "content": prompt}]}).encode()
            req = urllib.request.Request(OMNI, body, {"Authorization": "Bearer " + key,
                                                      "Content-Type": "application/json"})
            with urllib.request.urlopen(req, timeout=60) as r:
                txt = json.load(r)["choices"][0]["message"]["content"] or ""
            v = parse_list(txt)
            if v:
                return v
            print("IA sin JSON: " + txt[:300], file=sys.stderr)
        except Exception as e:
            print("IA falló: " + str(e), file=sys.stderr)
    return []


def norm_title(s):
    s = re.sub(r"[^\w ]", "", (s or "").lower().replace("&", "and"))
    return re.sub(r"^(the|a|an|el|la|los|las) ", "", s).strip()


def resolve(title, year, type_, strict=False):
    """Título (+año) → ficha de Cinemeta (con id de IMDb)."""
    q = urllib.parse.quote(title)
    best = None
    for t in ([type_, "movie" if type_ == "series" else "series"]):
        try:
            metas = S.get_json(f"{S.CINEMETA}/catalog/{t}/top/search={q}.json", 7 * 24 * 3600).get("metas") or []
        except Exception:
            continue
        for m in metas[:10]:
            y = str(m.get("releaseInfo") or m.get("year") or "")[:4]
            same = norm_title(m.get("name")) == norm_title(title)
            close = year and y.isdigit() and abs(int(y) - int(year)) <= 1
            if same and (close or not year):
                return m
            if same and not best and not (strict and year):
                best = m
        if best:
            return best
    return None


def build_similar(type_, id_):
    a = cached("about-" + id_, 3 * 24 * 3600, lambda: build_about(type_, id_)) or {}
    hints = [x["name"] for x in a.get("lbSimilar") or []]
    kind = "series" if type_ == "series" else "películas"
    prompt = (
        f"{'Serie' if type_ == 'series' else 'Película'}: {a.get('name', '')} ({a.get('year', '')})\n"
        f"Dirección: {', '.join(a.get('director') or []) or '?'}\n"
        f"Fotografía: {', '.join(a.get('dop') or []) or '?'}\n"
        f"Géneros: {', '.join(a.get('genres') or [])}\n"
        f"Sinopsis: {a.get('descriptionEn') or a.get('description') or ''}\n"
        + (f"Pistas de Letterboxd (las ve la misma gente; puede que sean recientes y no las conozcas): {', '.join(hints)}\n" if hints else "")
        + f"\nRecomendá 10 {kind} parecidas por su FOTOGRAFÍA / estética visual (paleta, encuadres, textura, "
        "cámara) y por la FORMA de contar (tono, ritmo, estructura, punto de vista, humor). NO por la trama ni "
        "el tema: que la historia sea distinta está bien. Mezclá clásicos y recientes; podés incluir pistas si "
        "de verdad se parecen en estilo. Nada de la misma saga.\n"
        'Respondé SOLO un JSON: [{"title":"título original","year":2020,"why":"qué tienen en común de estilo, '
        'en español rioplatense, máx 10 palabras"}]')
    picks = ask_ai(prompt)
    src = "ai"
    if not picks:                                # sin IA: las de Letterboxd
        src = "letterboxd"
        for n in hints:
            m = re.match(r"(.*) \((\d{4})\)$", n)
            picks.append({"title": m.group(1) if m else n, "year": int(m.group(2)) if m else 0,
                          "why": "la ve la misma gente en Letterboxd"})

    def res(p):
        try:
            m = resolve(str(p.get("title", "")), int(p.get("year") or 0), type_)
        except Exception:
            m = None
        if not m:
            return None
        x = S.norm_meta(m)
        x["why"] = str(p.get("why", ""))
        return x
    with ThreadPoolExecutor(8) as ex:
        items = [x for x in ex.map(res, picks[:12]) if x and x["id"] != id_]
    seen, uniq = set(), []
    for x in items:
        if x["id"] not in seen:
            seen.add(x["id"]); uniq.append(x)
    return {"items": uniq[:8], "source": src} if uniq else None


def cmd_similar(type_, id_):
    d = cached("similar-" + id_, 30 * 24 * 3600, lambda: build_similar(type_, id_))
    out(d or {"items": [], "error": "sin recomendaciones"})


# ── Perfil de una persona (director, actor, etc.) ──────────────────────────
ROLE_ES = {"Director": "Dirección", "Co-Director": "Codirección", "Actor": "Actuación", "Writer": "Guion",
           "Producer": "Producción", "Executive Producer": "Producción ejecutiva", "Cinematography": "Fotografía",
           "Editor": "Montaje", "Composer": "Música", "Creator": "Creación", "Songs": "Canciones",
           "Original Writer": "Obra original", "Story": "Historia", "Casting": "Casting",
           "Production Design": "Diseño de producción", "Art Direction": "Dirección de arte", "Costume Design": "Vestuario",
           "Sound": "Sonido", "Visual Effects": "Efectos visuales", "Additional Directing": "Dirección adicional",
           "Stunts": "Dobles de riesgo", "Choreography": "Coreografía", "Camera Operator": "Cámara",
           "Lighting": "Iluminación", "Set Decoration": "Ambientación", "Makeup": "Maquillaje", "Hairstyling": "Peinados",
           "Assistant Director": "Asistente de dirección", "Additional Photography": "Fotografía adicional",
           "Narrator": "Narración", "Self": "Como sí mismo", "Studio": "Estudio"}
ROLE_ORDER = ["Director", "Co-Director", "Creator", "Actor", "Writer", "Original Writer", "Story", "Cinematography",
              "Editor", "Composer", "Songs", "Producer", "Executive Producer"]
UA_WIKI = {"User-Agent": "rice-cine/1.0 (uso personal)"}
MONTHS = ["enero", "febrero", "marzo", "abril", "mayo", "junio", "julio", "agosto", "septiembre", "octubre",
          "noviembre", "diciembre"]


def wjson(url, params):
    u = url + "?" + urllib.parse.urlencode(dict(params, format="json"))
    with urllib.request.urlopen(urllib.request.Request(u, headers=UA_WIKI), timeout=25) as r:
        return json.load(r)


def lb_person_page(op, path):
    with op.open("https://letterboxd.com" + path, timeout=25) as r:
        return r.read().decode("utf-8", "replace")


def lb_films(h):
    films = []
    for m in re.finditer(r'data-item-name="([^"]+)"[^>]*?data-item-slug="([^"]+)"', h):
        full, slug = html.unescape(m.group(1)), m.group(2)
        mm = re.match(r"(.*) \((\d{4})\)$", full)
        films.append({"name": mm.group(1) if mm else full, "year": int(mm.group(2)) if mm else 0, "slug": slug})
    return films


def lb_roles(h, path):
    """Pestañas de rol de la página de una persona: [(rol en inglés, ruta)]."""
    slug = path.strip("/").split("/")[-1]
    roles = []
    for href, name in re.findall(r'<a href="(/[a-z-]+/' + re.escape(slug) + r'/)"\s+class="(?:item|selected)"[^>]*>\s*([^<]+?)\s*<', h):
        roles.append((name, href))
    kind = path.strip("/").split("/")[0]           # la pestaña en la que entramos (por la ruta)
    cur = {"co-director": "Co-Director", "executive-producer": "Executive Producer", "original-writer": "Original Writer",
           "visual-effects": "Visual Effects", "production-design": "Production Design", "art-direction": "Art Direction",
           "costume-design": "Costume Design", "set-decoration": "Set Decoration", "additional-directing": "Additional Directing",
           "assistant-director": "Assistant Director", "camera-operator": "Camera Operator",
           "additional-photography": "Additional Photography"}.get(kind, kind.replace("-", " ").title())
    roles = [(n, hr) for n, hr in roles if n in ROLE_ES or hr.split("/")[1] != "films"]
    roles.insert(0, (cur, path))
    seen, out_ = set(), []
    for n, hr in roles:
        if hr not in seen:
            seen.add(hr); out_.append((n, hr))
    return out_


def wd_entity(tmdb, name):
    q = None
    if tmdb:
        s = wjson("https://www.wikidata.org/w/api.php", {"action": "query", "list": "search",
                                                          "srsearch": f"haswbstatement:P4985={tmdb}"})
        hits = s["query"]["search"]
        q = hits[0]["title"] if hits else None
    if not q and name:                             # por nombre: la primera persona del cine
        s = wjson("https://www.wikidata.org/w/api.php", {"action": "wbsearchentities", "search": name,
                                                          "language": "es", "type": "item", "limit": 5})
        for x in s.get("search", []):
            if re.search(r"act|direct|cine|film|guion|escrit|writer|composer|músic|productor|fotógraf|cinematograph|editor|montaj",
                         x.get("description", ""), re.I):
                q = x["id"]; break
    if not q:
        return None
    e = wjson("https://www.wikidata.org/w/api.php", {"action": "wbgetentities", "ids": q,
                                                     "props": "claims|sitelinks|labels|descriptions", "languages": "es|en"})
    return e["entities"][q]


def claim(e, p):
    return [c["mainsnak"].get("datavalue", {}).get("value") for c in e.get("claims", {}).get(p, [])
            if c["mainsnak"].get("datavalue")]


def wd_labels(ids, female=False):
    if not ids:
        return {}
    e = wjson("https://www.wikidata.org/w/api.php", {"action": "wbgetentities", "ids": "|".join(ids[:40]),
                                                     "props": "labels|claims" if female else "labels", "languages": "es|en"})
    out_ = {}
    for k, v in e.get("entities", {}).items():
        lab = (v.get("labels", {}).get("es") or v.get("labels", {}).get("en") or {}).get("value", "")
        if female:                                   # P2521 = forma femenina de la etiqueta
            fem = [x["text"] for x in claim(v, "P2521") if isinstance(x, dict) and x.get("language") == "es"]
            lab = fem[0] if fem else lab
        out_[k] = lab
    return out_


def wd_date(v):
    m = re.match(r"[+-](\d{4})-(\d{2})-(\d{2})", (v or {}).get("time", ""))
    if not m:
        return "", None
    y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
    prec = (v or {}).get("precision", 11)
    if prec >= 11 and mo and d:
        return f"{d} de {MONTHS[mo - 1]} de {y}", (y, mo, d)
    return str(y), (y, 0, 0)


def years_between(a, b):
    if not a or not b or not a[1] or not b[1]:
        return None
    return b[0] - a[0] - ((b[1], b[2]) < (a[1], a[2]))


def wiki_intro(lang, title):
    r = wjson(f"https://{lang}.wikipedia.org/w/api.php", {"action": "query", "prop": "extracts", "exintro": 1,
                                                         "explaintext": 1, "redirects": 1, "titles": title})
    for pg in r["query"]["pages"].values():
        t = (pg.get("extract") or "").strip()
        return re.sub(r"\s*\([^()]*\)", "", t, count=1) if lang == "en" else t
    return ""


def translate(txt):
    if not txt or not os.path.exists(OMNI_KEY):
        return txt or ""
    key = open(OMNI_KEY).read().strip()
    body = json.dumps({"model": MODELS[0], "max_tokens": 1500, "temperature": 0.2, "messages": [{"role": "user", "content":
        "Traducí al español rioplatense neutro (sin voseo forzado), natural, sin agregar nada. Solo el texto:\n\n" + txt}]}).encode()
    try:
        req = urllib.request.Request(OMNI, body, {"Authorization": "Bearer " + key, "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as r:
            return (json.load(r)["choices"][0]["message"]["content"] or "").strip() or txt
    except Exception:
        return txt


def wd_filmography(q):
    """Películas/series con IMDb donde participó (para emparejar con Letterboxd)."""
    sparql = f"""SELECT ?imdb ?y ?en ?es WHERE {{
      ?f wdt:P57|wdt:P161|wdt:P58|wdt:P344|wdt:P1040|wdt:P86|wdt:P162|wdt:P1431|wdt:P170 wd:{q}; wdt:P345 ?imdb.
      OPTIONAL {{ ?f wdt:P577 ?d. BIND(YEAR(?d) AS ?y) }}
      OPTIONAL {{ ?f rdfs:label ?en FILTER(LANG(?en)="en") }}
      OPTIONAL {{ ?f rdfs:label ?es FILTER(LANG(?es)="es") }} }}"""
    r = wjson("https://query.wikidata.org/sparql", {"query": sparql})
    out_ = []
    for b in r["results"]["bindings"]:
        g = lambda k: b.get(k, {}).get("value", "")
        if g("imdb").startswith("tt"):
            out_.append({"imdb": g("imdb"), "year": int(g("y") or 0), "en": g("en"), "es": g("es")})
    return out_


def build_person(name, path):
    op, _ = lb_module().opener()
    h = lb_person_page(op, path) if path else ""
    tmdb = (re.search(r"themoviedb\.org/person/(\d+)", h) or [None, None])[1] if h else None
    lb_name = text((re.search(r'<h1 class="title-1[^"]*"[^>]*>(.*?)</h1>', h, re.S) or [None, ""])[1]) if h else ""
    lb_name = re.sub(r"^(Films )?(starring|directed by|written by|with|by)\s+", "", lb_name, flags=re.I).strip()
    lb_bio = text((re.search(r'<div class="bio[^"]*"[^>]*>(.*?)</div>\s*</div>', h, re.S) or [None, ""])[1]) if h else ""
    lb_bio = re.sub(r"\s*(More details at TMDB|Read more).*$", "", lb_bio, flags=re.S).strip()
    roles = lb_roles(h, path) if h else []

    def role_page(rp):
        n, hr = rp
        try:
            return n, lb_films(h if hr == path else lb_person_page(op, hr))
        except Exception:
            return n, []
    with ThreadPoolExecutor(6) as ex:
        role_films = list(ex.map(role_page, roles[:8]))
        f_ent = ex.submit(wd_entity, tmdb, name)
        try:
            e = f_ent.result() or {}
        except Exception:
            e = {}

    p = {"type": "person", "id": "person:" + (path or name), "name": lb_name or name, "lbPath": path or "",
         "tmdb": tmdb or "", "photo": "", "description": "", "facts": [], "bio": "", "bioSource": "", "roles": []}
    if e:
        lab = e.get("labels", {})
        p["name"] = (lab.get("es") or lab.get("en") or {}).get("value") or p["name"]
        desc = e.get("descriptions", {})
        p["description"] = (desc.get("es") or desc.get("en") or {}).get("value", "")
        img = claim(e, "P18")
        if img:
            p["photo"] = "https://commons.wikimedia.org/wiki/Special:FilePath/" + urllib.parse.quote(img[0].replace(" ", "_")) + "?width=500"
        born, by = wd_date((claim(e, "P569") or [None])[0])
        died, dy = wd_date((claim(e, "P570") or [None])[0])
        places = [x["id"] for x in claim(e, "P19")[:1] + claim(e, "P20")[:1]]
        occ = [x["id"] for x in claim(e, "P106")[:5]]
        female = any(x.get("id") == "Q6581072" for x in claim(e, "P21"))
        labels = wd_labels(places)
        labels.update(wd_labels(occ, female))
        if born:
            place = labels.get(claim(e, "P19")[0]["id"], "") if claim(e, "P19") else ""
            t = time.localtime()
            age = years_between(by, (t.tm_year, t.tm_mon, t.tm_mday)) if not died else None
            p["facts"].append(["NACIMIENTO", born + (", " + place if place else "") + (f"  ({age} años)" if age is not None else "")])
        if died:
            age = years_between(by, dy)
            p["facts"].append(["MUERTE", died + (f"  (a los {age} años)" if age is not None else "")])
        o = [labels.get(x, "") for x in occ if labels.get(x)]
        if o:
            p["facts"].append(["OFICIO", ", ".join(o[:4])])
        sl = e.get("sitelinks", {})
        try:
            if "eswiki" in sl:
                p["bio"], p["bioSource"] = wiki_intro("es", sl["eswiki"]["title"]), "Wikipedia"
            elif "enwiki" in sl:
                p["bio"], p["bioSource"] = translate(wiki_intro("en", sl["enwiki"]["title"])), "Wikipedia (traducida)"
        except Exception:
            pass
        try:
            wdf = wd_filmography(e["id"])
        except Exception:
            wdf = []
    else:
        wdf = []
    if not p["bio"] and lb_bio:
        p["bio"], p["bioSource"] = translate(lb_bio), "TMDB (traducida)"
    if len(p["bio"]) > 1400:                        # lo justo para leer en la tele
        cut = p["bio"][:1400]
        p["bio"] = cut[:cut.rfind(". ") + 1] if ". " in cut else cut + "…"

    # emparejar Letterboxd ↔ IMDb (Wikidata primero, Cinemeta para el resto)
    by_title = {}
    for w in wdf:
        for t in (w["en"], w["es"]):
            if t:
                by_title.setdefault((norm_title(t), w["year"]), w["imdb"])
                by_title.setdefault((norm_title(t), 0), w["imdb"])

    def match(f):
        k = norm_title(f["name"])
        for y in (f["year"], f["year"] - 1, f["year"] + 1):
            if (k, y) in by_title:
                return by_title[(k, y)]
        return by_title.get((k, 0)) if not f["year"] else None
    todo = []
    order = {r: i for i, r in enumerate(ROLE_ORDER)}
    role_films.sort(key=lambda rf: order.get(rf[0], 99))
    for n, films in role_films:
        if not films:
            continue
        items = []
        for f in films[:40]:
            it = {"name": f["name"], "year": f["year"], "slug": f["slug"], "type": "movie", "id": match(f) or ""}
            items.append(it)
            if not it["id"]:
                todo.append(it)
        p["roles"].append({"role": n, "label": ROLE_ES.get(n, n), "count": len(films), "items": items})

    def res(it):
        try:
            m = resolve(it["name"], it["year"], "movie", strict=True)
            if m:
                it["id"] = m.get("imdb_id") or m.get("id") or ""
                it["poster"] = m.get("poster") or ""
        except Exception:
            pass
    with ThreadPoolExecutor(8) as ex:
        list(ex.map(res, todo[:60]))
    for r in p["roles"]:
        for it in r["items"]:
            if it["id"].startswith("tt") and not it.get("poster"):
                it["poster"] = f"https://images.metahub.space/poster/medium/{it['id']}/img"
    if not p["photo"] and tmdb:
        p["photo"] = ""                             # la del reparto la pone la pestaña
    return p if (p["roles"] or p["bio"]) else None


def cmd_person(name, path=""):
    key = re.sub(r"[^\w-]+", "_", (path or name).strip("/"))
    d = cached("person-" + key, 14 * 24 * 3600, lambda: build_person(name, path))
    out(d or {"error": "sin datos", "name": name})


def cmd_prefetch(*pairs):
    """about.py prefetch <nombre> <ruta> [<nombre> <ruta> …]: deja los perfiles listos en caché."""
    for name, path in zip(pairs[::2], pairs[1::2]):
        key = re.sub(r"[^\w-]+", "_", (path or name).strip("/"))
        try:
            cached("person-" + key, 14 * 24 * 3600, lambda: build_person(name, path))
        except Exception:
            pass
    out({"ok": True})


def cmd_warm(*items):
    """about.py warm movie:tt… series:tt… — deja listas ficha y parecidas (de a una, en segundo plano)."""
    lock = os.path.join(CACHE, "warm.lock")         # una sola precarga a la vez (sin flock: anda en Windows)
    os.makedirs(CACHE, exist_ok=True)
    if os.path.exists(lock) and time.time() - os.path.getmtime(lock) < 10 * 60:
        out({"ok": True, "busy": True})
        return
    open(lock, "w").close()
    try:
        _warm(items, lock)
    finally:
        try:
            os.remove(lock)
        except OSError:
            pass
    out({"ok": True})


def _warm(items, lock):
    for x in items:
        type_, _, id_ = x.partition(":")
        if not id_.startswith("tt"):
            continue
        path = os.path.join(CACHE, "similar-" + id_ + ".json")
        if os.path.exists(path) and time.time() - os.path.getmtime(path) < 30 * 24 * 3600:
            continue
        os.utime(lock)                             # sigo vivo
        try:
            cached("about-" + id_, 3 * 24 * 3600, lambda: build_about(type_, id_))
            cached("similar-" + id_, 30 * 24 * 3600, lambda: build_similar(type_, id_))
        except Exception as e:
            print(f"{id_}: {e}", file=sys.stderr)


def cmd_lbfilm(slug):
    """Película de Letterboxd sin IMDb conocido → id de IMDb (al elegirla)."""
    def get():
        op, _ = lb_module().opener()
        with op.open(f"https://letterboxd.com/film/{slug}/", timeout=25) as r:
            h = r.read().decode("utf-8", "replace")
        m = re.search(r"imdb\.com/title/(tt\d+)", h)
        return {"id": m.group(1), "type": "movie"} if m else None
    d = cached("lbfilm-" + slug, 90 * 24 * 3600, get)
    out(d or {"error": "sin IMDb"})


def main():
    a = sys.argv[1:]
    try:
        {"about": cmd_about, "similar": cmd_similar, "person": cmd_person, "lbfilm": cmd_lbfilm, "prefetch": cmd_prefetch, "warm": cmd_warm}[a[0]](*a[1:])
    except (IndexError, KeyError, TypeError):
        raise SystemExit(__doc__)
    except Exception as e:
        out({"error": str(e)})


if __name__ == "__main__":
    main()
