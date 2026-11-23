package ar.sintonia;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ServiceInfo;
import android.net.Uri;
import android.net.wifi.WifiManager;
import android.os.Handler;
import android.os.IBinder;
import android.os.Looper;
import android.os.PowerManager;
import android.util.Log;

import androidx.mediarouter.media.MediaRouteSelector;
import androidx.mediarouter.media.MediaRouter;

import com.google.android.gms.cast.CastMediaControlIntent;
import com.google.android.gms.cast.MediaInfo;
import com.google.android.gms.cast.MediaLoadRequestData;
import com.google.android.gms.cast.MediaMetadata;
import com.google.android.gms.cast.MediaSeekOptions;
import com.google.android.gms.cast.MediaStatus;
import com.google.android.gms.cast.MediaTrack;
import com.google.android.gms.cast.framework.CastContext;
import com.google.android.gms.cast.framework.CastSession;
import com.google.android.gms.cast.framework.SessionManager;
import com.google.android.gms.cast.framework.SessionManagerListener;
import com.google.android.gms.cast.framework.media.RemoteMediaClient;
import com.google.android.gms.common.images.WebImage;

import org.json.JSONArray;
import org.json.JSONObject;

import java.io.File;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

/**
 * Ver en la tele (Chromecast). El celular baja el torrent y se lo sirve a la tele
 * por la red de la casa. Corre como servicio en primer plano (con su aviso fijo):
 * así Android no lo corta aunque bloquees el teléfono o cambies de app — el
 * problema que tiene la app de Stremio, que pide permisos de segundo plano.
 */
public class TeleService extends Service {
    private static final String TAG = "SintoniaTele";
    static final String CANAL = "tele";
    static volatile TeleService actual;
    static MediaRouteSelector selector;
    private static final MediaRouter.Callback descubrir = new MediaRouter.Callback() { };

    private final Handler ui = new Handler(Looper.getMainLooper());
    private JSONObject job;
    private JSONArray cands;
    private int cand = -1;
    private String routeId;
    private Torrent torrent;
    private PowerManager.WakeLock wake;
    private WifiManager.WifiLock wifi;
    volatile String msg = "SINTONIZANDO…", device = "";
    private volatile boolean loaded = false, finished = false, subsOn = false, cerrando = false;
    private volatile double lastPos = 0, lastDur = 0;
    private long candSince = 0;
    private Thread worker;

    // ── Buscar teles (mientras la app está abierta) ─────────────────────────
    static MediaRouteSelector selector() {
        if (selector == null) selector = new MediaRouteSelector.Builder()
                .addControlCategory(CastMediaControlIntent.categoryForCast(CastMediaControlIntent.DEFAULT_MEDIA_RECEIVER_APPLICATION_ID))
                .build();
        return selector;
    }

    static void buscar(Context c, boolean on) {
        try {
            CastContext.getSharedInstance(c);
            MediaRouter r = MediaRouter.getInstance(c);
            if (on) r.addCallback(selector(), descubrir, MediaRouter.CALLBACK_FLAG_REQUEST_DISCOVERY);
            else r.removeCallback(descubrir);
        } catch (Exception e) {
            Log.w(TAG, "sin Chromecast: " + e);
        }
    }

    static JSONArray teles(Context c) {
        JSONArray a = new JSONArray();
        try {
            for (MediaRouter.RouteInfo r : MediaRouter.getInstance(c).getRoutes()) {
                if (r.isDefault() || !r.isEnabled() || !r.matchesSelector(selector())) continue;
                a.put(new JSONObject().put("id", r.getId()).put("name", r.getName()));
            }
        } catch (Exception ignored) { }
        return a;
    }

    // ── Servicio ────────────────────────────────────────────────────────────
    @Override public IBinder onBind(Intent i) { return null; }

