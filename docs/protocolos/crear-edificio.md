# Crear un edificio

1. `python3 tools/new_content.py edificio --id <id> --en "<Name>" --es "<Nombre>"`
2. Rellena `data/buildings/<id>.json`: `category`, `parcel_type`, `footprint` (casillas), coste y días de obra, `upkeep`,
   `storage_stacks`, `base_employees`, `zones` (puestos: id y tipo craft/sales/storage/service), `night_production`,
   `includes_housing`.
3. Interior: escena con un `Marker2D` por puesto (nombre = id del puesto) cuando exista `game/interior/` (H2).
4. Arte: entradas `bld_<id>` (exterior) e `int_<id>` (kit de interior) en `assets/inventario.json`.
5. Árbol de mejoras (H5) y recetas del edificio.
6. Rituales: validador · `arte.py` · pruebas · arranque con un escenario que lo use.
