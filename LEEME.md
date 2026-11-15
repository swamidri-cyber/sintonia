# SINTONÍA 同調

El modo cine hecho app: una tele que sintoniza canales (Stremio, Netflix, Disney+,
Max, Prime, Crunchyroll, YouTube), para Linux y Windows.

- `python -m sintonia` abre la app (necesita PySide6; los shaders se compilan con
  `pyside6-qsb`, ver `herramientas_vm.sh subir`).
- `python -m sintonia ipc cine dbg` consulta el estado (pruebas).
- `sintonia/compat.py` imita las piezas de Quickshell que usaba la interfaz original.
- `sintonia/backend/` son los scripts de datos (Stremio, YouTube, reproductor, tele,
  teléfono); reciben las carpetas de la app por variables de entorno (`lugares.py`).
- Se prueba en una máquina virtual silenciada: `herramientas_vm.sh` (QEMU sin pantalla
  ni sonido, `~/VMs/sintonia`).

Tipografías incluidas (todas con licencia SIL OFL): Noto Sans CJK JP recortada,
Departure Mono Nerd Font, Liberation Serif, Inter.
