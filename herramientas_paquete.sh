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
# Lo que la app no usa de Qt (3D, gráficos, mapas, estilos de controles)
$VM 'set -e; cd ~/armado/dist/Sintonia/_internal/PySide6/Qt
  rm -rf qml/Qt3D qml/QtQuick3D qml/QtCharts qml/QtGraphs qml/QtDataVisualization qml/QtLocation qml/QtPositioning \
         qml/QtQuick/Controls/Fusion qml/QtQuick/Controls/Universal qml/QtQuick/Controls/Material \
         qml/QtQuick/Controls/Imagine qml/QtQuick/Controls/FluentWinUI3 qml/QtQuick/Controls/iOS qml/QtQuick/Controls/macOS \
         qml/QtQuick/Scene3D qml/QtQuick/Scene2D qml/QtQuick/VirtualKeyboard qml/QtTextToSpeech qml/QtSensors qml/Qt/labs/stylekit
  rm -f lib/libQt63D* lib/libQt6Quick3D* lib/libQt6Graphs* lib/libQt6Charts* lib/libQt6DataVisualization* \
        lib/libQt6Location* lib/libQt6LabsStyleKit* lib/libQt6VirtualKeyboard* lib/libQt6TextToSpeech* lib/libQt6Sensors* \
        lib/libQt6QuickControls2Fusion* lib/libQt6QuickControls2Universal* lib/libQt6QuickControls2Material* \
        lib/libQt6QuickControls2Imagine* lib/libQt6QuickControls2FluentWinUI3* lib/libQt6QuickControls2IOS* lib/libQt6QuickControls2MacOS*
  du -sh ~/armado/dist/Sintonia'
# AppImage
$VM 'set -e; cd ~/armado
  [ -x ~/appimagetool ] || { curl -sL -o ~/appimagetool https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage; chmod +x ~/appimagetool; }
  rm -rf AppDir && mkdir -p AppDir/usr/lib && cp -a dist/Sintonia AppDir/usr/lib/sintonia
  cp empaque/AppRun AppDir/ && cp empaque/sintonia.desktop AppDir/ && cp sintonia/icono.png AppDir/sintonia.png
  ARCH=x86_64 ~/appimagetool --appimage-extract-and-run --comp zstd AppDir dist/Sintonia-x86_64.AppImage >/dev/null 2>&1
  ls -la dist/Sintonia-x86_64.AppImage'