    @Override
    public int onStartCommand(Intent i, int flags, int startId) {
        if (i != null && "cortar".equals(i.getAction())) { cortar(); return START_NOT_STICKY; }
        if (i == null || i.getStringExtra("job") == null) { stopSelf(); return START_NOT_STICKY; }
        if (actual != null && actual != this) actual.cortar();
        actual = this;
        try {
            job = new JSONObject(i.getStringExtra("job"));
            cands = job.optJSONArray("candidates");
            if (cands == null) cands = new JSONArray();
        } catch (Exception e) { stopSelf(); return START_NOT_STICKY; }
        routeId = i.getStringExtra("route");
        aviso();
        PowerManager pm = (PowerManager) getSystemService(POWER_SERVICE);
        wake = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "sintonia:tele");
        wake.acquire(6 * 3600 * 1000L);
        WifiManager wm = (WifiManager) getApplicationContext().getSystemService(WIFI_SERVICE);
        wifi = wm.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "sintonia:tele");
        wifi.acquire();
        conectar();
        return START_NOT_STICKY;
    }

    private void aviso() {
        NotificationManager nm = getSystemService(NotificationManager.class);
        nm.createNotificationChannel(new NotificationChannel(CANAL, "En la tele", NotificationManager.IMPORTANCE_LOW));
        PendingIntent abrir = PendingIntent.getActivity(this, 0, new Intent(this, MainActivity.class).setFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE);
        PendingIntent cortar = PendingIntent.getService(this, 1, new Intent(this, TeleService.class).setAction("cortar"),
                PendingIntent.FLAG_IMMUTABLE);
        Notification n = new Notification.Builder(this, CANAL)
                .setSmallIcon(android.R.drawable.ic_media_play)
                .setContentTitle("SINTONÍA · EN LA TELE")
                .setContentText(job.optString("title", ""))
                .setContentIntent(abrir)
                .setOngoing(true)
                .addAction(new Notification.Action.Builder(null, "CORTAR", cortar).build())
                .build();
        startForeground(7, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK);
    }

    // ── Sesión con la tele ──────────────────────────────────────────────────
    private CastContext cc() { return CastContext.getSharedInstance(this); }

    private final SessionManagerListener<CastSession> sesiones = new SessionManagerListener<CastSession>() {
        @Override public void onSessionStarted(CastSession s, String id) { if (cand < 0) siguiente(); }
        @Override public void onSessionResumed(CastSession s, boolean w) { if (cand < 0) siguiente(); }
        @Override public void onSessionStartFailed(CastSession s, int e) { msg = "NO SE PUDO CONECTAR CON LA TELE"; ui.postDelayed(TeleService.this::cortar, 4000); }
        @Override public void onSessionEnded(CastSession s, int e) { if (!cerrando) cortar(); }
        @Override public void onSessionStarting(CastSession s) { }
        @Override public void onSessionEnding(CastSession s) { }
        @Override public void onSessionResuming(CastSession s, String id) { }
        @Override public void onSessionResumeFailed(CastSession s, int e) { }
        @Override public void onSessionSuspended(CastSession s, int r) { }
    };

    private void conectar() {
        SessionManager sm = cc().getSessionManager();
        sm.addSessionManagerListener(sesiones, CastSession.class);
        MediaRouter r = MediaRouter.getInstance(this);
        MediaRouter.RouteInfo ruta = null;
        for (MediaRouter.RouteInfo x : r.getRoutes()) if (x.getId().equals(routeId)) ruta = x;
        if (ruta == null) { msg = "NO ENCUENTRO ESA TELE"; ui.postDelayed(this::cortar, 4000); return; }
        device = String.valueOf(ruta.getName());
        CastSession cur = sm.getCurrentCastSession();
        if (cur != null && cur.isConnected() && r.getSelectedRoute().getId().equals(routeId)) siguiente();
        else { msg = "CONECTANDO CON " + device.toUpperCase() + "…"; r.selectRoute(ruta); }
    }

    private RemoteMediaClient rmc() {
        CastSession s = cc().getSessionManager().getCurrentCastSession();
        return s == null ? null : s.getRemoteMediaClient();
    }

    // ── Fuentes ─────────────────────────────────────────────────────────────
    private void siguiente() {
        cand++;
        loaded = false;
        if (torrent != null) { final Torrent t = torrent; torrent = null; new Thread(t::stop).start(); }
        if (worker != null) worker.interrupt();
        if (cand >= cands.length()) { msg = "NINGUNA FUENTE ANDUVO EN LA TELE"; ui.postDelayed(this::cortar, 6000); return; }
        final JSONObject s = cands.optJSONObject(cand);
        final double from = Math.max(job.optDouble("start", 0), lastPos);
        candSince = System.currentTimeMillis();
        msg = cand == 0 ? "SINTONIZANDO…" : "PROBANDO OTRA FUENTE (" + (cand + 1) + ")…";
        worker = new Thread(() -> {
            String url = s.optString("url", "");
            Torrent t = null;
            if (!s.optString("hash", "").isEmpty()) {
                List<String> src = new ArrayList<>();
                JSONArray a = s.optJSONArray("sources");
                if (a != null) for (int k = 0; k < a.length(); k++) src.add(a.optString(k));
                t = new Torrent(this, s.optString("hash"), s.isNull("fileIdx") ? -1 : s.optInt("fileIdx", -1), src);
                t.paraLaTele = true;
                final Torrent tt = t;
                ui.post(() -> torrent = tt);
                url = t.start(45);
                if (url == null) { if (!Thread.currentThread().isInterrupted()) ui.post(this::siguiente); return; }
                // subtítulos: la tele los pide al celular
                JSONArray subs = job.optJSONArray("subs");
                if (subs != null) for (int k = 0; k < subs.length() && t.vtt == null; k++) {
                    try {
                        File f = Red.bajar(this, subs.optString(k), "tele.srt");
                        t.vtt = Red.srtAVtt(Files.readAllBytes(f.toPath()));
                    } catch (Exception ignored) { }
                }
            }
            final String u = url, subsUrl = t != null && t.vtt != null ? url.replace("/video", "/subs.vtt") : null;
            ui.post(() -> cargar(u, subsUrl, from));
        });
        worker.start();
    }

    private void cargar(String url, String subsUrl, double from) {
        RemoteMediaClient c = rmc();
        if (c == null) { msg = "SE PERDIÓ LA TELE"; return; }
        MediaMetadata md = new MediaMetadata(MediaMetadata.MEDIA_TYPE_MOVIE);
        md.putString(MediaMetadata.KEY_TITLE, job.optString("title", ""));
        md.putString(MediaMetadata.KEY_SUBTITLE, job.optString("sub", ""));
        String img = job.optString("image", "");
        if (!img.isEmpty()) md.addImage(new WebImage(Uri.parse(img)));
        MediaInfo.Builder mb = new MediaInfo.Builder(url)
                .setStreamType(MediaInfo.STREAM_TYPE_BUFFERED)
                .setContentType(url.toLowerCase().endsWith(".webm") ? "video/webm" : "video/mp4")
                .setMetadata(md);
        if (subsUrl != null) {
            mb.setMediaTracks(Collections.singletonList(new MediaTrack.Builder(1, MediaTrack.TYPE_TEXT)
                    .setName("Español").setSubtype(MediaTrack.SUBTYPE_SUBTITLES).setContentId(subsUrl)
                    .setContentType("text/vtt").setLanguage("es").build()));
        }
        MediaLoadRequestData.Builder rb = new MediaLoadRequestData.Builder().setMediaInfo(mb.build()).setAutoplay(true)
                .setCurrentTime((long) (from * 1000));
        subsOn = subsUrl != null && job.optBoolean("wantSubs", false);
        if (subsOn) rb.setActiveTrackIds(new long[]{1});
        c.registerCallback(estado);
        c.load(rb.build()).setResultCallback(r -> {
            if (!r.getStatus().isSuccess()) { Log.w(TAG, "load: " + r.getStatus()); siguiente(); }
        });
        ui.removeCallbacks(tick);
        ui.postDelayed(tick, 1000);
    }

    private final RemoteMediaClient.Callback estado = new RemoteMediaClient.Callback() {
        @Override public void onStatusUpdated() {
            RemoteMediaClient c = rmc();
            if (c == null) return;
            MediaStatus st = c.getMediaStatus();
            if (st == null) return;
            int ps = st.getPlayerState();
            if (ps == MediaStatus.PLAYER_STATE_PLAYING || ps == MediaStatus.PLAYER_STATE_PAUSED) { loaded = true; msg = ""; }
            if (ps == MediaStatus.PLAYER_STATE_BUFFERING) msg = loaded ? "CARGANDO…" : msg;
            if (ps == MediaStatus.PLAYER_STATE_IDLE) {
                int why = st.getIdleReason();
                if (why == MediaStatus.IDLE_REASON_FINISHED && loaded) { finished = true; cortar(); }
                else if (why == MediaStatus.IDLE_REASON_ERROR) { msg = "LA TELE NO PUDO CON ESTA FUENTE"; siguiente(); }
            }
        }
    };

    private final Runnable tick = new Runnable() {
        @Override public void run() {
            RemoteMediaClient c = rmc();
            if (c != null && loaded) {
                long p = c.getApproximateStreamPosition(), d = c.getStreamDuration();
                if (p > 0) lastPos = p / 1000.0;
                if (d > 0) lastDur = d / 1000.0;
            }
            if (!loaded && torrent != null && candSince > 0 && System.currentTimeMillis() - candSince > 150000) siguiente();
            long now = System.currentTimeMillis();
            if (loaded && now - lastSave > 30000) { lastSave = now; guardar(false); }
            ui.postDelayed(this, 1000);
        }
    };
    private long lastSave = 0;

    // ── Lo que pide la app ──────────────────────────────────────────────────
    JSONObject estado() {
        JSONObject o = new JSONObject();
        try {
            RemoteMediaClient c = rmc();
            MediaStatus st = c == null ? null : c.getMediaStatus();
            o.put("active", true).put("title", job.optString("title")).put("sub", job.optString("sub"))
                    .put("image", job.optString("image")).put("device", device).put("msg", msg)
                    .put("pos", lastPos).put("dur", lastDur).put("subs", subsOn).put("loaded", loaded)
                    .put("pause", st != null && st.getPlayerState() == MediaStatus.PLAYER_STATE_PAUSED)
                    .put("volume", st != null ? Math.round(st.getStreamVolume() * 100) : -1);
            if (c != null && loaded) o.put("pos", c.getApproximateStreamPosition() / 1000.0);
            Torrent t = torrent;
            if (t != null) { int[] e = t.estado(); o.put("peers", e[0]).put("kbps", e[1]); }
        } catch (Exception ignored) { }
        return o;
    }

    void comando(String cmd) {
        RemoteMediaClient c = rmc();
        String[] p = cmd.split(" ");
        try {
            switch (p[0]) {
                case "stop": cortar(); return;
                case "pause": if (c != null) c.togglePlayback(); return;
                case "seek": if (c != null) c.seek(new MediaSeekOptions.Builder().setPosition(Math.max(0, c.getApproximateStreamPosition() + (long) (Double.parseDouble(p[1]) * 1000))).build()); return;
                case "seekto": if (c != null) c.seek(new MediaSeekOptions.Builder().setPosition((long) (Double.parseDouble(p[1]) * 1000)).build()); return;
                case "vol": if (c != null && c.getMediaStatus() != null) c.setStreamVolume(Math.max(0, Math.min(1, c.getMediaStatus().getStreamVolume() + Double.parseDouble(p[1])))); return;
                case "subs":
                    if (c == null || c.getMediaInfo() == null || c.getMediaInfo().getMediaTracks() == null || c.getMediaInfo().getMediaTracks().isEmpty()) return;
                    subsOn = !subsOn;
                    c.setActiveMediaTracks(subsOn ? new long[]{1} : new long[0]);
                    return;
                case "next": siguiente(); return;
            }
        } catch (Exception e) { Log.w(TAG, "comando " + cmd, e); }
    }

    // ── Guardar y cortar ────────────────────────────────────────────────────
    private void guardar(boolean close) {
        if (!loaded && !finished) return;
        try {
            JSONObject r = new JSONObject();
            r.put("item", job.optJSONObject("item"));
            r.put("videoId", job.optString("videoId"));
            r.put("pos", lastPos);
            r.put("dur", lastDur);
            r.put("start", job.optDouble("start", 0));
            r.put("finished", finished || (lastDur > 0 && lastPos > lastDur * 0.92));
            r.put("close", close);
            r.put("tele", true);
            SharedPreferences sp = getSharedPreferences("reproductor", MODE_PRIVATE);
            sp.edit().putString("fin", r.toString()).apply();
        } catch (Exception ignored) { }
        MainActivity m = MainActivity.viva;
        if (m != null && close) m.entregarPendienteAhora();
    }

    void cortar() {
        if (cerrando) return;
        cerrando = true;
        ui.removeCallbacks(tick);
        guardar(true);
        try {
            RemoteMediaClient c = rmc();
            if (c != null) { c.unregisterCallback(estado); c.stop(); }
            cc().getSessionManager().removeSessionManagerListener(sesiones, CastSession.class);
            cc().getSessionManager().endCurrentSession(true);
        } catch (Exception ignored) { }
        if (worker != null) worker.interrupt();
        if (torrent != null) { final Torrent t = torrent; torrent = null; new Thread(t::stop).start(); }
        try { if (wake != null && wake.isHeld()) wake.release(); } catch (Exception ignored) { }
        try { if (wifi != null && wifi.isHeld()) wifi.release(); } catch (Exception ignored) { }
        if (actual == this) actual = null;
        stopForeground(STOP_FOREGROUND_REMOVE);
        stopSelf();
    }

    @Override public void onDestroy() {
        if (!cerrando) cortar();
        super.onDestroy();
    }
}
