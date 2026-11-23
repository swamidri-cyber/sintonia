// SINTONÍA en el celular — datos de Stremio y Letterboxd (lo mismo que stremio.py y
// letterboxd.py en la PC, pero adentro del teléfono). Los pedidos salen por Android.req
// (sin CORS, con caché en disco y las cookies del navegador de la app).
"use strict";

const N = window.Android;
const API = "https://api.strem.io/api/";
const CINEMETA = "https://v3-cinemeta.strem.io";
const STREAMING = "https://7a82163c306e-stremio-netflix-catalog-addon.baby-beamup.club";
const TOPSTREAM = "https://top-streaming.stream/username=temporary_username";
const LB = "https://letterboxd.com";

const PLATFORMS = {
  stremio: [CINEMETA, "top"], netflix: [STREAMING, "nfx"], disney: [STREAMING, "dnp"], max: [STREAMING, "hbm"],
  prime: [STREAMING, "amp"], crunchyroll: [STREAMING, "cru"],
  "stremio-new": [CINEMETA, "year"], "stremio-best": [CINEMETA, "imdbRating"], top10: [TOPSTREAM, "popular-{type}-global"],
};
const PAGED = ["netflix", "disney", "max", "prime", "crunchyroll"];
const DEFAULT_ADDONS = [CINEMETA + "/manifest.json", STREAMING + "/manifest.json", TOPSTREAM + "/manifest.json",
                        "https://hispasubs.ak-forge.workers.dev/manifest.json"];

// ── Pedidos ────────────────────────────────────────────────────────────────
const _pend = {}; let _rid = 0;
window.__res = (id, r) => { const p = _pend[id]; delete _pend[id]; if (p) p(r); };
function req(o) {
  return new Promise(res => { const id = "r" + (++_rid); _pend[id] = res; N.req(id, JSON.stringify(o)); });
}
async function getJSON(url, ttl = 0, timeoutMs = 25000) {
  const r = await Promise.race([req({ url, ttl }), new Promise(res => setTimeout(() => res({ status: 0, error: "tiempo" }), timeoutMs))]);
  if (r.status !== 200) throw new Error(r.error || "HTTP " + r.status);
  return JSON.parse(r.body);
}
async function api(method, body) {
  const r = await req({ url: API + method, method: "POST", body: JSON.stringify(body), headers: { "Content-Type": "application/json" } });
  let d = {}; try { d = JSON.parse(r.body || "{}"); } catch (e) { throw new Error("Stremio no responde"); }
  if (d.error) throw new Error(d.error.message || "error de Stremio");
  return d.result;
}

// ── Cuenta de Stremio ──────────────────────────────────────────────────────
const Cuenta = {
  get() { try { return JSON.parse(localStorage.stremio || "null"); } catch (e) { return null; } },
  set(v) { if (v) localStorage.stremio = JSON.stringify(v); else localStorage.removeItem("stremio"); },
};
async function defaultAddons() {
  const res = [];
  await Promise.all(DEFAULT_ADDONS.map(async u => { try { res.push({ transportUrl: u, manifest: await getJSON(u, 7 * 86400) }); } catch (e) {} }));
  return res;
}
async function profile() {
  const ses = Cuenta.get();
  if (ses && ses.authKey) {
    if (Date.now() / 1000 - (ses.addonsTs || 0) > 6 * 3600 || !ses.addons) {
      try {
        const r = await api("addonCollectionGet", { type: "AddonCollectionGet", authKey: ses.authKey, update: true });
        ses.addons = r.addons || []; ses.addonsTs = Date.now() / 1000; Cuenta.set(ses);
      } catch (e) {}
    }
    return { key: ses.authKey, email: ses.email, addons: ses.addons && ses.addons.length ? ses.addons : await defaultAddons() };
  }
  return { key: null, addons: await defaultAddons() };
}
async function login(email, pw) {
  let r;
  try { r = await api("login", { type: "Login", email, password: pw, facebook: false }); }
  catch (e) {
    const m = String(e.message).toLowerCase();
    if (m.includes("password") || m.includes("wrong") || m.includes("passphrase")) throw new Error("Mail o contraseña incorrectos");
    if (m.includes("user not found")) throw new Error("No hay una cuenta de Stremio con ese mail");
    throw e;
  }
  Cuenta.set({ authKey: r.authKey, email: (r.user || {}).email || email });
  await profile();
}
async function logout() {
  const s = Cuenta.get();
  if (s && s.authKey) { try { await api("logout", { type: "Logout", authKey: s.authKey }); } catch (e) {} }
  Cuenta.set(null);
}

