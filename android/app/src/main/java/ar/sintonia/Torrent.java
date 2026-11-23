package ar.sintonia;

import android.content.Context;
import android.util.Log;

import org.libtorrent4j.FileStorage;
import org.libtorrent4j.Priority;
import org.libtorrent4j.SessionHandle;
import org.libtorrent4j.SessionManager;
import org.libtorrent4j.TorrentFlags;
import org.libtorrent4j.TorrentHandle;
import org.libtorrent4j.TorrentInfo;
import org.libtorrent4j.TorrentStatus;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.io.RandomAccessFile;
import java.net.ServerSocket;
import java.util.List;
import java.util.Locale;

import fi.iki.elonen.NanoHTTPD;

/**
 * Ver un torrent mientras baja (lo que hace el servidor de Stremio en la PC):
 * baja primero las partes que el reproductor va a leer y se las sirve por
 * http://127.0.0.1:<puerto>/video. Al terminar se borra todo.
 */
final class Torrent {
    private static final String TAG = "SintoniaTorrent";
    private static SessionManager sm;
    private static final String[] TRACKERS = {
            "udp://tracker.opentrackr.org:1337/announce", "udp://open.demonii.com:1337/announce",
            "udp://tracker.torrent.eu.org:451/announce", "udp://open.stealth.si:80/announce",
            "udp://exodus.desync.com:6969/announce", "udp://tracker.openbittorrent.com:6969/announce",
            "udp://explodie.org:6969/announce", "udp://tracker.dler.org:6969/announce"};
    private static final String[] VIDEO = {".mkv", ".mp4", ".avi", ".m4v", ".mov", ".webm", ".ts", ".wmv"};

    private final File dir;
    private final String hash;
    private final int fileIdx;
    private final List<String> sources;
    private volatile boolean closed = false;
    private TorrentHandle th;
    private TorrentInfo ti;
    private int idx, pieceLen, firstPiece, lastPiece;
    private long fileOff, fileSize;
    private File file;
    private Server server;
    volatile String error = null;
    volatile String fileName = "";

    Torrent(Context c, String hash, int fileIdx, List<String> sources) {
        this.hash = hash.toLowerCase(Locale.ROOT);
        this.fileIdx = fileIdx;
        this.sources = sources;
        this.dir = new File(c.getCacheDir(), "torrent");
    }

    static synchronized SessionManager session() {
        if (sm == null) {
            sm = new SessionManager(false);
            sm.start();
        }
        return sm;
    }

    /** Bloquea hasta tener la dirección para el reproductor (o null si no se pudo). */
    String start(int timeoutSec) {
        try {
            borrar(dir);
            dir.mkdirs();
            SessionManager s = session();
            StringBuilder mag = new StringBuilder("magnet:?xt=urn:btih:").append(hash);
            for (String t : TRACKERS) mag.append("&tr=").append(java.net.URLEncoder.encode(t, "UTF-8"));
            if (sources != null) for (String src : sources) {
                if (src.startsWith("tracker:")) mag.append("&tr=").append(java.net.URLEncoder.encode(src.substring(8), "UTF-8"));
            }
            byte[] data = s.fetchMagnet(mag.toString(), timeoutSec, dir);
            if (data == null || closed) { error = "No aparece nadie que comparta este archivo"; return null; }
            ti = new TorrentInfo(data);
            FileStorage fs = ti.files();
            idx = fileIdx >= 0 && fileIdx < fs.numFiles() ? fileIdx : elegir(fs);
            Priority[] pr = Priority.array(Priority.IGNORE, fs.numFiles());
            pr[idx] = Priority.DEFAULT;
            s.download(ti, dir, null, pr, null, TorrentFlags.SEQUENTIAL_DOWNLOAD);
            for (int i = 0; i < 100 && (th == null || !th.isValid()); i++) {
                th = s.find(ti.infoHash());
                if (th == null || !th.isValid()) Thread.sleep(100);
            }
            if (th == null) { error = "No se pudo empezar la descarga"; return null; }
            pieceLen = ti.pieceLength();
            fileOff = fs.fileOffset(idx);
            fileSize = fs.fileSize(idx);
            fileName = fs.fileName(idx);
            firstPiece = (int) (fileOff / pieceLen);
            lastPiece = (int) ((fileOff + fileSize - 1) / pieceLen);
            file = new File(dir, fs.filePath(idx));
            // el principio y el final (los índices de mkv/mp4 suelen estar ahí)
            for (int p = firstPiece, k = 0; p <= lastPiece && k < 6; p++, k++) th.setPieceDeadline(p, 100 * k);
            th.setPieceDeadline(lastPiece, 400);
            if (lastPiece - 1 > firstPiece) th.setPieceDeadline(lastPiece - 1, 500);
            int port;
            try (ServerSocket ss = new ServerSocket(0)) { port = ss.getLocalPort(); }
            server = new Server(port);
            server.start(NanoHTTPD.SOCKET_READ_TIMEOUT, true);
            return "http://127.0.0.1:" + port + "/video";
        } catch (Exception e) {
            Log.e(TAG, "start", e);
            error = String.valueOf(e.getMessage());
            return null;
        }
    }

