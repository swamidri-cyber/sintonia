#!/usr/bin/env python3
"""rice-cine — servidor web de la casa (puerto 20130, solo red local).

  /cast/<archivo>   lo que el Chromecast le pide a la PC: listas HLS
                    reescritas y subtítulos .vtt (los deja player.py en
                    $XDG_RUNTIME_DIR/rice-cine-web/cast)
  /app/…  /api/…    la app del teléfono (etapa C, ver phone.py)

Corre como servicio de usuario (rice-cine-web.service) desde que arranca la
sesión. Todo lo temporal vive en $XDG_RUNTIME_DIR: al reiniciar no queda nada.
"""
import http.server
import os
import sys

import lugares  # carpetas de SINTONÍA

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

PORT = 20130
RUNTIME = lugares.RUNTIME
CAST_DIR = os.path.join(RUNTIME, "web", "cast")
TYPES = {".vtt": "text/vtt; charset=utf-8", ".m3u8": "application/vnd.apple.mpegurl"}

try:
    import phone  # noqa: E402  (etapa C: si todavía no está, el servidor anda igual)
except Exception:
    phone = None


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def end_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        super().end_headers()

    def send_bytes(self, code, body, ctype, extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_OPTIONS(self):
        self.send_bytes(204, b"", "text/plain")

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        path = self.path.split("?", 1)[0]
        if path.startswith("/cast/"):
            name = os.path.basename(path)
            f = os.path.join(CAST_DIR, name)
            if not name or not os.path.isfile(f):
                return self.send_bytes(404, b"no", "text/plain")
            return self.send_bytes(200, open(f, "rb").read(), TYPES.get(os.path.splitext(name)[1], "application/octet-stream"))
        if phone:
            return phone.handle(self, "GET")
        self.send_bytes(404, b"no", "text/plain")

    def do_POST(self):
        if phone:
            return phone.handle(self, "POST")
        self.send_bytes(404, b"no", "text/plain")


if __name__ == "__main__":
    os.makedirs(CAST_DIR, exist_ok=True)
    srv = http.server.ThreadingHTTPServer(("0.0.0.0", PORT), Handler)
    srv.daemon_threads = True
    srv.serve_forever()
