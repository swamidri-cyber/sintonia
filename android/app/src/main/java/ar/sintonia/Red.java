package ar.sintonia;

import android.content.Context;
import android.webkit.CookieManager;
import android.webkit.WebSettings;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.security.MessageDigest;
import java.util.Iterator;
import java.util.List;
import java.util.Map;

/** Pedidos HTTP para la interfaz (sin CORS), con caché en disco y las cookies del navegador de la app. */
final class Red {
    private static String ua;

    static String ua(Context c) {
        if (ua == null) {
            try { ua = WebSettings.getDefaultUserAgent(c); } catch (Exception e) { ua = "Mozilla/5.0 (Linux; Android) Sintonia"; }
        }
        return ua;
    }

    /** {url, method, headers, body, ttl (s), cookies} → {status, body, url} */
    static JSONObject pedir(Context c, JSONObject q) throws Exception {
        String url = q.getString("url");
        String method = q.optString("method", "GET");
        String body = q.has("body") && !q.isNull("body") ? q.getString("body") : null;
        long ttl = q.optLong("ttl", 0);
        boolean cookies = q.optBoolean("cookies", false);
        File cache = new File(c.getCacheDir(), "red/" + sha1(method + " " + url + " " + (body == null ? "" : body)));
        if (ttl > 0 && cache.exists() && System.currentTimeMillis() - cache.lastModified() < ttl * 1000) {
            return resp(200, leer(cache), url);
        }
        try {
            HttpURLConnection con = abrir(c, url, method, q.optJSONObject("headers"), body, cookies, 0);
            int st = con.getResponseCode();
            InputStream in = st >= 400 ? con.getErrorStream() : con.getInputStream();
            String txt = in == null ? "" : new String(todo(in), StandardCharsets.UTF_8);
            String fin = con.getURL().toString();
            if (cookies) guardarCookies(con, fin);
            con.disconnect();
            if (ttl > 0 && st == 200) {
                cache.getParentFile().mkdirs();
                try (OutputStream o = new FileOutputStream(cache)) { o.write(txt.getBytes(StandardCharsets.UTF_8)); }
            }
            return resp(st, txt, fin);
        } catch (Exception e) {
            if (ttl > 0 && cache.exists()) return resp(200, leer(cache), url);   // sin red: lo último que haya
            throw e;
        }
    }

    private static HttpURLConnection abrir(Context c, String url, String method, JSONObject headers, String body,
                                           boolean cookies, int saltos) throws Exception {
        HttpURLConnection con = (HttpURLConnection) new URL(url).openConnection();
        con.setConnectTimeout(15000);
        con.setReadTimeout(25000);
        con.setRequestMethod(method);
        con.setInstanceFollowRedirects(!cookies);
        con.setRequestProperty("User-Agent", ua(c));
        con.setRequestProperty("Accept-Language", "es-AR,es;q=0.9,en;q=0.7");
        if (headers != null) {
            for (Iterator<String> it = headers.keys(); it.hasNext(); ) {
                String k = it.next();
                con.setRequestProperty(k, headers.getString(k));
            }
        }
        if (cookies) {
            String ck = CookieManager.getInstance().getCookie(url);
            if (ck != null) con.setRequestProperty("Cookie", ck);
        }
        if (body != null) {
            con.setDoOutput(true);
            if (con.getRequestProperty("Content-Type") == null) con.setRequestProperty("Content-Type", "application/json");
            try (OutputStream o = con.getOutputStream()) { o.write(body.getBytes(StandardCharsets.UTF_8)); }
        }
        int st = con.getResponseCode();
        if (cookies && st >= 300 && st < 400 && saltos < 6) {        // redirecciones a mano, guardando cookies
            guardarCookies(con, url);
            String loc = con.getHeaderField("Location");
            con.disconnect();
            if (loc != null) return abrir(c, new URL(new URL(url), loc).toString(), "GET", headers, null, true, saltos + 1);
        }
        return con;
    }

    private static void guardarCookies(HttpURLConnection con, String url) {
        Map<String, List<String>> h = con.getHeaderFields();
        for (Map.Entry<String, List<String>> e : h.entrySet()) {
            if (e.getKey() != null && e.getKey().equalsIgnoreCase("Set-Cookie")) {
                for (String v : e.getValue()) CookieManager.getInstance().setCookie(url, v);
            }
        }
        CookieManager.getInstance().flush();
    }

    /** Baja un archivo (subtítulos) a la caché y devuelve la ruta. */
    static File bajar(Context c, String url, String nombre) throws Exception {
        HttpURLConnection con = (HttpURLConnection) new URL(url).openConnection();
        con.setConnectTimeout(15000);
        con.setReadTimeout(30000);
        con.setRequestProperty("User-Agent", ua(c));
        File f = new File(c.getCacheDir(), nombre);
        try (InputStream in = con.getInputStream(); OutputStream o = new FileOutputStream(f)) {
            byte[] b = new byte[16384];
            int n;
            while ((n = in.read(b)) > 0) o.write(b, 0, n);
        }
        return f;
    }

    private static JSONObject resp(int st, String body, String url) throws Exception {
        JSONObject r = new JSONObject();
        r.put("status", st);
        r.put("body", body);
        r.put("url", url);
        return r;
    }

    static byte[] todo(InputStream in) throws Exception {
        ByteArrayOutputStream b = new ByteArrayOutputStream();
        byte[] buf = new byte[16384];
        int n;
        while ((n = in.read(buf)) > 0) b.write(buf, 0, n);
        return b.toByteArray();
    }

    private static String leer(File f) throws Exception {
        return new String(Files.readAllBytes(f.toPath()), StandardCharsets.UTF_8);
    }

    /** La IP del celular en la red de la casa (para que la tele lo encuentre). */
    static String ipLocal() {
        try {
            String alguna = null;
            for (java.net.NetworkInterface ni : java.util.Collections.list(java.net.NetworkInterface.getNetworkInterfaces())) {
                if (!ni.isUp() || ni.isLoopback()) continue;
                for (java.net.InetAddress a : java.util.Collections.list(ni.getInetAddresses())) {
                    if (a instanceof java.net.Inet4Address && !a.isLoopbackAddress()) {
                        if (ni.getName().startsWith("wlan") || ni.getName().startsWith("eth")) return a.getHostAddress();
                        if (alguna == null) alguna = a.getHostAddress();
                    }
                }
            }
            return alguna != null ? alguna : "127.0.0.1";
        } catch (Exception e) {
            return "127.0.0.1";
        }
    }

    /** SRT → WebVTT (lo que entiende la tele). */
    static byte[] srtAVtt(byte[] srt) {
        String t = new String(srt, StandardCharsets.UTF_8);
        if (t.startsWith("\uFEFF")) t = t.substring(1);
        t = t.replace("\r\n", "\n").replaceAll("(\\d\\d:\\d\\d:\\d\\d),(\\d\\d\\d)", "$1.$2");
        return ("WEBVTT\n\n" + t).getBytes(StandardCharsets.UTF_8);
    }

    static String sha1(String s) {
        try {
            byte[] d = MessageDigest.getInstance("SHA-1").digest(s.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder();
            for (int i = 0; i < 12; i++) sb.append(String.format("%02x", d[i]));
            return sb.toString();
        } catch (Exception e) {
            return Integer.toHexString(s.hashCode());
        }
    }
}
