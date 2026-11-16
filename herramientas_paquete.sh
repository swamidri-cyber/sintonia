#!/usr/bin/env bash
# Arma el paquete de Linux en la máquina virtual (Ubuntu 24.04):
#   bash herramientas_paquete.sh      → dist/Sintonia-x86_64.AppImage (y la carpeta dist/Sintonia)
set -e
VM=~/VMs/sintonia/vm.sh
cd "$(dirname "$0")"
tar --exclude=.herramientas --exclude=.git --exclude=__pycache__ --exclude=dist --exclude=build -cz . \
  | $VM 'rm -rf ~/armado && mkdir ~/armado && tar -C ~/armado -xz'
$VM 'set -e; cd ~/armado
  ~/venv/bin/pip install -q --timeout 120 --retries 10 pyinstaller >/dev/null
  cd sintonia/shaders && for f in *.frag; do ~/venv/bin/pyside6-qsb --qt6 -o $f.qsb $f; done; cd ~/armado
  ~/venv/bin/pyinstaller --noconfirm --log-level WARN sintonia.spec 2>&1 | tail -15
  du -sh dist/Sintonia'
# AppImage
$VM 'set -e; cd ~/armado
  [ -x ~/appimagetool ] || { curl -sL -o ~/appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage; chmod +x ~/appimagetool; }
  rm -rf AppDir && mkdir -p AppDir/usr/lib && cp -a dist/Sintonia AppDir/usr/lib/sintonia
  cp empaque/AppRun AppDir/ && cp empaque/sintonia.desktop AppDir/ && cp sintonia/icono.png AppDir/sintonia.png
  ARCH=x86_64 ~/appimagetool --appimage-extract-and-run --comp zstd AppDir dist/Sintonia-x86_64.AppImage >/dev/null 2>&1
  ls -la dist/Sintonia-x86_64.AppImage'
