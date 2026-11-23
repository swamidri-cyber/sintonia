# SINTONÍA 同調 · para desarrolladores

Cómo está armado y cómo se compila. Para instalar la app, ver el [README](README.md).

## Escritorio (Linux y Windows)

- `python -m sintonia` abre la app (necesita PySide6; los shaders se compilan con
  `pyside6-qsb`, ver `herramientas_vm.sh subir`).
- `python -m sintonia ipc cine dbg` consulta el estado (pruebas).
- `sintonia/compat.py` imita las piezas de Quickshell que usaba la interfaz original.
- `sintonia/backend/` son los scripts de datos (Stremio, reproductor, tele,
  teléfono); reciben las carpetas de la app por variables de entorno (`lugares.py`).
- Se prueba en una máquina virtual silenciada: `herramientas_vm.sh` (QEMU sin pantalla
  ni sonido, `~/VMs/sintonia`).

Tipografías incluidas (todas con licencia SIL OFL): Noto Sans CJK JP recortada,
Departure Mono Nerd Font, Liberation Serif, Inter.

## Android (`android/`)

App nativa en Java: la interfaz es web (`app/src/main/assets/web`) dentro de un WebView,
el reproductor es libmpv (`dev.jdtech.mpv:libmpv`), los torrents se bajan en el teléfono con
libtorrent4j y se sirven al reproductor por HTTP local (`Torrent.java`), y Chromecast usa un
servicio en primer plano (`TeleService.java`).

```
cd android
JAVA_HOME=/ruta/a/jdk-21 ANDROID_HOME=/ruta/al/Sdk ./gradlew assembleRelease
```

Necesita JDK 21 y el SDK de Android 36.
