// ─────────────────────────────────────────────────────────────────────────────
//  rice-cine — "modo cine": un televisor que sintoniza canales. Cada
//  plataforma es un canal con su color de fósforo (el shader CRT se tiñe con
//  cinefx.frag, sobre el fondo; el filtro global de Hyprland se apaga con
//  riceCine() mientras está abierto, así las portadas se ven tal cual);
//  cambiar de canal = estática + sintonía.
//  Películas y series con los datos de tu cuenta de Stremio, en carruseles
//  grandes (tipo Netflix) para verlos de lejos, y títulos con tipografía de
//  placa de Evangelion.
//
//  · INICIO: seguir viendo, mi lista, populares (películas y series), ver de nuevo.
//  · PELÍCULAS / SERIES: populares y una fila por género del canal elegido
//    (Stremio = Cinemeta, Netflix/Disney+/Max/Prime = addon Streaming Catalogs).
//  · Elegir un título abre abajo el menú (REPRODUCIR, EPISODIOS, MI LISTA).
//    Etapa 1: reproducir abre la ficha en la app de Stremio.
//
//  Control (pad.py del modo consola), teclado y mouse:
//    cruceta/stick/flechas/WASD  mover        A/Enter/clic   elegir
//    B/Esc/clic derecho     volver       LB RB / Q E    sección
//    Y / P                  guía de canales   LT RT / 1-5   canal
//    X, Ctrl+F o "/"        buscar
//    Super+M, botón de la Waybar o VIEW en el modo consola: abrir/cerrar
//
//  Datos: ~/.config/rice-cine/stremio.py
//  IPC:   qs -c rice-cine ipc call cine toggle
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import QtQuick.Effects
import QtQuick.Window
import Quickshell
import Quickshell.Io
import Sintonia

