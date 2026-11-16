"""Tipografías de los subtítulos, en versión fija (libass no elige pesos dentro
de una fuente variable). Corre con el Python de .herramientas (fonttools):

    .herramientas/bin/python herramientas_subs.py
"""
import os
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ORIGEN = os.path.expanduser("~/.local/share/fonts/rice-cine")
DESTINO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "sintonia", "fonts")
# (archivo variable, peso, nombre con el que lo pide settings.json)
FUENTES = [("Inter[opsz,wght].ttf", 500, "Inter", "Medium", {"opsz": 24}),
           ("Figtree[wght].ttf", 600, "Figtree", "SemiBold", {}),
           ("AtkinsonHyperlegibleNext[wght].ttf", 500, "Atkinson Hyperlegible Next", "Medium", {}),
           ("Outfit[wght].ttf", 500, "Outfit", "Medium", {}),
           ("PlusJakartaSans[wght].ttf", 600, "Plus Jakarta Sans", "SemiBold", {})]

for arch, peso, fam, sub, extra in FUENTES:
    f = TTFont(os.path.join(ORIGEN, arch))
    ejes = {"wght": peso, **extra}
    ejes = {k: v for k, v in ejes.items() if k in [a.axisTag for a in f["fvar"].axes]}
    st = instantiateVariableFont(f, ejes)
    nombre = st["name"]
    full = f"{fam} {sub}"
    for rec in list(nombre.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17):
            nombre.removeNames(nameID=rec.nameID)
    nombre.setName(full, 1, 3, 1, 0x409)         # familia (para libass: "Inter Medium")
    nombre.setName("Regular", 2, 3, 1, 0x409)
    nombre.setName(full + ";SINTONIA", 3, 3, 1, 0x409)
    nombre.setName(full, 4, 3, 1, 0x409)
    nombre.setName(full.replace(" ", ""), 6, 3, 1, 0x409)
    nombre.setName(fam, 16, 3, 1, 0x409)          # familia tipográfica (para Qt: "Figtree" + peso)
    nombre.setName(sub, 17, 3, 1, 0x409)
    st["OS/2"].usWeightClass = peso
    out = os.path.join(DESTINO, "sub-" + full.replace(" ", "") + ".ttf")
    st.save(out)
    print(out, os.path.getsize(out))
