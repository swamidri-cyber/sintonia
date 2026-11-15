#!/usr/bin/env bash
# Recorta las tipografías que trae la app (las CJK enteras pesan ~20 MB c/u).
# Uso: bash herramientas_fuentes.sh   (necesita .herramientas con fonttools)
set -e; cd "$(dirname "$0")"
CH=$(python3 -c "
import glob
s=set()
for f in glob.glob('sintonia/qml/*.qml'): s|=set(c for c in open(f).read() if ord(c)>0x2000)
print(''.join(sorted(s)))")
UNI="U+0020-024F,U+0300-036F,U+1E00-1EFF,U+2000-206F,U+20A0-20CF,U+2100-21FF,U+2190-21FF,U+2200-22FF,U+2300-23FF,U+2400-243F,U+2500-25FF,U+2600-27BF,U+2800-28FF,U+3000-303F"
for w in Regular Medium Bold Black; do
  .herramientas/bin/pyftsubset /usr/share/fonts/noto-cjk/NotoSansCJK-$w.ttc --font-number=0 \
    --unicodes="$UNI" --text="$CH" --layout-features='*' --output-file=sintonia/fonts/SintoniaSans-$w.otf
done
cp /usr/share/fonts/OTF/DepartureMonoNerdFont-Regular.otf sintonia/fonts/
cp /usr/share/fonts/liberation/LiberationSerif-Bold.ttf sintonia/fonts/
cp "$HOME/.local/share/fonts/rice-cine/Inter[opsz,wght].ttf" sintonia/fonts/Inter.ttf
