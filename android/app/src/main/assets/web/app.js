// SINTONÍA en el celular — la interfaz de tele.
"use strict";

const $ = s => document.querySelector(s);
const el = (tag, cls, html) => { const e = document.createElement(tag); if (cls) e.className = cls; if (html != null) e.innerHTML = html; return e; };
const esc = t => String(t ?? "").replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const fmt = s => { s = Math.max(0, Math.round(s || 0)); const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60;
                   return (h ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(x).padStart(2, "0"); };
const vibe = (ms = 12) => { try { N.vibrate(ms); } catch (e) {} };
const THIS_YEAR = new Date().getFullYear();
const THROWBACK = 1975 + Math.floor(Date.now() / 86400000) % 40;

const CHANNELS = [
  { id: "stremio", ch: "01", name: "STREMIO", kana: "初号機", ep: "第壱話", bg: "#07020c", deep: "#14072a", line: "#3d2260", dim: "#9a74c8", fg: "#e2ceff", hi: "#f6eeff", warn: "#ff8a3d" },
  { id: "netflix", ch: "02", name: "NETFLIX", kana: "赤", ep: "第弐話", bg: "#0b0202", deep: "#200606", line: "#5a1616", dim: "#c0605a", fg: "#ffd0ca", hi: "#fff2ee", warn: "#ffd25a" },
  { id: "disney", ch: "03", name: "DISNEY+", kana: "零号機", ep: "第参話", bg: "#02060d", deep: "#07152c", line: "#1d3a66", dim: "#6b9ad2", fg: "#cde1ff", hi: "#f0f6ff", warn: "#ffb35a" },
  { id: "max", ch: "04", name: "MAX", kana: "白", ep: "第四話", bg: "#050505", deep: "#141416", line: "#3a3a3e", dim: "#9a9aa0", fg: "#ececE8", hi: "#ffffff", warn: "#ff6a5a" },
  { id: "prime", ch: "05", name: "PRIME VIDEO", kana: "青", ep: "第伍話", bg: "#010a0b", deep: "#051d20", line: "#145055", dim: "#5bbcc0", fg: "#c8f9f5", hi: "#effffd", warn: "#ffb35a" },
  { id: "crunchyroll", ch: "06", name: "CRUNCHYROLL", kana: "アニメ", ep: "第六話", bg: "#0c0601", deep: "#241204", line: "#6a3410", dim: "#d08a4a", fg: "#ffdcbc", hi: "#fff3e8", warn: "#ff5a8a" },
];
const TABS = [["home", "INICIO"], ["movie", "PELÍCULAS"], ["series", "SERIES"]];
const STREMIO_HOME = [
  ["TOP 10 EN EL MUNDO · PELÍCULAS", "top10", "movie", ""], ["TOP 10 EN EL MUNDO · SERIES", "top10", "series", ""],
  ["PELÍCULAS POPULARES", "stremio", "movie", ""], ["ESTRENOS", "stremio-new", "movie", String(THIS_YEAR)],
  ["SERIES POPULARES", "stremio", "series", ""], ["SERIES NUEVAS", "stremio-new", "series", String(THIS_YEAR)],
  ["DESTACADAS", "stremio-best", "movie", ""], ["PARA REÍRSE", "stremio", "movie", "Comedy"],
  ["PARA NO DORMIR", "stremio", "movie", "Horror"], ["ADRENALINA", "stremio", "movie", "Action"],
  ["OTROS MUNDOS", "stremio", "movie", "Sci-Fi"], ["SERIES DE CRIMEN Y MISTERIO", "stremio", "series", "Crime"],
  ["ANIMACIÓN", "stremio", "movie", "Animation"], ["UN VIAJE A " + THROWBACK, "stremio-new", "movie", String(THROWBACK)],
  ["HISTORIAS REALES", "stremio", "movie", "Documentary"], ["PARA ENAMORARSE", "stremio", "movie", "Romance"]];
const GENRES = [["Action", "ACCIÓN"], ["Comedy", "COMEDIA"], ["Drama", "DRAMA"], ["Thriller", "SUSPENSO"], ["Horror", "TERROR"],
  ["Sci-Fi", "CIENCIA FICCIÓN"], ["Animation", "ANIMACIÓN"], ["Romance", "ROMANCE"], ["Crime", "POLICIALES"], ["Documentary", "DOCUMENTALES"]];
const PLAT_GENRES = [[["Comedy"], "PARA REÍRSE"], [["Horror"], "PARA NO DORMIR"], [["Action"], "ADRENALINA"], [["Drama"], "DRAMAS"],
  [["Sci-Fi", "Fantasy"], "OTROS MUNDOS"], [["Crime", "Mystery"], "CRIMEN Y MISTERIO"], [["Family", "Animation"], "EN FAMILIA"],
  [["Documentary", "Biography"], "HISTORIAS REALES"], [["Romance"], "PARA ENAMORARSE"]];
const ANIME_GENRES = [[["Action"], "PELEAS ÉPICAS"], [["Fantasy", "Adventure"], "MUNDOS FANTÁSTICOS"], [["Comedy"], "PARA REÍRSE"],
  [["Romance"], "ROMANCE"], [["Drama"], "DRAMAS"], [["Sci-Fi"], "CIENCIA FICCIÓN"]];
const GENRE_ES = { Action: "Acción", Adventure: "Aventura", Animation: "Animación", Comedy: "Comedia", Crime: "Policial",
  Documentary: "Documental", Drama: "Drama", Family: "Familiar", Fantasy: "Fantasía", Horror: "Terror", Mystery: "Misterio",
  Romance: "Romance", "Sci-Fi": "Ciencia ficción", Thriller: "Suspenso", War: "Bélica", History: "Historia", Biography: "Biografía" };

const prefs = () => { try { return JSON.parse(localStorage.prefs || "{}"); } catch (e) { return {}; } };
const setPref = (k, v) => { const p = prefs(); p[k] = v; localStorage.prefs = JSON.stringify(p); };
let S = { ch: "stremio", tab: "home", item: null, meta: null, season: null, lib: null };

function toast(t) { const e = $("#toast"); e.textContent = t; e.classList.remove("hidden"); clearTimeout(toast.t); toast.t = setTimeout(() => e.classList.add("hidden"), 2800); }

// ── Tele: estática y barras ─────────────────────────────────────────
const cv = $("#static"), cx = cv.getContext("2d");
let staticOn = 0, staticRaf = 0;
function noise() {
  const w = cv.width = Math.ceil(innerWidth / 3), h = cv.height = Math.ceil(innerHeight / 3);
  const img = cx.createImageData(w, h), d = img.data;
  for (let i = 0; i < d.length; i += 4) { const v = Math.random() * 255 | 0; d[i] = d[i + 1] = d[i + 2] = v; d[i + 3] = 255; }
  cx.putImageData(img, 0, 0);
  if (staticOn) staticRaf = requestAnimationFrame(noise);
}
function staticFor(ms, amt = 0.9) {
  staticOn++; cv.style.transition = "none"; cv.style.opacity = amt; cancelAnimationFrame(staticRaf); noise();
  return new Promise(res => setTimeout(() => {
    cv.style.transition = "opacity .25s"; cv.style.opacity = 0;
    setTimeout(() => { if (--staticOn <= 0) { staticOn = 0; cancelAnimationFrame(staticRaf); } res(); }, 250);
  }, ms));
}
const SMPTE = ["#c0c0c0", "#c0c000", "#00c0c0", "#00c000", "#c000c0", "#c00000", "#0000c0"];
$("#bars").innerHTML = SMPTE.map(c => `<i style="background:${c}"></i>`).join("");
function osd(t) { const o = $("#osd"); o.textContent = t; o.classList.add("on"); clearTimeout(osd.t); osd.t = setTimeout(() => o.classList.remove("on"), 2200); }
// Entrada: la tele se enciende, dos señales se buscan hasta quedar en sintonía (同調)
// y aparece el nombre. Tocar la pantalla la saltea.
const ease = { outExpo: k => k >= 1 ? 1 : 1 - Math.pow(2, -10 * k), inCubic: k => k * k * k,
               inOut: k => k < .5 ? 4 * k * k * k : 1 - Math.pow(-2 * k + 2, 3) / 2, outCubic: k => 1 - Math.pow(1 - k, 3) };
const clamp01 = v => Math.max(0, Math.min(1, v));
function encender() {
  return new Promise(done => {
    const c = chan(), root = $("#intro"), cvs = $("#introCv"), g = cvs.getContext("2d");
    const dpr = 1, W = innerWidth, H = innerHeight;     // resolución de tele vieja: liviano y con grano
    cvs.width = W * dpr; cvs.height = H * dpr; g.setTransform(dpr, 0, 0, dpr, 0, 0);
    $("#introTitle").innerHTML = [..."SINTONÍA"].map((l, i) => `<span style="--i:${i}">${l}</span>`).join("");
    $("#introTag").textContent = `CH ${c.ch} · ${c.name} · EN EL AIRE`;
    root.className = "";
    // ruido de tele (chico y estirado: barato y con grano grueso)
    const nz = document.createElement("canvas"); nz.width = Math.ceil(W / 5); nz.height = Math.ceil(H / 5);
    const nzg = nz.getContext("2d"), nzImg = nzg.createImageData(nz.width, nz.height);
    const ruido = alpha => {
      const d = nzImg.data; for (let i = 0; i < d.length; i += 4) { const v = Math.random() * 255 | 0; d[i] = d[i + 1] = d[i + 2] = v; d[i + 3] = 255; }
      nzg.putImageData(nzImg, 0, 0); g.globalAlpha = alpha; g.imageSmoothingEnabled = false; g.drawImage(nz, 0, 0, W, H); g.globalAlpha = 1;
    };
    const cy = H * 0.62, A = Math.min(W, H) * 0.075, ph2 = Math.random() * 6;
    const onda = (freq, phase, amp, jit, color, width, glow) => {
      g.beginPath();
      for (let x = 0; x <= W; x += 3) {
        const y = cy + amp * Math.sin(x / W * freq * Math.PI * 2 + phase) + (Math.random() - .5) * jit;
        x ? g.lineTo(x, y) : g.moveTo(x, y);
      }
      g.strokeStyle = color; g.lineWidth = width; g.shadowColor = color; g.shadowBlur = glow; g.stroke(); g.shadowBlur = 0;
    };
    let t0 = performance.now(), fin = false, buzz = false;
    const terminar = () => { if (fin) return; fin = true; root.className = "hidden"; staticFor(200, .45); done(); };
    root.onclick = terminar;
    const frame = now => {
      if (fin) return;
      const t = now - t0;
      g.fillStyle = "#000"; g.fillRect(0, 0, W, H);
      // 1) encendido del tubo: punto → línea → destello
      if (t < 240) {
        const k = ease.outExpo(t / 240);
        g.shadowColor = "#fff"; g.shadowBlur = 24; g.fillStyle = "#fff";
        g.fillRect(W / 2 - W * k / 2, H / 2 - 1.5, Math.max(4, W * k), 3); g.shadowBlur = 0;
      } else if (t < 440) {
        const k = ease.inCubic((t - 240) / 200), h = Math.max(3, H * k);
        g.fillStyle = "#fff"; g.fillRect(0, H / 2 - h / 2, W, h);
      } else if (t < 1150) {
        ruido(t < 620 ? 1 : 1 - .82 * clamp01((t - 620) / 530));
        if (t < 620) { g.fillStyle = `rgba(255,255,255,${1 - (t - 440) / 180})`; g.fillRect(0, 0, W, H); }
      } else ruido(.18 * (1 - clamp01((t - 2300) / 900)) + .03);
      // 2) sintonizando: dos señales que se buscan
      if (t > 850 && t < 2900) {
        const p = ease.inOut(clamp01((t - 950) / 1350)), fade = clamp01((t - 850) / 300);
        const base = (t / 1000) * 2.2;
        g.globalAlpha = fade;
        if (p < 1) {
          onda(5.2 + (2.2 - 5.2) * p, base * 1.7, A * (0.6 + .4 * p), 26 * (1 - p), c.hi, 2.4, 14);
          onda(0.9 + (2.2 - 0.9) * p, ph2 + (base * 1.7 - ph2) * p, A * (1.3 - .3 * p), 30 * (1 - p), c.warn, 2.4, 14);
        } else {
          // 3) en sintonía: una sola señal que se aplana
          const q = clamp01((t - 2300) / 450);
          onda(2.2, base * 1.7, A * (1 - ease.outCubic(q)), 0, "#fff", 3 - q, 30 * (1 - q) + 8);
        }
        // dial de radio
        const dy = H * 0.8, off = (p * W * 1.6) % 18;
        g.strokeStyle = c.dim; g.lineWidth = 1;
        for (let x = -off, n = 0; x < W; x += 18, n++) { const big = (n + Math.floor(p * W * 1.6 / 18)) % 5 === 0;
          g.beginPath(); g.moveTo(x, dy); g.lineTo(x, dy - (big ? 16 : 7)); g.stroke(); }
        g.fillStyle = c.warn; g.fillRect(W / 2 - 1, dy - 26, 2, 32);
        g.font = "13px Mono"; g.textAlign = "center"; g.fillStyle = p < 1 ? c.fg : "#fff";
        g.fillText(p < 1 ? `SINTONIZANDO  ${(76.3 + 24.8 * p).toFixed(1).replace(".", ",")} MHz` : "同調 · EN SINTONÍA", W / 2, dy + 26);
        g.globalAlpha = 1;
      }
      if (t >= 2300 && !buzz) { buzz = true; vibe(28); root.classList.add("sync"); }
      // 4) salto de barras y la tele se "apaga" hacia la app
      if (t > 3400 && !root.classList.contains("glitch")) root.classList.add("glitch");
      if (t > 3720 && !root.classList.contains("off")) root.classList.add("off");
      if (t > 4230) { terminar(); return; }
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
  });
}

// ── Canales ────────────────────────────────────────────────────────────────
const chan = () => CHANNELS.find(c => c.id === S.ch) || CHANNELS[0];
function theme() {
  const c = chan();
  for (const k of ["bg", "deep", "line", "dim", "fg", "hi", "warn"]) document.documentElement.style.setProperty("--" + k, c[k]);
  try { N.barColor(c.bg); } catch (e) {}
  $("#chNum").textContent = "CH " + c.ch + " · " + c.kana;
  $("#chName").textContent = c.name;
}
function renderChips() {
  const box = $("#chips"); box.innerHTML = "";
  for (const c of CHANNELS) {
    const b = el("button", "chip" + (c.id === S.ch ? " on" : ""), "CH " + c.ch + " " + esc(c.name));
    b.onclick = () => cambiarCanal(c.id);
    box.appendChild(b);
  }
  const on = box.querySelector(".on"); if (on) on.scrollIntoView({ inline: "center", block: "nearest" });
}
async function cambiarCanal(id) {
  if (id === S.ch) return;
  vibe(18);
  const st = staticFor(380);
  S.ch = id; S.tab = "home"; localStorage.ch = id;
  setTimeout(() => { theme(); renderChips(); renderTabs(); loadRows(); osd("CH " + chan().ch); }, 160);
  await st;
}
function renderTabs() {
  const box = $("#tabs"); box.innerHTML = "";
  for (const [id, label] of TABS) {
    const b = el("button", "tab" + (id === S.tab ? " on" : ""), label);
    b.onclick = () => { vibe(); S.tab = id; renderTabs(); loadRows(); };
    box.appendChild(b);
  }
}
// Varias capas: la primera que exista tapa a las demás (si una no carga, se ve la siguiente)
function imgs(it) {
  const l = [...new Set([it.background, it.background0, it.poster, it.poster0].filter(Boolean))];
  return l.map(u => `url("${u}")`).join(", ");
}
function card(it) {
  const c = el("button", "card");
  c.style.backgroundImage = imgs(it);
  c.appendChild(el("div", "t", esc(it.name)));
  if (it.progress > 0.01 && it.progress < 0.97) { const p = el("div", "p"); p.style.width = (it.progress * 100) + "%"; c.appendChild(p); }
  if (it.type === "series") c.appendChild(el("div", "badge", "SERIE"));
  c.onclick = () => { vibe(); openSheet(it); };
  return c;
}

// ── Filas de cada canal ────────────────────────────────────────────────────
// Arma las filas del canal; paint(filas) se llama cada vez que llega un catálogo
// (así se ve algo enseguida aunque alguno tarde).
async function rowsFor(ch, tab, paint) {
  const cats = {}; let lib = null;
  const add = (R, t, items, mn = 1) => { if (items && items.length >= mn) R.push({ title: t, items: items.slice(0, 40) }); };
  let build, keys;
  if (ch === "stremio" && tab === "home") {
    keys = STREMIO_HOME.map(([, s, t, g]) => `${s}|${t}|${g}`);
    build = () => {
      const R = [];
      if (lib) { add(R, "SEGUIR VIENDO", lib.continue); add(R, "MI LISTA", lib.list); }
      STREMIO_HOME.forEach(([title], i) => add(R, title, cats[keys[i]], 4));
      if (lib) add(R, "VER DE NUEVO", lib.again);
      return R;
    };
  } else if (ch === "stremio") {
    keys = [`stremio|${tab}|`].concat(GENRES.map(([g]) => `stremio|${tab}|${g}`));
    build = () => { const R = []; add(R, "POPULARES", cats[keys[0]]); GENRES.forEach(([, title], i) => add(R, title, cats[keys[i + 1]], 4)); return R; };
  } else {
    const km = `${ch}|movie|`, ks = `${ch}|series|`;
    keys = [km, ks];
    build = () => {
      const R = [], M = cats[km] || [], Sr = cats[ks] || [];
      const anime = ch === "crunchyroll", gl = anime ? ANIME_GENRES : PLAT_GENRES;
      const both = []; for (let i = 0; i < Math.max(M.length, Sr.length); i++) { if (M[i]) both.push(M[i]); if (Sr[i]) both.push(Sr[i]); }
      const has = (x, gs) => gs.some(g => (x.genres || []).includes(g));
      const year = x => parseInt(String(x.year).slice(0, 4)) || 0, rating = x => parseFloat(x.rating) || 0;
      if (tab === "movie") { add(R, "POPULARES", M); gl.forEach(([gs, t]) => add(R, t, M.filter(x => has(x, gs)), 4)); }
      else if (tab === "series") { add(R, "POPULARES", Sr); gl.forEach(([gs, t]) => add(R, t, Sr.filter(x => has(x, gs)), 4)); }
      else {
        add(R, anime ? "TOP 10 ANIME" : "TOP 10 EN " + chan().name, both.slice(0, 10));
        add(R, anime ? "ANIME POPULAR" : "SERIES POPULARES", Sr);
        add(R, anime ? "PELÍCULAS DE ANIME" : "PELÍCULAS POPULARES", M);
        add(R, "ESTRENOS", both.filter(x => year(x) >= THIS_YEAR - 1).sort((a, b) => year(b) - year(a)));
        add(R, "LAS MEJOR PUNTUADAS", both.filter(x => rating(x) >= 7.3).sort((a, b) => rating(b) - rating(a)));
        gl.forEach(([gs, t]) => add(R, t, both.filter(x => has(x, gs)), 4));
      }
      return R;
    };
  }
  let pend = false;
  const tick = () => { if (pend) return; pend = true; setTimeout(() => { pend = false; paint(build()); }, 250); };
  const jobs = [catalogs(keys, (k, v) => { cats[k] = v; tick(); })];
  if (ch === "stremio" && tab === "home") jobs.push(library().then(l => { lib = S.lib = l; tick(); }).catch(() => {}));
  await Promise.all(jobs);
  return build();
}
let rowsReq = 0;
async function loadRows() {
  const n = ++rowsReq, box = $("#rows");
  box.innerHTML = '<div class="loading">SINTONIZANDO…</div>';
  const paint = (rows, final) => {
    if (n !== rowsReq || (!final && !rows.length)) return;
    box.innerHTML = "";
    if (S.ch === "stremio" && S.tab === "home" && !Cuenta.get()) {
      const h = el("div", "hola", `<div class="eva">BIENVENIDO</div><p>Conectá tu cuenta de Stremio para ver: con ella vienen tus addons (las fuentes), tu lista y dónde quedaste. Sin cuenta solo se ven los catálogos.</p>`);
      const b = el("button", "btn main", "CONECTAR STREMIO"); b.onclick = openCfg; h.appendChild(b); box.appendChild(h);
    }
    if (!rows.length) box.innerHTML += '<div class="loading">NO HAY SEÑAL EN ESTE CANAL</div>';
    for (const r of rows) {
      const row = el("section", "row"); row.appendChild(el("h3", "", esc(r.title)));
      const sc = el("div", "scroller"); r.items.forEach(it => sc.appendChild(card(it))); row.appendChild(sc); box.appendChild(row);
    }
    if (!final) box.appendChild(el("div", "loading", "SINTONIZANDO MÁS…"));
  };
  try { paint(await rowsFor(S.ch, S.tab, r => paint(r, false)), true); }
  catch (e) { if (n === rowsReq) box.innerHTML = '<div class="loading">SIN SEÑAL: ¿HAY INTERNET?</div>'; }
}

// ── Buscar (menú propio al tocar la lupa) ─────────────────────────────────
const GEN_KANJI = { Action: "闘", Comedy: "笑", Drama: "涙", Thriller: "緊", Horror: "怖", "Sci-Fi": "宙", Animation: "絵",
  Romance: "恋", Crime: "罪", Documentary: "実" };
const BQ = { tipo: "all", genero: null };
const recientes = () => { try { return JSON.parse(localStorage.recientes || "[]"); } catch (e) { return []; } };
function recordar(q) { q = q.trim(); if (q.length < 2) return; localStorage.recientes = JSON.stringify([q].concat(recientes().filter(x => x.toLowerCase() !== q.toLowerCase())).slice(0, 10)); }
$("#searchBtn").onclick = () => { vibe(); openBuscar(); };
$("#bqClose").onclick = () => close("buscar");
function openBuscar() {
  BQ.genero = null;
  $("#buscar").classList.add("open"); $("#buscar").scrollTop = 0;
  if (!stack.includes("buscar")) push("buscar");
  renderTipo(); renderBuscar();
  setTimeout(() => $("#q").focus(), 330);
}
function renderTipo() {
  const box = $("#bqTipo"); box.innerHTML = "";
  for (const [v, l] of [["all", "TODO"], ["movie", "PELÍCULAS"], ["series", "SERIES"]]) {
    const b = el("button", "chip" + (BQ.tipo === v ? " on" : ""), l);
    b.onclick = () => { vibe(); BQ.tipo = v; renderTipo(); renderBuscar(); };
    box.appendChild(b);
  }
}
function cardBq(it) {
  const c = card(it);
  c.onclick = () => { vibe(); const q = $("#q").value.trim(); if (q) recordar(q); openSheet(it); };
  if (it.year && it.type !== "series") c.appendChild(el("div", "yr", esc(String(it.year).slice(0, 4))));
  return c;
}
let bqReq = 0, qTimer = null;
$("#q").oninput = () => { $("#qClear").classList.toggle("hidden", !$("#q").value); BQ.genero = null; clearTimeout(qTimer); qTimer = setTimeout(renderBuscar, 380); };
$("#q").onkeydown = e => { if (e.key === "Enter") { recordar($("#q").value); $("#q").blur(); } };
$("#qClear").onclick = () => { $("#q").value = ""; $("#qClear").classList.add("hidden"); renderBuscar(); $("#q").focus(); };
async function renderBuscar() {
  const n = ++bqReq, box = $("#bqBody"), q = $("#q").value.trim();
  const filtro = l => BQ.tipo === "all" ? l : l.filter(x => x.type === BQ.tipo);
  const grilla = (titulo, items, vacio) => {
    box.innerHTML = "";
    const h = el("div", "bqH", `<span>${esc(titulo)}</span>`);
    if (BQ.genero) { const b = el("button", "", "✕ GÉNEROS"); b.onclick = () => { BQ.genero = null; renderBuscar(); }; h.appendChild(b); }
    box.appendChild(h);
    if (!items.length) { box.appendChild(el("div", "loading", vacio)); return; }
    const g = el("div", "grid"); items.forEach(it => g.appendChild(cardBq(it))); const w = el("div", "bqRes"); w.appendChild(g); box.appendChild(w);
  };
  if (q.length >= 2) {
    box.innerHTML = '<div class="loading">BUSCANDO…</div>';
    const items = filtro(await search(q).catch(() => []));
    if (n === bqReq) grilla(`RESULTADOS · ${items.length}`, items, "NADA CON ESE NOMBRE");
    return;
  }
  if (BQ.genero) {
    const [g, label] = BQ.genero;
    box.innerHTML = '<div class="loading">SINTONIZANDO ' + esc(label) + '…</div>';
    const keys = (BQ.tipo === "all" ? ["movie", "series"] : [BQ.tipo]).map(t => `stremio|${t}|${g}`);
    const cats = await catalogs(keys);
    const ls = keys.map(k => cats[k] || []), mix = [];
    for (let i = 0; i < Math.max(...ls.map(l => l.length)); i++) for (const l of ls) if (l[i]) mix.push(l[i]);
    if (n === bqReq) grilla(label, mix, "NO HAY SEÑAL");
    return;
  }
  // sin escribir: recientes + géneros
  box.innerHTML = "";
  const rec = recientes();
  if (rec.length) {
    const h = el("div", "bqH", "<span>BÚSQUEDAS RECIENTES</span>");
    const b = el("button", "", "BORRAR"); b.onclick = () => { localStorage.removeItem("recientes"); renderBuscar(); }; h.appendChild(b);
    box.appendChild(h);
    const r = el("div", "recents");
    for (const x of rec) { const c = el("button", "chip", esc(x)); c.onclick = () => { vibe(); $("#q").value = x; $("#qClear").classList.remove("hidden"); renderBuscar(); }; r.appendChild(c); }
    box.appendChild(r);
  }
  box.appendChild(el("div", "bqH", "<span>EXPLORAR POR GÉNERO</span>"));
  const gr = el("div", "generos");
  for (const [g, label] of GENRES) {
    const b = el("button", "gen", `<i>${GEN_KANJI[g] || ""}</i><b>${esc(label)}</b>`);
    b.onclick = () => { vibe(); BQ.genero = [g, label]; $("#q").blur(); renderBuscar(); };
    gr.appendChild(b);
  }
  box.appendChild(gr);
}

// ── Pila de pantallas (botón atrás de Android) ─────────────────────────────
const stack = [];
function push(v) { stack.push(v); }
window.__back = () => {
  if (!$("#pick").classList.contains("hidden")) { pickCancel(); return; }
  const v = stack.pop();
  if (v === "sheet") $("#sheet").classList.remove("open");
  else if (v === "cfg") $("#cfg").classList.remove("open");
  else if (v === "review") $("#review").classList.remove("open");
  else if (v === "buscar") { if (BQ.genero) { BQ.genero = null; renderBuscar(); stack.push("buscar"); } else $("#buscar").classList.remove("open"); }
  else if (v === "remote") $("#remote").classList.remove("open");
  else if (S.tab !== "home") { S.tab = "home"; renderTabs(); loadRows(); }
  else N.salir();
};
const close = id => { const i = stack.lastIndexOf(id); if (i >= 0) stack.splice(i, 1); $("#" + id).classList.remove("open"); };

// ── Ficha ──────────────────────────────────────────────────────────────────
async function openSheet(it) {
  S.item = it; S.meta = null; S.season = null;
  $("#hero").style.backgroundImage = imgs(it);
  renderInfo();
  $("#sheet").classList.add("open"); $("#sheet").scrollTop = 0;
  if (!stack.includes("sheet")) push("sheet");
  try { const m = await meta(it.type, it.id); if (S.item === it) { S.meta = m; renderInfo(); } } catch (e) {}
}
$("#sheetClose").onclick = () => close("sheet");
function libOf(id) { const l = S.lib; if (!l) return null; return [...l.continue, ...l.list, ...l.again].find(x => x.id === id) || null; }
function renderInfo() {
  const lib = libOf(S.item.id) || {};
  const it = Object.assign({}, S.item, S.meta || {}, { offset: lib.offset ?? S.item.offset, videoId: lib.videoId ?? S.item.videoId, progress: lib.progress ?? S.item.progress });
  const box = $("#info");
  const meta_ = [it.year, it.rating ? "★ " + it.rating : "", it.runtime, (it.genres || []).slice(0, 3).map(g => GENRE_ES[g] || g).join(", ")]
    .filter(Boolean).join("  ·  ");
  const people = [(it.director || []).length ? "Dirección: " + it.director.join(", ") : "", (it.cast || []).length ? "Con " + it.cast.join(", ") : ""].filter(Boolean).join("<br>");
  box.innerHTML = `<div class="eva title">${esc((it.name || "").toUpperCase())}</div><div class="meta">${esc(meta_)}</div>
                   <div class="desc">${esc(it.description || "")}</div><div class="cast">${esc(people).replace(/&lt;br&gt;/g, "<br>")}</div>
                   <div id="acts"></div><div id="eps"></div>`;
  const acts = $("#acts");
  const resume = (it.offset || 0) > 60000 && (it.progress || 0) < 0.95;
  if (it.type === "series") {
    const vids = (S.meta?.videos || []);
    const cur = vids.find(v => v.id === it.videoId);
    if (cur) { const b = el("button", "btn main", `CONTINUAR <small>T${cur.season} · E${cur.episode}</small>`); b.onclick = () => playFlow(cur.id, it.offset || 0, cur); acts.appendChild(b); }
    else if (vids[0]) { const b = el("button", "btn main", "EMPEZAR LA SERIE"); b.onclick = () => playFlow(vids[0].id, 0, vids[0]); acts.appendChild(b); }
    renderEpisodes(vids, cur, it);
  } else {
    if (resume) { const b = el("button", "btn main", `CONTINUAR <small>desde ${fmt((it.offset || 0) / 1000)}</small>`); b.onclick = () => playFlow(it.id, it.offset || 0); acts.appendChild(b); }
    const b = el("button", "btn" + (resume ? "" : " main"), resume ? "DESDE EL PRINCIPIO" : "REPRODUCIR"); b.onclick = () => playFlow(it.id, 0); acts.appendChild(b);
  }
  if (Cuenta.get()) {
    const two = el("div", "btns2");
    const inList = !!(S.lib && S.lib.list.find(x => x.id === it.id));
    const l = el("button", "btn", inList ? "QUITAR DE MI LISTA" : "AGREGAR A MI LISTA");
    l.onclick = async () => {
      vibe(); try { await myList(inList ? "remove" : "add", it.type, it.id, it.name); toast(inList ? "QUITADA DE MI LISTA" : "AGREGADA A MI LISTA");
        S.lib = await library(); renderInfo(); if (S.ch === "stremio" && S.tab === "home") loadRows(); } catch (e) { toast("NO SE PUDO: " + e.message); }
    };
    two.appendChild(l);
    if ((it.offset || 0) > 0) {
      const d = el("button", "btn", "QUITAR DE SEGUIR VIENDO");
      d.onclick = async () => { vibe(); try { await dismiss(it.id); toast("QUITADA DE SEGUIR VIENDO"); S.lib = await library(); renderInfo(); loadRows(); } catch (e) { toast("NO SE PUDO"); } };
      two.appendChild(d);
    }
    acts.appendChild(two);
  }
}
function renderEpisodes(vids, cur, it) {
  const box = $("#eps"); if (!vids.length) return;
  const seasons = [...new Set(vids.map(v => v.season))];
  S.season = S.season ?? (cur ? cur.season : seasons[0]);
  const sb = el("div", "seasons");
  for (const s of seasons) { const b = el("button", "chip" + (s === S.season ? " on" : ""), "TEMPORADA " + s); b.onclick = () => { S.season = s; box.innerHTML = ""; renderEpisodes(vids, cur, it); }; sb.appendChild(b); }
  box.appendChild(sb);
  for (const v of vids.filter(v => v.season === S.season)) {
    const e = el("button", "ep");
    e.innerHTML = `<div class="n">E${v.episode}</div><div class="x">${esc(v.name || "Episodio " + v.episode)}<div>${esc(v.overview || "")}</div></div>` +
                  (v.thumbnail ? `<img loading="lazy" src="${esc(v.thumbnail)}">` : "");
    e.onclick = () => playFlow(v.id, cur && cur.id === v.id ? (it.offset || 0) : 0, v);
    box.appendChild(e);
  }
}

// ── Elegir (idioma, subtítulos…) ───────────────────────────────────────────
let pickRes = null;
function pickCancel() { $("#pick").classList.add("hidden"); if (pickRes) { const r = pickRes; pickRes = null; r(null); } }
$("#pick").onclick = e => { if (e.target.id === "pick") pickCancel(); };
function pick(question, opts, note) {
  return new Promise(res => {
    pickRes = res;
    const box = $("#pickBox"); box.innerHTML = `<div class="q">${esc(question)}</div>` + (note ? `<div class="err">${esc(note)}</div>` : "");
    opts.forEach(o => {
      const b = el("button", "opt" + (o.def ? " def" : ""), `<span>${esc(o.label)}</span><small>${esc(o.small || "")}</small>`);
      b.onclick = () => { vibe(); pickRes = null; $("#pick").classList.add("hidden"); res(o); };
      box.appendChild(b);
    });
    const c = el("button", "opt", "<span>Cancelar</span>"); c.style.borderColor = "transparent"; c.onclick = pickCancel; box.appendChild(c);
    $("#pick").classList.remove("hidden");
  });
}
function busy(t) { $("#pickBox").innerHTML = `<div class="loading">${esc(t)}</div>`; $("#pick").classList.remove("hidden"); }

// ── Reproducir: idioma → subtítulos → reproductor ──────────────────────────
async function playFlow(videoId, startMs, ep) {
  const it = Object.assign({}, S.item, S.meta || {});
  if (!Cuenta.get()) { toast("CONECTÁ TU CUENTA DE STREMIO PARA VER"); openCfg(); return; }
  const epName = ep ? `T${ep.season} · E${ep.episode}  ${ep.name || ""}` : "";
  busy("BUSCANDO FUENTES EN TUS ADDONS…");
  let d;
  try { d = await streams(it.type, it.id, videoId); } catch (e) { $("#pick").classList.add("hidden"); toast("SIN SEÑAL"); return; }
  if ($("#pick").classList.contains("hidden")) return;     // canceló mientras buscaba
  $("#pick").classList.add("hidden");
  if (!d.options.length) { toast("NO HAY FUENTES PARA ESTE TÍTULO"); return; }
  const p = prefs();
  const defI = (p.prefAudio || "original") === "es" ? Math.max(0, d.options.findIndex(o => o.lang === "es-419")) : 0;
  const lang = await pick("¿EN QUÉ IDIOMA?", d.options.map((o, i) => {
    const s = o.streams[0]; return { label: o.label, small: s ? `${s.res}p · ${s.size || "?"} GB` : "", v: o, def: i === defI };
  }));
  if (!lang) return;
  const ps = p.prefSubs || "auto", isEs = (lang.v.lang || "").startsWith("es");
  const subDef = ps === "always" ? true : ps === "never" ? false : !isEs;
  const sb = await pick("¿SUBTÍTULOS EN ESPAÑOL?", [{ label: "Sí, en español", v: true, def: subDef }, { label: "No, sin subtítulos", v: false, def: !subDef }]);
  if (!sb) return;
  let subs = [];
  if (sb.v) { busy("BUSCANDO SUBTÍTULOS…"); subs = await subsEs(it.type, videoId, lang.v.streams[0].filename); $("#pick").classList.add("hidden"); }
  const dest = await chooseDest(); if (!dest) return;
  const c = chan();
  let cands = lang.v.streams;
  if (dest !== "phone") {
    // a la tele primero lo que el Chromecast reproduce seguro (H.264, sin DTS, mejor MP4)
    const pen = s => (s.av1 ? 6 : 0) + (s.audioBad ? 3 : 0) + (s.hevc ? 2 : 0) + (s.mkv ? 0.5 : 0) + (s.res > 1080 ? 2 : 0);
    cands = cands.map((s, i) => [s, i]).sort((a, b) => pen(a[0]) - pen(b[0]) || a[1] - b[1]).map(x => x[0]);
  }
  const job = {
    title: it.name, sub: (epName ? epName + "  ·  " : "") + lang.v.label.toUpperCase(), image: it.background || it.poster || "",
    item: { id: it.id, type: it.type, name: it.name }, videoId, start: (startMs || 0) / 1000,
    candidates: cands.map(s => ({ hash: s.hash, fileIdx: s.fileIdx, url: s.url, sources: s.sources, res: s.res, title: s.title })),
    subs, wantSubs: sb.v, theme: { hi: c.hi, warn: c.warn },
  };
  if (dest === "phone") N.play(JSON.stringify(job));
  else { N.castPlay(dest, JSON.stringify(job)); openRemote(); }
}

// ── ¿En el celular o en la tele? ───────────────────────────────────────────
function teles() { try { return JSON.parse(N.teles()); } catch (e) { return []; } }
async function chooseDest() {
  const ts = teles(), d = prefs().dest || "ask";
  if (!ts.length || d === "phone") return "phone";
  if (d === "tv" && ts.length === 1) return ts[0].id;
  const o = await pick("¿DÓNDE LO VES?", [{ label: "En el celular", small: "ESTA PANTALLA", v: "phone", def: d !== "tv" }]
    .concat(ts.map((t, i) => ({ label: "En la tele · " + t.name, small: "CHROMECAST", v: t.id, def: d === "tv" && i === 0 }))));
  return o ? o.v : null;
}

// ── Control remoto de la tele ──────────────────────────────────────────────
function openRemote() { $("#remote").classList.add("open"); if (!stack.includes("remote")) push("remote"); poll(); }
$("#rClose").onclick = () => close("remote");
function cmd(c) { vibe(); N.castCmd(c); setTimeout(poll, 300); }
document.querySelectorAll("[data-c]").forEach(b => b.onclick = () => cmd(b.dataset.c));
$("#nPP").onclick = e => { e.stopPropagation(); cmd("pause"); };
$("#now").onclick = () => openRemote();
$("#exitBtn").onclick = async () => {
  const o = await pick("¿CORTAR LA PELÍCULA?", [{ label: "Sí, cortar", small: "SE GUARDA DÓNDE QUEDASTE", v: true }]);
  if (o) { cmd("stop"); close("remote"); }
};
(() => {
  const bar = $("#bar"); let drag = false;
  const at = e => { const r = bar.querySelector(".track").getBoundingClientRect(); return Math.min(1, Math.max(0, ((e.touches?.[0] || e).clientX - r.left) / r.width)); };
  const show = k => { $("#fill").style.width = k * 100 + "%"; $("#knob").style.left = k * 100 + "%"; $("#tPos").textContent = fmt(k * (S.now?.dur || 0)); };
  bar.addEventListener("pointerdown", e => { drag = true; bar.setPointerCapture(e.pointerId); show(at(e)); });
  bar.addEventListener("pointermove", e => { if (drag) show(at(e)); });
  bar.addEventListener("pointerup", e => { if (!drag) return; drag = false; const dur = S.now?.dur || 0; if (dur) cmd("seekto " + Math.round(at(e) * dur)); });
  bar.dragging = () => drag;
})();
let pollT = null;
function poll() {
  clearTimeout(pollT);
  let n = null; try { n = JSON.parse(N.castState()); } catch (e) {}
  S.now = n;
  const open = $("#remote").classList.contains("open");
  if (n && n.active) {
    $("#rBg").style.backgroundImage = n.image ? `url("${n.image}")` : "";
    $("#rTitle").textContent = (n.title || "").toUpperCase();
    $("#rEp").textContent = n.sub || "";
    $("#rWhere").innerHTML = `<span class="live"></span> EN LA TELE · ${esc((n.device || "").toUpperCase())}`;
    $("#rMsg").textContent = n.msg ? n.msg + (n.peers != null && !n.loaded ? `  ·  ${n.peers} PERSONAS · ${n.kbps} KB/S` : "") : n.pause ? "EN PAUSA" : "";
    const dur = n.dur || 0, pos = n.pos || 0;
    if (!$("#bar").dragging()) {
      const k = dur ? pos / dur : 0;
      $("#fill").style.width = k * 100 + "%"; $("#knob").style.left = k * 100 + "%";
      $("#tPos").textContent = fmt(pos); $("#tLeft").textContent = "-" + fmt(dur - pos);
    }
    $("#volLine").textContent = n.volume >= 0 ? "VOLUMEN " + n.volume + "%" : "";
    $("#ppBtn").textContent = n.pause ? "▶" : "❚❚"; $("#nPP").textContent = n.pause ? "▶" : "❚❚";
    $("#subBtn").classList.toggle("on", !!n.subs);
    $("#nTh").style.backgroundImage = n.image ? `url("${n.image}")` : "";
    $("#nTitle").textContent = n.title || "En la tele";
    $("#nSub").textContent = "EN LA TELE · " + (n.loaded ? fmt(pos) + " / " + fmt(dur) : "SINTONIZANDO");
    $("#now").classList.toggle("hidden", open);
  } else {
    $("#now").classList.add("hidden");
    if (open) $("#rMsg").textContent = "NO HAY NADA EN LA TELE";
  }
  pollT = setTimeout(poll, open ? 1000 : 4000);
}
document.addEventListener("visibilitychange", () => { if (!document.hidden) poll(); });

// Lo que devuelve el reproductor (al salir o, si se cerró la app, al volver a abrirla)
window.__ended = async raw => {
  let r; try { r = JSON.parse(raw); } catch (e) { return; }
  const it = r.item || {};
  if (!it.id) return;
  const watched = r.pos - (r.start || 0);
  if (r.dur > 0 && (r.finished || watched >= 60)) {
    try { await progress(it.type, it.id, r.videoId || it.id, Math.round(r.pos * 1000), Math.round(r.dur * 1000), !!r.finished); } catch (e) {}
  }
  if (r.close && S.ch === "stremio" && S.tab === "home") { S.lib = await library().catch(() => S.lib); loadRows(); }
  if (S.item && S.item.id === it.id && $("#sheet").classList.contains("open")) renderInfo();
  if (r.close && r.finished && it.type === "movie" && Letterboxd.logged() && String(it.id).startsWith("tt")) openReview(it);
};

// ── Configuración ──────────────────────────────────────────────────────────
$("#cfgBtn").onclick = () => { vibe(); openCfg(); };
$("#cfgClose").onclick = () => close("cfg");
let lbUser = localStorage.lbUser || "";
function openCfg() { renderCfg(); $("#cfg").classList.add("open"); $("#cfg").scrollTop = 0; if (!stack.includes("cfg")) push("cfg"); }
function renderCfg(err) {
  const box = $("#cfgBox"), s = Cuenta.get(), p = prefs();
  box.innerHTML = `<div class="eva" style="font-size:44px;color:var(--hi)">CONFIGURACIÓN</div>`;
  box.appendChild(el("h2", "", "STREMIO · PELÍCULAS Y SERIES"));
  if (s) {
    box.appendChild(el("div", "who", `Conectada: <b>${esc(s.email)}</b>`));
    box.appendChild(el("div", "note", "Tus addons, tu lista y dónde quedaste salen de tu cuenta de Stremio (los mismos que en la PC)."));
    const b = el("button", "btn", "CERRAR SESIÓN"); b.onclick = async () => { await logout(); S.lib = null; renderCfg(); loadRows(); }; box.appendChild(b);
  } else {
    box.appendChild(el("div", "note", "Con tu cuenta vienen tus addons (las fuentes para ver), tu lista y dónde quedaste."));
    const m = el("input", "field"); m.type = "email"; m.placeholder = "Mail de Stremio"; m.autocomplete = "email";
    const pw = el("input", "field"); pw.type = "password"; pw.placeholder = "Contraseña";
    const b = el("button", "btn main", "CONECTAR");
    b.onclick = async () => {
      b.textContent = "CONECTANDO…";
      try { await login(m.value.trim(), pw.value); toast("STREMIO CONECTADO"); renderCfg(); loadRows(); }
      catch (e) { renderCfg(e.message); }
    };
    box.append(m, pw, b);
    if (err) box.appendChild(el("div", "err", esc(err)));
  }
  box.appendChild(el("h2", "", "LETTERBOXD"));
  if (Letterboxd.logged()) {
    box.appendChild(el("div", "who", lbUser ? `Conectado: <b>${esc(lbUser)}</b>` : "Conectado"));
    box.appendChild(el("div", "note", "Al terminar una película te ofrezco dejar la reseña (siempre te pregunto antes de publicar)."));
    const b = el("button", "btn", "CERRAR SESIÓN"); b.onclick = () => { N.lbLogout(); lbUser = ""; localStorage.removeItem("lbUser"); renderCfg(); }; box.appendChild(b);
  } else {
    box.appendChild(el("div", "note", "Se abre la página de Letterboxd para entrar. Después, al terminar una película, podés dejar la reseña."));
    const b = el("button", "btn main", "CONECTAR LETTERBOXD"); b.onclick = () => N.lbLogin(); box.appendChild(b);
  }
  box.appendChild(el("h2", "", "IDIOMA DEL AUDIO"));
  box.appendChild(seg([["original", "ORIGINAL"], ["es", "ESPAÑOL LATINO"]], p.prefAudio || "original", v => { setPref("prefAudio", v); renderCfg(); }));
  box.appendChild(el("h2", "", "SUBTÍTULOS EN ESPAÑOL"));
  box.appendChild(seg([["auto", "SI NO ES EN ESPAÑOL"], ["always", "SIEMPRE"], ["never", "NUNCA"]], p.prefSubs || "auto", v => { setPref("prefSubs", v); renderCfg(); }));
  box.appendChild(el("h2", "", "DÓNDE VER"));
  box.appendChild(seg([["ask", "PREGUNTAR"], ["phone", "SIEMPRE EN EL CELULAR"], ["tv", "EN LA TELE"]], p.dest || "ask", v => { setPref("dest", v); renderCfg(); }));
  box.appendChild(el("div", "note", "La tele es un Chromecast en el mismo wifi. Mientras mirás en la tele, el celular baja la película y se la pasa: podés bloquearlo o usar otras apps (queda un aviso fijo de SINTONÍA para que Android no lo corte)."));
  box.appendChild(el("h2", "", "AL ABRIR"));
  box.appendChild(seg([["full", "TELE QUE SE ENCIENDE"], ["quick", "DIRECTO"]], p.intro || "full", v => { setPref("intro", v); renderCfg(); }));
  box.appendChild(el("div", "note", "SINTONÍA 同調 · versión para el celular"));
}
function seg(opts, cur, on) {
  const s = el("div", "seg");
  for (const [v, l] of opts) { const b = el("button", "chip" + (v === cur ? " on" : ""), l); b.onclick = () => { vibe(); on(v); }; s.appendChild(b); }
  return s;
}
window.__lb = async ok => {
  if (!ok) { renderCfg(); return; }
  toast("LETTERBOXD CONECTADO");
  try { lbUser = await Letterboxd.user(); localStorage.lbUser = lbUser; } catch (e) {}
  renderCfg();
};

// ── Reseña al terminar una película ────────────────────────────────────────
$("#rvClose").onclick = () => close("review");
function openReview(it) {
  const st = { stars: 0, like: false, spoilers: false, text: "", rewatch: !!(libOf(it.id) || {}).watched };
  const box = $("#rvBox");
  const render = () => {
    box.innerHTML = `<div class="mono" style="color:var(--dim);font-size:12px">LETTERBOXD${lbUser ? " · " + esc(lbUser.toUpperCase()) : ""}</div>
      <div class="eva" style="font-size:40px;color:var(--hi);white-space:normal;max-width:125%">${esc((it.name || "").toUpperCase())}</div>
      <div class="note">¿Qué te pareció? Tocá dos veces una estrella para media.</div>`;
    const stars = el("div", "stars");
    for (let i = 1; i <= 5; i++) {
      const full = st.stars >= i * 2, half = st.stars === i * 2 - 1;
      const b = el("button", full ? "on" : half ? "half" : "", "★");
      b.onclick = () => { vibe(); st.stars = st.stars === i * 2 ? i * 2 - 1 : st.stars === i * 2 - 1 ? 0 : i * 2; render(); };
      stars.appendChild(b);
    }
    box.appendChild(stars);
    const t = el("textarea", "field"); t.placeholder = "Tu reseña (opcional)"; t.value = st.text; t.oninput = () => st.text = t.value; box.appendChild(t);
    const tg = el("div", "toggles");
    const tog = (k, l) => { const b = el("button", "chip" + (st[k] ? " on" : ""), l); b.onclick = () => { st[k] = !st[k]; vibe(); render(); }; tg.appendChild(b); };
    tog("like", "♥ ME GUSTÓ"); tog("rewatch", "LA VOLVÍ A VER"); tog("spoilers", "TIENE SPOILERS");
    box.appendChild(tg);
    const pub = el("button", "btn main", "PUBLICAR");
    pub.onclick = async () => {
      const o = await pick("¿PUBLICAR EN LETTERBOXD?", [{ label: "Sí, publicar", small: "QUEDA EN TU PERFIL, CON FECHA DE HOY", v: true }]);
      if (!o) return;
      pub.textContent = "PUBLICANDO…";
      try { await Letterboxd.log(it.id, st.stars, st.like, st.rewatch, st.spoilers, st.text); toast("PUBLICADA EN LETTERBOXD"); close("review"); }
      catch (e) { pub.textContent = "PUBLICAR"; toast("NO SE PUDO: " + e.message); }
    };
    const no = el("button", "btn", "AHORA NO"); no.onclick = () => close("review");
    box.append(pub, no);
  };
  render();
  $("#review").classList.add("open"); $("#review").scrollTop = 0; push("review");
}

// ── Arranque ───────────────────────────────────────────────────────────────
(async () => {
  S.ch = CHANNELS.some(c => c.id === localStorage.ch) ? localStorage.ch : "stremio";
  theme(); renderChips(); renderTabs();
  const full = (prefs().intro || "full") === "full";
  if (!full) $("#intro").className = "hidden";
  const intro = full ? encender() : staticFor(300, 0.7);
  loadRows();
  await intro;
  window.__ready = true;
  poll();
})();
