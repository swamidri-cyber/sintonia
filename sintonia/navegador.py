"""SINTONÍA — el navegador de adentro, para iniciar sesión en YouTube y Letterboxd.

Un perfil propio de QtWebEngine (Chromium) guardado en la carpeta de datos de
la app. Cuando se detecta que entraste (las cookies de sesión de cada sitio),
se escriben en cuentas/<servicio>.txt (formato Netscape), que es lo que usan
los scripts de backend/ (yt-dlp, letterboxd.py).

En QML:  Navegador.perfil            → para WebEngineView.profile
         Navegador.url(servicio)     → dónde se inicia sesión
         Navegador.conectado(serv)   → ¿ya entraste?
         Navegador.guardar(serv, usuario)
         Navegador.olvidar(serv)     → cierra la sesión (borra sus cookies)
         señal cambio()              → llegaron cookies nuevas
"""
from __future__ import annotations

import json
import os
import sys
import time

from PySide6.QtCore import QObject, Property, QUrl, Signal, Slot
from PySide6.QtQml import QmlElement, QmlSingleton

from . import rutas

sys.path.insert(0, rutas.BACKEND)
import cuentas  # noqa: E402

try:
    from PySide6.QtWebEngineQuick import QQuickWebEngineProfile
    from PySide6.QtWebEngineCore import QWebEngineProfile  # noqa: F401
    HAY_WEB = True
except ImportError:          # sin QtWebEngine: sin inicio de sesión web (queda Zen/Firefox)
    HAY_WEB = False

QML_IMPORT_NAME = "Sintonia"
QML_IMPORT_MAJOR_VERSION = 1

SERVICIOS = {
    "youtube": {
        "url": "https://accounts.google.com/ServiceLogin?service=youtube&hl=es-419&continue="
               "https%3A%2F%2Fwww.youtube.com%2Fsignin%3Faction_handle_signin%3Dtrue%26next%3D%252F",
        "dominios": ("youtube.com", "google.com"),
        "marca": ("youtube.com", ("SAPISID", "__Secure-3PAPISID", "LOGIN_INFO")),
    },
    "letterboxd": {
        "url": "https://letterboxd.com/sign-in/",
        "dominios": ("letterboxd.com",),
        "marca": ("letterboxd.com", ("letterboxd.user.CURRENT",)),
    },
}


def _texto(b) -> str:
    if isinstance(b, str):
        return b
    try:
        return bytes(b).decode("utf-8", "replace")
    except Exception:
        return str(b)


@QmlElement
@QmlSingleton
class Navegador(QObject):
    cambio = Signal()

    def __init__(self, parent=None):
        super().__init__(parent)
        self._cookies = {}          # (dominio, nombre, ruta) → QNetworkCookie
        self._perfil = None
        if HAY_WEB:
            p = QQuickWebEngineProfile(self)
            p.setStorageName("sintonia")
            base = os.path.join(rutas.DATOS_USUARIO, "navegador")
            os.makedirs(base, exist_ok=True)
            p.setPersistentStoragePath(base)
            p.setCachePath(os.path.join(rutas.CACHE, "navegador"))
            p.setPersistentCookiesPolicy(QQuickWebEngineProfile.PersistentCookiesPolicy.ForcePersistentCookies)
            # un Chrome común (Google no deja entrar desde "navegadores embebidos")
            ua = p.httpUserAgent()
            ua = ua.replace("QtWebEngine/", "Safari/").split(" Safari/")[0] + " Safari/537.36"
            ua = "".join(x for x in ua if x.isprintable())
            p.setHttpUserAgent(ua)
            p.setHttpAcceptLanguage("es-419,es;q=0.9,en;q=0.7")
            st = p.cookieStore()
            st.cookieAdded.connect(self._agregada)
            st.cookieRemoved.connect(self._quitada)
            st.loadAllCookies()
            self._perfil = p
            nav = cuentas.leer_json("navegador.json") or {}
            nav["ua"] = ua
            cuentas.escribir_json("navegador.json", nav)

    # ── cookies ─────────────────────────────────────────────────────────
    def _clave(self, c):
        return (c.domain().lstrip("."), _texto(c.name()), c.path())

    def _agregada(self, c):
        self._cookies[self._clave(c)] = c
        self.cambio.emit()

    def _quitada(self, c):
        self._cookies.pop(self._clave(c), None)
        self.cambio.emit()

    def _de(self, servicio):
        doms = SERVICIOS[servicio]["dominios"]
        return [c for (d, _n, _p), c in self._cookies.items() if any(d == x or d.endswith("." + x) for x in doms)]

    # ── para QML ────────────────────────────────────────────────────────
    @Property(QObject, constant=True)
    def perfil(self):
        return self._perfil

    @Property(bool, constant=True)
    def disponible(self):
        return HAY_WEB

    @Slot(str, result=str)
    def url(self, servicio):
        return SERVICIOS.get(servicio, {}).get("url", "about:blank")

    @Slot(str, result=bool)
    def conectado(self, servicio):
        s = SERVICIOS.get(servicio)
        if not s:
            return False
        dom, nombres = s["marca"]
        for (d, n, _p), _c in self._cookies.items():
            if (d == dom or d.endswith("." + dom)) and n in nombres:
                return True
        return False

    @Slot(str, str, result=int)
    def guardar(self, servicio, usuario):
        """Escribe las cookies del servicio en cuentas/<servicio>.txt (Netscape)."""
        filas = ["# Netscape HTTP Cookie File", "# SINTONÍA: " + servicio, ""]
        n = 0
        for c in self._de(servicio):
            dom = c.domain()
            sub = "TRUE" if dom.startswith(".") else "FALSE"   # con punto: vale para los subdominios
            exp = c.expirationDate()
            vence = int(exp.toSecsSinceEpoch()) if exp.isValid() else int(time.time()) + 30 * 86400
            nombre, valor = _texto(c.name()), _texto(c.value())
            if "\t" in nombre or "\n" in valor:
                continue
            filas.append("\t".join([("#HttpOnly_" if c.isHttpOnly() else "") + dom, sub, c.path() or "/",
                                    "TRUE" if c.isSecure() else "FALSE", str(vence), nombre, valor]))
            n += 1
        p = cuentas.ruta(servicio + ".txt")
        tmp = p + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write("\n".join(filas) + "\n")
        try:
            os.chmod(tmp, 0o600)
        except OSError:
            pass
        os.replace(tmp, p)
        nav = cuentas.leer_json("navegador.json") or {}
        nav.setdefault("usuarios", {})[servicio] = usuario or nav.get("usuarios", {}).get(servicio, "")
        if self._perfil is not None:
            nav["ua"] = self._perfil.httpUserAgent()
        cuentas.escribir_json("navegador.json", nav)
        return n

    @Slot(str)
    def olvidar(self, servicio):
        if self._perfil is not None:
            st = self._perfil.cookieStore()
            for c in self._de(servicio):
                dom = c.domain().lstrip(".")
                st.deleteCookie(c, QUrl("https://" + dom))
        cuentas.borrar(servicio + ".txt")
        nav = cuentas.leer_json("navegador.json") or {}
        (nav.get("usuarios") or {}).pop(servicio, None)
        cuentas.escribir_json("navegador.json", nav)
        self.cambio.emit()

    @Slot(result=str)
    def estado(self):
        return json.dumps(cuentas.estado(), ensure_ascii=False)
