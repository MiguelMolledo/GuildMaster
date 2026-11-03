"""Rutas del arte con fal. En git solo va lo final (assets/art/portraits/, illustrations/, icons/, buildings/fal/…),
el gasto (assets/art/fal_piloto/gasto.json), los informes y los scripts. Los crudos, mapas, pixelados intermedios y
vistas de revisión viven fuera de cualquier repo, con la misma estructura de carpetas:

  $GUILDMASTER_ARTE_CRUDOS (por defecto ~/Code/GuildMaster-arte-crudos)/
    fal_piloto/<pieza>/{crudo,celdas,local,i2p}/ y _refs/
    fal_produccion/{retratos,ilustraciones,iconos,fachadas,pool}/{crudo,i2p,celdas,natural,ref,vista}/

Así se pueden repetir el proceso y las galerías sin volver a pagar las generaciones.
"""
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CRUDOS = os.path.abspath(os.path.expanduser(os.environ.get("GUILDMASTER_ARTE_CRUDOS",
                                                           "~/Code/GuildMaster-arte-crudos")))
# En el repo
PILOTO_REPO = os.path.join(ROOT, "assets", "art", "fal_piloto")  # INFORME.md, gasto.json, galeria.html, */final/
LEDGER = os.path.join(PILOTO_REPO, "gasto.json")
# Fuera del repo
PILOTO = os.path.join(CRUDOS, "fal_piloto")
PRODUCCION = os.path.join(CRUDOS, "fal_produccion")


def piloto(*parts):
    """Ruta del piloto: lo final (<pieza>/final/…), el informe, el gasto y la galería en el repo; el resto, fuera."""
    if (len(parts) > 1 and parts[1] == "final") or (parts and parts[0] in ("gasto.json", "INFORME.md",
                                                                          "galeria.html")):
        return os.path.join(PILOTO_REPO, *parts)
    return os.path.join(PILOTO, *parts)


def produccion(*parts):
    return os.path.join(PRODUCCION, *parts)