Item {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string cfg:  App.backendDir             // scripts de datos (backend/)
    readonly property string userCfg: App.configDir            // settings.json del usuario
    readonly property string runtime: App.runtimeDir
    readonly property string mono: "DepartureMono Nerd Font"     // rótulos técnicos (canal, hora)
    readonly property string sans: "Noto Sans CJK JP"            // textos para leer

    // ── Canales: cada plataforma con su fósforo ────────────────────────────
    readonly property var platforms: [
        { id: "stremio", ramp: [Qt.rgba(0.026, 0.008, 0.042, 1), Qt.rgba(0.88, 0.76, 1.0, 1)], ch: "01", name: "STREMIO",     kana: "初号機", tint: "purple",
          colors: { bg: "#07020c", deep: "#14072a", line: "#3d2260", dim: "#9a74c8", fg: "#e2ceff", hi: "#f6eeff", warn: "#ff8a3d", glow: Qt.rgba(0.72, 0.45, 1.0, 0.6) } },
        { id: "netflix", ramp: [Qt.rgba(0.055, 0.003, 0.003, 1), Qt.rgba(1.0, 0.30, 0.26, 1)], ch: "02", name: "NETFLIX",     kana: "赤",     tint: "red",
          colors: { bg: "#0b0202", deep: "#200606", line: "#5a1616", dim: "#c0605a", fg: "#ffd0ca", hi: "#fff2ee", warn: "#ffd25a", glow: Qt.rgba(1.0, 0.3, 0.25, 0.6) } },
        { id: "disney", ramp: [Qt.rgba(0.006, 0.016, 0.042, 1), Qt.rgba(0.74, 0.87, 1.0, 1)],  ch: "03", name: "DISNEY+",     kana: "零号機", tint: "blue",
          colors: { bg: "#02060d", deep: "#07152c", line: "#1d3a66", dim: "#6b9ad2", fg: "#cde1ff", hi: "#f0f6ff", warn: "#ffb35a", glow: Qt.rgba(0.4, 0.65, 1.0, 0.6) } },
        { id: "max", ramp: [Qt.rgba(0.020, 0.020, 0.022, 1), Qt.rgba(0.96, 0.96, 0.93, 1)],     ch: "04", name: "MAX",         kana: "白",     tint: "white",
          colors: { bg: "#050505", deep: "#141416", line: "#3a3a3e", dim: "#9a9aa0", fg: "#ececE8", hi: "#ffffff", warn: "#ff6a5a", glow: Qt.rgba(1.0, 1.0, 1.0, 0.5) } },
        { id: "prime", ramp: [Qt.rgba(0.004, 0.032, 0.036, 1), Qt.rgba(0.72, 1.0, 0.98, 1)],   ch: "05", name: "PRIME VIDEO", kana: "青",     tint: "cyan",
          colors: { bg: "#010a0b", deep: "#051d20", line: "#145055", dim: "#5bbcc0", fg: "#c8f9f5", hi: "#effffd", warn: "#ffb35a", glow: Qt.rgba(0.35, 1.0, 0.95, 0.55) } },
        { id: "crunchyroll", ramp: [Qt.rgba(0.052, 0.012, 0.000, 1), Qt.rgba(1.0, 0.58, 0.22, 1)], ch: "06", name: "CRUNCHYROLL", kana: "アニメ", tint: "orange",
          colors: { bg: "#0c0601", deep: "#241204", line: "#6a3410", dim: "#d08a4a", fg: "#ffdcbc", hi: "#fff3e8", warn: "#ff5a8a", glow: Qt.rgba(1.0, 0.6, 0.25, 0.6) } }
    ]
    property string platform: "stremio"
    readonly property var plat: platforms.find(p => p.id === platform) ?? platforms[0]
    readonly property var theme: Object.assign({ font: mono }, plat.colors)

    // ── Estado ──────────────────────────────────────────────────────────────
    property bool   open: false
    property bool   shown: false
    property bool   fromConsole: false          // se entró desde el modo consola: al salir, vuelve ahí
    property string tab: "home"                 // home | movie | series
    property int    rowIndex: 0
    property string focusRowId: ""
    property var    colMap: ({})                // fila → tarjeta elegida (cada fila recuerda la suya)
    property bool   sheetOpen: false
    property int    sheetIndex: 0
    property bool   pickerOpen: false            // guía de canales
    property int    pickerIndex: 0
    property bool   epOpen: false                // episodios de una serie
    property var    epShow: null
    property int    epSeason: 1
    property int    epIndex: 0
    property string toast: ""
    property string padName: ""
    property string loginError: ""
    property bool   touched: false

    readonly property var tabs: [["home", "INICIO"], ["movie", "PELÍCULAS"], ["series", "SERIES"], ["letterboxd", "LETTERBOXD"]]
    readonly property var genreRows: [["Action", "ACCIÓN"], ["Comedy", "COMEDIA"], ["Drama", "DRAMA"],
                                      ["Thriller", "SUSPENSO"], ["Horror", "TERROR"], ["Sci-Fi", "CIENCIA FICCIÓN"],
                                      ["Animation", "ANIMACIÓN"], ["Romance", "ROMANCE"], ["Crime", "POLICIALES"],
                                      ["Documentary", "DOCUMENTALES"]]
    readonly property var genreEs: ({ Action: "Acción", Adventure: "Aventura", Animation: "Animación", Biography: "Biografía",
        Comedy: "Comedia", Crime: "Policial", Documentary: "Documental", Drama: "Drama", Family: "Familiar",
        Fantasy: "Fantasía", History: "Historia", Horror: "Terror", Music: "Música", Musical: "Musical",
        Mystery: "Misterio", Romance: "Romance", "Sci-Fi": "Ciencia ficción", Sport: "Deporte", Thriller: "Suspenso",
        War: "Bélica", Western: "Western", "Reality-TV": "Reality", "Talk-Show": "Talk show", "Game-Show": "Concurso",
        News: "Noticias", Short: "Corto" })

    // ── Watchlist de Letterboxd (pestaña LETTERBOXD, LbLayer.qml) ──────────
    //  La arma letterboxd-sync.py (cada 15 min y al abrir el cine), en el orden
    //  de Letterboxd: la que agregaste último primero.
    property var  lbItems: []
    property int  lbIndex: 0
    property bool lbLoaded: false
    FileView {
        path: root.stateDir + "/letterboxd-watchlist.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const cur = root.lbItems[root.lbIndex]?.id;
                root.lbItems = JSON.parse(text()).items ?? [];
                root.lbLoaded = true;
                const i = root.lbItems.findIndex(x => x.id === cur);   // quedarse en la misma
                root.lbIndex = i >= 0 ? i : Math.min(root.lbIndex, Math.max(0, root.lbItems.length - 1));
            } catch (e) {}
        }
    }
    function lbNav(dir) {
        const n = lbItems.length, cols = lbLayer.cols, c = lbIndex % cols;
        if (n === 0) { bump(dir); return; }
        if (dir === "left")  { if (c > 0) lbIndex--; else bump(dir); }
        if (dir === "right") { if (c < cols - 1 && lbIndex < n - 1) lbIndex++; else bump(dir); }
        if (dir === "up")    { if (lbIndex >= cols) lbIndex -= cols; else bump(dir); }
        if (dir === "down")  { if (lbIndex + cols < n) lbIndex += cols; else if (Math.floor(lbIndex / cols) < Math.floor((n - 1) / cols)) lbIndex = n - 1; else bump(dir); }
    }

    // ── Biblioteca (cuenta de Stremio) ─────────────────────────────────────
    property var library: ({ "continue": [], again: [], list: [] })
    readonly property var listIds: library.list.map(x => x.id)
    Process {
        id: libProc
        command: [root.cfg + "/stremio.py", "library"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null; try { d = JSON.parse(text); } catch (e) {}
                if (!d || d.error) {
                    root.loginError = d?.error === "nologin" ? "Sin cuenta de Stremio: conectala en CONFIGURACIÓN → CUENTAS (tecla coma o ≡)"
                                    : "Sin conexión con Stremio";
                    return;
                }
                root.loginError = "";
                root.library = { "continue": d["continue"], again: d.again, list: d.list };
                // parecidas listas de antemano para Seguir viendo y Mi lista (en segundo plano, de a una)
                const warm = d["continue"].concat(d.list).filter(x => (x.id ?? "").startsWith("tt")).map(x => (x.type === "series" ? "series" : "movie") + ":" + x.id);
                if (warm.length) Quickshell.execDetached([root.cfg + "/about.py", "warm"].concat(warm));
                // recién abierto y sin tocar nada: arrancar en la primera fila
                if (!root.touched) { root.rowIndex = 0; root.focusRowId = root.rows[0]?.id ?? ""; }
            }
        }
    }

    // ── Foto de lo último que se vio (arranque al instante) ────────────────
    //  Al abrir se muestra lo de la última vez y, cuando Stremio termina de
    //  sincronizar, se reemplaza solo. Lo cargado de la foto queda "stale".
    property bool snapLoaded: false
    FileView {
        id: snapFile
        path: (Quickshell.env("XDG_CACHE_HOME") || root.home + "/.cache") + "/rice-cine/ui-snapshot.json"
        printErrors: false
        onLoaded: {
            if (root.snapLoaded) return;
            root.snapLoaded = true;
            try {
                const d = JSON.parse(text());
                if (d.library && !root.library["continue"].length && !root.library.list.length) root.library = d.library;
                const c = Object.assign({}, root.srcCache);
                for (const k in (d.src ?? {})) if (!c[k]) c[k] = { items: d.src[k], done: false, stale: true };
                root.srcCache = c;
                root.ensureSources();
            } catch (e) {}
        }
        onLoadFailed: root.snapLoaded = true
    }
    Timer { id: snapSave; interval: 4000; onTriggered: root.saveSnapshot() }
    onLibraryChanged: if (snapLoaded) snapSave.restart()
    onSrcCacheChanged: if (snapLoaded) snapSave.restart()
    function saveSnapshot() {
        const src = {};
        for (const k in srcCache) if (srcCache[k].items?.length) src[k] = srcCache[k].items.slice(0, 120);
        Quickshell.execDetached(["mkdir", "-p", (Quickshell.env("XDG_CACHE_HOME") || home + "/.cache") + "/rice-cine"]);
        snapFile.setText(JSON.stringify({ library: library, src: src }));
    }

    // ── Catálogos ───────────────────────────────────────────────────────────
    //  Fuente = "canal|tipo|género". Stremio filtra el género en el servidor;
    //  el addon de plataformas no: se traen ~300 títulos y se filtra acá.
    property var srcCache: ({})                 // clave → { items, done }
    property var srcQueue: []
    Process {
        id: srcProc
        property string key: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null; try { d = JSON.parse(text); } catch (e) {}
                const key = srcProc.key;
                let old = root.srcCache[key] ?? { items: [], done: false };
                if (old.stale) {
                    if (!d || d.error || !(d.metas ?? []).length) return;     // sin conexión: queda la foto
                    old = { items: [], done: false };
                }
                const ids = new Set(old.items.map(x => x.id));
                const fresh = (d?.metas ?? []).filter(x => !ids.has(x.id));
                const c = Object.assign({}, root.srcCache);      // objeto nuevo: si no, QML no avisa
                c[key] = { items: old.items.concat(fresh), done: !d || !!d.error || fresh.length === 0 };
                root.srcCache = c;
                // plataformas: juntar unas páginas para que las filas por género tengan con qué
                const parts = key.split("|");
                if (["netflix", "disney", "max", "prime", "crunchyroll"].includes(parts[0]) && parts[2] === "" && !c[key].done && c[key].items.length < 300)
                    root.srcQueue = root.srcQueue.concat([key]);
            }
        }
        onExited: Qt.callLater(root.pumpSrc)
    }
    function srcKey(type, genre) { return platform + "|" + type + "|" + (platform === "stremio" ? (genre || "") : ""); }
    function keyOf(source, type, genre) { return source + "|" + type + "|" + (genre || ""); }
    function requestSrc(key, more) {
        const e = srcCache[key];
        if (e && !e.stale && (e.done || !more)) return;
        if ((srcProc.running && srcProc.key === key) || srcQueue.includes(key)) return;
        srcQueue = srcQueue.concat([key]);
        pumpSrc();
    }
    function pumpSrc() {
        if (srcProc.running || srcQueue.length === 0) return;
        const key = srcQueue[0];
        srcQueue = srcQueue.slice(1);
        let e = srcCache[key];
        if (e?.stale) e = null;                      // de la foto: pedir de cero (lo viejo se ve mientras)
        if (e?.done) { pumpSrc(); return; }
        const parts = key.split("|");
        srcProc.key = key;
        srcProc.command = [cfg + "/stremio.py", "catalog", parts[0], parts[1], String(e ? e.items.length : 0), parts[2]];
        srcProc.running = true;
    }
    // ── Carruseles de cada canal ───────────────────────────────────────────
    readonly property int thisYear: new Date().getFullYear()
    // un año distinto cada día para "UN VIAJE A…"
    readonly property int throwback: 1975 + Math.floor(Date.now() / 86400000) % 40
    // Stremio: [id, título, fuente, tipo, género/año]
    readonly property var stremioHome: [
        ["top10-movie", "TOP 10 EN EL MUNDO · PELÍCULAS", "top10", "movie", ""],
        ["top10-series", "TOP 10 EN EL MUNDO · SERIES", "top10", "series", ""],
        ["pop-movie", "PELÍCULAS POPULARES", "stremio", "movie", ""],
        ["new-movie", "ESTRENOS", "stremio-new", "movie", String(thisYear)],
        ["pop-series", "SERIES POPULARES", "stremio", "series", ""],
        ["new-series", "SERIES NUEVAS", "stremio-new", "series", String(thisYear)],
        ["best-movie", "DESTACADAS", "stremio-best", "movie", ""],
        ["comedy", "PARA REÍRSE", "stremio", "movie", "Comedy"],
        ["horror", "PARA NO DORMIR", "stremio", "movie", "Horror"],
        ["action", "ADRENALINA", "stremio", "movie", "Action"],
        ["scifi", "OTROS MUNDOS", "stremio", "movie", "Sci-Fi"],
        ["crime-series", "SERIES DE CRIMEN Y MISTERIO", "stremio", "series", "Crime"],
        ["animation", "ANIMACIÓN", "stremio", "movie", "Animation"],
        ["throwback", "UN VIAJE A " + throwback, "stremio-new", "movie", String(throwback)],
        ["docs", "HISTORIAS REALES", "stremio", "movie", "Documentary"],
        ["romance", "PARA ENAMORARSE", "stremio", "movie", "Romance"]
    ]
    // Plataformas: [géneros, título] (sale de su catálogo)
    readonly property var platGenres: [[["Comedy"], "PARA REÍRSE"], [["Horror"], "PARA NO DORMIR"], [["Action"], "ADRENALINA"],
        [["Drama"], "DRAMAS"], [["Sci-Fi", "Fantasy"], "OTROS MUNDOS"], [["Crime", "Mystery"], "CRIMEN Y MISTERIO"],
        [["Family", "Animation"], "EN FAMILIA"], [["Documentary", "Biography"], "HISTORIAS REALES"], [["Romance"], "PARA ENAMORARSE"]]
    readonly property var animeGenres: [[["Action"], "PELEAS ÉPICAS"], [["Fantasy", "Adventure"], "MUNDOS FANTÁSTICOS"],
        [["Romance"], "ROMANCE"], [["Comedy"], "PARA REÍRSE"], [["Drama"], "DRAMA"], [["Sci-Fi"], "CIENCIA FICCIÓN"],
        [["Mystery", "Horror", "Thriller"], "MISTERIO Y TERROR"]]
    function ensureSources() {
        let keys = [];
        if (platform === "stremio") {
            const list = tab === "home" ? stremioHome
                : [["pop", "", "stremio", tab, ""]].concat(genreRows.map(g => ["g-" + g[0], g[1], "stremio", tab, g[0]]));
            keys = list.map(r => keyOf(r[2], r[3], r[4]));
        } else if (!plat.external) {
            keys = [keyOf(platform, "movie", ""), keyOf(platform, "series", "")];
        }
        batchFetch(keys.filter(k => !srcCache[k] || srcCache[k].stale));
    }
    // Los catálogos que faltan, en un pedido (stremio.py catalogs, en paralelo
    // adentro). Cada pedido es un proceso propio: cambiar de canal no espera a
    // que termine lo que pidió el canal anterior.
    property var batchInFlight: ({})            // clave → true mientras se pide
    function batchFetch(keys) {
        keys = keys.filter(k => !batchInFlight[k]);
        if (!keys.length) return;
        const f = Object.assign({}, batchInFlight);
        for (const k of keys) f[k] = true;
        batchInFlight = f;
        batchComp.createObject(root, { keys: keys });
    }
    Component {
        id: batchComp
        Process {
            id: bp
            property var keys: []
            command: [root.cfg + "/stremio.py", "catalogs"].concat(keys)
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    let d = null; try { d = JSON.parse(text); } catch (e) {}
                    const c = Object.assign({}, root.srcCache);
                    for (const k of bp.keys) {
                        const items = d?.[k] ?? [];
                        const src = k.split("|")[0];
                        if (!items.length && c[k]?.stale) continue;        // sin conexión: queda la foto
                        // las de Stremio se pueden seguir paginando (srcProc); el resto vino completo
                        c[k] = { items: items, done: !items.length || !src.startsWith("stremio") };
                    }
                    root.srcCache = c;
                }
            }
            onExited: {
                const f = Object.assign({}, root.batchInFlight);
                for (const k of bp.keys) delete f[k];
                root.batchInFlight = f;
                bp.destroy(1000);
            }
        }
    }
    onTabChanged: ensureSources()
    onPlatformChanged: ensureSources()

    // Búsqueda (en todo el catálogo de Stremio, películas y series)
    property string query: ""
    property bool searchActive: false
    property var searchItems: []
    property bool searching: false
    Timer { id: searchDebounce; interval: 380; onTriggered: root.runSearch() }
    Process {
        id: searchProc
        property string q: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null; try { d = JSON.parse(text); } catch (e) {}
                if (searchProc.q === root.query) { root.searchItems = d?.metas ?? []; root.searching = false; }
                else Qt.callLater(root.runSearch);
            }
        }
    }
    function runSearch() {
        if (query.trim() === "" || tab === "letterboxd") { searchItems = []; searching = false; return; }
        if (searchProc.running) return;            // al terminar vuelve a buscar con lo último
        searching = true;
        searchProc.q = query;
        searchProc.command = [cfg + "/stremio.py", "search", query.trim()];
        searchProc.running = true;
    }

    // ── Filas ───────────────────────────────────────────────────────────────
    function srcItems(key) { const e = srcCache[key]; return e ? e.items : null; }   // null = cargando
    function mk(id, title, items, extra) {
        return Object.assign({ id: id, title: title, items: items ?? [], loading: items === null, key: "", moreKey: "" }, extra || {});
    }
    function hasGenre(x, gs) { return (x.genres ?? []).some(g => gs.includes(g)); }
    function yearOf(x) { return parseInt(String(x.year || "0")) || 0; }
    function interleave(a, b) {
        const out = [];
        for (let i = 0; i < Math.max(a.length, b.length); i++) { if (i < a.length) out.push(a[i]); if (i < b.length) out.push(b[i]); }
        return out;
    }
    // ¿Este título va en "seguir viendo"/"mi lista" de este canal? Lo empezaste
    // o agregaste desde ahí, está en su catálogo, o (Crunchyroll) es anime.
    property var origin: ({})                   // id → canal (state/origin.json)
    readonly property string stateDir: App.stateDir
    FileView {
        path: root.stateDir + "/origin.json"
        printErrors: false
        onLoaded: { try { root.origin = JSON.parse(text()); } catch (e) {} }
    }
    function setOrigin(id) {
        if (platform === "stremio" || plat.external || origin[id] === platform) return;
        const o = Object.assign({}, origin); o[id] = platform; origin = o;
        App.writeFile(stateDir + "/origin.json", JSON.stringify(o));
    }
    // anime = animación cuyo PRIMER país es Japón (Pixar/Disney también traen "Japan" en la lista)
    function isAnime(x) { return hasGenre(x, ["Animation"]) && String(x.country ?? "").split(",")[0].trim() === "Japan"; }
    readonly property var catIds: {
        const ids = {};
        for (const t of ["movie", "series"]) for (const x of srcItems(keyOf(platform, t, "")) ?? []) ids[x.id] = true;
        return ids;
    }
    function belongs(x) {
        if (platform === "stremio") return true;
        if (origin[x.id] === platform || catIds[x.id]) return true;
        return platform === "crunchyroll" && isAnime(x);
    }
    function platformRows() {
        const M = srcItems(keyOf(platform, "movie", "")), S = srcItems(keyOf(platform, "series", ""));
        const anime = platform === "crunchyroll";
        if (!M || !S) return [mk("top", "TOP 10 EN " + plat.name, null)];
        const both = interleave(M, S);
        const R = [mk("top", anime ? "TOP 10 ANIME" : "TOP 10 EN " + plat.name, both.slice(0, 10)),
                   mk("pop-series", anime ? "ANIME POPULAR" : "SERIES POPULARES", S),
                   mk("pop-movie", anime ? "PELÍCULAS DE ANIME" : "PELÍCULAS POPULARES", M),
                   mk("new", "ESTRENOS", both.filter(x => yearOf(x) >= thisYear - 1).sort((a, b) => yearOf(b) - yearOf(a))),
                   mk("best", "LAS MEJOR PUNTUADAS", both.filter(x => parseFloat(x.rating) >= 7.3)
                                                        .sort((a, b) => parseFloat(b.rating) - parseFloat(a.rating)))];
        for (const g of (anime ? animeGenres : platGenres)) R.push(mk("g-" + g[0].join("-"), g[1], both.filter(x => hasGenre(x, g[0]))));
        return R;
    }
    readonly property var rows: {
        const R = [];
        const add = (r, min) => { if (r.loading || r.items.length >= (min ?? 1)) R.push(r); };
        if (plat.external) return R;
        if (tab === "letterboxd") return R;          // la grilla la dibuja LbLayer
        const own = l => l.filter(x => belongs(x));
        if (tab === "home") {
            add(mk("continue", "SEGUIR VIENDO", own(library["continue"])));
            add(mk("list", "MI LISTA", own(library.list)));
            if (platform === "stremio")
                for (const r of stremioHome) {
                    const k = keyOf(r[2], r[3], r[4]);
                    add(mk(r[0], r[1], srcItems(k), { moreKey: r[2] === "top10" ? "" : k }), 4);
                }
            else for (const r of platformRows()) add(r, 4);
            add(mk("again", "VER DE NUEVO", own(library.again)));
        } else if (platform === "stremio") {
            add(mk("pop", "POPULARES", srcItems(keyOf("stremio", tab, "")), { moreKey: keyOf("stremio", tab, "") }));
            for (const g of genreRows) { const k = keyOf("stremio", tab, g[0]); add(mk("g-" + g[0], g[1], srcItems(k), { moreKey: k }), 4); }
        } else {
            const pool = srcItems(keyOf(platform, tab, ""));
            add(mk("pop", "POPULARES EN " + plat.name, pool));
            if (pool) for (const g of genreRows) add(mk("g-" + g[0], g[1], pool.filter(x => hasGenre(x, [g[0]]))), 4);
        }
        return R;
    }
    // Si las filas cambian (llegan catálogos), quedarse en la misma
    onRowsChanged: {
        cleanSoon();
        const i = rows.findIndex(r => r.id === focusRowId);
        rowIndex = i >= 0 ? i : Math.max(0, Math.min(rows.length - 1, rowIndex));
        if (i < 0) focusRowId = rows[rowIndex]?.id ?? "";
    }
    readonly property var curRow: rows[rowIndex] ?? null
    function colOf(id) { return colMap[id] ?? 0; }
    function setCol(id, v) { const m = Object.assign({}, colMap); m[id] = v; colMap = m; }
    readonly property int col: curRow ? Math.min(colOf(curRow.id), Math.max(0, curRow.items.length - 1)) : 0
    readonly property var current: searchActive && sFocus === "results" ? (searchResults[resIndex]?.recent ? null : searchResults[resIndex] ?? null)
                                                                       : tab === "letterboxd" ? (lbItems[lbIndex] ?? null)
                                                                       : curRow?.items[col] ?? null

    // Fichas completas (descripción, géneros, episodios), a pedido
    property var metaCache: ({})
    readonly property var info: current ? Object.assign({}, current, metaCache[current.id] ?? {}) : null
    Timer { id: metaDebounce; interval: 280; onTriggered: root.fetchMeta(root.current) }
    onCurrentChanged: if (current && current.type !== "video" && !metaCache[current.id]) metaDebounce.restart()
    Process {
        id: metaProc
        property string id: ""
        property var queued: null
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null; try { d = JSON.parse(text); } catch (e) {}
                if (d && !d.error) { const m = Object.assign({}, root.metaCache); m[metaProc.id] = d; root.metaCache = m; }
            }
        }
        onExited: if (queued) { const q = queued; queued = null; Qt.callLater(() => root.fetchMeta(q)); }
    }
    function fetchMeta(it) {
        if (!it || metaCache[it.id] || String(it.id).startsWith("tmdb:")) return;
        if (metaProc.running) { metaProc.queued = it; return; }
        metaProc.id = it.id;
        metaProc.command = [cfg + "/stremio.py", "meta", it.type, it.id];
        metaProc.running = true;
    }

    // Agregar / quitar de Mi lista (en tu cuenta de Stremio)
    Process {
        id: actProc
        property string msg: ""
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null; try { d = JSON.parse(text); } catch (e) {}
                root.toast = d?.ok ? actProc.msg : "No se pudo: " + (d?.error ?? "error");
                if (!d?.ok) sfx.play("error");
                libProc.running = true;
            }
        }
    }

    // ── Control (el mismo lector que el modo consola) ──────────────────────
    Process {
        id: pad
        running: true
        command: [root.cfg + "/mando.py"]
        stdout: SplitParser { onRead: line => root.padEvent(line) }
        onExited: restartPad.start()
    }
    Timer { id: restartPad; interval: 3000; onTriggered: pad.running = true }
    // ── Teclado o control: la interfaz se adapta a lo último que usaste ─────
    //  (como los juegos: apretás un botón del control y todo cambia a "joystick")
    property string inputMode: "kb"               // kb = teclado/mouse · pad = control
    readonly property bool padMode: inputMode === "pad"
    function usingPad() { if (inputMode !== "pad") inputMode = "pad"; }
    function usingKb()  { if (inputMode !== "kb") inputMode = "kb"; }
    function padEvent(line) {
        const p = line.split(" ");
        if (p[0] === "pad") { padName = p[1] === "connected" ? p.slice(2).join(" ") : ""; return; }
        if (p[0] === "nav" || p[0] === "press") usingPad();
        if (modal && !settingsLayer.open && !webLogin.open) return;   // (rice-settings manda)
        if (settingsLayer.open || webLogin.open) {
            if (p[0] === "nav") navigate(p[1]);
            else if (p[0] === "press") button(p[1]);
            return;
        }
        if (!open) return;
        if (p[0] === "nav") navigate(p[1]);
        else if (p[0] === "press") button(p[1]);
    }

    // ── Abrir / cerrar ──────────────────────────────────────────────────────
    // Al arrancar (o recargarse): si había quedado abierto, sacar el tinte y
    // devolver el mouse. El archivo de estado lo mira el modo consola.
    // la app arranca mostrándose (con la entrada de tele que se prende) y termina
    // cuando la tele se termina de apagar
    Component.onCompleted: Qt.callLater(root.appear, false)
    property bool wasShown: false
    onShownChanged: {
        if (shown) {
            wasShown = true;
            // (sin gestor de ventanas, pantalla completa no agranda: se le da el tamaño de la pantalla)
            win.x = win.screen.virtualX; win.y = win.screen.virtualY;
            win.width = win.screen.width; win.height = win.screen.height;
            win.showFullScreen(); win.requestActivate();
        }
        else if (wasShown) App.quit();
    }
    property bool sessionChecked: false
    Timer {
        interval: 50; running: !root.sessionChecked
        onTriggered: { root.sessionChecked = true; Quickshell.execDetached([root.cfg + "/player-link.py", "send", "hide"]); }
    }
    function writeState(on) {
        App.writeFile(runtime + "/sintonia-state", on ? "1" : "0");
    }

    IpcHandler {
        target: "cine"
        function toggle(): void { root.toggle() }
        function show(): void { if (!root.open) root.appear(false); win.raise(); win.requestActivate(); }
        function close(): void  { root.hide() }
        // Super+M / Super+G (rice-mode.sh): ¿está abierto? y salir directo al escritorio
        // (aunque se haya entrado desde la consola: no vuelve a ella)
        // letterboxd-sync.py cambió Mi lista: recargarla si el cine está a la vista
        function refreshLibrary(): void { if (root.open) libProc.running = true }
        function isOpen(): string { return root.open || root.shown ? "1" : "0" }
        function exit(): void { root.exitToDesktop() }
        // el teléfono arrancó algo: true = en esta PC (abrir el cine si hace falta), false = solo si está abierto
        function attach(force: bool): void { root.phoneAttach(force) }
        function modal(on: bool): void { root.modal = on; if (!on && root.open) stage.forceActiveFocus(); }
        function fromConsole(): void { if (!root.open) root.appear(true) }
        function handoff(): void { root.vanish(false) }
        function staticTest(v: real): void { root.staticAmt = v }
        function setPlatform(id: string): void { root.switchPlatform(id) }
        // pruebas: reproducir sin guardar progreso en la cuenta
        function test(on: bool): void {
            root.testMode = on;
            if (on) testOff.restart(); else testOff.stop();
            // también para lo que se lance desde el teléfono (player.py mira este archivo)
            if (on) App.writeFile(root.runtime + "/sintonia-test", ""); else App.removeFile(root.runtime + "/sintonia-test");
        }
        // pruebas: abrir la pantalla de reseña de una película (tt…)
        function review(id: string, name: string): void { root.openReview(id, name, false) }
        function go(t: string): void { root.setTab(t) }
        function settings(): void { root.openSettings() }
        function welcome(): void { settingsLayer.show(true) }
        function settingsDbg(): string { return settingsLayer.dbg() }
        function fiesta(id: string): void { root.fiestaPreview = id }
        function webLogin(s: string): void { root.openWebLogin(s) }
        function webSave(s: string): int { return Navegador.guardar(s, "") }   // (pruebas)
        // un video de la compu (también para las pruebas)
        function playFile(path: string, name: string): void { root.playFile(path, name) }
        function find(q: string): void { root.openSearch(); root.setQuery(q); }
        function key(k: string): void { ["up", "down", "left", "right"].includes(k) ? root.navigate(k) : root.button(k); }
        function about(type: string, id: string): void { root.openAbout({ type: type, id: id, name: id }, "new") }
        function aboutDbg(): string { return JSON.stringify({ open: root.aboutOpen, name: root.aboutInfo?.name, data: !!root.aboutData, desc: (root.aboutData?.description ?? "").slice(0, 40), sim: root.aboutSim?.length ?? null, stack: root.aboutStack.length, actions: root.aboutActions(root.aboutInfo).map(x => x.id), focus: root.aboutFocus + ":" + root.aboutIndex + "/" + root.aboutSimIndex + "/" + root.aboutPplIndex, person: root.personView ? { name: root.personData?.name, roles: root.personRoles.map(r => r.label + ":" + r.items.length), row: root.personRow, col: root.personCol, msg: root.personMsg } : null, people: root.aboutPeople.map(x => x.name + "@" + x.line + "." + x.col).join("|"), sheet: root.actions(root.aboutInfo).map(x => x.id) }) }
        function input(m: string): void { root.inputMode = m }
        function dbg(): string { return JSON.stringify({ input: root.inputMode, sFocus: root.sFocus, rvEditing: root.rvEditing, rvKey: root.rvKeyIndex, rv: root.rvState, rvUser: root.rvUser, rvMsg: root.rvMsg, play: root.playStep, playIndex: root.playIndex, playMsg: root.playMsg, playErr: root.playErr, casting: root.casting, castName: root.castName, devices: root.castDevices.length, phase: root.phase, tab: root.tab, platform: root.platform, rows: root.rows.map(r => r.id + ":" + r.items.length), row: root.rowIndex, col: root.col, current: root.current?.name, loginError: root.loginError }); }
    }
    function toggle() {
        open ? hide() : appear(false);
    }
    function appear(viaConsole) {
        if (open) return;
        const keep = recentlyClosed();
        if ((cs.intro ?? "full") === "quick" && !viaConsole) {
            if (!keep) {
                if ((cs.startChannel ?? "stremio") !== "last") platform = "stremio";
                tab = "home"; rowIndex = 0; focusRowId = rows[0]?.id ?? "";
            }
            appearQuick();
            return;
        }
        fromConsole = !!viaConsole;
        libProc.running = true;
        Quickshell.execDetached(["systemctl", "--user", "start", "--no-block", "rice-cine-lbsync.service"]);   // watchlist de Letterboxd → Mi lista
        if (!castDisc.running) castDisc.running = true;
        toast = ""; pickerOpen = false;
        mouseMode = false; lastMouse = Qt.point(-1, -1);
        if (keep) restorePlace();
        else {
            resetPlace();
            if ((cs.startChannel ?? "stremio") !== "last") platform = "stremio";   // arranca en Stremio (o el último, según CONFIGURACIÓN)
            tab = "home"; rowIndex = 0; focusRowId = rows[0]?.id ?? "";
        }
        ensureSources();
        open = true;
        writeState(true);
        deskPow = 1; tube = 0; uiIn = 0; closing = false;
        staticAmt = 0; barsAmt = 0; cardIn = 0;
        phase = "off"; offStarted = false;
        Quickshell.execDetached(["hyprctl", "dispatch", "riceCursorHide(true)"]);
        shown = true;
        offFallback.restart();
    }
    // Volver al mismo lugar si se cerró hace menos de 3 h (si no, arranca de cero)
    property real closedAt: 0
    function recentlyClosed() { return closedAt > 0 && Date.now() - closedAt < 3 * 3600 * 1000; }
    function resetPlace() {
        sheetOpen = false; epOpen = false;
        aboutOpen = false; aboutItem = null; aboutStack = [];
        searchActive = false; query = ""; searchItems = []; searchLayer.setField("");
        touched = false;
    }
    function restorePlace() {
        if (searchActive) Qt.callLater(() => { searchLayer.setField(query); if (sFocus === "keys") searchLayer.focusField(); });
        else Qt.callLater(() => stage.forceActiveFocus());
    }
    function exitToDesktop() {
        fromConsole = false;
        handoffFallback.stop();
        if (open) { hide(); return; }
        if (shown) {
            vanish(false);
            Quickshell.execDetached(["sh", "-c", 'hyprctl dispatch \'riceTint("")\'; hyprctl dispatch "riceCursorHide(false)"']);
        }
    }
    function hide() {
        if (!open) return;
        closedAt = Date.now();
        if (playStep === "on") detachPlay();
        else if (playStep !== "") stopPlay();
        writeClean("");
        open = false;
        sfx.play("close");
        writeState(false);
        if (fromConsole) {
            // vuelve al modo consola: él saca la foto de esta pantalla, se
            // apaga como tubo y después nos pide desaparecer (handoff)
            Quickshell.execDetached(["qs", "-c", "rice-console", "ipc", "call", "console", "toggle"]);
            handoffFallback.restart();
            return;
        }
        Quickshell.execDetached(["hyprctl", "dispatch", "riceCursorHide(false)"]);
        closeAnim.restart();
    }
    Timer { id: handoffFallback; interval: 3000; onTriggered: if (root.shown) { root.fromConsole = false; root.closeAnim.restart(); } }
    function vanish(keepState) {
        handoffFallback.stop();
        writeClean("");
        offAnim.stop(); openAnim.stop(); closeAnim.stop(); chAnim.stop();
        open = false; shown = false; closing = false; phase = "ui"; tube = 1; uiIn = 1; staticAmt = 0; barsAmt = 0; cardIn = 0;
        pickerOpen = false;
        writeState(!!keepState);
        // a la consola (o donde sea): vuelve el filtro global
        if (!keepState) Quickshell.execDetached(["hyprctl", "dispatch", "riceCine(false)"]);
    }

    // ── Navegación ──────────────────────────────────────────────────────────
    property bool mouseMode: false
    property point lastMouse: Qt.point(-1, -1)
    function mouseMoved(p) {
        if (lastMouse.x < 0) { lastMouse = p; return; }
        // solo cuenta si el puntero se movió de verdad (no avisos sueltos de Qt)
        if (Math.abs(p.x - lastMouse.x) + Math.abs(p.y - lastMouse.y) > 2) {
            lastMouse = p; mouseMode = true; usingKb();
            if (playStep === "on") showCtrl();
        }
    }
    // Hover de tarjetas/listas: cuenta SOLO si el puntero se movió de verdad en la
    // pantalla. Si la vista se desplaza bajo un mouse quieto, Qt manda eventos de
    // hover igual; sin este filtro elegir una fila movía la vista, la tarjeta de
    // abajo del puntero cambiaba y el cine subía/bajaba solo sin parar.
    property point lastPick: Qt.point(-1, -1)
    function realMove(item, m) {
        const p = item.mapToItem(null, m.x, m.y);
        if (Math.abs(p.x - lastPick.x) + Math.abs(p.y - lastPick.y) <= 2) return false;
        lastPick = Qt.point(p.x, p.y);
        return true;
    }
    property real bumpX: 0
    property real bumpY: 0
    SequentialAnimation {
        id: bumpAnim
        property real dx: 0
        property real dy: 0
        ParallelAnimation {
            NumberAnimation { target: root; property: "bumpX"; to: bumpAnim.dx; duration: 70; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "bumpY"; to: bumpAnim.dy; duration: 70; easing.type: Easing.OutQuad }
        }
        ParallelAnimation {
            NumberAnimation { target: root; property: "bumpX"; to: 0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 3 }
            NumberAnimation { target: root; property: "bumpY"; to: 0; duration: 260; easing.type: Easing.OutBack; easing.overshoot: 3 }
        }
    }
    function bump(dir) {
        bumpAnim.dx = dir === "left" ? 16 : dir === "right" ? -16 : 0;
        bumpAnim.dy = dir === "up" ? 16 : dir === "down" ? -16 : 0;
        bumpAnim.restart();
    }

    function navigate(dir) {
        if (webLogin.open) return;
        if (settingsLayer.open) { settingsLayer.navigate(dir); return; }
        if (phase !== "ui" || !open) return;
        mouseMode = false; touched = true;
        const before = [rowIndex, col, sheetIndex, pickerIndex, epIndex, epSeason, sheetOpen, playIndex, ctrlIndex, ctrlFocus, trackIndex, aboutFocus, aboutIndex, aboutSimIndex, aboutPplIndex, personRow, personCol].join();
        navigateRaw(dir);
        if ([rowIndex, col, sheetIndex, pickerIndex, epIndex, epSeason, sheetOpen, playIndex, ctrlIndex, ctrlFocus, trackIndex, aboutFocus, aboutIndex, aboutSimIndex, aboutPplIndex, personRow, personCol].join() !== before && playStep !== "on") sfx.play("nav");
    }
    function navigateRaw(dir) {
        if (review) { reviewNav(dir); return; }
        if (playStep !== "") { playNav(dir); return; }
        if (pickerOpen) {
            if (dir === "up")   pickerIndex = Math.max(0, pickerIndex - 1);
            if (dir === "down") pickerIndex = Math.min(platforms.length - 1, pickerIndex + 1);
            return;
        }
        if (epOpen) {
            if (dir === "up")    { if (epIndex > 0) epIndex--; else bump(dir); }
            if (dir === "down")  { if (epIndex < episodes.length - 1) epIndex++; else bump(dir); }
            if (dir === "left")  changeSeason(-1);
            if (dir === "right") changeSeason(1);
            return;
        }
        if (aboutOpen) { aboutNav(dir); return; }
        if (sheetOpen) {
            const n = actions(info).length;
            if (dir === "left")  sheetIndex = Math.max(0, sheetIndex - 1);
            if (dir === "right") sheetIndex = Math.min(n - 1, sheetIndex + 1);
            if (dir === "up" || dir === "down") sheetOpen = dir === "up";
            return;
        }
        if (searchActive) { searchNav(dir); return; }
        if (tab === "letterboxd") { lbNav(dir); return; }
        if (!curRow) return;
        if (dir === "left")  { if (col > 0) setCol(curRow.id, col - 1); else bump(dir); }
        if (dir === "right") { if (col < curRow.items.length - 1) setCol(curRow.id, col + 1); else bump(dir); }
        if (dir === "up")    { if (rowIndex > 0) { rowIndex--; focusRowId = rows[rowIndex].id; } else bump(dir); }
        if (dir === "down")  { if (rowIndex < rows.length - 1) { rowIndex++; focusRowId = rows[rowIndex].id; } else bump(dir); }
        // cerca del final de la fila: traer más
        if (curRow?.moreKey && col > curRow.items.length - 6) requestSrc(curRow.moreKey, true);
    }
    // Clic derecho = volver atrás, pero NUNCA saca del cine ni corta la película
    function mouseBack() {
        if (phase !== "ui" || !open) return;
        if (playStep === "on" && !review && !nextEp && trackMenu === "" && ctrlFocus !== 1) return;
        if (playStep === "" && !review && !nextEp && !pickerOpen && !epOpen && !sheetOpen && !searchActive && !aboutOpen) return;
        button("b");
    }
    function button(b) {
        if (webLogin.open) { if (b === "b" || b === "guide") webLogin.cerrar(); return; }
        if (settingsLayer.open) { settingsLayer.button(b); return; }
        if (phase !== "ui" || !open) return;
        if (b === "menu") { openSettings(); return; }       // ≡ = CONFIGURACIÓN (también viendo algo)
        mouseMode = false; touched = true;
        if (review) { reviewButton(b); return; }
        if (playStep !== "") { playButton(b); return; }
        if (nextEp) {
            if (b === "a") { sfx.play("select"); playNext(); }
            if (b === "b") { sfx.play("back"); nextEp = null; nextTimer.stop(); }
            return;
        }
        if (b === "a") sfx.play("select");
        else if (b === "b" && (sheetOpen || pickerOpen || epOpen)) sfx.play("back");
        else if (["lb", "rb", "y"].includes(b)) sfx.play("nav");
        if (pickerOpen) {
            if (b === "a") { pickerOpen = false; switchPlatform(platforms[pickerIndex].id); }
            if (b === "b" || b === "y") pickerOpen = false;
            return;
        }
        if (epOpen) {
            if (b === "a") playEpisode(episodes[epIndex]);
            if (b === "b") epOpen = false;
            if (b === "lb") changeSeason(-1);
            if (b === "rb") changeSeason(1);
            return;
        }
        if (aboutOpen) { aboutButton(b); return; }
        if (sheetOpen) {
            if (b === "a") doAction(info, actions(info)[sheetIndex]?.id);
            if (b === "b") { sheetOpen = false; if (searchActive) searchLayer.focusField(); }
            return;
        }
        if (searchActive) { searchButton(b); return; }
        switch (b) {
        case "a":  openSheet(); break;
        case "b":  hide(); break;
        case "lb": cycleTab(-1); break;
        case "rb": cycleTab(1); break;
        case "lt": cyclePlatform(-1); break;
        case "rt": cyclePlatform(1); break;
        case "y":  pickerIndex = platforms.findIndex(p => p.id === platform); pickerOpen = true; break;
        case "x":  openSearch(); break;
        case "menu": hide(); break;
        }
    }
    function setTab(t) {
        if (!tabs.some(x => x[0] === t)) return;
        if (searchActive) closeSearch();
        tab = t; sheetOpen = false;
        rowIndex = 0; focusRowId = rows[0]?.id ?? "";
        stage.forceActiveFocus();
    }
    function cycleTab(d) {
        const i = tabs.findIndex(x => x[0] === tab);
        setTab(tabs[(i + d + tabs.length) % tabs.length][0]);
    }
    function cyclePlatform(d) {
        const i = platforms.findIndex(p => p.id === platform);
        switchPlatform(platforms[(i + d + platforms.length) % platforms.length].id);
    }
    function openSheet() {
        if (!current) return;
        if (String(current.id).startsWith("lb:")) { toast = "Sin ficha en IMDb: no se puede buscar en Stremio"; sfx.play("error"); return; }
        if (String(current.id).startsWith("tmdb:")) { openAbout(current, "new"); return; }   // sin IMDb: solo la pestaña
        sheetIndex = 0;
        sheetOpen = true;
    }
    // ── Buscador ────────────────────────────────────────────────────────────
    //  Pantalla propia: la búsqueda grande, un teclado en pantalla (joystick) y
    //  los resultados en pósters. En un canal de plataforma, primero lo que hay
    //  en ese canal (al instante, de su catálogo) y después todo Stremio.
    //  Sin escribir nada: búsquedas recientes.
    property string sFocus: "keys"              // "keys" | "results"
    property int    keyIndex: 0
    property int    resIndex: 0
    property var    recents: []
    readonly property var keyboard: "ABCDEFGHIJKLMNÑOPQRSTUVWXYZ0123456789".split("").concat(["ESPACIO", "⌫", "BORRAR"])
    readonly property int keyCols: 8
    function norm(t) { return (t || "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase().replace(/[^a-z0-9ñ ]+/g, "").trim(); }
    readonly property var searchResults: {
        const q = norm(query);
        if (q === "") return recents.map(r => ({ recent: true, name: r, id: "recent:" + r }));
        if (tab === "letterboxd") return lbItems.filter(x => norm(x.name).includes(q) || String(x.year) === q);
        if (platform === "stremio") return searchItems;
        const pool = interleave(srcItems(keyOf(platform, "movie", "")) ?? [], srcItems(keyOf(platform, "series", "")) ?? []);
        const mine = pool.filter(x => norm(x.name).includes(q)).map(x => Object.assign({}, x, { here: true }));
        const seen = {};
        for (const x of mine) seen[x.id] = true;
        return mine.concat(searchItems.filter(x => !seen[x.id]));
    }
    FileView {
        path: root.stateDir + "/recent-searches.json"
        printErrors: false
        onLoaded: { try { root.recents = JSON.parse(text()); } catch (e) {} }
    }
    function addRecent(q) {
        q = q.trim();
        if (q === "") return;
        const l = [q].concat(recents.filter(r => r.toLowerCase() !== q.toLowerCase())).slice(0, 12);
        recents = l;
        App.writeFile(stateDir + "/recent-searches.json", JSON.stringify(l));
    }
    function openSearch() {
        if (phase !== "ui" || plat.external) return;
        sheetOpen = false;
        searchActive = true;
        sFocus = "keys"; keyIndex = 0; resIndex = 0;
        searchLayer.focusField();
    }
    function closeSearch() {
        searchActive = false;
        query = ""; searchItems = [];
        searchLayer.setField("");
        stage.forceActiveFocus();
    }
    function setQuery(q) {
        query = q;
        searchLayer.setField(q);
        resIndex = 0;
        searchDebounce.restart();
    }
    function queryTyped(t) { query = t; resIndex = 0; searchDebounce.restart(); }   // teclado de verdad
    function typeKey(k) {
        if (k === "⌫") setQuery(query.slice(0, -1));
        else if (k === "BORRAR") setQuery("");
        else setQuery(query + (k === "ESPACIO" ? " " : k.toLowerCase()));
    }
    function searchNav(dir) {
        const n = searchResults.length, cols = searchLayer.resCols;
        if (!padMode) {                            // teclado: el campo arriba, los resultados abajo
            if (sFocus === "keys") { if (dir === "down" && n > 0) { sFocus = "results"; resIndex = 0; } else bump(dir); return; }
            const c = resIndex % cols;
            if (dir === "left")  { if (c > 0) resIndex--; else bump(dir); }
            if (dir === "right") { if (c < cols - 1 && resIndex < n - 1) resIndex++; else bump(dir); }
            if (dir === "up")    { if (resIndex >= cols) resIndex -= cols; else sFocus = "keys"; }
            if (dir === "down")  { if (resIndex + cols < n) resIndex += cols; else if (Math.floor(resIndex / cols) < Math.floor((n - 1) / cols)) resIndex = n - 1; else bump(dir); }
            return;
        }
        if (sFocus === "keys") {
            const nk = keyboard.length, c = keyIndex % keyCols;
            if (dir === "left")  { if (c > 0) keyIndex--; else bump(dir); }
            if (dir === "right") { if (c < keyCols - 1 && keyIndex < nk - 1) keyIndex++; else if (n > 0) { sFocus = "results"; resIndex = 0; } else bump(dir); }
            if (dir === "up")    { if (keyIndex >= keyCols) keyIndex -= keyCols; else bump(dir); }
            if (dir === "down")  { if (keyIndex + keyCols < nk) keyIndex += keyCols; else bump(dir); }
        } else {
            const c = resIndex % cols;
            if (dir === "left")  { if (c > 0) resIndex--; else sFocus = "keys"; }
            if (dir === "right") { if (c < cols - 1 && resIndex < n - 1) resIndex++; else bump(dir); }
            if (dir === "up")    { if (resIndex >= cols) resIndex -= cols; else bump(dir); }
            if (dir === "down")  { if (resIndex + cols < n) resIndex += cols; else if (Math.floor(resIndex / cols) < Math.floor((n - 1) / cols)) resIndex = n - 1; else bump(dir); }
        }
    }
    function searchButton(b) {
        if (b === "a") sfx.play("select"); else if (b === "b") sfx.play("back");
        switch (b) {
        case "a":
            if (sFocus === "keys") { typeKey(keyboard[keyIndex]); break; }
            const it = searchResults[resIndex];
            if (!it) break;
            if (it.recent) { setQuery(it.name); break; }
            addRecent(query);
            openSheet();
            stage.forceActiveFocus();
            break;
        case "b": closeSearch(); break;
        case "x": typeKey("⌫"); break;
        case "y": typeKey("ESPACIO"); break;
        }
    }

    // ── Cambio de canal: estática, el número en pantalla y el color nuevo ─
    property string nextPlatform: ""
    property real   staticAmt: 0      // nieve encima de todo (tvstatic.frag)
    property real   barsAmt: 0        // barras de color
    property bool   osdOn: false      // número de canal arriba a la derecha
    Timer { id: osdTimer; interval: 2600; onTriggered: root.osdOn = false }
    function switchPlatform(id) {
        if (!platforms.some(p => p.id === id) || id === platform || chAnim.running) return;
        nextPlatform = id;
        sfx.play("off");
        chAnim.restart();
    }
    SequentialAnimation {
        id: chAnim
        NumberAnimation { target: root; property: "staticAmt"; to: 1; duration: 110 }
        ScriptAction { script: {
            if (root.searchActive) root.closeSearch();
            root.platform = root.nextPlatform;
            if (!root.tabs.some(t => t[0] === root.tab)) root.tab = "home";
            root.rowIndex = 0; root.focusRowId = root.rows[0]?.id ?? "";
            root.osdOn = true; osdTimer.restart();
        } }
        PauseAnimation { duration: 260 }
        ScriptAction { script: sfx.play("open") }
        NumberAnimation { target: root; property: "staticAmt"; to: 0; duration: 380; easing.type: Easing.InQuad }
    }

    // El cine aparece al toque (sin la foto del escritorio que se apaga): entrada rápida
    function appearQuick() {
        if (open) return;
        fromConsole = false;
        libProc.running = true;
        Quickshell.execDetached(["systemctl", "--user", "start", "--no-block", "rice-cine-lbsync.service"]);   // watchlist de Letterboxd → Mi lista
        toast = ""; pickerOpen = false;
        mouseMode = false; lastMouse = Qt.point(-1, -1);
        if (recentlyClosed()) restorePlace(); else resetPlace();
        ensureSources();
        open = true; shown = true;
        writeState(true);
        offAnim.stop(); openAnim.stop(); closeAnim.stop();
        phase = "ui"; deskPow = 1; tube = 1; uiIn = 1; closing = false; cardIn = 0; barsAmt = 0;
        staticAmt = 1;
        quickIn.restart();
        Quickshell.execDetached(["sh", "-c", 'hyprctl dispatch "riceCine(true)"; hyprctl dispatch "riceCursorHide(false)"']);
        sfx.play("open");
    }
    NumberAnimation { id: quickIn; target: root; property: "staticAmt"; to: 0; duration: 420; easing.type: Easing.InQuad; onFinished: root.attachSession() }

    // ── Qué se puede hacer con cada título ─────────────────────────────────
    function actions(it) {
        if (!it) return [];
        const a = [];
        if (it.type === "video") {
            if ((it.offset ?? 0) > 0) a.push({ id: "resume", glyph: "\u{f040a}", label: "CONTINUAR", note: "desde " + fmtTime(it.offset) });
            a.push({ id: "play", glyph: (it.offset ?? 0) > 0 ? "\u{f0459}" : "\u{f040a}", label: (it.offset ?? 0) > 0 ? "DESDE EL PRINCIPIO" : "REPRODUCIR" });
            if (castDevices.length) a.push({ id: "tv", glyph: "\u{f0118}", label: "EN LA TELE", note: tvNote() });
            if ((it.offset ?? 0) > 0) a.push({ id: "dismiss", glyph: "\u{f0156}", label: "QUITAR DE SEGUIR VIENDO" });
            return a;
        }
        // reproducir solo desde la pestaña SOBRE LA PELÍCULA (AboutLayer.qml)
        a.push({ id: "about", glyph: "\u{f040a}", label: "ABRIR", note: "sinopsis · tráiler · reproducir" });
        if ((library["continue"] ?? []).some(x => x.id === it.id))
            a.push({ id: "dismiss", glyph: "\u{f0156}", label: "QUITAR DE SEGUIR VIENDO" });
        if (listIds.includes(it.id))
            a.push({ id: "unlist", glyph: "\u{f0376}", label: "QUITAR DE MI LISTA" });
        else
            a.push({ id: "list", glyph: "\u{f0412}", label: "AGREGAR A MI LISTA" });
        return a;
    }
    // botones de reproducir (los usa la pestaña SOBRE LA PELÍCULA)
    function playActions(it) {
        if (!it || String(it.id).startsWith("tmdb:")) return [];      // sin IMDb no hay dónde verla
        const a = [];
        if (it.type === "series") {
            if (it.videoId && it.season > 0)
                a.push({ id: "resume", glyph: "\u{f040a}", label: "CONTINUAR", note: "T" + it.season + " · E" + it.episode });
            a.push({ id: "episodes", glyph: "\u{f0411}", label: "EPISODIOS", note: (it.videos?.length ? seasonsOf(it).length + " temporadas" : "") });
        } else {
            if ((it.offset ?? 0) > 0)
                a.push({ id: "resume", glyph: "\u{f040a}", label: "CONTINUAR", note: "desde " + fmtTime(it.offset) });
            a.push({ id: "play", glyph: (it.offset ?? 0) > 0 ? "\u{f0459}" : "\u{f040a}", label: (it.offset ?? 0) > 0 ? "DESDE EL PRINCIPIO" : "REPRODUCIR" });
        }
        // a la tele directo (si hay un Chromecast en la casa)
        if (castDevices.length && (it.type !== "series" || (it.videoId && it.season > 0)))
            a.splice(1, 0, { id: "tv", glyph: "\u{f0118}", label: "EN LA TELE", note: tvNote() });
        return a;
    }

    // ── Pestaña SOBRE LA PELÍCULA ───────────────────────────────────────────
    property bool   aboutOpen: false
    property var    aboutItem: null
    property var    aboutData: null              // about.py about (null = cargando)
    property var    aboutSim: null               // about.py similar (null = buscando)
    property var    aboutStack: []               // recomendaciones abiertas una encima de otra
    property string aboutFocus: "act"            // act = botones · sim = parecidas · ppl = equipo/reparto · role = filas del perfil
    property int    aboutIndex: 0
    property int    aboutSimIndex: 0
    property int    aboutPplIndex: 0
    // perfil de una persona (aboutItem.type === "person")
    property var    personData: null             // about.py person (null = cargando)
    property int    personRow: 0
    property var    personCols: ({})             // fila → película elegida (cada fila recuerda la suya)
    property string personMsg: ""
    readonly property bool personView: aboutItem?.type === "person"
    readonly property var personRoles: (personData?.roles ?? []).filter(r => r.items?.length)
    readonly property int personCol: personCols[personRow] ?? 0
    function setPersonCol(c) { const m = Object.assign({}, personCols); m[personRow] = c; personCols = m; }
    // Equipo y reparto de la película como lista navegable: [{ name, role, path, photo, line, col }]
    function slugify(n) {
        return (n || "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
    }
    readonly property var aboutPeople: {
        const d = aboutData, r = [];
        if (!d || personView) return r;
        const map = d.people ?? {};
        let line = 0;
        const crewRows = [[aboutItem?.type === "series" ? "creator" : "director", d.director], ["writer", d.writer],
                          ["cinematography", d.dop], ["editor", d.editing], ["composer", d.music]];
        for (const [kind, names] of crewRows) {
            if (!names?.length) continue;
            names.slice(0, 3).forEach((n, i) => r.push({ name: n, kind: kind, path: map[n.toLowerCase()] ?? ("/" + kind + "/" + slugify(n) + "/"), photo: "", line: line, col: i }));
            line++;
        }
        (d.castFull ?? []).slice(0, 6).forEach((c, i) => r.push({ name: c.name, kind: "actor", path: map[c.name.toLowerCase()] ?? ("/actor/" + slugify(c.name) + "/"),
                                                                    photo: c.photo ?? "", line: line + Math.floor(i / 3), col: i % 3 }));
        return r;
    }
    // dejar listos (en segundo plano) los perfiles más probables: dirección y reparto principal
    function prefetchPeople() {
        const P = aboutPeople;
        const pick = P.filter(x => x.kind !== "actor").slice(0, 2).concat(P.filter(x => x.kind === "actor").slice(0, 3));
        if (!pick.length) return;
        Quickshell.execDetached([cfg + "/about.py", "prefetch"].concat(...pick.map(x => [x.name, x.path])));
    }
    function openPerson(x) {
        if (!x) return;
        openAbout({ type: "person", id: "person:" + x.path, name: x.name, path: x.path, photo: x.photo }, "push");
    }
    readonly property var aboutInfo: aboutItem ? Object.assign({}, aboutItem, metaCache[aboutItem.id] ?? {}, libProgress(aboutItem.id)) : null
    function libProgress(id) {
        const x = library["continue"].find(y => y.id === id) ?? library.again.find(y => y.id === id);
        if (!x) return {};
        return { offset: x.offset, duration: x.duration, progress: x.progress, videoId: x.videoId,
                 season: x.season, episode: x.episode, watched: x.watched };
    }
    function aboutActions(it) {
        const a = playActions(it);
        if (aboutData?.trailer) a.push({ id: "trailer", glyph: "\u{f0fce}", label: "TRÁILER" });
        return a;
    }
    function openAbout(it, mode) {          // mode: new | push | back
        if (!it || !it.id) return;
        if (mode === "push" && aboutItem)
            aboutStack = aboutStack.concat([Object.assign({}, aboutItem, { _st: { focus: aboutFocus, index: aboutIndex, sim: aboutSimIndex,
                ppl: aboutPplIndex, row: personRow, cols: personCols, data: aboutData, simData: aboutSim, person: personData } })]);
        if (mode === "new") aboutStack = [];
        const st = mode === "back" ? it._st : null;
        aboutItem = it; aboutData = st?.data ?? null; aboutSim = st?.simData ?? null; personData = st?.person ?? null;
        aboutFocus = st?.focus ?? (it.type === "person" ? "role" : "act");
        aboutIndex = st?.index ?? 0; aboutSimIndex = st?.sim ?? 0; aboutPplIndex = st?.ppl ?? 0;
        personRow = st?.row ?? 0; personCols = st?.cols ?? ({}); personMsg = "";
        sheetOpen = false; epOpen = false;
        aboutOpen = true;
        if (it.type === "person") {
            if (!st?.person) aboutComp.createObject(root, { kind: "person", forId: it.id, args: ["person", it.name, it.path ?? ""] });
            return;
        }
        fetchMeta(it);
        if (st?.data && st?.simData) return;            // volviendo: ya estaba todo cargado
        const t = it.type === "series" ? "series" : "movie";
        aboutComp.createObject(root, { kind: "about", forId: it.id, args: ["about", t, it.id] });
        aboutComp.createObject(root, { kind: "similar", forId: it.id, args: ["similar", t, it.id] });
    }
    function closeAbout() {
        if (aboutStack.length) {
            const prev = aboutStack[aboutStack.length - 1];
            aboutStack = aboutStack.slice(0, -1);
            openAbout(prev, "back");
            return;
        }
        aboutOpen = false; aboutItem = null;
    }
    Component {
        id: aboutComp
        Process {
            id: ap
            property string kind: ""
            property string forId: ""
            property var args: []
            property var film: null
            command: [root.cfg + "/about.py"].concat(args)
            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    let d = null; try { d = JSON.parse(text); } catch (e) {}
                    if (root.aboutItem?.id !== ap.forId) return;
                    if (ap.kind === "about") { root.aboutData = d && !d.error ? d : {}; Qt.callLater(root.prefetchPeople); }
                    else if (ap.kind === "person") root.personData = d && !d.error ? d : { roles: [], error: true };
                    else if (ap.kind === "lbfilm") {
                        root.personMsg = "";
                        if (d?.id) root.openAbout(Object.assign({}, ap.film, { id: d.id, type: "movie" }), "push");
                        else root.personMsg = "No encontré «" + (ap.film?.name ?? "") + "» en el catálogo.";
                    }
                    else root.aboutSim = d?.items ?? [];
                }
            }
            onExited: ap.destroy(1000)
        }
    }
    function aboutButton(b) {
        if (b === "b") { sfx.play("back"); closeAbout(); return; }
        if (b !== "a") return;
        if (personView) {
            const f = personRoles[personRow]?.items?.[personCol];
            if (!f) return;
            const film = { type: "movie", id: f.id, name: f.name, year: f.year, poster: f.poster ?? "" };
            if (f.id) { openAbout(film, "push"); return; }
            personMsg = "Buscando «" + f.name + "»…";
            aboutComp.createObject(root, { kind: "lbfilm", forId: aboutItem.id, film: film, args: ["lbfilm", f.slug] });
            return;
        }
        if (aboutFocus === "ppl") { openPerson(aboutPeople[aboutPplIndex]); return; }
        if (aboutFocus === "sim") {
            const x = (aboutSim ?? [])[aboutSimIndex];
            if (x) openAbout(x, "push");
            return;
        }
        const id = aboutActions(aboutInfo)[aboutIndex]?.id;
        if (id === "trailer") playTrailer();
        else doAction(aboutInfo, id);
    }
    function aboutNav(dir) {
        if (personView) {
            const rs = personRoles;
            if (!rs.length) { bump(dir); return; }
            const n = rs[personRow]?.items?.length ?? 0;
            if (dir === "up")    { if (personRow > 0) personRow--; else bump(dir); }
            if (dir === "down")  { if (personRow < rs.length - 1) personRow++; else bump(dir); }
            if (dir === "left")  { if (personCol > 0) setPersonCol(personCol - 1); else bump(dir); }
            if (dir === "right") { if (personCol < n - 1) setPersonCol(personCol + 1); else bump(dir); }
            personMsg = "";
            return;
        }
        if (aboutFocus === "ppl") {
            const P = aboutPeople, cur = P[aboutPplIndex];
            if (!cur) { aboutFocus = "act"; return; }
            const lines = P.map(x => x.line), last = Math.max(...lines);
            const goLine = (l) => {                    // la más cercana en columna de esa línea
                const c = P.filter(x => x.line === l);
                const best = c.reduce((a, x) => Math.abs(x.col - cur.col) < Math.abs(a.col - cur.col) ? x : a, c[0]);
                aboutPplIndex = P.indexOf(best);
            };
            if (dir === "left")  { if (aboutPplIndex > 0 && P[aboutPplIndex - 1].line === cur.line) aboutPplIndex--; else aboutFocus = "act"; }
            if (dir === "right") { if (aboutPplIndex < P.length - 1 && P[aboutPplIndex + 1].line === cur.line) aboutPplIndex++; else bump(dir); }
            if (dir === "up")    { if (cur.line > 0) goLine(cur.line - 1); else bump(dir); }
            if (dir === "down")  { if (cur.line < last) goLine(cur.line + 1); else if (aboutSim?.length) aboutFocus = "sim"; else bump(dir); }
            return;
        }
        if (aboutFocus === "act") {
            const n = aboutActions(aboutInfo).length;
            if (dir === "left")  { if (aboutIndex > 0) aboutIndex--; else bump(dir); }
            if (dir === "right") { if (aboutIndex < n - 1) aboutIndex++; else if (aboutPeople.length) { aboutFocus = "ppl"; aboutPplIndex = 0; } else bump(dir); }
            if (dir === "down")  { if (aboutSim?.length) aboutFocus = "sim"; else bump(dir); }
            if (dir === "up")    { if (aboutPeople.length) { aboutFocus = "ppl"; aboutPplIndex = 0; } else bump(dir); }
        } else {
            const n = aboutSim?.length ?? 0;
            if (dir === "left")  { if (aboutSimIndex > 0) aboutSimIndex--; else bump(dir); }
            if (dir === "right") { if (aboutSimIndex < n - 1) aboutSimIndex++; else bump(dir); }
            if (dir === "up")    aboutFocus = "act";
            if (dir === "down")  bump(dir);
        }
    }
    function playTrailer() {
        const t = aboutData?.trailer;
        if (!t) return;
        startPlay({ type: "video", id: "yt:" + t, name: "Tráiler · " + (aboutInfo?.name ?? ""), channel: "", trailer: true }, "yt:" + t, 0);
    }

    function doAction(it, id) {
        if (!it || !id) return;
        switch (id) {
        case "about":    openAbout(it, "new"); break;
        case "resume":   startPlay(it, it.type === "series" ? it.videoId : it.id, it.offset ?? 0); break;
        case "play":     startPlay(it, it.id, 0); break;
        case "episodes": openEpisodes(it); break;
        case "tv":
            forceTv = true;
            if (it.type === "series") startPlay(it, it.videoId, it.offset ?? 0);
            else startPlay(it, it.id, it.offset ?? 0);
            break;
        case "list":
        case "unlist":
            actProc.msg = (id === "list" ? "Agregada a Mi lista: " : "Quitada de Mi lista: ") + it.name;
            if (id === "list") setOrigin(it.id);
            actProc.command = [cfg + "/stremio.py", "mylist", id === "list" ? "add" : "remove", it.type, it.id, it.name];
            actProc.running = true;
            sheetOpen = false;
            break;
        case "dismiss":
            actProc.msg = "Quitada de Seguir viendo: " + (it.name ?? it.title ?? "");
            actProc.command = [cfg + "/stremio.py", "dismiss", it.id];
            actProc.running = true;
            sheetOpen = false;
            break;
        }
    }
    // Etapa 1: la ficha se abre en la app de Stremio (etapa 2: reproductor propio)
    function openInStremio(type, id, videoId) {
        Qt.openUrlExternally("stremio:///detail/" + type + "/" + id + "/" + encodeURIComponent(videoId || id));
        sheetOpen = false; epOpen = false;
        fromConsole = false;
        hide();
    }

    // ── Episodios ───────────────────────────────────────────────────────────
    function seasonsOf(it) {
        const s = [];
        for (const v of it?.videos ?? []) if (!s.includes(v.season)) s.push(v.season);
        return s;
    }
    readonly property var epInfo: epShow ? Object.assign({}, epShow, metaCache[epShow.id] ?? {}) : null
    readonly property var seasons: seasonsOf(epInfo)
    readonly property var episodes: (epInfo?.videos ?? []).filter(v => v.season === epSeason)
    function openEpisodes(it) {
        epShow = it;
        fetchMeta(it);
        epSeason = it.season > 0 ? it.season : 1;
        epIndex = 0;
        epOpen = true; sheetOpen = false;
        Qt.callLater(focusEpisode);
    }
    onEpInfoChanged: if (epOpen) focusEpisode()
    function focusEpisode() {
        if (!epInfo?.videos?.length) return;
        if (!seasons.includes(epSeason)) epSeason = seasons.find(s => s > 0) ?? seasons[0];
        const i = episodes.findIndex(v => v.id === epShow.videoId);
        epIndex = Math.max(0, i);
        epList.positionViewAtIndex(epIndex, ListView.Center);
    }
    function changeSeason(d) {
        const i = seasons.indexOf(epSeason) + d;
        if (i < 0 || i >= seasons.length) { bump(d < 0 ? "left" : "right"); return; }
        epSeason = seasons[i]; epIndex = 0;
        epList.positionViewAtBeginning();
    }
    function playEpisode(v) {
        if (!v) return;
        const resume = v.id === epShow.videoId ? (epShow.offset ?? 0) : 0;
        startPlay(epShow, v.id, resume);
    }

    // ── Reproductor (etapa 2) ───────────────────────────────────────────────
    //  playStep: "" | "lang" (elegir audio) | "subs" (¿subtítulos?) | "load"
    //  (sintonizando la fuente) | "on" (se ve: mpv a pantalla completa debajo
    //  de esta ventana transparente, que dibuja los controles)
    property var    play: null              // { item, videoId, start (ms), epName }
    property string playStep: ""
    readonly property bool playFull: playStep === "load" || playStep === "on"
    // reloj del ruido de imagen (cinecrt.frag y grain.frag)
    property real grainTime: 0
    Timer { interval: 41; repeat: true; running: root.shown; onTriggered: root.grainTime = (root.grainTime + 0.041667) % 3600 }
    property var    playOpts: null          // fuentes por idioma (stremio.py streams)
    property int    playIndex: 0
    property var    playLang: null
    property bool   playSubs: true
    property string playMsg: ""
    property string playErr: ""
    property var    playStats: ({ peers: 0, speed: 0, progress: 0 })
    property var    pst: ({ pos: 0, dur: 0, pause: false, buffering: false, cache: 100, subDelay: 0 })
    property var    ptracks: ({ audio: [], subs: [] })
    property bool   ctrlVisible: true
    property int    ctrlFocus: 0            // 0 = barra de tiempo, 1 = botones
    property int    ctrlIndex: 0
    property string trackMenu: ""           // "audio" | "subs"
    property int    trackIndex: 0
    property var    lastChoice: null        // idioma y subtítulos (para el siguiente episodio)
    property bool   testMode: false         // pruebas: no guardar progreso (IPC test)
    // vence solo, igual que el archivo que mira player.py (no heredarlo de sesiones viejas)
    Timer { id: testOff; interval: 3 * 3600 * 1000; onTriggered: root.testMode = false }
    property var    nextEp: null            // { item, video } mientras corre la cuenta regresiva
    property var    syncInfo: null          // último aviso del sincronizador de subtítulos
    property string syncNote: ""
    Timer { id: syncNoteTimer; interval: 5000; onTriggered: root.syncNote = "" }
    function fmtDelay(d) {
        const v = Number(d || 0);
        return (v > 0 ? "+" : v < 0 ? "−" : "±") + Math.abs(v).toFixed(1).replace(".", ",") + " s";
    }
    function subsOn() { return ptracks.subs.some(t => t.selected); }
    function nudgeSubs(d) {
        if (!subsOn()) return;
        playerCmd("subdelay " + d);
        syncNote = "SUBTÍTULOS: " + fmtDelay((pst.subDelay || 0) + d) + " (A MANO)";
        syncNoteTimer.restart();
    }
    property int    nextCount: 0

    // ── Ajustes (los cambia rice-settings: CONFIGURACIÓN) ─────────────────
    property var cs: ({})
    FileView {
        path: root.userCfg + "/settings.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { root.cs = JSON.parse(text()); } catch (e) {} }
    }
    property bool modal: false               // la configuración está abierta encima
    function openSettings() {
        if (webLogin.open) return;
        settingsLayer.open ? settingsLayer.hide() : settingsLayer.show(false);
    }
    // ── Para CONFIGURACIÓN, el navegador y las fiestas ─────────────────────
    function playSfx(n) { sfx.play(n); }
    function stageFocus() { stage.forceActiveFocus(); }
    function quitApp() { App.quit(); }
    function openWebLogin(s) { webLogin.abrir(s); }
    function refreshAll() {
        libProc.running = true;
    }
    property string fiestaPreview: ""
    readonly property var fiestaList: fiestas.list
    readonly property string fiestaHoy: fiestas.hoy
    // primera vez: la bienvenida (CUENTAS)
    onPhaseChanged: if (phase === "ui" && open && !welcomeChecked) welcomeTimer.restart()
    Timer { id: welcomeTimer; interval: 900; onTriggered: root.maybeWelcome() }
    property bool welcomeChecked: false
    function maybeWelcome() {
        if (welcomeChecked) return;
        welcomeChecked = true;
        if (!App.exists(App.configDir + "/bienvenida.json")) settingsLayer.show(true);
    }
    // el servidor del teléfono y de la tele (Chromecast) mientras la app está abierta
    // (si el puerto está ocupado, por ejemplo por rice-cine, prueba unas veces y deja)
    property int webTries: 0
    Process { id: webServer; running: true; command: [root.cfg + "/web.py"]; onExited: if (++root.webTries < 4) webRestart.start() }
    Timer { id: webRestart; interval: 5000; onTriggered: webServer.running = true }
    // tu watchlist de Letterboxd → Mi lista (como el servicio de rice-cine, cada 15 min)
    Process { id: lbSync; command: [root.cfg + "/letterboxd-sync.py"]; onExited: root.refreshAll() }
    Timer { interval: 15 * 60 * 1000; repeat: true; running: true; triggeredOnStart: true; onTriggered: if (!lbSync.running) lbSync.running = true }

    // ── En la tele (etapa B): Chromecasts de la casa ───────────────────────
    property var    castDevices: []          // [{ name, uuid, host, model }] (cast.py discover)
    property var    playTarget: null         // null = esta pantalla
    property bool   casting: false
    property string castName: ""
    property int    lastDest: 0              // la última elección (PC o tele) queda marcada
    property string lastTv: ""               // uuid de la última tele elegida
    property bool   destTvOnly: false        // "¿EN QUÉ TELE?": solo teles, sin la PC
    function destOptions() {
        const tvs = castDevices.map(d => ({ label: "En la tele  ·  " + d.name, note: "CHROMECAST", target: d }));
        return destTvOnly ? tvs : [{ label: "En esta pantalla", note: "PC", target: null }].concat(tvs);
    }
    function tvNote() { return castDevices.length > 1 ? castDevices.length + " TELES" : castDevices[0]?.name ?? ""; }
    // una sola tele: va directo; dos o más: pregunta cuál (true = preguntó)
    function chooseTv() {
        if (castDevices.length === 1) { playTarget = castDevices[0]; return false; }
        destTvOnly = true;
        playStep = "dest";
        playIndex = Math.max(0, castDevices.findIndex(d => d.uuid === lastTv));
        return true;
    }
    Process {
        id: castDisc
        command: [root.cfg + "/cast.py", "discover"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { try { const d = JSON.parse(text); if (Array.isArray(d)) root.castDevices = d; } catch (e) {} }
        }
    }
    // CONFIGURACIÓN → dónde ver: "pc" / "tv" van directo; "ask" pregunta (si hay tele)
    property bool forceTv: false             // botón EN LA TELE / A LA TELE
    function pickDest() {
        if (forceTv && castDevices.length) { forceTv = false; return chooseTv(); }
        forceTv = false;
        const d = cs.dest ?? "ask";
        if (d === "tv" && castDevices.length) return chooseTv();
        if (d === "pc" || !castDevices.length) { playTarget = null; return false; }
        askDest();
        return true;
    }
    function askDest() {
        destTvOnly = false;
        playStep = "dest";
        playIndex = Math.min(lastDest, destOptions().length - 1);
    }

    function startPlay(it, videoId, startMs) {
        if (!it.trailer) setOrigin(it.id);
        const v = (metaCache[it.id]?.videos ?? []).find(x => x.id === videoId);
        play = { item: it, videoId: videoId, start: startMs || 0,
                 seenBefore: library.again.some(x => x.id === it.id) || !!it.watched,
                 epName: v ? "T" + v.season + " · E" + v.episode + "  " + (v.name || "") : "" };
        sheetOpen = false; epOpen = false; nextEp = null;
        playOpts = null; playErr = ""; playIndex = 0; playLang = null;
        if (it.type === "video") {
            if (!pickDest()) launchVideo();
            return;
        }
        playStep = "lang";
        streamsProc.command = [cfg + "/stremio.py", "streams", it.type, it.id, videoId];
        streamsProc.running = true;
    }
    Process {
        id: streamsProc
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null; try { d = JSON.parse(text); } catch (e) {}
                if (root.playStep !== "lang") return;
                if (!d || d.error || !d.options?.length) {
                    root.playErr = d?.error ? "Error: " + d.error : "No hay fuentes para este título";
                    return;
                }
                root.playOpts = d;
                // CONFIGURACIÓN → audio preferido: queda marcado primero
                if ((root.cs.prefAudio ?? "original") === "es") {
                    const i = d.options.findIndex(x => x.lang === "es-419");
                    const j = i >= 0 ? i : d.options.findIndex(x => (x.lang || "").startsWith("es"));
                    if (j >= 0) root.playIndex = j;
                }
                // siguiente episodio en automático: mismo idioma y subtítulos
                if (root.lastChoice?.auto) {
                    const o = d.options.find(x => x.lang === root.lastChoice.lang) ?? d.options[0];
                    root.playLang = o; root.playSubs = root.lastChoice.subs;
                    root.playTarget = root.lastChoice.target ?? null;
                    root.launchPlayer();
                }
            }
        }
    }
    function chooseLang(o) {
        playLang = o;
        // audio que no es español → subtítulos sí por defecto
        const ps = cs.prefSubs ?? "auto";
        playSubs = ps === "always" ? true : ps === "never" ? false : !o.lang.startsWith("es");
        playIndex = playSubs ? 0 : 1;
        playStep = "subs";
    }
    function launchVideo() {
        playLang = { lang: "", label: "Tráiler" }; playSubs = false;
        playStep = "load";
        playMsg = "SINTONIZANDO…";
        playStats = { peers: 0, speed: 0, progress: 0 };
        pst = { pos: (play.start || 0) / 1000, dur: 0, pause: false, buffering: false, cache: 100, subDelay: 0 };
        ptracks = { audio: [], subs: [] };
        trackMenu = ""; ctrlFocus = 0; ctrlIndex = 0; syncInfo = null; syncNote = "";
        runPlayer({
            type: "video", id: play.item.id, videoId: play.item.id, name: play.item.name, channel: play.item.channel ?? "",
            trailer: !!play.item.trailer,
            start: (play.start || 0) / 1000, nosave: testMode });
    }
    function playFile(path, name) {
        play = { item: { id: "file:" + path, name: name, type: "archivo" }, start: 0 };
        playLang = { lang: "", label: name }; playSubs = false; playTarget = null;
        playStep = "load";
        playMsg = "SINTONIZANDO…";
        playStats = { peers: 0, speed: 0, progress: 0 };
        pst = { pos: 0, dur: 0, pause: false, buffering: false, cache: 100, subDelay: 0 };
        ptracks = { audio: [], subs: [] };
        trackMenu = ""; ctrlFocus = 0; ctrlIndex = 0; syncInfo = null; syncNote = "";
        runPlayer({ type: "archivo", id: "file:" + path, videoId: "file:" + path, name: name, url: path, nosave: true });
    }
    function launchPlayer() {
        lastChoice = { lang: playLang.lang, subs: playSubs, auto: false, target: playTarget };
        playStep = "load";
        playMsg = "SINTONIZANDO…";
        playStats = { peers: 0, speed: 0, progress: 0 };
        pst = { pos: (play.start || 0) / 1000, dur: 0, pause: false, buffering: false, cache: 100, subDelay: 0 };
        ptracks = { audio: [], subs: [] };
        trackMenu = ""; ctrlFocus = 0; ctrlIndex = 0; syncInfo = null; syncNote = "";
        // el fósforo se ve encima de la película: el reproductor va limpio
        runPlayer({
            type: play.item.type, id: play.item.id, videoId: play.videoId, name: play.item.name,
            lang: playLang.lang, original: playOpts.original, subs: playSubs,
            start: (play.start || 0) / 1000, streams: playLang.streams, nosave: testMode });
    }
    Process {
        id: playerProc
        stdinEnabled: true
        stdout: SplitParser { onRead: line => root.onPlayer(line) }
        onExited: root.playerGone()
    }
    function playerCmd(c) { if (playerProc.running) playerProc.write(c + "\n"); }

    // ── Sesión: la película corre aparte del cine (player-link.py) ─────────
    //  Si el cine se cierra, la película se pausa y espera escondida; al
    //  volver, attachSession() la retoma. Al reiniciar la PC no queda nada.
    property bool linkQuiet: false          // el puente se cerró a propósito: no es "se cortó"
    property bool attaching: false
    property var  pendingRun: null
    function runPlayer(job) {
        // lo que hace falta para rearmar la pantalla si después te vas y volvés
        job.ui = { play: play, lastChoice: lastChoice, playLang: playLang ? { lang: playLang.lang, label: playLang.label } : null,
                   playSubs: playSubs, platform: platform, testMode: testMode, target: playTarget };
        if (playTarget) job.target = { uuid: playTarget.uuid, host: playTarget.host, name: playTarget.name };
        casting = !!playTarget;
        castName = playTarget?.name ?? "";
        attaching = false;
        if (playerProc.running) { pendingRun = job; linkQuiet = true; playerProc.running = false; return; }
        playerProc.command = [cfg + "/player-link.py", "start", JSON.stringify(job)];
        playerProc.running = true;
    }
    function detachPlay() {
        playerCmd("hide");
        linkQuiet = true;
        detachTimer.restart();
        playStep = ""; nextEp = null; trackMenu = "";
    }
    Timer { id: detachTimer; interval: 300; onTriggered: playerProc.running = false }
    function attachSession() {
        if (playerProc.running) return;
        attaching = true;
        playerProc.command = [cfg + "/player-link.py", "attach"];
        playerProc.running = true;
    }
    property bool pendingAttach: false
    function phoneAttach(force) {
        if (!open) { if (force) appear(false); return; }
        if (playerProc.running) { pendingAttach = true; return; }
        attachSession();
    }
    function resumeSession(e) {
        attaching = false;
        const u = e.ui ?? {};
        if (!u.play) { playerCmd("show"); return; }
        play = u.play; lastChoice = u.lastChoice; playLang = u.playLang; playSubs = !!u.playSubs;
        playTarget = u.target ?? null; casting = !!u.target; castName = u.target?.name ?? "";
        sheetOpen = false; epOpen = false; pickerOpen = false; nextEp = null; playErr = "";
        playStats = { peers: 0, speed: 0, progress: 0 };
        ptracks = { audio: [], subs: [] };
        trackMenu = ""; ctrlFocus = 0; ctrlIndex = 0; syncInfo = null; syncNote = "";
        playMsg = "RETOMANDO…";
        playStep = "load";
        playerCmd("show");
    }
    function onPlayer(line) {
        let e = null; try { e = JSON.parse(line); } catch (x) { return; }
        switch (e.ev) {
        case "none":    attaching = false; linkQuiet = true; break;
        case "session": if (attaching) resumeSession(e); break;
        case "status":  playMsg = e.msg; break;
        case "stats":   playStats = e; break;
        case "error":   playErr = e.msg; sfx.play("error"); break;
        case "playing": playMsg = "SEÑAL ENCONTRADA"; onAirDelay.restart(); break;
        // mpv ya tapa la pantalla: recién ahí esta ventana se vuelve transparente
        // (antes se veía el escritorio un momento al abrir la película)
        case "fullscreen": onAirDelay.stop(); onAirSoon.restart(); break;
        // en la tele: el Chromecast ya está reproduciendo
        case "casting": castName = e.name; casting = true; onAirDelay.stop(); onAirSoon.restart(); break;
        case "state":
            if (pst.volume !== undefined && e.volume !== pst.volume && trackMenu !== "vol") { volFlash = true; volFlashOff.restart(); }
            pst = e;
            break;
        case "tracks":  ptracks = e; break;
        case "sync":
            syncInfo = e;
            syncNote = e.state === "working" ? "SINCRONIZANDO SUBTÍTULOS CON LAS VOCES…"
                     : e.state === "auto" ? "SUBTÍTULOS SINCRONIZADOS SOLOS: " + fmtDelay(e.delay)
                     : e.state === "saved" ? "SUBTÍTULOS CON TU AJUSTE GUARDADO: " + fmtDelay(e.delay)
                     : e.state === "unsure" ? "NO PUDE SINCRONIZAR SOLO: AJUSTALOS CON Z / X O SINCRONIZAR"
                     : e.state === "reset" ? "SUBTÍTULOS EN AUTOMÁTICO" : "";
            syncNoteTimer.restart();
            break;
        case "ended":   playEnded = e; break;
        }
    }
    property var playEnded: null
    // mpv tarda un toque en abrir a pantalla completa: recién ahí se ve
    Timer { id: onAirDelay; interval: 12000; onTriggered: root.goOnAir() }     // por si no llega el aviso
    Timer { id: onAirSoon; interval: 350; onTriggered: root.goOnAir() }
    function goOnAir() {
        if (playStep !== "load") return;
        playStep = "on";
        showCtrl();
        playerCmd("submargin controls");
    }
    function stopPlay() {
        // la sesión entiende "quit" también mientras busca la fuente
        playerCmd("quit");
        playStep = "";
        nextEp = null;
    }
    function playerGone() {
        if (linkQuiet) {
            linkQuiet = false;
            if (pendingAttach && !pendingRun) { pendingAttach = false; Qt.callLater(attachSession); return; }
            if (pendingRun) {
                const j = pendingRun; pendingRun = null;
                playerProc.command = [cfg + "/player-link.py", "start", JSON.stringify(j)];
                playerProc.running = true;
            }
            return;
        }
        attaching = false;
        casting = false;
        if (pendingAttach) { pendingAttach = false; playEnded = null; playStep = ""; Qt.callLater(attachSession); return; }
        const end = playEnded; playEnded = null;
        const wasPlaying = playStep !== "";
        if (playStep === "load" && playErr === "") playErr = "Se cortó la señal";
        if (playStep === "on" || playStep === "load") {
            if (playErr !== "" && playStep === "load") playStep = "lang";   // el error se ve en el menú de idioma (para probar otro)
            else playStep = "";
        }
        libProc.running = true;
        stage.forceActiveFocus();
        // serie terminada: siguiente episodio con cuenta regresiva
        if (end?.finished && play?.item.type === "series") {
            const vids = metaCache[play.item.id]?.videos ?? [];
            const i = vids.findIndex(v => v.id === play.videoId);
            if (i >= 0 && i + 1 < vids.length && (cs.autoNext ?? true)) { nextEp = { item: play.item, video: vids[i + 1] }; nextCount = cs.autoNextSecs ?? 10; nextTimer.restart(); }
            else if (i >= 0 && i + 1 < vids.length) toast = "Terminó el episodio";
        } else if (end?.finished && play?.item.type === "movie" && !testMode && (cs.review ?? true)) {
            openReview(play.item.id, play.item.name, play.seenBefore);
        } else if (end?.finished) {
            toast = "Terminaste " + play.item.name;
        }
    }
    Timer {
        id: nextTimer; interval: 1000; repeat: true
        running: false
        onTriggered: {
            if (!root.nextEp) { stop(); return; }
            root.nextCount--;
            if (root.nextCount <= 0) { stop(); root.playNext(); }
        }
    }
    function playNext() {
        const n = nextEp; nextEp = null; nextTimer.stop();
        if (!n) return;
        startPlay(n.item, n.video.id, 0);
        if (lastChoice) lastChoice = Object.assign({}, lastChoice, { auto: true });
    }

    // Controles: aparecen con cualquier tecla o movimiento, se van solos
    // Volumen: en la PC hasta 130 % (mpv); en la tele 0-100 % es el de la tele
    // y de 101 a 300 % es refuerzo (player.py → ffmpeg de Stremio). Tráileres en la tele: hasta 100.
    function volMax() { return !casting ? 130 : play?.item.type === "video" ? 100 : 300; }
    property bool volFlash: false
    Timer { id: volFlashOff; interval: 1800; onTriggered: root.volFlash = false }
    // 2 s sin tocar nada → se va todo (también en pausa o con un menú abierto); solo SINCRONIZAR se queda
    Timer {
        id: ctrlTimer; interval: 2000
        onTriggered: {
            if (root.trackMenu === "sync") return;
            if (root.trackMenu !== "") root.trackMenu = "";
            root.ctrlFocus = 0;
            root.ctrlVisible = false;
        }
    }
    onTrackMenuChanged: if (playStep === "on") ctrlTimer.restart()
    function showCtrl() { ctrlVisible = true; ctrlTimer.restart(); }
    // los subtítulos suben para no quedar debajo de la barra
    onCtrlVisibleChanged: if (playStep === "on") playerCmd("submargin " + (ctrlVisible ? "controls" : "normal"))
    function ctrlButtons() {
        const b = [{ id: "pause", glyph: pst.pause ? "\u{f040a}" : "\u{f03e4}", label: pst.pause ? "SEGUIR" : "PAUSA" },
                   { id: "back10", glyph: "\u{f0d2a}", label: "-10 S" },
                   { id: "fwd10", glyph: "\u{f0d71}", label: "+10 S" },
                   { id: "audio", glyph: "\u{f05ca}", label: "AUDIO" },
                   { id: "subs", glyph: "\u{f0a16}", label: "SUBTÍTULOS" }];
        if (play?.item.type === "video") b.splice(3, 2);
        if (subsOn()) b.push({ id: "sync", glyph: "\u{f04e6}", label: "SINCRONIZAR" });
        if (play?.item.type === "series") b.push({ id: "next", glyph: "\u{f04ad}", label: "SIGUIENTE" });
        b.push({ id: "vol", glyph: "\u{f057e}", label: "VOLUMEN" });
        if (!casting && castDevices.length) b.push({ id: "tocast", glyph: "\u{f0118}", label: "A LA TELE" });
        b.push({ id: "exit", glyph: "\u{f0a48}", label: "SALIR" });
        return b;
    }
    function trackList() {
        if (trackMenu === "audio") return ptracks.audio.map(t => ({ id: t.id, label: trackName(t), on: t.selected }));
        if (trackMenu === "subs") return [{ id: "no", label: "Sin subtítulos", on: !ptracks.subs.some(t => t.selected) }]
                                         .concat(ptracks.subs.map(t => ({ id: t.id, label: trackName(t), on: t.selected })));
        return [];
    }
    readonly property var langEs: ({ eng: "Inglés", en: "Inglés", spa: "Español", es: "Español", kor: "Coreano", jpn: "Japonés",
        fre: "Francés", fra: "Francés", ger: "Alemán", deu: "Alemán", ita: "Italiano", por: "Portugués", pob: "Portugués (Brasil)",
        rus: "Ruso", chi: "Chino", zho: "Chino", ara: "Árabe", hin: "Hindi", tur: "Turco", pol: "Polaco", dut: "Neerlandés",
        swe: "Sueco", dan: "Danés", nor: "Noruego", fin: "Finlandés", ukr: "Ucraniano", heb: "Hebreo", gre: "Griego" })
    function trackName(t) {
        const l = langEs[t.lang] ?? (t.lang ? t.lang.toUpperCase() : "Pista " + t.id);
        return l + (t.title ? "  ·  " + t.title : "");
    }
    function ctrlAction(id) {
        switch (id) {
        case "pause":  playerCmd("pause"); break;
        case "back10": playerCmd("seek -10"); break;
        case "fwd10":  playerCmd("seek 10"); break;
        case "sync":
            trackMenu = "sync";
            break;
        case "vol":
            trackMenu = "vol";
            break;
        case "audio":
        case "subs":
            trackMenu = id;
            trackIndex = Math.max(0, trackList().findIndex(t => t.on));
            break;
        case "next": {
            const vids = metaCache[play.item.id]?.videos ?? [];
            const i = vids.findIndex(v => v.id === play.videoId);
            if (i >= 0 && i + 1 < vids.length) {
                const n = { item: play.item, video: vids[i + 1] };
                pendingNext = n;
                stopPlay();
            }
            break;
        }
        case "exit":   stopPlay(); break;
        case "tocast":
            // misma peli, mismo segundo, mismo idioma y subtítulos, pero en la tele
            pendingCast = { item: play.item, videoId: play.videoId, startMs: Math.max(0, (pst.pos - 3)) * 1000 };
            stopPlay();
            break;
        }
    }
    // "SIGUIENTE" mientras se ve: espera a que mpv cierre y guarde, y sigue
    property var pendingNext: null
    property var pendingCast: null
    Timer {
        id: castLater; interval: 300
        onTriggered: {
            const c = root.pendingCast; root.pendingCast = null;
            if (!c || !root.castDevices.length) return;
            if (c.item.type !== "video" && root.playOpts && root.playLang?.streams) {
                root.play = Object.assign({}, root.play, { start: c.startMs });
                if (!root.chooseTv()) root.launchPlayer();
            } else if (c.item.type === "video") {
                root.play = Object.assign({}, root.play, { start: c.startMs });
                if (!root.chooseTv()) root.launchVideo();
            } else {
                root.forceTv = true;
                root.startPlay(c.item, c.videoId, c.startMs);
            }
        }
    }
    Connections {
        target: playerProc
        function onRunningChanged() {
            if (!playerProc.running && root.pendingCast) { castLater.restart(); return; }
            if (!playerProc.running && root.pendingNext) {
                const n = root.pendingNext; root.pendingNext = null;
                root.lastChoice = Object.assign({}, root.lastChoice, { auto: true });
                root.startPlay(n.item, n.video.id, 0);
            }
        }
    }

    function playNav(dir) {
        if (playStep === "lang" || playStep === "subs" || playStep === "dest") {
            const n = playStep === "lang" ? (playOpts?.options.length ?? 0) : playStep === "dest" ? destOptions().length : 2;
            if (dir === "up")   playIndex = Math.max(0, playIndex - 1);
            if (dir === "down") playIndex = Math.min(n - 1, playIndex + 1);
            return;
        }
        if (playStep !== "on") return;
        const wasHidden = !ctrlVisible;
        showCtrl();
        if (trackMenu === "vol") {
            if (dir === "left")  playerCmd("volume -5");
            if (dir === "right") playerCmd("volume 5");
            if (dir === "up")    playerCmd("volume 25");
            if (dir === "down")  playerCmd("volume -25");
            return;
        }
        if (trackMenu === "sync") {
            if (dir === "left")  nudgeSubs(-0.1);
            if (dir === "right") nudgeSubs(0.1);
            if (dir === "up")    nudgeSubs(0.5);
            if (dir === "down")  nudgeSubs(-0.5);
            return;
        }
        if (trackMenu !== "") {
            const n = trackList().length;
            if (dir === "up")   trackIndex = Math.max(0, trackIndex - 1);
            if (dir === "down") trackIndex = Math.min(n - 1, trackIndex + 1);
            return;
        }
        if (wasHidden && (dir === "up" || dir === "down")) return;   // primero solo aparecen
        if (ctrlFocus === 0) {
            if (dir === "left")  playerCmd("seek -10");
            if (dir === "right") playerCmd("seek 10");
            if (dir === "down")  { ctrlFocus = 1; ctrlIndex = 0; }
        } else {
            const n = ctrlButtons().length;
            if (dir === "left")  ctrlIndex = Math.max(0, ctrlIndex - 1);
            if (dir === "right") ctrlIndex = Math.min(n - 1, ctrlIndex + 1);
            if (dir === "up")    ctrlFocus = 0;
        }
    }
    // Viendo algo con el teclado: atajos directos, sin depender de qué botón está marcado
    //  Espacio/K/Enter pausa · ←/→ 10 s (Shift: 1 min) · ↑/↓ volumen · S subtítulos · A audio · N siguiente
    function playKey(e) {
        if (playStep !== "on" || review || nextEp || trackMenu !== "") return false;
        const k = e.key, shift = e.modifiers & Qt.ShiftModifier;
        showCtrl();
        if (k === Qt.Key_Space || k === Qt.Key_K || k === Qt.Key_Return || k === Qt.Key_Enter) playerCmd("pause");
        else if (k === Qt.Key_Left)  playerCmd(shift ? "seek -60" : "seek -10");
        else if (k === Qt.Key_Right) playerCmd(shift ? "seek 60" : "seek 10");
        else if (k === Qt.Key_Up)    playerCmd("volume 5");
        else if (k === Qt.Key_Down)  playerCmd("volume -5");
        else if (k === Qt.Key_S && play?.item.type !== "video") ctrlAction("subs");
        else if (k === Qt.Key_A && play?.item.type !== "video") ctrlAction("audio");
        else if (k === Qt.Key_N && play?.item.type === "series") ctrlAction("next");
        else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) stopPlay();
        else return false;
        return true;
    }
    function playButton(b) {
        if (playStep === "lang") {
            if (b === "a" && playOpts?.options.length) { sfx.play("select"); chooseLang(playOpts.options[playIndex]); }
            if (b === "b") { sfx.play("back"); playStep = ""; streamsProc.running = false; }
            return;
        }
        if (playStep === "subs") {
            if (b === "a") {
                sfx.play("select"); playSubs = playIndex === 0;
                if (!pickDest()) launchPlayer();
            }
            if (b === "b") { sfx.play("back"); playStep = "lang"; playIndex = Math.max(0, playOpts.options.indexOf(playLang)); }
            return;
        }
        if (playStep === "dest") {
            const isVideo = play?.item.type === "video";
            if (b === "a") {
                sfx.play("select");
                playTarget = destOptions()[playIndex]?.target ?? null;
                if (playTarget) lastTv = playTarget.uuid;
                if (!destTvOnly) lastDest = playIndex;
                isVideo ? launchVideo() : launchPlayer();
            }
            if (b === "b") {
                sfx.play("back");
                if (isVideo) playStep = "";
                else { playStep = "subs"; playIndex = playSubs ? 0 : 1; }
            }
            return;
        }
        if (playStep === "load") {
            if (b === "b") { sfx.play("back"); stopPlay(); }
            return;
        }
        // viendo
        showCtrl();
        if (trackMenu === "vol") {
            if (b === "a" || b === "b") trackMenu = "";
            return;
        }
        if (trackMenu === "sync") {
            if (b === "a" || b === "b") trackMenu = "";
            if (b === "x") { playerCmd("resync"); trackMenu = ""; }
            return;
        }
        if (trackMenu !== "") {
            if (b === "a") {
                const t = trackList()[trackIndex];
                if (t) playerCmd((trackMenu === "audio" ? "aid " : "sid ") + t.id);
                trackMenu = "";
            }
            if (b === "b") trackMenu = "";
            return;
        }
        switch (b) {
        case "a":  if (ctrlFocus === 0) playerCmd("pause"); else ctrlAction(ctrlButtons()[ctrlIndex].id); break;
        case "b":  if (ctrlFocus === 1) ctrlFocus = 0; else stopPlay(); break;
        case "lb": playerCmd("seek -60"); break;
        case "rb": playerCmd("seek 60"); break;
        case "x":  ctrlAction("subs"); ctrlFocus = 1; break;
        case "y":  ctrlAction("audio"); ctrlFocus = 1; break;
        }
    }
    function fmtClock(sec) {
        const s = Math.max(0, Math.floor(sec || 0));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60, ss = s % 60;
        const p = n => String(n).padStart(2, "0");
        return (h > 0 ? h + ":" + p(m) : m) + ":" + p(ss);
    }

    // ── Portadas sin filtro ─────────────────────────────────────────────────
    //  Las tarjetas que se ven van "limpias" (sin el fósforo del shader CRT) y
    //  el resto de la pantalla con filtro: se escriben sus rectángulos en
    //  $XDG_RUNTIME_DIR/rice-cine-clean y media-clean.py se los pasa a
    //  riceClean() (shader.lua). Se recalcula cuando la fila deja de moverse.
    // ya no hacen falta: con el cine abierto el filtro global está apagado (riceCine)
    readonly property bool cleanWanted: false
    property string cleanSpec: ""
    Timer { id: cleanTimer; interval: 380; onTriggered: root.updateClean() }
    // cualquier movimiento: afuera las zonas ya (si no, el shader copia contenido
    // corrido sobre lo que se mueve) y vuelven cuando todo queda quieto
    function cleanSoon() { writeClean(""); cleanTimer.restart(); }
    onCleanWantedChanged: cleanWanted ? cleanSoon() : writeClean("")
    onRowIndexChanged: cleanSoon()
    onColChanged: cleanSoon()
    onResIndexChanged: cleanSoon()
    onSearchResultsChanged: cleanSoon()
    onSearchActiveChanged: cleanSoon()
    function updateClean() {
        if (!cleanWanted) { writeClean(""); return; }
        const out = [];
        const clip = (c, view) => {
            const r = c.mapToItem(null, 0, 0, c.width, c.height);
            const x0 = Math.max(r.x, view.x, 0), y0 = Math.max(r.y, view.y, 0);
            const x1 = Math.min(r.x + r.width, view.x + view.width, win.width);
            const y1 = Math.min(r.y + r.height, view.y + view.height, win.height);
            if (x1 - x0 > 40 && y1 - y0 > 40)
                out.push([Math.round(x0 + 3), Math.round(y0 + 3), Math.round(x1 - x0 - 6), Math.round(y1 - y0 - 6)].join(","));
        };
        if (searchActive) {         // en el buscador: los pósters de los resultados
            const g = searchLayer.grid, gv = g.mapToItem(null, 0, 0, g.width, g.height);
            for (const cell of g.contentItem.children)
                for (const it of cell.children)
                    for (const f of it.children) if (f.objectName === "poster" && it.visible) clip(f, gv);
            writeClean(out.sort().join(";"));
            return;
        }
        const view = rowsView.mapToItem(null, 0, 0, rowsView.width, rowsView.height);
        for (const row of rowsView.contentItem.children) {
            for (const lv of row.children) {
                if (lv.objectName !== "cards") continue;
                for (const c of lv.contentItem.children) {
                    if (c.objectName !== "card" || !c.visible) continue;
                    const r = c.mapToItem(null, 0, 0, c.width, c.height);
                    const x0 = Math.max(r.x, view.x, 0), y0 = Math.max(r.y, view.y, 0);
                    const x1 = Math.min(r.x + r.width, view.x + view.width, win.width);
                    const y1 = Math.min(r.y + r.height, view.y + view.height, win.height);
                    if (x1 - x0 > 40 && y1 - y0 > 40)
                        out.push([Math.round(x0 + 2), Math.round(y0 + 2), Math.round(x1 - x0 - 4), Math.round(y1 - y0 - 4)].join(","));
                }
            }
        }
        writeClean(out.sort().join(";"));
    }
    function writeClean(spec) {
        if (spec === cleanSpec) return;
        cleanSpec = spec;
        // (en la app no hay filtro global que limpiar)
    }

    // ── Máscara de portadas (para el filtro CRT propio, cinecrt.frag) ─────
    property var maskRects: []
    property string maskKey: ""
    FrameAnimation {
        running: root.shown && root.phase === "ui" && !root.playFull
        onTriggered: root.updateMask()
    }
    function updateMask() {
        const out = [];
        const take = (c, view) => {
            const r = c.mapToItem(null, 0, 0, c.width, c.height);
            const x0 = Math.max(r.x, view.x), y0 = Math.max(r.y, view.y);
            const x1 = Math.min(r.x + r.width, view.x + view.width), y1 = Math.min(r.y + r.height, view.y + view.height);
            if (x1 - x0 > 4 && y1 - y0 > 4) out.push([Math.round(x0), Math.round(y0), Math.round(x1 - x0), Math.round(y1 - y0)]);
        };
        const covered = review || pickerOpen || epOpen;           // capas que tapan todo
        if (!covered && searchActive) {
            const g = searchLayer.grid, gv = g.mapToItem(null, 0, 0, g.width, g.height);
            for (const cell of g.contentItem.children)
                for (const it of cell.children)
                    for (const f of it.children) if (f.objectName === "poster" && it.visible) take(f, gv);
        } else if (!covered && ui.visible) {
            const view = rowsView.mapToItem(null, 0, 0, rowsView.width, rowsView.height);
            // el menú de abajo tapa las filas: la máscara termina donde empieza
            if (sheetOpen) view.height = Math.max(0, sheet.mapToItem(null, 0, 0).y - view.y);
            for (const row of rowsView.contentItem.children)
                for (const lv of row.children) {
                    if (lv.objectName !== "cards") continue;
                    for (const c of lv.contentItem.children) if (c.objectName === "card" && c.visible) take(c, view);
                }
        }
        const k = JSON.stringify(out);
        if (k !== maskKey) { maskKey = k; maskRects = out; }
    }

    // ── Reseña en Letterboxd (etapa 5) ─────────────────────────────────────
    //  Al terminar una película: estrellas, me gustó, texto, spoilers →
    //  PUBLICAR (pide confirmación: queda público). letterboxd.py usa tu sesión de Zen.
    property var    review: null            // { id, name, rewatch }
    property int    rvRow: 0                // 0 estrellas · 1 me gustó · 2 texto · 3 spoilers · 4 botones
    property int    rvStars: 0              // 0-10 (medias estrellas)
    property bool   rvLiked: false
    property bool   rvSpoilers: false
    property int    rvButton: 0             // 0 PUBLICAR · 1 AHORA NO
    property bool   rvConfirm: false
    property bool   rvEditing: false
    property string rvState: ""             // "" | "checking" | "posting" | "done" | "error"
    property string rvMsg: ""
    property string rvUser: ""
    readonly property var reviewText: reviewLayer.textEdit
    function openReview(id, name, rewatch) {
        review = { id: id, name: name, rewatch: !!rewatch };
        rvRow = 0; rvStars = 0; rvLiked = false; rvSpoilers = false; rvButton = 0;
        rvConfirm = false; rvEditing = false; rvState = "checking"; rvMsg = ""; rvUser = "";
        reviewText.text = "";
        lbCheck.command = [cfg + "/letterboxd.py", "check", id];
        lbCheck.running = true;
    }
    Process {
        id: lbCheck
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null; try { d = JSON.parse(text); } catch (e) {}
                if (d?.user) { root.rvUser = d.user; root.rvState = ""; }
                else { root.rvState = "error"; root.rvMsg = d?.error === "nologin" ? "No hay sesión de Letterboxd en Zen: iniciá sesión y probá de nuevo"
                                                            : "Letterboxd: " + (d?.error ?? "no responde"); }
            }
        }
    }
    Process {
        id: lbPost
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null; try { d = JSON.parse(text); } catch (e) {}
                if (d?.ok) { root.rvState = "done"; root.rvMsg = "Publicada en el diario de " + d.user; sfx.play("select"); rvClose.restart(); }
                else { root.rvState = "error"; root.rvMsg = "No se pudo publicar: " + (d?.error ?? "error"); sfx.play("error"); }
            }
        }
    }
    Timer { id: rvClose; interval: 2600; onTriggered: root.review = null }
    function postReview() {
        rvConfirm = false;
        if (testMode) { rvState = "done"; rvMsg = "MODO PRUEBA: no se publicó nada"; rvClose.restart(); return; }
        rvState = "posting";
        // la reseña va como argumento (sin shell de por medio)
        lbPost.command = [cfg + "/letterboxd.py", "log", review.id, String(rvStars), rvLiked ? "1" : "0",
                          review.rewatch ? "1" : "0", rvSpoilers ? "1" : "0", reviewText.text];
        lbPost.running = true;
    }
    property int rvKeyIndex: 0
    readonly property bool rvPadKeys: rvEditing && padMode
    function reviewNav(dir) {
        if (rvPadKeys) {
            const nk = keyboard.length, c = rvKeyIndex % keyCols;
            if (dir === "left")  { if (c > 0) rvKeyIndex--; else bump(dir); }
            if (dir === "right") { if (c < keyCols - 1 && rvKeyIndex < nk - 1) rvKeyIndex++; else bump(dir); }
            if (dir === "up")    { if (rvKeyIndex >= keyCols) rvKeyIndex -= keyCols; else bump(dir); }
            if (dir === "down")  { if (rvKeyIndex + keyCols < nk) rvKeyIndex += keyCols; else bump(dir); }
            return;
        }
        if (rvConfirm) { if (dir === "left" || dir === "right") rvButton = 1 - rvButton; return; }
        if (dir === "up")   rvRow = Math.max(0, rvRow - 1);
        if (dir === "down") rvRow = Math.min(4, rvRow + 1);
        if (rvRow === 0 && dir === "left")  rvStars = Math.max(0, rvStars - 1);
        if (rvRow === 0 && dir === "right") rvStars = Math.min(10, rvStars + 1);
        if (rvRow === 4 && (dir === "left" || dir === "right")) rvButton = 1 - rvButton;
    }
    function reviewButton(b) {
        if (rvState === "posting") return;
        if (rvState === "checking" && rvRow === 4 && b === "a" && rvButton === 0) return;   // esperar a saber quién sos
        if (rvState === "done") { review = null; return; }
        if (rvPadKeys) {
            const t = reviewText;
            if (b === "b") { endEditing(); return; }
            if (b === "x" || (b === "a" && keyboard[rvKeyIndex] === "⌫")) { if (t.length) t.remove(t.length - 1, t.length); return; }
            if (b === "a" && keyboard[rvKeyIndex] === "BORRAR") { t.text = ""; return; }
            if (b === "y" || (b === "a" && keyboard[rvKeyIndex] === "ESPACIO")) { t.insert(t.length, " "); return; }
            if (b === "a") { const ch = keyboard[rvKeyIndex]; t.insert(t.length, t.length === 0 || /[.!?]\s$/.test(t.text) ? ch : ch.toLowerCase()); }
            return;
        }
        if (rvConfirm) {
            if (b === "a") { if (rvButton === 0) postReview(); else rvConfirm = false; }
            if (b === "b") rvConfirm = false;
            return;
        }
        if (b === "b") { review = null; return; }
        if (b !== "a") return;
        switch (rvRow) {
        case 1: rvLiked = !rvLiked; break;
        case 2: rvEditing = true; rvKeyIndex = 0; reviewText.forceActiveFocus(); reviewText.cursorPosition = reviewText.length; break;
        case 3: rvSpoilers = !rvSpoilers; break;
        case 4:
            if (rvButton === 1) { review = null; break; }
            if (rvState === "error" && rvUser === "") { openReview(review.id, review.name, review.rewatch); break; }
            if (rvStars === 0 && reviewText.text.trim() === "" && !rvLiked) { rvMsg = "Poné estrellas, un me gustó o algo escrito"; break; }
            rvConfirm = true; rvButton = 0;
            break;
        default: rvRow = 4; break;
        }
    }
    function endEditing() { rvEditing = false; rvRow = 3; stage.forceActiveFocus(); }

    // ── Entrada: el escritorio se apaga y la tele se prende ────────────────
    //  "off":  foto de la pantalla que se apaga como un tubo (como el resto del rice)
    //  "boot": a oscuras se tiñe el CRT; nieve → barras de color con el canal →
    //          placa de título estilo Evangelion → la interfaz
    property string phase: "ui"
    property real deskPow: 1
    property real tube: 1
    property bool closing: false
    property bool offStarted: false
    property real fxTime: 0
    property real cardIn: 0          // placa de título
    property real uiIn: 1
    FrameAnimation {
        running: root.shown && (root.tube < 1 || root.phase !== "ui" || root.closing || root.staticAmt > 0 || root.barsAmt > 0)
        onTriggered: root.fxTime += frameTime
    }
    function startOff() {
        if (offStarted) return;
        offStarted = true;
        Quickshell.execDetached(["hyprctl", "dispatch", "riceShaderHold(true)"]);
        // si veníamos del modo consola, ya está en la foto: que desaparezca
        if (fromConsole) Quickshell.execDetached(["qs", "-c", "rice-console", "ipc", "call", "console", "handoff"]);
        sfx.play("off");
        offAnim.restart();
    }
    Timer { id: offFallback; interval: 600; onTriggered: root.startOff() }
    SequentialAnimation {
        id: offAnim
        NumberAnimation { target: root; property: "deskPow"; to: 0; duration: 560 }
        PauseAnimation { duration: 120 }
        ScriptAction { script: Quickshell.execDetached(["sh", "-c", 'hyprctl dispatch "riceCine(true)" && hyprctl dispatch "riceShaderHold(false)"']) }
        PauseAnimation { duration: 160 }
        ScriptAction { script: { root.phase = "boot"; sfx.play("open"); openAnim.restart(); } }
    }
    SequentialAnimation {
        id: openAnim
        ScriptAction { script: { root.tube = 0; root.uiIn = 0; root.cardIn = 0; root.staticAmt = 1; root.barsAmt = 0; } }
        NumberAnimation { target: root; property: "tube"; to: 1; duration: 520 }          // se prende: nieve
        PauseAnimation { duration: 260 }
        NumberAnimation { target: root; property: "barsAmt"; to: 1; duration: 90 }        // sintoniza: barras
        ScriptAction { script: root.staticAmt = 0 }
        PauseAnimation { duration: 650 }
        ScriptAction { script: { root.barsAmt = 0; root.staticAmt = 1; sfx.play("tick"); } }
        PauseAnimation { duration: 140 }
        ScriptAction { script: { root.staticAmt = 0; root.cardIn = 1; } }                 // placa de título
        PauseAnimation { duration: 1100 }
        ScriptAction { script: { root.staticAmt = 0.8; root.cardIn = 0; } }
        PauseAnimation { duration: 90 }
        ScriptAction { script: {
            root.phase = "ui"; root.uiIn = 1;
            root.osdOn = true; osdTimer.restart();
            root.attachSession();
            Quickshell.execDetached(["hyprctl", "dispatch", "riceCursorHide(false)"]);
        } }
        NumberAnimation { target: root; property: "staticAmt"; to: 0; duration: 320; easing.type: Easing.InQuad }
    }
    SequentialAnimation {
        id: closeAnim
        NumberAnimation { target: root; property: "staticAmt"; to: 1; duration: 120 }
        NumberAnimation { target: root; property: "tube"; to: 0; duration: 420 }
        ScriptAction { script: {
            Quickshell.execDetached(["sh", "-c", 'hyprctl dispatch "riceCine(false)"; hyprctl dispatch "riceShaderHold(true)"']);
            root.deskPow = 0; root.closing = true; root.staticAmt = 0;
        } }
        PauseAnimation { duration: 140 }
        NumberAnimation { target: root; property: "deskPow"; to: 1; duration: 800 }
        ScriptAction { script: Quickshell.execDetached(["hyprctl", "dispatch", "riceShaderHold(false)"]) }
        PauseAnimation { duration: 50 }
        ScriptAction { script: { root.shown = false; root.closing = false; } }
    }

    SystemClock { id: clock; precision: SystemClock.Seconds }
    Sfx { id: sfx; names: ["nav", "select", "back", "open", "close", "error", "off", "tick"] }
    Timer { interval: 4500; running: root.toast !== ""; onTriggered: root.toast = "" }

    // ── Pantalla ────────────────────────────────────────────────────────────
    Window {
        id: win
        // una ventana propia a pantalla completa (antes: capa de Hyprland encima de todo)
        title: "Sintonía"
        color: "black"
        // al cerrarse la tele, la app termina
        onClosing: App.quit()

        // ── El video (mpv adentro de la app, abajo de todo: lo demás va encima) ──
        MpvVideo {
            id: video
            anchors.fill: parent
            visible: activo
        }

        // ── Fondo: la imagen del título elegido, a pantalla completa ──
        // (SINTONÍA: va DEBAJO de la capa con el filtro de tele, así la imagen se
        // ve tal cual; el filtro solo toca textos, botones y marcos)
        Item {
            id: backdrop
            anchors.fill: parent
            visible: stage.visible && !root.playFull

            opacity: root.uiIn
            property string src: root.current?.background ?? ""
            property bool flip: false
            onSrcChanged: bgDebounce.restart()
            Timer {
                id: bgDebounce; interval: 200
                onTriggered: {
                    backdrop.flip = !backdrop.flip;
                    (backdrop.flip ? bgB : bgA).source = backdrop.src;
                }
            }
            Image {
                id: bgA
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 1920
                opacity: !backdrop.flip && status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
            }
            Image {
                id: bgB
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 1920
                opacity: backdrop.flip && status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 700; easing.type: Easing.InOutQuad } }
            }
            NumberAnimation on scale { from: 1.0; to: 1.05; duration: 50000; loops: Animation.Infinite; easing.type: Easing.InOutSine; running: root.shown }
        }
        Item {
            id: stage
            anchors.fill: parent
            visible: root.phase !== "off"
            focus: true
            // Siempre pasa por un shader: el ojo de pez del monitor (curve.frag) o,
            // mientras se prende/apaga, el tubo (crtfx). Durante la película no
            // (la carcasa negra taparía los bordes del video).
            layer.enabled: root.tube < 1 || !root.playFull
            layer.mipmap: true
            layer.samplerName: "src"
            layer.effect: ShaderEffect {
                property real time: root.tube < 1 ? root.fxTime : root.grainTime   // tubo / ruido de imagen
                property real power: root.tube
                property real glitch: 0.15 + 0.5 * (1 - root.tube)
                property real amount: 0.8
                property real bloomAmt: 0.45
                property real expo: 1.0
                property real sat: 1.0
                property real style: 0
                property size res: Qt.size(width, height)
                // filtro completo (cinecrt): portadas limpias según la máscara
                property real keep: 0.35
                property real strength: root.cs.crt ?? 1
                property color dark: root.plat.ramp[0]
                property color light: root.plat.ramp[1]
                property var mask: maskTex
                fragmentShader: root.tube < 1 ? App.url("shaders/crtfx.frag.qsb")
                                              : App.url("shaders/cinecrt.frag.qsb")
            }

            HoverHandler { onPointChanged: root.mouseMoved(point.scenePosition) }
            Keys.onPressed: (e) => {
                const k = e.key;
                root.usingKb();
                if (root.playKey(e)) { e.accepted = true; return; }
                if (k === Qt.Key_Comma) { root.openSettings(); e.accepted = true; return; }
                if (k === Qt.Key_Slash || k === Qt.Key_F) {   // F, Ctrl+F o / = buscar
                    root.openSearch(); e.accepted = true; return;
                }
                if (k >= Qt.Key_1 && k <= Qt.Key_1 + root.platforms.length - 1 && !root.pickerOpen) {
                    root.switchPlatform(root.platforms[k - Qt.Key_1].id); e.accepted = true; return;
                }
                if (k === Qt.Key_Left || k === Qt.Key_A)  root.navigate("left");
                else if (k === Qt.Key_Right || k === Qt.Key_D) root.navigate("right");
                else if (k === Qt.Key_Up || k === Qt.Key_W)    root.navigate("up");
                else if (k === Qt.Key_Down || k === Qt.Key_S)  root.navigate("down");
                else if (k === Qt.Key_Return || k === Qt.Key_Enter || k === Qt.Key_Space) root.button("a");
                else if (k === Qt.Key_Escape || k === Qt.Key_Backspace) root.button("b");
                else if (k === Qt.Key_Q) root.button("lb");
                else if (k === Qt.Key_E || k === Qt.Key_Tab) root.button("rb");
                else if (k === Qt.Key_P || k === Qt.Key_Y) root.button("y");
                else if (root.playStep === "on" && (k === Qt.Key_Plus || k === Qt.Key_Equal)) root.playerCmd("volume 5");
                else if (root.playStep === "on" && k === Qt.Key_Minus) root.playerCmd("volume -5");
                else if (root.playStep === "on" && k === Qt.Key_Z) { root.showCtrl(); root.nudgeSubs(-0.1); }
                else if (root.playStep === "on" && k === Qt.Key_X) { root.showCtrl(); root.nudgeSubs(0.1); }
                else return;
                e.accepted = true;
            }

            Rectangle {   // a la izquierda, para leer la ficha
                anchors.fill: parent
                visible: !root.playFull
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0;  color: Qt.rgba(0, 0, 0, 0.92) }
                    GradientStop { position: 0.38; color: Qt.rgba(0, 0, 0, 0.62) }
                    GradientStop { position: 0.75; color: Qt.rgba(0, 0, 0, 0.05) }
                }
            }
            Rectangle {   // abajo, para las filas
                anchors.fill: parent
                visible: !root.playFull
                gradient: Gradient {
                    GradientStop { position: 0.0;  color: Qt.rgba(0, 0, 0, 0.55) }
                    GradientStop { position: 0.14; color: "transparent" }
                    GradientStop { position: 0.45; color: "transparent" }
                    GradientStop { position: 0.62; color: Qt.rgba(0, 0, 0, 0.82) }
                    GradientStop { position: 1.0;  color: "black" }
                }
            }

            // ── Interfaz ──────────────────────────────────────────────────
            Item {
                id: ui
                anchors.fill: parent
                opacity: root.uiIn
                visible: root.uiIn > 0 && !root.playFull

                // Arriba a la izquierda: "en el aire" + canal (clic = guía)
                Row {
                    id: bug
                    anchors { left: parent.left; top: parent.top; leftMargin: 90; topMargin: 46 }
                    spacing: 16
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 12; height: 12; radius: 6
                            color: root.theme.warn
                            SequentialAnimation on opacity {
                                loops: Animation.Infinite; running: root.shown
                                NumberAnimation { to: 0.2; duration: 700 }
                                NumberAnimation { to: 1.0; duration: 700 }
                            }
                        }
                        Text { text: "EN EL AIRE"; font.family: root.mono; font.pixelSize: 15; color: root.theme.warn; anchors.verticalCenter: parent.verticalCenter }
                    }
                    Rectangle { width: 1; height: 26; color: root.theme.line; anchors.verticalCenter: parent.verticalCenter }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "CH " + root.plat.ch
                        font.family: root.mono; font.pixelSize: 17
                        color: root.theme.dim
                    }
                    EvaText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.plat.name
                        size: 34
                        color: root.theme.hi
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.plat.kana + "  ▾"
                        font.family: root.sans; font.pixelSize: 16
                        color: root.theme.dim
                    }
                    TapHandler { onTapped: root.button("y") }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }

                // Secciones (LB / RB), o la búsqueda
                Row {
                    anchors { horizontalCenter: parent.horizontalCenter; verticalCenter: bug.verticalCenter }
                    spacing: 44
                    visible: !root.searchActive
                    Repeater {
                        model: root.tabs
                        Item {
                            required property var modelData
                            readonly property bool on: root.tab === modelData[0]
                            width: tabTxt.implicitWidth; height: 40
                            Text {
                                id: tabTxt
                                anchors.centerIn: parent
                                text: parent.modelData[1]
                                font.family: root.sans; font.pixelSize: 22; font.weight: parent.on ? Font.Bold : Font.Normal
                                font.letterSpacing: 3
                                color: parent.on ? root.theme.hi : root.theme.dim
                            }
                            Rectangle {
                                anchors { horizontalCenter: parent.horizontalCenter; top: tabTxt.bottom; topMargin: 4 }
                                width: parent.on ? tabTxt.implicitWidth : 0; height: 3
                                color: root.theme.hi
                                Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                            }
                            TapHandler { onTapped: root.setTab(parent.modelData[0]) }
                            HoverHandler { cursorShape: Qt.PointingHandCursor }
                        }
                    }
                }

                // Arriba a la derecha: buscar + hora
                Row {
                    anchors { right: parent.right; rightMargin: 90; verticalCenter: bug.verticalCenter }
                    spacing: 28
                    // Botón BUSCAR. El filtro de tele (ojo de pez) dibuja esta esquina
                    // ~40 px a la izquierda y ~26 px más abajo de donde está de verdad:
                    // la zona de clic se agranda para cubrir lo que se VE y lo real.
                    Rectangle {
                        id: searchBtn
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.plat.external
                        width: searchRow.implicitWidth + 32; height: 42; radius: 21
                        color: searchHit.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.04)
                        border.width: 1
                        border.color: searchHit.containsMouse ? root.theme.hi : root.theme.line
                        Row {
                            id: searchRow
                            anchors.centerIn: parent
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "\u{f002}"
                                font.family: root.mono; font.pixelSize: 20
                                color: root.theme.hi
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "BUSCAR"
                                font.family: root.sans; font.pixelSize: 17; font.weight: Font.Bold
                                font.letterSpacing: 2
                                color: root.theme.hi
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "F"
                                font.family: root.mono; font.pixelSize: 14
                                color: root.theme.dim
                            }
                        }
                        MouseArea {
                            id: searchHit
                            anchors { fill: parent; leftMargin: -60; rightMargin: -12; topMargin: -16; bottomMargin: -40 }
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.searchActive ? root.closeSearch() : root.openSearch()
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Qt.formatDateTime(clock.date, "hh:mm")
                        font.family: root.mono; font.pixelSize: 26
                        color: root.theme.hi
                    }
                }

                // ── Ficha del título elegido ──────────────────────────────
                Column {
                    id: hero
                    visible: root.tab !== "letterboxd"
                    anchors { left: parent.left; leftMargin: 90; bottom: rowsView.top; bottomMargin: 34 }
                    width: parent.width * 0.46
                    spacing: 14
                    Image {
                        id: heroLogo
                        source: root.info?.logo ?? ""
                        visible: status === Image.Ready
                        height: 150
                        width: Math.min(640, implicitWidth * height / Math.max(1, implicitHeight))
                        fillMode: Image.PreserveAspectFit
                        horizontalAlignment: Image.AlignLeft
                        sourceSize.height: 300
                        asynchronous: true
                    }
                    EvaText {
                        visible: !heroLogo.visible && root.info?.type !== "video"
                        text: (root.info?.name ?? "").toUpperCase()
                        size: 92
                        maxWidth: hero.width
                        color: root.theme.hi
                    }
                    Text {
                        visible: root.info?.type === "video"
                        width: hero.width
                        text: root.info?.name ?? ""
                        wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight
                        font.family: root.sans; font.pixelSize: 44; font.weight: Font.Black
                        color: root.theme.hi
                        lineHeight: 1.05
                    }
                    Text {
                        text: root.metaLine(root.info)
                        font.family: root.sans; font.pixelSize: 21; font.weight: Font.Medium
                        color: root.theme.fg
                    }
                    Text {
                        width: parent.width
                        text: root.info?.description ?? ""
                        wrapMode: Text.WordWrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        font.family: root.sans; font.pixelSize: 20
                        color: Qt.rgba(1, 1, 1, 0.82)
                        lineHeight: 1.2
                    }
                    Row {
                        visible: (root.info?.offset ?? 0) > 0
                        spacing: 16
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 300; height: 6; radius: 3; color: Qt.rgba(1, 1, 1, 0.18)
                            Rectangle { height: parent.height; radius: 3; width: parent.width * Math.max(0.02, root.info?.progress ?? 0); color: root.theme.hi }
                        }
                        Text {
                            text: (root.info?.season > 0 ? "T" + root.info.season + " · E" + root.info.episode + "    " : "")
                                  + "quedan " + root.fmtTime(Math.max(0, (root.info?.duration ?? 0) - (root.info?.offset ?? 0)))
                            font.family: root.sans; font.pixelSize: 17
                            color: root.theme.fg
                        }
                    }
                }

                // ── Carruseles ─────────────────────────────────────────────
                ListView {
                    id: rowsView
                    visible: root.tab !== "letterboxd"
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: parent.height * 0.47
                    Behavior on height { NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                    clip: true
                    interactive: false
                    model: root.rows
                    currentIndex: root.rowIndex
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: 0
                    preferredHighlightEnd: 330
                    highlightMoveDuration: 280
                    transform: Translate { y: root.bumpY }
                    delegate: Item {
                        id: rowItem
                        required property var modelData
                        required property int index
                        readonly property bool focused: index === root.rowIndex
                        width: rowsView.width; height: 330
                        Row {
                            id: rowHead
                            x: 90; y: 10
                            spacing: 16
                            EvaText {
                                text: rowItem.modelData.title
                                size: 36
                                color: rowItem.focused ? root.theme.hi : root.theme.dim
                            }
                            Text {
                                anchors.bottom: parent.bottom; anchors.bottomMargin: 6
                                text: rowItem.modelData.loading ? "sintonizando…" : String(rowItem.modelData.items.length).padStart(2, "0")
                                font.family: root.mono; font.pixelSize: 16
                                color: root.theme.dim
                            }
                        }
                        ListView {
                            id: cards
                            objectName: "cards"
                            anchors { left: parent.left; right: parent.right; top: rowHead.bottom; topMargin: 18 }
                            height: 245
                            orientation: ListView.Horizontal
                            spacing: 24
                            leftMargin: 90; rightMargin: 90
                            interactive: false
                            model: rowItem.modelData.items
                            currentIndex: Math.min(root.colOf(rowItem.modelData.id), Math.max(0, count - 1))
                            highlightRangeMode: ListView.ApplyRange
                            preferredHighlightBegin: 90
                            preferredHighlightEnd: width - 520
                            highlightMoveDuration: 240
                            transform: Translate { x: rowItem.focused ? root.bumpX : 0 }
                            // positionViewAt… ignora el margen izquierdo: al principio, a mano
                            Component.onCompleted: if (currentIndex === 0) contentX = originX - leftMargin; else positionViewAtIndex(currentIndex, ListView.Contain)
                            onCountChanged: if (currentIndex === 0) contentX = originX - leftMargin
                            delegate: Card {
                                required property var modelData
                                required property int index
                                objectName: "card"
                                item: modelData
                                width: 400; height: 225
                                y: 10
                                theme: root.theme
                                rowFocused: rowItem.focused
                                selected: rowItem.focused && index === root.col && !root.epOpen && !root.pickerOpen
                                hover: root.mouseMode && cardMa.containsMouse
                                MouseArea {
                                    id: cardMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    // pasar el mouse por encima NO elige la tarjeta (solo el clic)
                                    onClicked: (m) => {
                                        if (m.button === Qt.RightButton) { root.mouseBack(); return; }
                                        root.rowIndex = rowItem.index; root.focusRowId = rowItem.modelData.id;
                                        root.setCol(rowItem.modelData.id, parent.index);
                                        root.openSheet();
                                    }
                                }
                            }
                            Text {
                                x: 90; y: 90
                                visible: rowItem.modelData.loading
                                text: "▒▒▒  SINTONIZANDO SEÑAL…"
                                font.family: root.mono; font.pixelSize: 18
                                color: root.theme.dim
                            }
                        }
                    }
                }
                // Ruedita del mouse: arriba/abajo = filas; Shift o de costado = dentro
                // de la fila. Solo atiende la rueda: los clics y el hover pasan.
                MouseArea {
                    anchors.fill: parent
                    z: 5
                    acceptedButtons: Qt.NoButton
                    property real acc: 0
                    property real accX: 0
                    onWheel: (w) => {
                        const horiz = (w.modifiers & Qt.ShiftModifier) || Math.abs(w.angleDelta.x) > Math.abs(w.angleDelta.y);
                        const d = horiz ? (w.angleDelta.x || w.angleDelta.y) : w.angleDelta.y;
                        if (horiz) accX += d; else acc += d;
                        while (Math.abs(acc) >= 120) { root.navigate(acc > 0 ? "up" : "down"); acc -= Math.sign(acc) * 120; }
                        while (Math.abs(accX) >= 120) { root.navigate(accX > 0 ? "left" : "right"); accX -= Math.sign(accX) * 120; }
                        // modo mouse apagado: el puntero quieto no vuelve a elegir lo que la
                        // fila hace pasar por debajo (vuelve recién si el mouse se mueve de verdad)
                        root.mouseMode = false;
                        root.lastMouse = Qt.point(-1, -1);
                    }
                }
                Text {
                    anchors.centerIn: rowsView
                    visible: root.rows.length === 0 && root.tab !== "letterboxd"
                    text: root.loginError || "Sin señal"
                    font.family: root.sans; font.pixelSize: 24
                    color: root.loginError ? root.theme.warn : root.theme.dim
                }

                // Ayuda de botones (abajo a la derecha, sobre una pastilla para leerse arriba de las portadas)
                Rectangle {
                    anchors { fill: helpTxt; margins: -8; leftMargin: -14; rightMargin: -14 }
                    visible: helpTxt.text !== "" && !root.sheetOpen && root.padMode
                    radius: height / 2
                    color: Qt.rgba(0, 0, 0, 0.72)
                    border.width: 1; border.color: root.theme.line
                }
                Text {
                    id: helpTxt
                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: 104; bottomMargin: 26 }
                    visible: !root.sheetOpen && root.padMode
                    text: root.pickerOpen ? "A SINTONIZAR   B VOLVER"
                        : root.epOpen ? "A REPRODUCIR   ◀ ▶ TEMPORADA   B VOLVER"
                        : root.sheetOpen ? "A ELEGIR   B VOLVER"
                        : root.searchActive ? ""
                        : root.tab === "letterboxd" ? "A ELEGIR   B SALIR   LB/RB SECCIÓN   Y CANALES   X BUSCAR EN TU LISTA"
                        : "A ELEGIR   B SALIR   LB/RB SECCIÓN   Y CANALES   X BUSCAR"
                    font.family: root.mono; font.pixelSize: 14; font.letterSpacing: 1
                    color: root.theme.dim
                }

                LbLayer { id: lbLayer; anchors.fill: parent; cine: root }
                SearchLayer { id: searchLayer; anchors.fill: parent; cine: root }
                AboutLayer { anchors.fill: parent; cine: root }
                PersonLayer { anchors.fill: parent; cine: root }

                // ── Menú de abajo (al elegir un título) ────────────────────
                Rectangle {
                    id: sheet
                    anchors { left: parent.left; right: parent.right }
                    height: 170
                    y: root.sheetOpen ? parent.height - height : parent.height + 10
                    Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0.93) }
                        GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.98) }
                    }
                    Rectangle {   // fundido hacia arriba, para que no corte en seco
                        anchors { left: parent.left; right: parent.right; bottom: parent.top }
                        height: 90
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0.93) }
                        }
                    }
                    Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 2; color: root.theme.hi; opacity: 0.6 }
                    Row {
                        anchors { left: parent.left; leftMargin: 90; verticalCenter: parent.verticalCenter }
                        spacing: 20
                        Repeater {
                            model: root.sheetOpen ? root.actions(root.info) : []
                            Rectangle {
                                required property var modelData
                                required property int index
                                readonly property bool on: index === root.sheetIndex
                                width: Math.max(220, act.implicitWidth + 56); height: 76; radius: 38
                                color: on ? root.theme.hi : Qt.rgba(1, 1, 1, 0.06)
                                border.color: on ? root.theme.hi : root.theme.line
                                border.width: 2
                                scale: on ? 1.05 : 1
                                Behavior on scale { NumberAnimation { duration: 140 } }
                                Column {
                                    id: act
                                    anchors.centerIn: parent
                                    spacing: 2
                                    Row {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        spacing: 12
                                        Text {   // ícono: siempre con la fuente de íconos y del mismo tamaño
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 26
                                            horizontalAlignment: Text.AlignHCenter
                                            text: modelData.glyph
                                            font.family: root.mono; font.pixelSize: 24
                                            color: on ? root.theme.bg : root.theme.fg
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: modelData.label
                                            font.family: root.sans; font.pixelSize: 21; font.weight: Font.Bold
                                            color: on ? root.theme.bg : root.theme.fg
                                        }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        visible: !!modelData.note
                                        text: modelData.note ?? ""
                                        font.family: root.sans; font.pixelSize: 14
                                        color: on ? root.theme.deep : root.theme.dim
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPositionChanged: (m) => { if (root.mouseMode && root.realMove(parent, m)) root.sheetIndex = index }
                                    onClicked: root.doAction(root.info, modelData.id)
                                }
                            }
                        }
                    }
                }

                // ── Episodios ──────────────────────────────────────────────
                Rectangle {
                    anchors.fill: parent
                    visible: root.epOpen
                    color: Qt.rgba(0, 0, 0, 0.9)
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (m) => { if (m.button === Qt.RightButton) root.mouseBack(); }
                        onWheel: (w) => root.navigate(w.angleDelta.y > 0 ? "up" : "down")
                    }
                    EvaText {
                        id: epTitle
                        anchors { left: parent.left; leftMargin: 120; top: parent.top; topMargin: 120 }
                        text: (root.epInfo?.name ?? "").toUpperCase()
                        size: 64
                        maxWidth: parent.width - 240
                        color: root.theme.hi
                    }
                    Row {
                        id: seasonRow
                        anchors { left: epTitle.left; top: epTitle.bottom; topMargin: 22 }
                        spacing: 14
                        Repeater {
                            model: root.seasons
                            Rectangle {
                                required property var modelData
                                readonly property bool on: modelData === root.epSeason
                                width: st.implicitWidth + 30; height: 40; radius: 20
                                color: on ? root.theme.hi : "transparent"
                                border.color: on ? root.theme.hi : root.theme.line
                                border.width: 2
                                Text {
                                    id: st
                                    anchors.centerIn: parent
                                    text: "Temporada " + parent.modelData
                                    font.family: root.sans; font.pixelSize: 17; font.weight: Font.Medium
                                    color: parent.on ? root.theme.bg : root.theme.fg
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: { root.epSeason = parent.modelData; root.epIndex = 0; } }
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !root.epInfo?.videos
                        text: "▒▒▒  SINTONIZANDO EPISODIOS…"
                        font.family: root.mono; font.pixelSize: 20
                        color: root.theme.dim
                    }
                    ListView {
                        id: epList
                        transform: Translate { y: root.bumpY }
                        anchors { left: epTitle.left; right: parent.right; rightMargin: 120; top: seasonRow.bottom; topMargin: 30; bottom: parent.bottom; bottomMargin: 80 }
                        clip: true
                        spacing: 14
                        model: root.episodes
                        currentIndex: root.epIndex
                        highlightRangeMode: ListView.ApplyRange
                        preferredHighlightBegin: 40; preferredHighlightEnd: height - 180
                        highlightMoveDuration: 200
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool on: index === root.epIndex
                            readonly property bool resume: modelData.id === root.epShow?.videoId
                            width: epList.width; height: 150; radius: 8
                            color: on ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                            border.color: on ? root.theme.hi : "transparent"
                            border.width: 2
                            Text {
                                id: epNum
                                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                                width: 60
                                text: modelData.episode
                                font.family: root.mono; font.pixelSize: 34
                                color: on ? root.theme.hi : root.theme.line
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Image {
                                id: thumb
                                anchors { left: epNum.right; leftMargin: 16; verticalCenter: parent.verticalCenter }
                                width: 224; height: 126
                                source: modelData.thumb
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 448
                            }
                            Column {
                                anchors { left: thumb.right; leftMargin: 24; right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                                spacing: 8
                                Text {
                                    width: parent.width; elide: Text.ElideRight
                                    text: (modelData.name || "Episodio " + modelData.episode) + (resume ? "    ◀ acá quedaste" : "")
                                    font.family: root.sans; font.pixelSize: 22; font.weight: Font.Bold
                                    color: on ? root.theme.hi : root.theme.fg
                                }
                                Text {
                                    width: parent.width
                                    text: modelData.overview
                                    wrapMode: Text.WordWrap; maximumLineCount: 2; elide: Text.ElideRight
                                    font.family: root.sans; font.pixelSize: 17
                                    color: Qt.rgba(1, 1, 1, 0.7)
                                }
                                Text {
                                    text: modelData.released
                                    font.family: root.mono; font.pixelSize: 13
                                    color: root.theme.line
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onPositionChanged: (m) => { if (root.mouseMode && root.realMove(parent, m)) root.epIndex = index }
                                onClicked: { root.epIndex = index; root.playEpisode(modelData); }
                            }
                        }
                    }
                }

                // ── Guía de canales ────────────────────────────────────────
                Rectangle {
                    anchors.fill: parent
                    visible: root.pickerOpen
                    color: Qt.rgba(0, 0, 0, 0.82)
                    MouseArea { anchors.fill: parent; onClicked: root.pickerOpen = false }
                    Column {
                        anchors.centerIn: parent
                        spacing: 10
                        Text {
                            text: "GUÍA DE CANALES"
                            font.family: root.mono; font.pixelSize: 16; font.letterSpacing: 4
                            color: root.theme.dim
                        }
                        Item { width: 1; height: 10 }
                        Repeater {
                            model: root.platforms
                            Item {
                                required property var modelData
                                required property int index
                                readonly property bool on: index === root.pickerIndex
                                width: 760; height: 86
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: parent.on ? parent.modelData.colors.deep : "transparent"
                                    border.color: parent.on ? parent.modelData.colors.hi : "transparent"
                                    border.width: 2
                                }
                                Text {
                                    id: chNum
                                    anchors { left: parent.left; leftMargin: 26; verticalCenter: parent.verticalCenter }
                                    text: parent.modelData.ch
                                    font.family: root.mono; font.pixelSize: 34
                                    color: parent.modelData.colors.dim
                                }
                                EvaText {
                                    anchors { left: chNum.right; leftMargin: 28; verticalCenter: parent.verticalCenter }
                                    text: parent.modelData.name
                                    size: parent.on ? 54 : 44
                                    color: parent.modelData.colors.fg
                                }
                                Text {
                                    anchors { right: parent.right; rightMargin: 26; verticalCenter: parent.verticalCenter }
                                    text: parent.modelData.kana + (parent.modelData.id === root.platform ? "   ● EN EL AIRE" : "")
                                    font.family: root.sans; font.pixelSize: 17
                                    color: parent.modelData.colors.dim
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onPositionChanged: (m) => { if (root.mouseMode && root.realMove(parent, m)) root.pickerIndex = parent.index }
                                    onClicked: { root.pickerIndex = parent.index; root.button("a"); }
                                }
                            }
                        }
                    }
                }

                // Número de canal, como el de una tele (al prender y al cambiar)
                Column {
                    anchors { right: parent.right; top: parent.top; rightMargin: 90; topMargin: 110 }
                    opacity: root.osdOn ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: 300 } }
                    Text {
                        anchors.right: parent.right
                        text: "CH " + root.plat.ch
                        font.family: root.mono; font.pixelSize: 64
                        color: root.theme.hi
                        style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.7)
                    }
                    Text {
                        anchors.right: parent.right
                        text: root.plat.name + "  " + root.plat.kana
                        font.family: root.mono; font.pixelSize: 20
                        color: root.theme.fg
                        style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.7)
                    }
                }

                // Avisos
                Rectangle {
                    z: 50
                    anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 110 }
                    visible: root.toast !== ""
                    width: toastTxt.implicitWidth + 50; height: 50; radius: 25
                    color: Qt.rgba(0, 0, 0, 0.88)
                    border.color: root.theme.hi; border.width: 2
                    Text {
                        id: toastTxt
                        anchors.centerIn: parent
                        text: root.toast
                        font.family: root.sans; font.pixelSize: 18; font.weight: Font.Medium
                        color: root.theme.hi
                    }
                }
            }

            // Ruido de imagen encima de la película: APAGADO (2026-11-15, el dueño: "el modo cine SIEMPRE
            // tiene ruido, incluso cuando estoy viendo la película"). La película se ve limpia.
            ShaderEffect {
                anchors.fill: parent
                visible: false
                property size res: Qt.size(width, height)
                property real time: root.grainTime
                property real amount: 0.09 * (root.cs.crt ?? 1)
                fragmentShader: App.url("shaders/grain.frag.qsb")
            }
            PlayerLayer { anchors.fill: parent; cine: root }
            ReviewLayer { id: reviewLayer; anchors.fill: parent; cine: root }

            // ── Placa de título (al prender), estilo Evangelion ───────────
            Rectangle {
                anchors.fill: parent
                color: "black"
                visible: root.cardIn > 0
                Column {
                    anchors { left: parent.left; leftMargin: parent.width * 0.12; verticalCenter: parent.verticalCenter }
                    spacing: 6
                    EvaText { text: "映画モード"; size: 120; squeeze: 0.9; color: "white" }
                    EvaText { text: "MODO CINE"; size: 150; color: "white" }
                    Item { width: 1; height: 18 }
                    EvaText { text: "CANAL " + root.plat.ch + ":  " + root.plat.name; size: 58; color: "white" }
                }
            }

            // Número de canal sobre las barras de color (al sintonizar)
            Text {
                z: 2
                visible: root.barsAmt > 0
                anchors { right: parent.right; top: parent.top; rightMargin: 90; topMargin: 70 }
                text: "CH " + root.plat.ch
                font.family: root.mono; font.pixelSize: 72
                color: "white"
                style: Text.Outline; styleColor: "black"
            }

            // Nieve / barras encima de todo
            ShaderEffect {
                anchors.fill: parent
                z: 1
                visible: root.staticAmt > 0 || root.barsAmt > 0
                property real time: root.fxTime
                property real noise: root.staticAmt
                property real bars: root.barsAmt
                property size res: Qt.size(width, height)
                fragmentShader: App.url("shaders/tvstatic.frag.qsb")
            }
        }

        // Máscara de portadas para el filtro (blanco = portada limpia). No se ve:
        // la lee cinecrt.frag. Se actualiza cada cuadro (si algo cambió), así
        // acompaña a las filas cuando se mueven.
        Rectangle {
            id: maskRoot
            width: win.width; height: win.height
            color: "black"
            Repeater {
                model: root.maskRects
                Rectangle {
                    required property var modelData
                    x: modelData[0]; y: modelData[1]; width: modelData[2]; height: modelData[3]
                    radius: 6
                    color: "white"
                }
            }
        }
        ShaderEffectSource { id: maskTex; sourceItem: maskRoot; hideSource: true; live: true; visible: false }

        // Foto de la pantalla (se saca al entrar): en la fase "off" se apaga
        // como un tubo, y al salir se vuelve a prender antes de mostrar la real
        Loader {
            anchors.fill: parent
            active: root.shown
            visible: root.phase === "off" || root.closing
            sourceComponent: Item {
                MouseArea { anchors.fill: parent; cursorShape: Qt.BlankCursor; visible: root.phase === "off" }
                Rectangle {
                    id: shot
                    anchors.fill: parent
                    color: "black"
                    Component.onCompleted: root.startOff()
                }
                ShaderEffectSource { id: shotTex; sourceItem: shot; hideSource: true; mipmap: true; smooth: true; visible: false }
                ShaderEffect {
                    anchors.fill: parent
                    visible: root.offStarted || root.closing
                    property var src: shotTex
                    property real time: root.fxTime
                    property real power: root.deskPow
                    property real glitch: 0.15 + 0.5 * (1 - root.deskPow)
                    property real amount: 0.8
                    property real bloomAmt: 0.0
                    property real expo: 1.0
                    property real sat: 1.0
                    property real style: 0
                    property size res: Qt.size(width, height)
                    fragmentShader: App.url("shaders/crtfx.frag.qsb")
                }
            }
        }

        // ── Fiestas, CONFIGURACIÓN y el navegador para las cuentas (encima de todo) ──
        Fiestas {
            id: fiestas
            anchors.fill: parent
            on: root.cs.fiestas ?? true
            preview: root.fiestaPreview
            hidden: root.playFull || root.phase !== "ui" || webLogin.open
        }
        SettingsLayer { id: settingsLayer; anchors.fill: parent; cine: root }
        WebLogin {
            id: webLogin
            anchors.fill: parent
            cine: root
            onListo: (s, u) => settingsLayer.webLoggedIn(s, u)
        }
    }

    // ── Textos ──────────────────────────────────────────────────────────────
    // "2019 · Serie · ★ 7.8 · 122 min · Drama, Suspenso"
    function metaLine(it) {
        if (!it) return "";
        const parts = [];
        if (it.type === "video") {
            if (it.channel) parts.push(it.channel);
            if (it.runtime) parts.push(it.runtime);
            if (it.views) parts.push(it.views >= 1e6 ? (it.views / 1e6).toFixed(1).replace(".", ",") + " M vistas"
                                     : it.views >= 1e3 ? Math.round(it.views / 1e3) + " mil vistas" : it.views + " vistas");
            if (it.year) parts.push(it.year);
            return parts.join("   ·   ");
        }
        if (it.year) parts.push(it.year);
        if (it.type === "series") parts.push("Serie");
        if (it.rating) parts.push("★ " + it.rating);
        if (it.runtime) parts.push(String(it.runtime));
        const g = (it.genres ?? []).slice(0, 3).map(x => genreEs[x] ?? x);
        if (g.length) parts.push(g.join(", "));
        return parts.join("   ·   ");
    }
    // milisegundos → "1 h 05 min" o "42 min"
    function fmtTime(ms) {
        const m = Math.round((ms || 0) / 60000);
        return m >= 60 ? Math.floor(m / 60) + " h " + String(m % 60).padStart(2, "0") + " min" : m + " min";
    }
}