// ── Formato común de un título ──────────────────────────────────────────────
const art = (kind, id, fb) => String(id).startsWith("tt") ? `https://images.metahub.space/${kind}/medium/${id}/img` : (fb || "");
function normMeta(m) {
  const id = m.imdb_id || m.id || "";
  return { id, type: m.type || "movie", name: m.name || "", year: String(m.releaseInfo || m.year || ""),
           rating: String(m.imdbRating || ""), genres: m.genres || m.genre || [], country: m.country || "",
           runtime: m.runtime || "", description: m.description || "",
           poster: art("poster", id, m.poster), background: art("background", id, m.background), logo: art("logo", id, m.logo) };
}
const isoTs = s => { const t = Date.parse(s || ""); return isNaN(t) ? 0 : t / 1000; };
function normItem(it) {
  const st = it.state || {}, off = st.timeOffset || 0, dur = st.duration || 0, id = it._id;
  return { id, type: it.type || "movie", name: it.name || "", year: String(it.year || ""),
           poster: art("poster", id, it.poster), background: art("background", id, it.background), logo: art("logo", id, it.logo),
           offset: off, duration: dur, progress: dur ? off / dur : 0, videoId: st.video_id || "",
           season: st.season || 0, episode: st.episode || 0, lastWatched: isoTs(st.lastWatched || it._mtime),
           watched: !!(st.timesWatched || st.flaggedWatched), inList: !it.removed && !it.temp };
}

// ── Biblioteca, catálogos, búsqueda, fichas ────────────────────────────────
async function library() {
  const ses = Cuenta.get();
  if (!ses || !ses.authKey) return { continue: [], again: [], list: [], nologin: true };
  let items;
  try {
    items = await api("datastoreGet", { authKey: ses.authKey, collection: "libraryItem", ids: [], all: true });
    localStorage.libCache = JSON.stringify(items);
  } catch (e) { items = JSON.parse(localStorage.libCache || "[]"); }
  const n = items.filter(i => i.type === "movie" || i.type === "series").map(normItem);
  const rec = l => l.sort((a, b) => b.lastWatched - a.lastWatched);
  return { continue: rec(n.filter(x => x.offset > 0)), again: rec(n.filter(x => x.watched && x.offset === 0)), list: rec(n.filter(x => x.inList)) };
}
async function fetchCatalog(src, type, skip = "0", genre = "") {
  const [base, c] = PLATFORMS[src]; const cat = c.replace("{type}", type);
  const extra = [];
  if (genre) extra.push("genre=" + encodeURIComponent(genre));
  if (skip && skip !== "0") extra.push("skip=" + skip);
  const url = `${base}/catalog/${type}/${cat}` + (extra.length ? "/" + extra.join("&") : "") + ".json";
  return ((await getJSON(url, 6 * 3600)).metas || []).filter(m => m.name).map(normMeta);
}
async function catalogs(keys) {
  const res = {};
  await Promise.all(keys.map(async k => {
    const [src, type, genre] = (k + "||").split("|");
    const pages = PAGED.includes(src) && !genre ? ["0", "100", "200"] : ["0"];
    const got = await Promise.all(pages.map(p => fetchCatalog(src, type, p, genre).catch(() => [])));
    const seen = new Set(), out = [];
    for (const l of got) for (const m of l) if (!seen.has(m.id)) { seen.add(m.id); out.push(m); }
    res[k] = out;
  }));
  return res;
}
async function search(q) {
  const qq = encodeURIComponent(q);
  const [a, b] = await Promise.all(["movie", "series"].map(t => getJSON(`${CINEMETA}/catalog/${t}/top/search=${qq}.json`, 3600).then(d => d.metas || []).catch(() => [])));
  const mixed = [];
  for (let i = 0; i < Math.max(a.length, b.length); i++) { if (a[i]) mixed.push(a[i]); if (b[i]) mixed.push(b[i]); }
  return mixed.filter(m => m.name).map(normMeta);
}
async function meta(type, id) {
  const m = (await getJSON(`${CINEMETA}/meta/${type}/${id}.json`, 86400)).meta || {};
  const r = normMeta(m);
  r.videos = (m.videos || []).filter(v => v.season).map(v => ({
    id: v.id, season: v.season, episode: v.episode || v.number, name: v.name || v.title || "",
    overview: v.overview || v.description || "", thumbnail: v.thumbnail || "", released: (v.released || "").slice(0, 10) }))
    .sort((x, y) => x.season - y.season || (x.episode || 0) - (y.episode || 0));
  r.cast = (m.cast || []).slice(0, 4); r.director = (m.director || []).slice(0, 2);
  return r;
}
const nowIso = () => new Date().toISOString();
async function libItem(id) {
  const ses = Cuenta.get(); if (!ses) throw new Error("nologin");
  const cur = await api("datastoreGet", { authKey: ses.authKey, collection: "libraryItem", ids: [id], all: false });
  return [ses, cur && cur[0]];
}
async function myList(action, type, id, name) {
  const [ses, cur] = await libItem(id);
  const item = cur || { _id: id, type, name: name || "", poster: art("poster", id), posterShape: "poster", background: "", logo: "", year: "", _ctime: nowIso(), state: {} };
  item.removed = action === "remove"; item.temp = false; item._mtime = nowIso();
  await api("datastorePut", { authKey: ses.authKey, collection: "libraryItem", changes: [item] });
}
async function dismiss(id) {
  const [ses, item] = await libItem(id);
  if (!item) return;
  (item.state = item.state || {}).timeOffset = 0; item._mtime = nowIso();
  await api("datastorePut", { authKey: ses.authKey, collection: "libraryItem", changes: [item] });
}
async function progress(type, id, videoId, offsetMs, durMs, finished) {
  const ses = Cuenta.get(); if (!ses || !ses.authKey) return;
  let [, item] = await libItem(id);
  if (!item) {
    let m = {}; try { m = (await getJSON(`${CINEMETA}/meta/${type}/${id}.json`, 86400)).meta || {}; } catch (e) {}
    item = { _id: id, type, name: m.name || "", poster: art("poster", id), posterShape: "poster", background: "", logo: "",
             year: String(m.year || ""), _ctime: nowIso(), removed: true, temp: true, state: {} };
  }
  const st = item.state = item.state || {};
  const prev = st.timeOffset || 0;
  const w = st.video_id === videoId ? Math.max(0, offsetMs - prev) : offsetMs;
  st.timeWatched = (st.timeWatched || 0) + w; st.overallTimeWatched = (st.overallTimeWatched || 0) + w;
  st.video_id = videoId; st.duration = durMs; st.lastWatched = nowIso();
  const p = videoId.split(":"); st.season = p.length === 3 ? +p[1] : 0; st.episode = p.length === 3 ? +p[2] : 0;
  if (finished) { st.timeOffset = 0; st.timesWatched = (st.timesWatched || 0) + 1; if (type === "movie") st.flaggedWatched = 1; }
  else st.timeOffset = offsetMs;
  item._mtime = nowIso();
  await api("datastorePut", { authKey: ses.authKey, collection: "libraryItem", changes: [item] });
}

