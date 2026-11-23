package ar.sintonia;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.graphics.Color;
import android.os.Bundle;
import android.webkit.CookieManager;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;

/** Entrar a Letterboxd con su propia página; las cookies quedan para la app. */
public class LoginActivity extends Activity {
    private WebView web;

    @SuppressLint("SetJavaScriptEnabled")
    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        web = new WebView(this);
        web.setBackgroundColor(Color.BLACK);
        WebSettings s = web.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        CookieManager.getInstance().setAcceptCookie(true);
        CookieManager.getInstance().setAcceptThirdPartyCookies(web, true);
        web.setWebViewClient(new WebViewClient() {
            @Override public void onPageFinished(WebView v, String url) { revisar(); }
        });
        setContentView(web);
        web.loadUrl("https://letterboxd.com/sign-in/");
    }

    private void revisar() {
        CookieManager.getInstance().flush();
        String ck = CookieManager.getInstance().getCookie("https://letterboxd.com");
        if (ck != null && ck.contains("letterboxd.user.CURRENT")) {
            setResult(RESULT_OK);
            finish();
        }
    }

    @Override
    public void onBackPressed() {
        if (web.canGoBack()) web.goBack();
        else { setResult(RESULT_CANCELED); finish(); }
    }
}
