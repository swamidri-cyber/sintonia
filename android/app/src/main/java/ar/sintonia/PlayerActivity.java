package ar.sintonia;

import android.app.Activity;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.GestureDetector;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.SeekBar;
import android.widget.TextView;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

import dev.jdtech.mpv.MPVLib;

/** El reproductor: libmpv (como en la PC) con los controles de la tele. */
public class PlayerActivity extends Activity implements MPVLib.EventObserver, SurfaceHolder.Callback {
    private final Handler ui = new Handler(Looper.getMainLooper());
    private JSONObject job;
    private JSONArray cands;
    private int cand = -1;
    private Torrent torrent;
    private volatile double pos = 0, dur = 0, startAt = 0;
    private volatile boolean paused = false, loaded = false, ended = false, buffering = false;
    private boolean mpvOn = false, surfaceOk = false, controlsOn = true, dragging = false;
    private double subDelay = 0;
    private int theme = Color.parseColor("#e2ceff"), warn = Color.parseColor("#ff8a3d");
    private Typeface mono, eva;
    private TextView title, sub, status, tPos, tLeft, ppBtn, subBtn, info;
    private SeekBar bar;
    private View controls;
    private Thread worker;
    private long candSince = 0;
    private volatile long loadAt = 0;          // cuándo se pidió el archivo actual (0 = nada pedido)

    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        try {
            job = new JSONObject(getIntent().getStringExtra("job"));
            cands = job.optJSONArray("candidates");
            if (cands == null) cands = new JSONArray();
            startAt = job.optDouble("start", 0);
            JSONObject th = job.optJSONObject("theme");
            if (th != null) { theme = Color.parseColor(th.optString("hi", "#f6eeff")); warn = Color.parseColor(th.optString("warn", "#ff8a3d")); }
        } catch (Exception e) { finish(); return; }
        mono = Typeface.createFromAsset(getAssets(), "web/font/mono.otf");
        eva = Typeface.createFromAsset(getAssets(), "web/font/serif.ttf");
        armarPantalla();
        if (android.os.Build.VERSION.SDK_INT >= 33) getOnBackInvokedDispatcher().registerOnBackInvokedCallback(
                android.window.OnBackInvokedDispatcher.PRIORITY_DEFAULT, this::atras);
        inmersivo();
        iniciarMpv();
        siguiente();
        ui.postDelayed(tick, 500);
    }

    // ── Pantalla ────────────────────────────────────────────────────────────
    private int dp(float v) { return (int) TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics()); }

    private TextView texto(float sp, Typeface tf, int color) {
        TextView t = new TextView(this);
        t.setTextSize(sp);
        t.setTypeface(tf);
        t.setTextColor(color);
        t.setShadowLayer(8, 0, 1, Color.BLACK);
        return t;
    }

    private TextView boton(String txt, View.OnClickListener cl) {
        TextView t = texto(13, mono, Color.WHITE);
        t.setText(txt);
        t.setLetterSpacing(0.1f);
        t.setGravity(Gravity.CENTER);
        t.setPadding(dp(16), dp(10), dp(16), dp(10));
        GradientDrawable g = new GradientDrawable();
        g.setCornerRadius(dp(24));
        g.setStroke(dp(1.5f), Color.argb(90, 255, 255, 255));
        t.setBackground(g);
        t.setOnClickListener(v -> { cl.onClick(v); mostrar(); });
        return t;
    }

    /** Botón redondo transparente (los del medio). */
    private TextView redondo(String txt, int diam, int sp, View.OnClickListener cl) {
        TextView t = texto(sp, mono, Color.WHITE);
        t.setText(txt);
        t.setGravity(Gravity.CENTER);
        t.setLineSpacing(0, 0.85f);
        GradientDrawable g = new GradientDrawable();
        g.setShape(GradientDrawable.OVAL);
        g.setColor(Color.argb(46, 255, 255, 255));
        g.setStroke(dp(1.5f), Color.argb(110, 255, 255, 255));
        t.setBackground(g);
        t.setLayoutParams(new LinearLayout.LayoutParams(dp(diam), dp(diam)));
        t.setMinimumWidth(dp(diam));
        t.setMinimumHeight(dp(diam));
        t.setOnClickListener(v -> { cl.onClick(v); mostrar(); });
        return t;
    }

    private View syncPanel;
    private TextView syncVal;

    /** Menú aparte para correr los subtítulos (±0,1 · ±0,5 · ±1 s). */
    private void armarSync(FrameLayout root) {
        FrameLayout fondo = new FrameLayout(this);
        fondo.setBackgroundColor(Color.argb(150, 0, 0, 0));
        fondo.setVisibility(View.GONE);
        fondo.setOnClickListener(v -> cerrarSync());
        LinearLayout p = new LinearLayout(this);
        p.setOrientation(LinearLayout.VERTICAL);
        p.setGravity(Gravity.CENTER_HORIZONTAL);
        p.setPadding(dp(28), dp(22), dp(28), dp(22));
        GradientDrawable g = new GradientDrawable();
        g.setCornerRadius(dp(26));
        g.setColor(Color.argb(235, 10, 6, 16));
        g.setStroke(dp(1.5f), Color.argb(90, 255, 255, 255));
        p.setBackground(g);
        p.setClickable(true);

        TextView t = texto(13, mono, theme);
        t.setLetterSpacing(0.22f);
        t.setText("SINCRONIZAR SUBTÍTULOS");
        t.setGravity(Gravity.CENTER);
        p.addView(t, new LinearLayout.LayoutParams(-1, -2));

        // una sola línea: ← antes  [valor]  después →
        LinearLayout fila = new LinearLayout(this);
        fila.setGravity(Gravity.CENTER_VERTICAL);
        fila.setPadding(0, dp(18), 0, dp(6));
        fila.addView(lado(new double[]{-1, -0.5, -0.1}, "‹  SALEN ANTES", Gravity.START));
        syncVal = texto(34, mono, Color.WHITE);
        syncVal.setGravity(Gravity.CENTER);
        fila.addView(syncVal, new LinearLayout.LayoutParams(dp(170), -2));
        fila.addView(lado(new double[]{0.1, 0.5, 1}, "SALEN DESPUÉS  ›", Gravity.END));
        p.addView(fila);

        LinearLayout r = new LinearLayout(this);
        r.setGravity(Gravity.CENTER);
        r.setPadding(0, dp(14), 0, 0);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(150), -2);
        lp.setMargins(dp(8), 0, dp(8), 0);
        r.addView(boton("VOLVER A 0", v -> delay(-subDelay)), lp);
        TextView listo = boton("LISTO", v -> cerrarSync());
        GradientDrawable gl = new GradientDrawable();
        gl.setCornerRadius(dp(24));
        gl.setColor(Color.WHITE);
        listo.setBackground(gl);
        listo.setTextColor(Color.BLACK);
        r.addView(listo, lp);
        p.addView(r);

        fondo.addView(p, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));
        root.addView(fondo, new FrameLayout.LayoutParams(-1, -1));
        syncPanel = fondo;
        pintarSync();
    }

    /** Tres botones iguales con su rótulo debajo (un lado del menú de sincronizar). */
    private LinearLayout lado(double[] pasos, String rotulo, int alin) {
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);
        LinearLayout bs = new LinearLayout(this);
        for (double d : pasos) {
            String l = (d > 0 ? "+" : "−") + (Math.abs(d) == 1 ? "1" : String.valueOf(Math.abs(d)).replace(".", ",")) + " S";
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(92), -2);
            lp.setMargins(dp(4), 0, dp(4), 0);
            bs.addView(boton(l, v -> delay(d)), lp);
        }
        col.addView(bs);
        TextView r = texto(11, mono, Color.argb(170, 255, 255, 255));
        r.setLetterSpacing(0.16f);
        r.setText(rotulo);
        r.setGravity(alin);
        r.setPadding(dp(6), dp(10), dp(6), 0);
        col.addView(r, new LinearLayout.LayoutParams(-1, -2));
        return col;
    }

    private void pintarSync() {
        if (syncVal != null) syncVal.setText((subDelay > 0 ? "+" : subDelay < 0 ? "−" : "") + String.format("%.1f", Math.abs(subDelay)).replace(".", ",") + " S");
    }

    private void abrirSync() {
        syncPanel.setAlpha(0);
        syncPanel.setVisibility(View.VISIBLE);
        syncPanel.animate().alpha(1).setDuration(160).start();
        controls.animate().alpha(0).setDuration(160).start();
        ui.removeCallbacks(autoOcultar);
        pintarSync();
    }

    private void cerrarSync() {
        syncPanel.animate().alpha(0).setDuration(160).withEndAction(() -> syncPanel.setVisibility(View.GONE)).start();
        mostrar();
    }

    private void armarPantalla() {
        FrameLayout root = new FrameLayout(this);
        root.setBackgroundColor(Color.BLACK);
        SurfaceView sv = new SurfaceView(this);
        sv.getHolder().addCallback(this);
        root.addView(sv, new FrameLayout.LayoutParams(-1, -1, Gravity.CENTER));

        status = texto(14, mono, theme);
        status.setLetterSpacing(0.14f);
        status.setGravity(Gravity.CENTER);
        root.addView(status, new FrameLayout.LayoutParams(-2, -2, Gravity.CENTER));

        LinearLayout c = new LinearLayout(this);
        c.setOrientation(LinearLayout.VERTICAL);
        c.setPadding(dp(28), dp(18), dp(28), dp(16));
        GradientDrawable sombra = new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,
                new int[]{Color.argb(200, 0, 0, 0), Color.TRANSPARENT, Color.TRANSPARENT, Color.argb(220, 0, 0, 0)});
        c.setBackground(sombra);

        LinearLayout top = new LinearLayout(this);
        top.setOrientation(LinearLayout.HORIZONTAL);
        top.setGravity(Gravity.CENTER_VERTICAL);
        TextView back = boton("✕", v -> salir());
        top.addView(back);
        LinearLayout tt = new LinearLayout(this);
        tt.setOrientation(LinearLayout.VERTICAL);
        tt.setPadding(dp(16), 0, 0, 0);
        title = texto(30, eva, Color.WHITE);
        title.setScaleX(0.8f);
        title.setPivotX(0);
        title.setSingleLine(true);
        title.setText(job.optString("title", "").toUpperCase());
        sub = texto(12, mono, theme);
        sub.setLetterSpacing(0.12f);
        sub.setText(job.optString("sub", ""));
        tt.addView(title);
        tt.addView(sub);
        top.addView(tt, new LinearLayout.LayoutParams(0, -2, 1));
        info = texto(11, mono, Color.argb(200, 255, 255, 255));
        top.addView(info);
        c.addView(top);

        // el medio: retroceder 10 · pausa grande · adelantar 10 (transparentes)
        LinearLayout mid = new LinearLayout(this);
        mid.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams lm = new LinearLayout.LayoutParams(-2, -2);
        lm.setMargins(dp(34), 0, dp(34), 0);
        mid.addView(redondo("⟲\n10", 64, 15, v -> { cmd("seek", "-10"); avisar("−10 S"); }), lm);
        ppBtn = redondo("❚❚", 96, 30, v -> togglePause());
        mid.addView(ppBtn, lm);
        mid.addView(redondo("⟳\n10", 64, 15, v -> { cmd("seek", "10"); avisar("+10 S"); }), lm);
        c.addView(mid, new LinearLayout.LayoutParams(-1, 0, 1));

        bar = new SeekBar(this);
        bar.setMax(1000);
        bar.getProgressDrawable().setTint(theme);
        bar.getThumb().setTint(Color.WHITE);
        bar.setOnSeekBarChangeListener(new SeekBar.OnSeekBarChangeListener() {
            @Override public void onProgressChanged(SeekBar s, int p, boolean user) {
                if (user) tPos.setText(fmt(p / 1000.0 * dur));
            }
            @Override public void onStartTrackingTouch(SeekBar s) { dragging = true; mostrar(); }
            @Override public void onStopTrackingTouch(SeekBar s) {
                dragging = false;
                if (dur > 0) cmd("seek", String.valueOf(s.getProgress() / 1000.0 * dur), "absolute");
                mostrar();
            }
        });
        c.addView(bar);
        LinearLayout times = new LinearLayout(this);
        tPos = texto(12, mono, Color.LTGRAY);
        tLeft = texto(12, mono, Color.LTGRAY);
        times.addView(tPos, new LinearLayout.LayoutParams(0, -2, 1));
        times.addView(tLeft);
        times.setPadding(dp(16), 0, dp(16), dp(8));
        c.addView(times);

        LinearLayout row = new LinearLayout(this);
        row.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(-2, -2);
        lp.setMargins(dp(6), 0, dp(6), 0);
        subBtn = boton("SUBTÍTULOS", v -> toggleSubs());
        row.addView(subBtn, lp);
        row.addView(boton("SINCRONIZAR", v -> abrirSync()), lp);
        row.addView(boton("OTRA FUENTE", v -> { avisar("CAMBIANDO DE FUENTE…"); siguiente(); }), lp);
        c.addView(row);
        controls = c;
        root.addView(c, new FrameLayout.LayoutParams(-1, -1));
        armarSync(root);

        GestureDetector gd = new GestureDetector(this, new GestureDetector.SimpleOnGestureListener() {
            @Override public boolean onSingleTapConfirmed(MotionEvent e) { if (controlsOn) ocultar(); else mostrar(); return true; }
            @Override public boolean onDoubleTap(MotionEvent e) {
                boolean der = e.getX() > root.getWidth() / 2f;
                cmd("seek", der ? "10" : "-10");
                avisar(der ? "+10 S" : "−10 S");
                return true;
            }
        });
        root.setOnTouchListener((v, e) -> { gd.onTouchEvent(e); return true; });
        c.setOnTouchListener((v, e) -> { gd.onTouchEvent(e); return true; });
        setContentView(root);
        mostrar();
    }

    private void inmersivo() {
        WindowInsetsController w = getWindow().getInsetsController();
        if (w != null) {
            w.hide(WindowInsets.Type.systemBars());
            w.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
        }
    }

    private final Runnable autoOcultar = this::ocultar;

    private void mostrar() {
        controlsOn = true;
        controls.animate().alpha(1).setDuration(180).start();
        ui.removeCallbacks(autoOcultar);
        ui.postDelayed(autoOcultar, 4500);
    }

    private void ocultar() {
        if (dragging || !loaded || (syncPanel != null && syncPanel.getVisibility() == View.VISIBLE)) return;
        controlsOn = false;
        controls.animate().alpha(0).setDuration(260).start();
    }

    private final Runnable sinAviso = () -> { if (loaded && !buffering) status.setText(""); };

    private void avisar(String t) {
        status.setText(t);
        ui.removeCallbacks(sinAviso);
        ui.postDelayed(sinAviso, 1600);
    }

    static String fmt(double s) {
        long x = Math.max(0, Math.round(s));
        long h = x / 3600, m = x % 3600 / 60, ss = x % 60;
        return h > 0 ? String.format("%d:%02d:%02d", h, m, ss) : String.format("%d:%02d", m, ss);
    }

    // ── mpv ─────────────────────────────────────────────────────────────────
    private File copiar(String asset, String nombre) {
        File f = new File(getFilesDir(), nombre);
        if (f.exists()) return f;
        f.getParentFile().mkdirs();
        try (InputStream in = getAssets().open(asset); OutputStream o = new FileOutputStream(f)) {
            byte[] b = new byte[65536];
            int n;
            while ((n = in.read(b)) > 0) o.write(b, 0, n);
        } catch (Exception ignored) { }
        return f;
    }

    private void iniciarMpv() {
        File ca = copiar("mpv/cacert.pem", "mpv/cacert.pem");
        copiar("mpv/subfont.ttf", "mpv/fonts/subfont.ttf");
        MPVLib.create(this);
        MPVLib.setOptionString("config", "no");
        MPVLib.setOptionString("vo", "gpu");
        MPVLib.setOptionString("gpu-context", "android");
        MPVLib.setOptionString("opengl-es", "yes");
        MPVLib.setOptionString("hwdec", "mediacodec,mediacodec-copy");
        MPVLib.setOptionString("hwdec-codecs", "h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1");
        MPVLib.setOptionString("ao", "audiotrack,opensles");
        MPVLib.setOptionString("tls-verify", "yes");
        MPVLib.setOptionString("tls-ca-file", ca.getAbsolutePath());
        MPVLib.setOptionString("ytdl", "no");
        MPVLib.setOptionString("cache", "yes");
        MPVLib.setOptionString("demuxer-max-bytes", "150MiB");
        MPVLib.setOptionString("demuxer-max-back-bytes", "50MiB");
        MPVLib.setOptionString("network-timeout", "60");
        MPVLib.setOptionString("keep-open", "yes");
        MPVLib.setOptionString("save-position-on-quit", "no");
        MPVLib.setOptionString("force-window", "no");
        MPVLib.setOptionString("idle", "yes");
        MPVLib.setOptionString("alang", "spa,es,lat,eng,en");
        MPVLib.setOptionString("slang", "spa,es,lat");
        MPVLib.setOptionString("sub-fonts-dir", new File(getFilesDir(), "mpv/fonts").getAbsolutePath());
        MPVLib.setOptionString("sub-font", "Inter Medium");
        MPVLib.setOptionString("sub-font-size", "44");
        MPVLib.setOptionString("sub-border-size", "2.6");
        MPVLib.setOptionString("sub-shadow-offset", "1.5");
        MPVLib.setOptionString("sub-margin-y", "40");
        MPVLib.setOptionString("sub-ass-override", "force");
        MPVLib.init();
        MPVLib.addObserver(this);
        MPVLib.observeProperty("time-pos", MPVLib.MPV_FORMAT_DOUBLE);
        MPVLib.observeProperty("duration", MPVLib.MPV_FORMAT_DOUBLE);
        MPVLib.observeProperty("pause", MPVLib.MPV_FORMAT_FLAG);
        MPVLib.observeProperty("paused-for-cache", MPVLib.MPV_FORMAT_FLAG);
        MPVLib.observeProperty("eof-reached", MPVLib.MPV_FORMAT_FLAG);
        mpvOn = true;
    }

    private void cmd(String... c) { if (mpvOn) MPVLib.command(c); }

    @Override public void surfaceCreated(SurfaceHolder h) {
        if (!mpvOn) return;
        MPVLib.attachSurface(h.getSurface());
        MPVLib.setOptionString("force-window", "yes");
        MPVLib.setPropertyString("vo", "gpu");
        surfaceOk = true;
    }

    @Override public void surfaceChanged(SurfaceHolder h, int f, int w, int hh) {
        if (mpvOn) MPVLib.setPropertyString("android-surface-size", w + "x" + hh);
    }

    @Override public void surfaceDestroyed(SurfaceHolder h) {
        if (!mpvOn) return;
        MPVLib.setPropertyString("vo", "null");
        MPVLib.setOptionString("force-window", "no");
        MPVLib.detachSurface();
        surfaceOk = false;
    }

    @Override public void eventProperty(String p) { }
    @Override public void eventProperty(String p, long v) { }
    @Override public void eventProperty(String p, String v) { }

    @Override public void eventProperty(String p, double v) {
        if (p.equals("time-pos")) { pos = v; if (v > 0.5 && !loaded) { loaded = true; ui.post(this::cargo); } }
        else if (p.equals("duration")) dur = v;
    }

    @Override public void eventProperty(String p, boolean v) {
        switch (p) {
            case "pause": paused = v; ui.post(() -> ppBtn.setText(v ? "▶" : "❚❚")); break;
            case "paused-for-cache": buffering = v; ui.post(() -> { if (v) status.setText("CARGANDO…"); else status.setText(""); }); break;
            case "eof-reached":
                if (v && dur > 0 && pos > dur - 30) { ended = true; ui.post(() -> guardar(true, true)); }
                break;
        }
    }

    @Override public void event(int ev) {
        if (ev == MPVLib.MPV_EVENT_END_FILE && !loaded && !ended && loadAt > 0
                && System.currentTimeMillis() - loadAt > 300) {
            // no se pudo abrir esta fuente: la que sigue
            loadAt = 0;
            ui.post(() -> { if (!loaded) siguiente(); });
        }
    }

    private void cargo() {
        status.setText("");
        candSince = 0;
        subtitulos();
        ocultar();
    }

    // ── Fuentes ─────────────────────────────────────────────────────────────
    private void siguiente() {
        cand++;
        loaded = false;
        loadAt = 0;
        if (torrent != null) { final Torrent t = torrent; torrent = null; new Thread(t::stop).start(); }
        if (worker != null) worker.interrupt();
        if (cand >= cands.length()) {
            status.setText("NINGUNA FUENTE ANDUVO.\nPROBÁ CON OTRO IDIOMA.");
            status.setTextColor(warn);
            return;
        }
        final JSONObject s = cands.optJSONObject(cand);
        final double from = Math.max(startAt, pos);
        candSince = System.currentTimeMillis();
        info.setText(s.optInt("res", 0) > 0 ? s.optInt("res") + "p" : "");
        status.setText(cand == 0 ? "SINTONIZANDO…" : "PROBANDO OTRA FUENTE (" + (cand + 1) + ")…");
        worker = new Thread(() -> {
            String url = s.optString("url", "");
            if (!s.optString("hash", "").isEmpty()) {
                List<String> src = new ArrayList<>();
                JSONArray a = s.optJSONArray("sources");
                if (a != null) for (int i = 0; i < a.length(); i++) src.add(a.optString(i));
                Torrent t = new Torrent(this, s.optString("hash"), s.isNull("fileIdx") ? -1 : s.optInt("fileIdx", -1), src);
                ui.post(() -> torrent = t);
                url = t.start(40);
                if (url == null) {
                    if (!Thread.currentThread().isInterrupted()) ui.post(this::siguiente);
                    return;
                }
            }
            final String u = url;
            ui.post(() -> {
                if (from > 5) MPVLib.setOptionString("start", String.valueOf((int) from));
                else MPVLib.setOptionString("start", "none");
                loadAt = System.currentTimeMillis();
                cmd("loadfile", u);
            });
        });
        worker.start();
    }

    private final Runnable tick = new Runnable() {
        @Override public void run() {
            if (!loaded && cand < cands.length()) {
                Torrent t = torrent;
                if (t != null) {
                    int[] e = t.estado();
                    status.setText((cand == 0 ? "SINTONIZANDO…" : "PROBANDO OTRA FUENTE…") + "\n" + e[0] + " PERSONAS · " + e[1] + " KB/S");
                    // dos minutos sin arrancar: probar la siguiente
                    if (candSince > 0 && System.currentTimeMillis() - candSince > 120000) siguiente();
                }
            } else if (loaded) {
                if (!dragging && dur > 0) {
                    bar.setProgress((int) (pos / dur * 1000));
                    tPos.setText(fmt(pos));
                    tLeft.setText("-" + fmt(dur - pos));
                }
                if (torrent != null) { int[] e = torrent.estado(); info.setText(e[0] + " PERSONAS · " + e[1] + " KB/S"); }
                long now = System.currentTimeMillis();
                if (now - lastSave > 30000) { lastSave = now; guardar(false, false); }
            }
            ui.postDelayed(this, 500);
        }
    };
    private long lastSave = 0;

    // ── Controles ───────────────────────────────────────────────────────────
    private void togglePause() {
        if (!mpvOn) return;
        MPVLib.setPropertyBoolean("pause", !paused);
    }

    private boolean subsOn = false;

    private void subtitulos() {
        JSONArray subs = job.optJSONArray("subs");
        if (subs == null || subs.length() == 0) {
            subsOn = job.optBoolean("wantSubs", false) && tieneSubsEs();
            if (!subsOn) MPVLib.setPropertyString("sid", "no");
            pintarSubs();
            return;
        }
        new Thread(() -> {
            int ok = 0;
            for (int i = 0; i < subs.length() && ok < 3; i++) {
                try {
                    File f = Red.bajar(this, subs.optString(i), "sub" + i + ".srt");
                    final String path = f.getAbsolutePath();
                    final boolean first = ok == 0;
                    ui.post(() -> cmd("sub-add", path, first ? "select" : "auto", "Español " + (first ? "" : "(otra)")));
                    ok++;
                } catch (Exception ignored) { }
            }
            final boolean any = ok > 0;
            ui.post(() -> { subsOn = any; pintarSubs(); if (!any) avisar("NO ENCONTRÉ SUBTÍTULOS"); });
        }).start();
    }

    private boolean tieneSubsEs() {
        try {
            int n = MPVLib.getPropertyInt("track-list/count");
            for (int i = 0; i < n; i++) {
                if ("sub".equals(MPVLib.getPropertyString("track-list/" + i + "/type"))) {
                    String l = MPVLib.getPropertyString("track-list/" + i + "/lang");
                    if (l != null && (l.startsWith("spa") || l.startsWith("es"))) return true;
                }
            }
        } catch (Exception ignored) { }
        return false;
    }

    private void pintarSubs() { subBtn.setTextColor(subsOn ? theme : Color.WHITE); subBtn.setText(subsOn ? "SUBTÍTULOS ●" : "SUBTÍTULOS"); }

    private void toggleSubs() {
        if (subsOn) { MPVLib.setPropertyString("sid", "no"); subsOn = false; avisar("SIN SUBTÍTULOS"); }
        else { cmd("cycle", "sub"); String sid = MPVLib.getPropertyString("sid"); subsOn = sid != null && !sid.equals("no"); avisar(subsOn ? "SUBTÍTULOS" : "NO HAY SUBTÍTULOS"); }
        pintarSubs();
    }

    private void delay(double d) {
        subDelay = Math.round((subDelay + d) * 10) / 10.0;
        MPVLib.setPropertyDouble("sub-delay", subDelay);
        pintarSync();
    }


    // ── Guardar y salir ─────────────────────────────────────────────────────
    private void guardar(boolean finished, boolean close) {
        if (!loaded && !finished) { if (close) finish(); return; }
        try {
            JSONObject r = new JSONObject();
            r.put("item", job.optJSONObject("item"));
            r.put("videoId", job.optString("videoId"));
            r.put("pos", pos);
            r.put("dur", dur);
            r.put("start", startAt);
            r.put("finished", finished || (dur > 0 && pos > dur * 0.92));
            r.put("close", close);
            SharedPreferences p = getSharedPreferences("reproductor", MODE_PRIVATE);
            p.edit().putString("fin", r.toString()).apply();
        } catch (Exception ignored) { }
        if (close) finish();
    }

    private void salir() { guardar(false, true); }

    @Override public void onBackPressed() { atras(); }

    private void atras() {
        if (syncPanel != null && syncPanel.getVisibility() == View.VISIBLE) cerrarSync();
        else salir();
    }

    @Override protected void onPause() {
        super.onPause();
        if (mpvOn && !isFinishing()) MPVLib.setPropertyBoolean("pause", true);
    }

    @Override protected void onDestroy() {
        ui.removeCallbacksAndMessages(null);
        if (!isFinishing()) guardar(false, false);
        if (worker != null) worker.interrupt();
        if (torrent != null) { final Torrent t = torrent; new Thread(t::stop).start(); }
        if (mpvOn) {
            MPVLib.removeObserver(this);
            MPVLib.destroy();
            mpvOn = false;
        }
        super.onDestroy();
    }
}