// ── Fuentes ────────────────────────────────────────────────────────────────
const COUNTRY_LANG = { "United States": "en", "United Kingdom": "en", Canada: "en", Australia: "en", Ireland: "en", "New Zealand": "en",
  "South Korea": "ko", Korea: "ko", Japan: "ja", France: "fr", Belgium: "fr", Spain: "es-ES", Argentina: "es-419", Mexico: "es-419",
  Colombia: "es-419", Chile: "es-419", Uruguay: "es-419", Peru: "es-419", Venezuela: "es-419", Cuba: "es-419", Germany: "de",
  Austria: "de", Switzerland: "de", Italy: "it", Brazil: "pt", Portugal: "pt", China: "zh", Taiwan: "zh", "Hong Kong": "zh",
  India: "hi", Russia: "ru", "Soviet Union": "ru", Denmark: "da", Sweden: "sv", Norway: "no", Finland: "fi", Netherlands: "nl",
  Poland: "pl", Turkey: "tr", Iran: "fa", Thailand: "th", Indonesia: "id", Philippines: "tl", Israel: "he", Greece: "el",
  "Czech Republic": "cs", Hungary: "hu", Romania: "ro", Ukraine: "uk", Egypt: "ar" };
const LANG_NAME = { en: "Inglés", ko: "Coreano", ja: "Japonés", fr: "Francés", "es-ES": "Español España", "es-419": "Español latino",
  de: "Alemán", it: "Italiano", pt: "Portugués", zh: "Chino", hi: "Hindi", ru: "Ruso", da: "Danés", sv: "Sueco", no: "Noruego",
  fi: "Finlandés", nl: "Neerlandés", pl: "Polaco", tr: "Turco", fa: "Persa", th: "Tailandés", id: "Indonesio", tl: "Filipino",
  he: "Hebreo", el: "Griego", cs: "Checo", hu: "Húngaro", ro: "Rumano", uk: "Ucraniano", ar: "Árabe" };