    private static int elegir(FileStorage fs) {
        int best = 0;
        long size = -1;
        for (int i = 0; i < fs.numFiles(); i++) {
            String n = fs.fileName(i).toLowerCase(Locale.ROOT);
            boolean video = false;
            for (String v : VIDEO) video |= n.endsWith(v);
            if (video && fs.fileSize(i) > size) { size = fs.fileSize(i); best = i; }
        }
        return best;
    }

    /** {peers, velocidad KB/s, % del archivo} */
    int[] estado() {
        if (th == null || !th.isValid()) return new int[]{0, 0, 0};
        TorrentStatus st = th.status();
        return new int[]{st.numPeers(), st.downloadRate() / 1024, (int) (st.progress() * 100)};
    }

    private void esperar(int piece) throws IOException {
        if (th.havePiece(piece)) return;
        int ahead = Math.max(8, (24 << 20) / pieceLen);
        for (int p = piece, k = 0; p <= lastPiece && k < ahead; p++, k++) {
            if (!th.havePiece(p)) th.setPieceDeadline(p, 150 * k);
        }
        while (!th.havePiece(piece)) {
            if (closed) throw new IOException("cerrado");
            try { Thread.sleep(60); } catch (InterruptedException e) { throw new IOException("cortado"); }
        }
    }

    void stop() {
        closed = true;
        try { if (server != null) server.stop(); } catch (Exception ignored) { }
        try { if (th != null && th.isValid()) session().remove(th, SessionHandle.DELETE_FILES); } catch (Exception ignored) { }
        new Thread(() -> {
            try { Thread.sleep(1500); } catch (InterruptedException ignored) { }
            borrar(dir);
        }).start();
    }

    private static void borrar(File f) {
        File[] l = f.listFiles();
        if (l != null) for (File x : l) borrar(x);
        f.delete();
    }

    private class Lector extends InputStream {
        private long pos;
        private final long end;
        private RandomAccessFile raf;

        Lector(long start, long end) { this.pos = start; this.end = end; }

        @Override public int read() throws IOException {
            byte[] b = new byte[1];
            return read(b, 0, 1) <= 0 ? -1 : b[0] & 0xff;
        }

        @Override public int read(byte[] b, int off, int len) throws IOException {
            if (pos > end) return -1;
            long abs = fileOff + pos;
            int piece = (int) (abs / pieceLen);
            esperar(piece);
            long pieceEnd = (long) (piece + 1) * pieceLen - fileOff;     // fin de esta parte, en el archivo
            int n = (int) Math.min(len, Math.min(pieceEnd - pos, end - pos + 1));
            if (raf == null) {
                for (int i = 0; i < 100 && !file.exists(); i++) {
                    try { Thread.sleep(50); } catch (InterruptedException e) { throw new IOException("cortado"); }
                }
                raf = new RandomAccessFile(file, "r");
            }
            raf.seek(pos);
            int r = raf.read(b, off, n);
            if (r > 0) pos += r;
            return r;
        }

        @Override public void close() throws IOException { if (raf != null) raf.close(); }
    }

    private class Server extends NanoHTTPD {
        Server(int port) { super("127.0.0.1", port); }

        @Override public Response serve(IHTTPSession s) {
            String mime = fileName.toLowerCase(Locale.ROOT).endsWith(".mp4") ? "video/mp4" : "video/x-matroska";
            String range = s.getHeaders().get("range");
            long start = 0, end = fileSize - 1;
            if (range != null && range.startsWith("bytes=")) {
                String[] r = range.substring(6).split("-");
                try {
                    start = Long.parseLong(r[0].trim());
                    if (r.length > 1 && !r[1].trim().isEmpty()) end = Math.min(end, Long.parseLong(r[1].trim()));
                } catch (NumberFormatException ignored) { }
            }
            if (start >= fileSize) {
                Response res = newFixedLengthResponse(Response.Status.RANGE_NOT_SATISFIABLE, "text/plain", "");
                res.addHeader("Content-Range", "bytes */" + fileSize);
                return res;
            }
            long len = end - start + 1;
            Response res = newFixedLengthResponse(range != null ? Response.Status.PARTIAL_CONTENT : Response.Status.OK,
                    mime, new Lector(start, end), len);
            res.addHeader("Accept-Ranges", "bytes");
            if (range != null) res.addHeader("Content-Range", "bytes " + start + "-" + end + "/" + fileSize);
            return res;
        }
    }
}
