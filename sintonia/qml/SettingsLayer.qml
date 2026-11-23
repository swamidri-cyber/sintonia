// ─────────────────────────────────────────────────────────────────────────────
//  CONFIGURACIÓN (設定) de SINTONÍA — el mismo menú que rice-settings, adentro
//  de la app y sin lo que dependía del escritorio (monitores, brillo, sonido
//  del sistema). Botón ≡ del joystick o la tecla coma. B vuelve / cierra.
//
//  Secciones: CUENTAS (Stremio, Letterboxd), SUBTÍTULOS,
//  REPRODUCCIÓN, SONIDO, IMAGEN, FIESTAS, TEMPORIZADOR, TELÉFONO y SISTEMA.
//  La primera vez que se abre la app, es la BIENVENIDA (abre en CUENTAS).
//
//  Guarda en <config>/settings.json (lo lee el cine y player.py) y
//  <config>/sonido.json (sonidos de la interfaz).
// ─────────────────────────────────────────────────────────────────────────────
import QtQuick
import Quickshell
import Quickshell.Io
import Sintonia

Item {
    id: st
    required property var cine
    readonly property var th: cine.theme
    readonly property string mono: cine.mono
    readonly property string sans: cine.sans

    property bool open: false
    property bool welcome: false            // primera vez: bienvenida
    property real fade: 0
    visible: fade > 0
    property int  cat: 0
    property string col: "cats"             // "cats" | "items"
    property int  idx: 0
    property string toast: ""
    Timer { id: toastTimer; interval: 3500; onTriggered: st.toast = "" }
    function say(t) { toast = t; toastTimer.restart(); }
    function sfx(n) { cine.playSfx(n); }

    // ── Archivos ───────────────────────────────────────────────────────────
    readonly property var cs: cine.cs
    property var snd: ({ enabled: true, sfx: 0.6 })
    FileView {
        id: sndFile
        path: App.configDir + "/sonido.json"
        watchChanges: true; printErrors: false
        onFileChanged: reload()
        onLoaded: { try { st.snd = Object.assign({ enabled: true, sfx: 0.6 }, JSON.parse(text())); } catch (e) {} }
    }
    function saveCine(p) {
        const n = Object.assign({}, cine.cs, p);
        cine.cs = n;
        App.writeFile(App.configDir + "/settings.json", JSON.stringify(n, null, 2) + "\n");
        cine.playerCmd("reloadcfg");          // la película que esté andando toma los cambios
    }
    function saveSnd(p) {
        snd = Object.assign({}, snd, p);
        App.writeFile(App.configDir + "/sonido.json", JSON.stringify(snd, null, 2) + "\n");
    }
    function c(k, d) { return cs[k] ?? d; }

    // ── Abrir / cerrar ─────────────────────────────────────────────────────
    function show(bienvenida) {
        if (open) return;
        welcome = !!bienvenida;
        cat = welcome ? 0 : Math.max(0, cat);
        col = welcome ? "items" : "cats";
        idx = welcome ? firstIdx() : 0;
        toast = "";
        open = true;
        cine.modal = true;
        sfx("open");
        fadeAnim.from = fade; fadeAnim.to = 1; fadeAnim.restart();
        enterCat();
    }
    function hide() {
        if (!open) return;
        if (stremioForm.visible) { stremioForm.cerrar(); return; }
        open = false;
        cine.modal = false;
        if (welcome) {
            welcome = false;
            App.writeFile(App.configDir + "/bienvenida.json", JSON.stringify({ vista: Date.now() }) + "\n");
        }
        sfx("close");
        fadeAnim.from = fade; fadeAnim.to = 0; fadeAnim.restart();
        cine.stageFocus();
        cine.refreshAll();                    // cuentas nuevas: catálogos y listas
    }
    NumberAnimation { id: fadeAnim; target: st; property: "fade"; duration: 220; easing.type: Easing.OutCubic }

    // ── Secciones ──────────────────────────────────────────────────────────
    readonly property var cats: [
        { id: "accounts", name: "CUENTAS",      kana: "口座", icon: "\u{f0004}" },
        { id: "subs",     name: "SUBTÍTULOS",   kana: "字幕", icon: "\u{f0a16}" },
        { id: "play",     name: "REPRODUCCIÓN", kana: "再生", icon: "\u{f040a}" },
        { id: "sound",    name: "SONIDO",       kana: "音響", icon: "\u{f057e}" },
        { id: "look",     name: "IMAGEN",       kana: "映像", icon: "\u{f03d8}" },
        { id: "fiestas",  name: "FIESTAS",      kana: "祭り", icon: "\u{f0f22}" },
        { id: "sleep",    name: "TEMPORIZADOR", kana: "睡眠", icon: "\u{f051b}" },
        { id: "phone",    name: "TELÉFONO",     kana: "携帯", icon: "\u{f011c}" },
        { id: "system",   name: "SISTEMA",      kana: "系統", icon: "\u{f0493}" }
    ]
    readonly property string catId: cats[cat].id
    function enterCat() {
        if (catId === "accounts") refreshAccounts();
        if (catId === "phone") newPin();
        if (catId === "system" || catId === "phone") refreshSys();
    }

    function choice(label, opts, cur, set, hint) {
        const i = Math.max(0, cur);
        return { kind: "choice", label: label, opts: opts, cur: i, value: opts[i]?.label ?? "—", set: set, hint: hint || "" };
    }
    function slider(label, v, min, max, step, fmt, set, hint) {
        return { kind: "slider", label: label, v: v, min: min, max: max, step: step, value: fmt(v), set: set, hint: hint || "" };
    }
    function toggle(label, on, set, hint) { return { kind: "toggle", label: label, on: !!on, value: on ? "SÍ" : "NO", set: set, hint: hint || "" }; }
    function action(label, note, run, hint) { return { kind: "action", label: label, value: note, run: run, hint: hint || "" }; }
    function info(label, value, hint) { return { kind: "info", label: label, value: value, hint: hint || "" }; }
    function head(label) { return { kind: "head", label: label, value: "" }; }
    function pct(v) { return Math.round(v * 100) + " %"; }

    readonly property var items: itemsFor(catId, acc, sys, cs, snd, pin, cine.fiestaPreview, nowMs)
    function itemsFor(id) {
        const out = [];
        switch (id) {
        case "accounts": {
            const s = acc.stremio ?? {};
            out.push(head("STREMIO · PELÍCULAS Y SERIES"));
            if (s.mine) out.push(action("Stremio · " + s.user, "CERRAR SESIÓN", () => stremioLogout(),
                "Tus addons, tu lista y dónde quedaste salen de tu cuenta de Stremio."));
            else if (s.logged) out.push(action("Stremio · la de la app de Stremio", "USAR OTRA", () => stremioForm.abrir(),
                "Encontré la sesión de la app de Stremio de esta compu y la estoy usando. Podés conectar tu cuenta acá directamente."));
            else out.push(action("Stremio", "CONECTAR", () => stremioForm.abrir(),
                "Con tu cuenta vienen tus addons (las fuentes para ver), tu lista y dónde quedaste. Sin cuenta solo se ven los catálogos."));
            out.push(head("LETTERBOXD"));
            const lb = acc.letterboxd ?? {};
            if (!Navegador.disponible) out.push(info("Letterboxd", "SIN NAVEGADOR", "Esta instalación no trae el navegador de adentro."));
            else if (lb.ok) out.push(action("Letterboxd" + (lb.user ? " · " + lb.user : " · conectado"), "CERRAR SESIÓN", () => webLogout("letterboxd"),
                "Tu watchlist pasa a «Mi lista» y al terminar una película podés dejar la reseña."));
            else out.push(action("Letterboxd", "CONECTAR", () => cine.openWebLogin("letterboxd"),
                "Para la pestaña LETTERBOXD, tu watchlist y las reseñas al terminar una película."));
            if (welcome) {
                out.push(head(""));
                out.push(action("Empezar a mirar", "EMPEZAR", () => hide(), "Todo esto se puede cambiar después en CONFIGURACIÓN → CUENTAS (botón ≡ o la tecla coma)."));
            }
            break;
        }
        case "subs": {
            const fonts = [{ label: "Inter", v: "Inter Medium" }, { label: "Figtree", v: "Figtree SemiBold" },
                           { label: "Atkinson Hyperlegible", v: "Atkinson Hyperlegible Next Medium" },
                           { label: "Outfit", v: "Outfit Medium" }, { label: "Plus Jakarta Sans", v: "Plus Jakarta Sans SemiBold" }];
            out.push(choice("Tipografía", fonts, fonts.findIndex(x => x.v === c("subFont", "Figtree SemiBold")), v => saveCine({ subFont: v })));
            out.push(slider("Tamaño", c("subSize", 34), 22, 50, 1, v => String(v), v => saveCine({ subSize: v })));
            out.push(slider("Altura", c("subMargin", 34), 10, 140, 4, v => String(v), v => saveCine({ subMargin: v }),
                "Qué tan arriba del borde de abajo aparecen."));
            const edges = [{ label: "Sombra suave", v: [0, 1.5] }, { label: "Contorno fino", v: [1.2, 0.6] },
                           { label: "Contorno grueso", v: [2.4, 1] }, { label: "Sin borde", v: [0, 0] }];
            const ce = edges.findIndex(x => x.v[0] === c("subOutline", 0) && x.v[1] === c("subShadow", 1.5));
            out.push(choice("Borde", edges, ce, v => saveCine({ subOutline: v[0], subShadow: v[1] })));
            const colors = [{ label: "Blanco", v: "#FFFFFF" }, { label: "Amarillo suave", v: "#FFF0A0" }, { label: "Gris claro", v: "#E2E2E2" }];
            out.push(choice("Color", colors, colors.findIndex(x => x.v === c("subColor", "#FFFFFF")), v => saveCine({ subColor: v }),
                "Todo se ve al toque en la muestra y en la peli que estés viendo."));
            break;
        }
        case "play": {
            const aud = [{ label: "Idioma original", v: "original" }, { label: "Español latino", v: "es" }];
            out.push(choice("Audio preferido", aud, aud.findIndex(x => x.v === c("prefAudio", "original")), v => saveCine({ prefAudio: v }),
                "Lo que queda marcado primero en «¿En qué idioma?»."));
            const sub = [{ label: "Automático", v: "auto" }, { label: "Siempre", v: "always" }, { label: "Nunca", v: "never" }];
            out.push(choice("Subtítulos en español", sub, sub.findIndex(x => x.v === c("prefSubs", "auto")), v => saveCine({ prefSubs: v }),
                "Automático: sí cuando el audio no es en español."));
            const q = [{ label: "Liviana · arranca rápido", v: "light" }, { label: "Equilibrada", v: "balanced" }, { label: "Máxima · 4K si hay", v: "max" }];
            out.push(choice("Calidad", q, q.findIndex(x => x.v === c("quality", "light")), v => saveCine({ quality: v }),
                "Liviana: el archivo 1080p más chico con buenas fuentes. Máxima: lo mejor que haya (tarda más en arrancar)."));
            const d = [{ label: "Preguntar siempre", v: "ask" }, { label: "Siempre en esta pantalla", v: "pc" }, { label: "Siempre en la tele", v: "tv" }];
            out.push(choice("Dónde ver", d, d.findIndex(x => x.v === c("dest", "ask")), v => saveCine({ dest: v })));
            out.push(head("SERIES"));
            out.push(toggle("Siguiente episodio solo", c("autoNext", true), v => saveCine({ autoNext: v })));
            const secs = [5, 10, 20, 30].map(x => ({ label: x + " segundos", v: x }));
            out.push(choice("Cuenta regresiva", secs, secs.findIndex(x => x.v === c("autoNextSecs", 10)), v => saveCine({ autoNextSecs: v })));
            out.push(head("AL TERMINAR UNA PELÍCULA"));
            out.push(toggle("Reseña en Letterboxd", c("review", true), v => saveCine({ review: v }),
                "La pantalla de estrellas al terminar. Siempre pregunta antes de publicar."));
            break;
        }
        case "sound": {
            out.push(head("PELÍCULAS"));
            out.push(toggle("Modo noche", c("nightMode", false), v => saveCine({ nightMode: v }),
                "Comprime los picos: las explosiones no despiertan a nadie y los diálogos se siguen escuchando. Se aplica también a la peli que estés viendo."));
            out.push(toggle("Voces más claras", c("dialogBoost", false), v => saveCine({ dialogBoost: v }),
                "Realza la banda de la voz humana. Ideal cuando la música tapa lo que dicen."));
            out.push(head("INTERFAZ"));
            out.push(toggle("Sonidos de la interfaz", snd.enabled, v => saveSnd({ enabled: v })));
            out.push(slider("Volumen de los sonidos", snd.sfx, 0, 1, 0.05, pct, v => { saveSnd({ sfx: v }); sfx("nav"); }));
            break;
        }
        case "look": {
            const crt = [{ label: "Completo", v: 1 }, { label: "Suave", v: 0.5 }, { label: "Apagado", v: 0 }];
            out.push(choice("Filtro de tubo", crt, crt.findIndex(x => x.v === c("crt", 1)), v => saveCine({ crt: v }),
                "Las líneas, el brillo en las letras y el color del canal. Las portadas y las imágenes siempre se ven limpias."));
            const intro = [{ label: "Completa", v: "full" }, { label: "Rápida", v: "quick" }];
            out.push(choice("Entrada", intro, intro.findIndex(x => x.v === c("intro", "full")), v => saveCine({ intro: v }),
                "Completa: nieve, barras y la placa del canal. Rápida: directo a los carruseles."));
            const ch = [{ label: "Stremio", v: "stremio" }, { label: "El último que viste", v: "last" }];
            out.push(choice("Canal al abrir", ch, ch.findIndex(x => x.v === c("startChannel", "stremio")), v => saveCine({ startChannel: v })));
            break;
        }
        case "fiestas": {
            out.push(toggle("Decorar en las fiestas", c("fiestas", true), v => saveCine({ fiestas: v }),
                "Unos días antes de cada fecha la interfaz se viste: lucecitas en Navidad, calabazas en Halloween, fuegos artificiales en Año Nuevo…"));
            const fs = cine.fiestaList;
            const prev = [{ label: "No (la de la fecha)", v: "" }].concat(fs.map(f => ({ label: f.nombre, v: f.id })));
            out.push(choice("Ver cómo queda", prev, prev.findIndex(x => x.v === cine.fiestaPreview), v => cine.fiestaPreview = v,
                "Una muestra ahora mismo (no se guarda: al cerrar la app vuelve a la de la fecha)."));
            out.push(head("CUÁNDO"));
            for (const f of fs) out.push(info(f.nombre, f.cuando + (f.id === cine.fiestaHoy ? "  ·  AHORA" : "")));
            break;
        }
        case "sleep": {
            const opts = [{ label: "No", v: 0 }, { label: "15 minutos", v: 15 }, { label: "30 minutos", v: 30 }, { label: "45 minutos", v: 45 },
                          { label: "1 hora", v: 60 }, { label: "1 h 30 min", v: 90 }, { label: "2 horas", v: 120 },
                          { label: "Al terminar lo que estoy viendo", v: -1 }];
            out.push(choice("Apagar", opts, opts.findIndex(x => x.v === sleepChoice), v => setSleep(v),
                "Para dormirte viendo algo. Un minuto antes te avisa por si querés seguir."));
            const what = [{ label: "Pausar", v: "pause" }, { label: "Pausar y cerrar SINTONÍA", v: "close" }];
            out.push(choice("Qué hacer", what, what.findIndex(x => x.v === c("sleepAction", "close")), v => saveCine({ sleepAction: v })));
            out.push(info("Falta", sleepLeft() || "—"));
            break;
        }
        case "phone": {
            out.push(info("Dirección", sys.ip ? "http://" + sys.ip + ":20130" : "SIN RED"));
            out.push(info("Código", pin || "…", "Escaneá el QR con la cámara del teléfono (o entrá a la dirección y poné el código). Dura 10 minutos."));
            out.push(info("Teléfonos vinculados", String(sys.phones ?? 0)));
            out.push(action("Código nuevo", "GENERAR", () => newPin()));
            out.push(action("Desvincular todos", "DESVINCULAR", () => { run(["phone.py", "forget"]); refreshSys(); say("LISTO: HAY QUE VOLVER A VINCULARLOS"); }));
            break;
        }
        case "system": {
            out.push(info("Joystick", cine.padName || "no conectado"));
            out.push(info("Red", sys.ip || "sin conexión"));
            out.push(info("Chromecast", (sys.casts ?? []).length ? sys.casts.map(x => x.name).join(", ") : "ninguno encontrado"));
            out.push(action("Buscar Chromecasts", "BUSCAR", () => { castScan.running = true; say("BUSCANDO EN LA RED…"); }));
            out.push(info("Servidor de Stremio", sys.services?.stremio ? "andando" : "apagado (arranca solo al reproducir)"));
            out.push(info("Servidor del teléfono", sys.services?.web ? "andando · puerto 20130" : "apagado"));
            out.push(info("Datos de la app", App.configDir));
            out.push(action("Volver a ver la bienvenida", "ABRIR", () => { hide(); Qt.callLater(() => show(true)); }));
            break;
        }
        }
        return out;
    }

    // ── Cuentas ────────────────────────────────────────────────────────────
    property var acc: ({})
    function run(args) { Quickshell.execDetached([App.backendDir + "/" + args[0]].concat(args.slice(1))); }
    Process {
        id: accProc
        command: [App.backendDir + "/cuentas.py", "estado"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {}; try { d = JSON.parse(text); } catch (e) {}
                st.acc = Object.assign({}, st.acc, { letterboxd: d.letterboxd ?? {} },
                                       { stremio: Object.assign({}, st.acc.stremio ?? {}, { mine: !!d.stremio?.ok, user: d.stremio?.user ?? "" }) });
            }
        }
    }
    Process {
        id: whoProc
        command: [App.backendDir + "/stremio.py", "whoami"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {}; try { d = JSON.parse(text); } catch (e) {}
                const s = Object.assign({}, st.acc.stremio ?? {}, { logged: !!d.logged, addons: d.addons ?? [] });
                if (!s.user) s.user = d.user ?? "";
                st.acc = Object.assign({}, st.acc, { stremio: s });
            }
        }
    }
    function refreshAccounts() { if (!accProc.running) accProc.running = true; if (!whoProc.running) whoProc.running = true; }
    Connections { target: Navegador; function onCambio() { if (st.open && st.catId === "accounts") accDelay.restart(); } }
    Timer { id: accDelay; interval: 600; onTriggered: st.refreshAccounts() }
    Process {
        id: logoutProc
        command: [App.backendDir + "/stremio.py", "logout"]
        onExited: { st.say("SESIÓN DE STREMIO CERRADA"); st.refreshAccounts(); }
    }
    function stremioLogout() { logoutProc.running = true; }
    function webLogout(s) { Navegador.olvidar(s); say("SESIÓN CERRADA"); refreshAccounts(); }
    function webLoggedIn(s, u) { say("LETTERBOXD CONECTADO" + (u ? " · " + u : "")); refreshAccounts(); }

    // ── Sistema / teléfono ─────────────────────────────────────────────────
    property var sys: ({})
    property string pin: ""
    property bool qrReady: false
    Process {
        id: sysProc
        command: [App.backendDir + "/sistema.py", "estado"]
        stdout: StdioCollector { onStreamFinished: { try { st.sys = JSON.parse(text); } catch (e) {} } }
    }
    function refreshSys() { if (!sysProc.running) sysProc.running = true; }
    Process { id: castScan; command: [App.backendDir + "/cast.py", "discover"]; onExited: { st.refreshSys(); st.say("LISTO"); } }
    Process {
        id: pinProc
        command: [App.backendDir + "/phone.py", "newpin"]
        stdout: StdioCollector {
            onStreamFinished: {
                st.pin = text.trim();
                st.qrReady = false;
                qrWait.restart();
            }
        }
    }
    // el QR necesita la dirección de la red: se arma cuando ya está
    Timer {
        id: qrWait; interval: 300; repeat: true
        onTriggered: {
            if (!st.sys.ip) { st.refreshSys(); return; }
            stop();
            if (!st.pin) return;
            qrProc.command = [App.backendDir + "/sistema.py", "qr", "http://" + st.sys.ip + ":20130/?pin=" + st.pin, App.runtimeDir + "/qr.svg"];
            qrProc.running = true;
        }
    }
    Process { id: qrProc; onExited: st.qrReady = true }
    function newPin() { if (!pinProc.running) pinProc.running = true; }

    // ── Temporizador ───────────────────────────────────────────────────────
    property int  sleepChoice: 0
    property real sleepAt: 0
    property bool sleepWarned: false
    property bool sleepSawPlay: false
    property real nowMs: Date.now()
    function setSleep(v) {
        sleepChoice = v; sleepWarned = false; sleepSawPlay = false;
        sleepAt = v > 0 ? Date.now() + v * 60000 : 0;
        say(v === 0 ? "TEMPORIZADOR APAGADO" : v < 0 ? "SE APAGA AL TERMINAR LO QUE ESTÁS VIENDO" : "SE APAGA EN " + v + " MINUTOS");
    }
    function sleepLeft() {
        if (sleepChoice < 0) return "al terminar lo que estás viendo";
        if (!sleepAt) return "";
        const s = Math.max(0, Math.round((sleepAt - nowMs) / 1000));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    Timer {
        interval: 1000; repeat: true; running: st.sleepChoice !== 0
        onTriggered: {
            st.nowMs = Date.now();
            if (st.sleepChoice > 0) {
                const left = st.sleepAt - st.nowMs;
                if (left < 60000 && !st.sleepWarned) { st.sleepWarned = true; st.cine.toast = "En 1 minuto se apaga (CONFIGURACIÓN → TEMPORIZADOR para seguir)"; }
                if (left <= 0) st.sleepNow();
            } else if (st.sleepChoice < 0) {
                if (st.cine.playStep === "on") st.sleepSawPlay = true;
                else if (st.sleepSawPlay) st.sleepNow();
            }
        }
    }
    function sleepNow() {
        sleepChoice = 0; sleepAt = 0;
        cine.playerCmd("pauseset 1");
        if (c("sleepAction", "close") === "close") cine.quitApp();
    }

    // ── Navegación ─────────────────────────────────────────────────────────
    function firstIdx() { for (let i = 0; i < items.length; i++) if (items[i].kind !== "head" && items[i].kind !== "info") return i; return 0; }
    function step(i, d) {
        let j = i + d;
        while (j >= 0 && j < items.length && items[j].kind === "head") j += d;
        return (j >= 0 && j < items.length) ? j : i;
    }
    function navigate(dir) {
        if (stremioForm.visible) return;
        if (col === "cats") {
            if (dir === "up" && cat > 0) { cat--; sfx("nav"); enterCat(); }
            else if (dir === "down" && cat < cats.length - 1) { cat++; sfx("nav"); enterCat(); }
            else if (dir === "right") { col = "items"; idx = firstIdx(); sfx("nav"); }
            return;
        }
        const it = items[idx];
        if (dir === "up" || dir === "down") {
            const j = step(idx, dir === "up" ? -1 : 1);
            if (j !== idx) { idx = j; sfx("nav"); }
            return;
        }
        const d = dir === "left" ? -1 : 1;
        if (it?.kind === "slider") {
            const v = Math.min(it.max, Math.max(it.min, Math.round((it.v + d * it.step) / it.step) * it.step));
            if (v !== it.v) it.set(Number(v.toFixed(3)));
            return;
        }
        if (it?.kind === "choice" && it.opts.length) {
            const j = Math.min(it.opts.length - 1, Math.max(0, it.cur + d));
            if (j !== it.cur) { sfx("nav"); it.set(it.opts[j].v); }
            return;
        }
        if (it?.kind === "toggle") { sfx("select"); it.set(!it.on); return; }
        if (dir === "left") { col = "cats"; sfx("back"); }
    }
    function button(b) {
        if (stremioForm.visible) { if (b === "b") stremioForm.cerrar(); return; }
        if (b === "menu" || b === "guide") { hide(); return; }
        if (b === "lb" || b === "rb") {
            cat = (cat + (b === "lb" ? -1 : 1) + cats.length) % cats.length;
            idx = col === "items" ? firstIdx() : 0;
            sfx("nav"); enterCat();
            return;
        }
        if (b === "b") {
            if (col === "items" && !welcome) { col = "cats"; sfx("back"); }
            else hide();
            return;
        }
        if (b !== "a") return;
        if (col === "cats") { col = "items"; idx = firstIdx(); sfx("select"); return; }
        const it = items[idx];
        if (!it) return;
        if (it.kind === "toggle") { sfx("select"); it.set(!it.on); }
        else if (it.kind === "choice" && it.opts.length) { sfx("select"); it.set(it.opts[(it.cur + 1) % it.opts.length].v); }
        else if (it.kind === "action") { sfx("select"); it.run(); }
    }
    function dbg() { return JSON.stringify({ open: open, welcome: welcome, cat: catId, col: col, idx: idx, items: items.map(i => i.label + "=" + (i.value ?? "")), acc: acc }); }

    // ── Lo que se ve ───────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        opacity: st.fade

        Rectangle { anchors.fill: parent; color: st.th.bg; opacity: 0.985 }
        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }
        Canvas {
            anchors.fill: parent
            opacity: 0.18
            onPaint: {
                const g = getContext("2d"); g.clearRect(0, 0, width, height);
                g.fillStyle = "#000"; for (let y = 0; y < height; y += 3) g.fillRect(0, y, width, 1);
            }
        }
        Text {
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 60; bottomMargin: 20 }
            text: st.welcome ? "同調" : "設定"
            font.family: st.sans; font.pixelSize: 300; font.weight: Font.Black
            color: st.th.line; opacity: 0.14
        }

        // encabezado
        Row {
            x: 110; y: 70 + (1 - st.fade) * 20
            spacing: 26
            EvaText { text: st.welcome ? "BIENVENIDO" : "CONFIGURACIÓN"; size: 92; color: st.th.hi }
            Column {
                anchors.bottom: parent.bottom; anchors.bottomMargin: 14
                spacing: 4
                Text { text: st.welcome ? "SINTONÍA 同調  ·  CONECTÁ TUS CUENTAS" : "設定  ·  SINTONÍA"; font.family: st.mono; font.pixelSize: 18; color: st.th.dim; font.letterSpacing: 3 }
                Rectangle { width: 380; height: 3; color: st.th.hi; opacity: 0.6 }
            }
        }

        // secciones (en la bienvenida, solo las cuentas)
        Column {
            x: 110; y: 230
            spacing: 6
            visible: !st.welcome
            Repeater {
                model: st.cats
                Rectangle {
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === st.cat
                    readonly property bool hot: sel && st.col === "cats"
                    width: 430; height: 66; radius: 33
                    color: hot ? st.th.hi : sel ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                    border.width: sel ? 2 : 0
                    border.color: st.th.hi
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        x: 30; anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.icon
                        font.family: st.mono; font.pixelSize: 28
                        color: parent.hot ? st.th.bg : parent.sel ? st.th.hi : st.th.dim
                    }
                    Text {
                        x: 84; anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.name
                        font.family: st.mono; font.pixelSize: 23; font.letterSpacing: 2
                        color: parent.hot ? st.th.bg : parent.sel ? st.th.hi : st.th.fg
                    }
                    Text {
                        anchors { right: parent.right; rightMargin: 30; verticalCenter: parent.verticalCenter }
                        text: parent.modelData.kana
                        font.family: st.sans; font.pixelSize: 18
                        color: parent.hot ? st.th.deep : st.th.dim
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { st.cat = parent.index; st.col = "items"; st.idx = st.firstIdx(); st.enterCat(); }
                    }
                }
            }
        }
        // bienvenida: qué es esto
        Column {
            x: 110; y: 250
            width: 430
            spacing: 18
            visible: st.welcome
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: "Películas y series en una sola pantalla, para mirar con el joystick, el teclado o el teléfono."
                font.family: st.sans; font.pixelSize: 26; font.weight: Font.Medium; lineHeight: 1.2
                color: st.th.fg
            }
            Text {
                width: parent.width; wrapMode: Text.WordWrap
                text: "Conectá las cuentas que uses. Ninguna es obligatoria."
                font.family: st.sans; font.pixelSize: 21; lineHeight: 1.2
                color: st.th.dim
            }
        }

        // panel derecho
        Item {
            id: panel
            x: 620; y: 230
            width: parent.width - x - 110
            height: parent.height - y - 150

            Item {
                id: extra
                width: parent.width
                height: st.catId === "subs" ? 330 : st.catId === "phone" ? 300 : 0
                visible: height > 0

                // subtítulos: una escena con el texto como va a salir
                Rectangle {
                    visible: st.catId === "subs"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 560; height: 315
                    radius: 12; clip: true
                    color: "black"
                    border.width: 2; border.color: st.th.line
                    Image {
                        anchors.fill: parent
                        source: st.catId === "subs" ? "https://images.metahub.space/background/medium/tt0353969/img" : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                    readonly property real k: height / 720       // mpv mide en una pantalla de 720 de alto
                    Text {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: st.c("subMargin", 34) * parent.k }
                        width: parent.width * 0.9
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        text: "Escuché que la vieja bruja\nfue senil el año pasado."
                        font.family: st.c("subFont", "Figtree SemiBold").replace(/ (Medium|SemiBold|Bold)$/, "")
                        font.weight: /SemiBold/.test(st.c("subFont", "Figtree SemiBold")) ? Font.DemiBold : Font.Medium
                        font.pixelSize: st.c("subSize", 34) * parent.k
                        color: st.c("subColor", "#FFFFFF")
                        style: st.c("subOutline", 0) > 0 ? Text.Outline : st.c("subShadow", 1.5) > 0 ? Text.Raised : Text.Normal
                        styleColor: st.c("subOutline", 0) > 0 ? "black" : Qt.rgba(0, 0, 0, 0.7)
                    }
                }
                // teléfono: el QR
                Row {
                    visible: st.catId === "phone"
                    anchors.centerIn: parent
                    spacing: 50
                    Rectangle {
                        width: 270; height: 270; radius: 14
                        color: "white"
                        Image {
                            anchors { fill: parent; margins: 14 }
                            source: st.qrReady ? App.fileUrl(App.runtimeDir + "/qr.svg") + "?" + st.pin : ""
                            sourceSize: Qt.size(480, 480)
                            smooth: false
                            cache: false
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12
                        Text { text: "CÓDIGO"; font.family: st.mono; font.pixelSize: 18; color: st.th.dim; font.letterSpacing: 4 }
                        Text { text: st.pin.split("").join(" "); font.family: st.mono; font.pixelSize: 72; color: st.th.hi }
                        Text { text: "Abrí la cámara del teléfono\ny apuntale al cuadrado."; font.family: st.sans; font.pixelSize: 20; color: st.th.fg; lineHeight: 1.2 }
                    }
                }
            }

            Rectangle {
                anchors { left: list.left; right: list.right; bottom: list.bottom }
                height: 80; z: 10
                visible: list.contentHeight > list.height && !list.atYEnd
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "transparent" }
                    GradientStop { position: 1.0; color: st.th.bg }
                }
            }
            ListView {
                id: list
                anchors { top: extra.bottom; topMargin: extra.visible ? 20 : 0; left: parent.left; right: parent.right; bottom: parent.bottom }
                model: st.items
                clip: true
                spacing: 6
                currentIndex: st.idx
                highlightMoveDuration: 140
                preferredHighlightBegin: 40; preferredHighlightEnd: height - 120
                highlightRangeMode: ListView.ApplyRange
                boundsBehavior: Flickable.StopAtBounds
                delegate: Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool sel: index === st.idx && st.col === "items"
                    readonly property var it: modelData
                    width: list.width
                    height: it.kind === "head" ? 54 : 70
                    Text {
                        visible: row.it.kind === "head"
                        anchors { left: parent.left; leftMargin: 8; bottom: parent.bottom; bottomMargin: 10 }
                        text: row.it.label
                        font.family: st.mono; font.pixelSize: 16; font.letterSpacing: 4
                        color: st.th.dim
                    }
                    Rectangle {
                        visible: row.it.kind !== "head"
                        anchors.fill: parent
                        radius: 35
                        color: row.sel ? Qt.rgba(1, 1, 1, 0.10) : Qt.rgba(1, 1, 1, 0.03)
                        border.width: row.sel ? 2 : 1
                        border.color: row.sel ? st.th.hi : st.th.line
                        Text {
                            anchors { left: parent.left; leftMargin: 34; verticalCenter: parent.verticalCenter }
                            width: parent.width * 0.5; elide: Text.ElideRight
                            text: row.it.label
                            font.family: st.sans; font.pixelSize: 24; font.weight: Font.Bold
                            color: row.sel ? st.th.hi : st.th.fg
                        }
                        Row {
                            anchors { right: parent.right; rightMargin: 30; verticalCenter: parent.verticalCenter }
                            spacing: 16
                            Item {
                                visible: row.it.kind === "slider"
                                width: 300; height: 14
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle { anchors.fill: parent; radius: 7; color: st.th.line }
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, ((row.it.v ?? 0) - (row.it.min ?? 0)) / (((row.it.max ?? 1) - (row.it.min ?? 0)) || 1)))
                                    height: parent.height; radius: 7
                                    color: row.sel ? st.th.hi : st.th.fg
                                    Behavior on width { NumberAnimation { duration: 90 } }
                                }
                            }
                            Rectangle {
                                visible: row.it.kind === "toggle"
                                width: 78; height: 38; radius: 19
                                anchors.verticalCenter: parent.verticalCenter
                                color: row.it.on ? st.th.hi : "transparent"
                                border.width: 2; border.color: row.it.on ? st.th.hi : st.th.dim
                                Rectangle {
                                    width: 28; height: 28; radius: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: row.it.on ? parent.width - width - 5 : 5
                                    color: row.it.on ? st.th.bg : st.th.dim
                                    Behavior on x { NumberAnimation { duration: 120 } }
                                }
                            }
                            Text {
                                visible: row.it.kind === "choice" && row.sel
                                text: "◀"; font.family: st.mono; font.pixelSize: 18
                                anchors.verticalCenter: parent.verticalCenter
                                color: (row.it.cur ?? 0) > 0 ? st.th.hi : st.th.line
                            }
                            Text {
                                visible: row.it.kind !== "toggle"
                                anchors.verticalCenter: parent.verticalCenter
                                text: row.it.kind === "action" ? "▶  " + row.it.value : (row.it.value ?? "")
                                font.family: row.it.kind === "choice" || row.it.kind === "info" ? st.sans : st.mono
                                font.pixelSize: row.it.kind === "slider" ? 20 : 21
                                color: row.it.kind === "action" ? (row.sel ? st.th.hi : st.th.dim) : row.sel ? st.th.hi : st.th.fg
                                width: Math.min(implicitWidth, 560); elide: Text.ElideRight
                            }
                            Text {
                                visible: row.it.kind === "choice" && row.sel
                                text: "▶"; font.family: st.mono; font.pixelSize: 18
                                anchors.verticalCenter: parent.verticalCenter
                                color: (row.it.cur ?? 0) < (row.it.opts?.length ?? 1) - 1 ? st.th.hi : st.th.line
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: row.it.kind === "info" ? Qt.ArrowCursor : Qt.PointingHandCursor
                            onClicked: { st.col = "items"; st.idx = row.index; st.button("a"); }
                        }
                    }
                }
            }
        }

        Column {
            x: 620; y: parent.height - 130
            width: parent.width - 620 - 110
            spacing: 14
            Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: st.col === "items" ? (st.items[st.idx]?.hint ?? "") : ""
                font.family: st.sans; font.pixelSize: 19
                color: st.th.dim
            }
        }
        Text {
            x: 110; y: parent.height - 70
            visible: st.cine.padMode
            text: st.welcome ? "▲▼ ELEGIR   A CONECTAR   B EMPEZAR"
                 : st.col === "cats" ? "A ENTRAR   ▲▼ SECCIÓN   B CERRAR" : "▲▼ ELEGIR   ◀▶ CAMBIAR   A ACTIVAR   B VOLVER   LB RB SECCIÓN"
            font.family: st.mono; font.pixelSize: 15; font.letterSpacing: 2
            color: st.th.line
        }
        Rectangle {
            visible: st.toast !== ""
            anchors { horizontalCenter: parent.horizontalCenter; top: parent.top; topMargin: 40 }
            width: toastText.implicitWidth + 60; height: 54; radius: 27
            color: st.th.hi
            Text { id: toastText; anchors.centerIn: parent; text: st.toast; font.family: st.mono; font.pixelSize: 19; color: st.th.bg }
        }

        // ── Stremio: mail y contraseña ─────────────────────────────────────
        Rectangle {
            id: stremioForm
            anchors.fill: parent
            visible: false
            color: st.th.bg
            property string err: ""
            property bool busy: false
            function abrir() { err = ""; busy = false; mail.text = ""; clave.text = ""; visible = true; mail.forceActiveFocus(); }
            function cerrar() { visible = false; st.cine.stageFocus(); }
            function enviar() {
                if (busy) return;
                if (!mail.text.includes("@") || clave.text === "") { err = "Poné tu mail y tu contraseña de Stremio"; return; }
                busy = true; err = "";
                loginProc.command = [App.backendDir + "/stremio.py", "login", mail.text.trim()];
                loginProc.running = true;
            }
            MouseArea { anchors.fill: parent }
            Process {
                id: loginProc
                stdinEnabled: true
                onRunningChanged: if (running) { write(clave.text + "\n"); }
                stdout: StdioCollector {
                    onStreamFinished: {
                        stremioForm.busy = false;
                        let d = {}; try { d = JSON.parse(text); } catch (e) {}
                        if (d.ok) { clave.text = ""; stremioForm.cerrar(); st.say("STREMIO CONECTADO · " + d.user); st.refreshAccounts(); st.sfx("select"); }
                        else { stremioForm.err = d.error || "No se pudo entrar"; st.sfx("error"); }
                    }
                }
            }
            Column {
                anchors.centerIn: parent
                width: 760
                spacing: 22
                Text { text: "STREMIO"; font.family: st.mono; font.pixelSize: 18; font.letterSpacing: 4; color: st.th.dim }
                EvaText { text: "TU CUENTA"; size: 84; color: st.th.hi }
                Text {
                    width: parent.width; wrapMode: Text.WordWrap
                    text: "La de stremio.com. La contraseña va directo a Stremio y no se guarda: queda solo la sesión."
                    font.family: st.sans; font.pixelSize: 20; color: st.th.fg; lineHeight: 1.2
                }
                Rectangle {
                    width: parent.width; height: 74; radius: 37
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: mail.activeFocus ? 3 : 1
                    border.color: mail.activeFocus ? st.th.hi : st.th.line
                    Text {
                        anchors { left: parent.left; leftMargin: 34; verticalCenter: parent.verticalCenter }
                        visible: mail.text === ""
                        text: "mail"
                        font.family: st.sans; font.pixelSize: 23; color: st.th.dim
                    }
                    TextInput {
                        id: mail
                        anchors { left: parent.left; right: parent.right; leftMargin: 34; rightMargin: 34; verticalCenter: parent.verticalCenter }
                        font.family: st.sans; font.pixelSize: 23; color: "white"
                        selectionColor: st.th.dim
                        clip: true
                        inputMethodHints: Qt.ImhEmailCharactersOnly | Qt.ImhNoAutoUppercase
                        KeyNavigation.tab: clave
                        Keys.onReturnPressed: clave.forceActiveFocus()
                        Keys.onEnterPressed: clave.forceActiveFocus()
                        Keys.onEscapePressed: stremioForm.cerrar()
                    }
                }
                Rectangle {
                    width: parent.width; height: 74; radius: 37
                    color: Qt.rgba(1, 1, 1, 0.06)
                    border.width: clave.activeFocus ? 3 : 1
                    border.color: clave.activeFocus ? st.th.hi : st.th.line
                    Text {
                        anchors { left: parent.left; leftMargin: 34; verticalCenter: parent.verticalCenter }
                        visible: clave.text === ""
                        text: "contraseña"
                        font.family: st.sans; font.pixelSize: 23; color: st.th.dim
                    }
                    TextInput {
                        id: clave
                        anchors { left: parent.left; right: parent.right; leftMargin: 34; rightMargin: 34; verticalCenter: parent.verticalCenter }
                        font.family: st.sans; font.pixelSize: 23; color: "white"
                        clip: true
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        KeyNavigation.tab: mail
                        Keys.onReturnPressed: stremioForm.enviar()
                        Keys.onEnterPressed: stremioForm.enviar()
                        Keys.onEscapePressed: stremioForm.cerrar()
                    }
                }
                Text {
                    visible: stremioForm.err !== "" || stremioForm.busy
                    text: stremioForm.busy ? "ENTRANDO…" : stremioForm.err
                    font.family: stremioForm.busy ? st.mono : st.sans; font.pixelSize: 21
                    color: stremioForm.busy ? st.th.dim : st.th.warn
                }
                Row {
                    spacing: 18
                    Rectangle {
                        width: ok.implicitWidth + 60; height: 62; radius: 31
                        color: st.th.hi
                        Text { id: ok; anchors.centerIn: parent; text: "ENTRAR"; font.family: st.sans; font.pixelSize: 21; font.weight: Font.Bold; color: st.th.bg }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: stremioForm.enviar() }
                    }
                    Rectangle {
                        width: no.implicitWidth + 60; height: 62; radius: 31
                        color: "transparent"; border.width: 2; border.color: st.th.line
                        Text { id: no; anchors.centerIn: parent; text: "CANCELAR"; font.family: st.sans; font.pixelSize: 21; font.weight: Font.Bold; color: st.th.fg }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: stremioForm.cerrar() }
                    }
                }
                Text {
                    text: "ENTER  ENTRAR      TAB  CAMBIAR DE CAMPO      ESC  CANCELAR"
                    font.family: st.mono; font.pixelSize: 15; font.letterSpacing: 2; color: st.th.line
                }
            }
        }
    }
}