const FLAG_LANG = { "🇬🇧": "en", "🇺🇸": "en", "🇪🇸": "es-ES", "🇲🇽": "es-419", "🇦🇷": "es-419", "🇫🇷": "fr", "🇩🇪": "de", "🇮🇹": "it",
  "🇵🇹": "pt", "🇧🇷": "pt", "🇯🇵": "ja", "🇰🇷": "ko", "🇨🇳": "zh", "🇹🇼": "zh", "🇮🇳": "hi", "🇷🇺": "ru", "🇺🇦": "uk", "🇵🇱": "pl",
  "🇳🇱": "nl", "🇩🇰": "da", "🇸🇪": "sv", "🇳🇴": "no", "🇫🇮": "fi", "🇹🇷": "tr", "🇬🇷": "el", "🇭🇺": "hu", "🇨🇿": "cs", "🇷🇴": "ro",
  "🇮🇱": "he", "🇸🇦": "ar", "🇹🇭": "th" };
const BAD = /\b(cam|camrip|hdcam|ts|telesync|hdts|tc|telecine|scr|screener)\b/i;

function parseStream(st, source) {
  const txt = ["name", "title", "description"].map(k => String(st[k] || "")).join(" ");
  const first = (st.title || st.description || "").split("\n")[0];
  const fname = (st.behaviorHints || {}).filename || first;
  const langs = new Set(Object.keys(FLAG_LANG).filter(f => txt.includes(f)).map(f => FLAG_LANG[f]));
  const low = txt.toLowerCase();
  if (/\blat(ino|am)?\b|dual lat/.test(low)) langs.add("es-419");
  if (/castellano|\bcast\b|\bspa(nish)?\b/.test(low) && !langs.has("es-419")) langs.add("es-ES");
  const res = /2160\s?px?|\b4k\b|uhd/.test(low) ? 2160 : /1080\s?px?|fullhd|full hd/.test(low) ? 1080 : /720\s?px?/.test(low) ? 720 : 480;
  let m = /💾\s*([\d.]+)\s*(gb|mb)/.exec(low);
  const size = m ? parseFloat(m[1]) * (m[2] === "gb" ? 1 : 1 / 1024) : 0;
  m = /👤\s*(\d+)/.exec(txt);
  const seeds = m ? +m[1] : 0;
  return { source, title: first.slice(0, 120), filename: fname, hash: st.infoHash || "", fileIdx: st.fileIdx ?? null,
           url: st.url || "", sources: st.sources || [], res, size: Math.round(size * 100) / 100, seeds, langs: [...langs].sort(),
           multi: low.includes("multi") || low.includes("dual"), bad: BAD.test(first),
           dv: /\bdv\b|dolby.?vision/.test(low) && !low.includes("hdr"), remux: low.includes("remux"),
           // el teléfono decodifica bien hasta 1080p; 4K pesa demasiado para bajar mientras se ve
           hevc: /hevc|x265|h\.?265/.test(low) };
}
function score(s) {
  if (s.bad || (s.hash && s.seeds === 0)) return -1;
  const base = { 1080: 10, 720: 7, 2160: 2 }[s.res] ?? 2;
  const size = s.size || 4;
  let seeds = Math.min(Math.log10(1 + s.seeds), 2.5) * 1.2;
  if (s.hash && s.seeds < 3) seeds -= 3;
  return base - size * 0.7 + seeds - (s.dv ? 1.5 : 0) - (s.remux ? 2 : 0);
}
async function streams(type, id, videoId) {
  let mt = {}; try { mt = (await getJSON(`${CINEMETA}/meta/${type}/${id}.json`, 86400)).meta || {}; } catch (e) {}
  const country = (mt.country || "").split(",")[0].trim();
  const orig = COUNTRY_LANG[country] || "en";
  const vid = encodeURIComponent(videoId).replace(/%3A/g, ":");
  const p = await profile();
  const adds = p.addons.filter(a => {
    const res = ((a.manifest || {}).resources || []).map(r => typeof r === "string" ? r : r.name);
    return res.includes("stream") && String(a.transportUrl).startsWith("http") && !a.transportUrl.includes("127.0.0.1");
  });
  if (!p.key) return { nologin: true, options: [] };
  const lists = await Promise.all(adds.map(async a => {
    const base = a.transportUrl.replace(/\/manifest\.json$/, "");
    try { return ((await getJSON(`${base}/stream/${type}/${vid}.json`, 0, 16000)).streams || []).map(s => parseStream(s, a.manifest.name)); }
    catch (e) { return []; }
  }));
  let all = lists.flat().filter(s => s.hash || s.url.startsWith("http"));
  const seen = new Set(), uniq = [];
  for (const s of all.sort((a, b) => score(b) - score(a))) {
    const k = s.hash ? s.hash + s.fileIdx : s.url;
    if (!seen.has(k) && score(s) >= 0) { seen.add(k); uniq.push(s); }
  }
  const inLang = (s, l) => l === orig ? (!s.langs.length || s.langs.includes(orig) || s.multi) : s.langs.includes(l);
  // nunca el doblaje de España, salvo que sea el idioma original (pedido 2026-11-14)
  const order = [orig].concat(orig !== "es-419" ? ["es-419"] : []);
  const options = [];
  for (const l of order) {
    const lst = uniq.filter(s => inLang(s, l)).slice(0, 8);
    if (lst.length) options.push({ lang: l, label: (LANG_NAME[l] || l) + (l === orig ? " (original)" : ""), streams: lst });
  }
  return { original: orig, originalName: LANG_NAME[orig] || orig, options, total: uniq.length };
}
async function subsEs(type, videoId, filename) {
  const extra = filename ? "/filename=" + encodeURIComponent(filename) : "";
  const vid = encodeURIComponent(videoId).replace(/%3A/g, ":");
  try {
    const d = await getJSON(`https://opensubtitles-v3.strem.io/subtitles/${type}/${vid}${extra}.json`, 6 * 3600, 15000);
    return (d.subtitles || []).filter(x => ["spa", "spn", "es", "esp", "ea"].includes(x.lang)).map(x => x.url);
  } catch (e) { return []; }
}

