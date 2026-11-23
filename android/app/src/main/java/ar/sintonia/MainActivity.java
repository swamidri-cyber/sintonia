package ar.sintonia;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.content.Intent;
import android.content.SharedPreferences;
import android.graphics.Color;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.VibrationEffect;
import android.os.Vibrator;
import android.view.View;
import android.view.Window;
import android.webkit.CookieManager;
import android.webkit.JavascriptInterface;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import org.json.JSONObject;

import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/** La interfaz de tele (web/index.html) y el puente con Android. */
public class MainActivity extends Activity {
    static final int PLAY = 1, LOGIN = 2;
    private WebView web;
    private final ExecutorService pool = Executors.newFixedThreadPool(8);
    private final Handler ui = new Handler(Looper.getMainLooper());
    private boolean listo = false;

    @SuppressLint({"SetJavaScriptEnabled", "AddJavascriptInterface"})
    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        web = new WebView(this);
        web.setBackgroundColor(Color.parseColor("#07020c"));
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setAllowFileAccess(true);
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setTextZoom(100);
        CookieManager.getInstance().setAcceptCookie(true);
        web.addJavascriptInterface(new Puente(), "Android");
        web.setWebChromeClient(new WebChromeClient());
        web.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView v, String url) { listo = true; entregarPendiente(); }
        });
        web.setOverScrollMode(View.OVER_SCROLL_NEVER);
        setContentView(web);
        web.loadUrl("file:///android_asset/web/index.html");
        probar(getIntent());
    }

    @Override
    protected void onNewIntent(Intent i) { super.onNewIntent(i); probar(i); }

    /** Pruebas: am start -n ar.sintonia/.MainActivity --es probar '{job}' abre el reproductor directo. */
    private void probar(Intent i) {
        String job = i == null ? null : i.getStringExtra("probar");
        if (job == null) return;
        i.removeExtra("probar");
        Intent p = new Intent(this, PlayerActivity.class);
        p.putExtra("job", job);
        startActivityForResult(p, PLAY);
    }

    @Override
    public void onBackPressed() {
        js("window.__back && window.__back()");
    }

    void js(String code) {
        ui.post(() -> web.evaluateJavascript(code, null));
    }

    /** Lo que el reproductor dejó guardado (aunque la app se haya cerrado a mitad). */
    private void entregarPendiente() {
        SharedPreferences p = getSharedPreferences("reproductor", MODE_PRIVATE);
        String fin = p.getString("fin", null);
        if (fin != null && listo) {
            p.edit().remove("fin").apply();
            js("window.__ended && window.__ended(" + JSONObject.quote(fin) + ")");
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        entregarPendiente();
    }

    @Override
    protected void onActivityResult(int req, int res, Intent data) {
        super.onActivityResult(req, res, data);
        if (req == PLAY) entregarPendiente();
        if (req == LOGIN) js("window.__lb && window.__lb(" + (res == RESULT_OK) + ")");
    }

    class Puente {
        @JavascriptInterface
        public void req(String id, String json) {
            pool.execute(() -> {
                String out;
                try {
                    out = Red.pedir(MainActivity.this, new JSONObject(json)).toString();
                } catch (Exception e) {
                    try { out = new JSONObject().put("status", 0).put("error", String.valueOf(e.getMessage())).toString(); }
                    catch (Exception x) { out = "{\"status\":0}"; }
                }
                js("window.__res(" + JSONObject.quote(id) + "," + out + ")");
            });
        }

        @JavascriptInterface
        public void play(String job) {
            Intent i = new Intent(MainActivity.this, PlayerActivity.class);
            i.putExtra("job", job);
            ui.post(() -> startActivityForResult(i, PLAY));
        }

        @JavascriptInterface
        public void lbLogin() {
            ui.post(() -> startActivityForResult(new Intent(MainActivity.this, LoginActivity.class), LOGIN));
        }

        @JavascriptInterface
        public boolean lbLogged() {
            String ck = CookieManager.getInstance().getCookie("https://letterboxd.com");
            return ck != null && ck.contains("letterboxd.user.CURRENT");
        }

        @JavascriptInterface
        public void lbLogout() {
            CookieManager cm = CookieManager.getInstance();
            String ck = cm.getCookie("https://letterboxd.com");
            if (ck != null) {
                for (String part : ck.split(";")) {
                    String name = part.split("=")[0].trim();
                    cm.setCookie("https://letterboxd.com", name + "=; Max-Age=0; Path=/");
                    cm.setCookie("https://letterboxd.com", name + "=; Max-Age=0; Path=/; Domain=.letterboxd.com");
                }
            }
            cm.flush();
        }

        @JavascriptInterface
        public void vibrate(int ms) {
            Vibrator v = (Vibrator) getSystemService(VIBRATOR_SERVICE);
            if (v != null) v.vibrate(VibrationEffect.createOneShot(Math.max(1, ms), VibrationEffect.DEFAULT_AMPLITUDE));
        }

        @JavascriptInterface
        public void barColor(String hex) {
            ui.post(() -> {
                try {
                    Window w = getWindow();
                    int c = Color.parseColor(hex);
                    w.setStatusBarColor(c);
                    w.setNavigationBarColor(c);
                    web.setBackgroundColor(c);
                } catch (Exception ignored) { }
            });
        }

        @JavascriptInterface
        public void salir() { ui.post(MainActivity.this::finish); }
    }
}
