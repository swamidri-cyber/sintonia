#!/usr/bin/env bash
# Pruebas de SINTONÍA en la máquina virtual silenciada (~/VMs/sintonia).
#   bash herramientas_vm.sh subir        copia el proyecto y compila los shaders
#   bash herramientas_vm.sh abrir        abre la app en una pantalla virtual (sin sonido)
#   bash herramientas_vm.sh foto [arch]  saca una foto de la pantalla virtual
#   bash herramientas_vm.sh ipc <target> <fn> [args…]
#   bash herramientas_vm.sh cerrar
set -e
VM=~/VMs/sintonia/vm.sh
case "$1" in
  subir)
    tar -C "$(dirname "$0")" --exclude=.herramientas --exclude=.git --exclude=__pycache__ -cz sintonia \
      | $VM 'rm -rf ~/sintonia-app && mkdir ~/sintonia-app && tar -C ~/sintonia-app -xz'
    $VM 'cd ~/sintonia-app/sintonia/shaders && for f in *.frag; do ~/venv/bin/pyside6-qsb --qt6 -o $f.qsb $f || exit 1; done && ls'
    ;;
  abrir)
    timeout 25 $VM -n '[ -f ~/app.pid ] && kill $(cat ~/app.pid) 2>/dev/null; pkill -x Xvfb; sleep 0.5
      setsid Xvfb :9 -screen 0 1920x1080x24 >/dev/null 2>&1 < /dev/null & sleep 1
      cd ~/sintonia-app && DISPLAY=:9 QT_QPA_PLATFORM=xcb PULSE_SERVER=none setsid ~/venv/bin/python -m sintonia > ~/sintonia.log 2>&1 < /dev/null & echo $! > ~/app.pid; sleep 1; echo abierta'
    ;;
  foto)
    out=${2:-/tmp/claude-1000/-home-swami/9472d9f3-d9d8-44d6-aaf1-ba626bfb9556/scratchpad/foto.png}
    timeout 60 $VM "rm -f /tmp/f.png; DISPLAY=:9 timeout 30 scrot -o /tmp/f.png && cat /tmp/f.png" > "$out"; echo "$out"
    ;;
  ipc) shift; $VM "cd ~/sintonia-app && ~/venv/bin/python -m sintonia ipc $*" ;;
  log) $VM 'cat ~/sintonia.log' ;;
  cerrar) $VM '[ -f ~/app.pid ] && kill $(cat ~/app.pid); pkill -x Xvfb' || true ;;
esac