// ── Letterboxd ─────────────────────────────────────────────────────────────
const Letterboxd = {
  logged() { try { return N.lbLogged(); } catch (e) { return false; } },
  async user() {
    const r = await req({ url: LB + "/", cookies: true });
    const m = /person\.username\s*=\s*"([^"]*)"/.exec(r.body || "");
    return m ? m[1] : "";
  },
  async film(imdb) {
    const r = await req({ url: `${LB}/imdb/${imdb}/`, cookies: true });
    if (r.status !== 200) throw new Error("Letterboxd respondió " + r.status);
    const h = r.body;
    const user = /person\.username\s*=\s*"([^"]*)"/.exec(h);
    const name = /data-item-full-display-name="([^"]+)"/.exec(h);
    const csrf = /supermodelCSRF\s*=\s*['"]([^'"]+)/.exec(h) || /name="__csrf"\s+value="([^"]+)"/.exec(h);
    if (!/data\.viewingable\.uid\s*=\s*'film:\d+'/.test(h) && !/film:\d+/.test(h)) throw new Error("Letterboxd no tiene esa película");
    return { user: user && user[1] ? user[1] : null, url: r.url, name: name ? name[1] : "", csrf: csrf ? csrf[1] : "" };
  },
  async log(imdb, stars10, like, rewatch, spoilers, text) {
    const f = await this.film(imdb);
    if (!f.user) throw new Error("No hay sesión de Letterboxd");
    const jr = await req({ url: f.url.replace(/\/$/, "") + "/json/", cookies: true,
                           headers: { "X-Requested-With": "XMLHttpRequest", Accept: "application/json", Referer: f.url } });
    const fj = JSON.parse(jr.body || "{}");
    const body = { productionId: fj.lid, diaryDetails: { diaryDate: new Date().toLocaleDateString("sv"), rewatch }, tags: [], like };
    if (text.trim()) body.review = { text: text.trim(), containsSpoilers: spoilers };
    if (stars10) body.rating = stars10 / 2;
    const r = await req({ url: LB + "/api/v0/production-log-entries", method: "POST", cookies: true, body: JSON.stringify(body),
                          headers: { "Content-Type": "application/json; charset=UTF-8", Accept: "application/json",
                                     "X-CSRF-TOKEN": fj.csrf || f.csrf, Origin: LB, Referer: f.url } });
    let res = {}; try { res = JSON.parse(r.body || "{}"); } catch (e) { throw new Error("Respuesta rara de Letterboxd (" + r.status + ")"); }
    const errs = (res.messages || []).filter(m => m && m.type === "Error");
    if (r.status >= 400 || errs.length || !res.logEntry)
      throw new Error(errs.map(m => m.title || m.code).join("; ") || res.message || "Letterboxd respondió " + r.status);
    return { user: f.user, film: f.name, url: f.url };
  },
};
