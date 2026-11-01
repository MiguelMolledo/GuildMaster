# Crear un edificio

1. `python3 tools/new_content.py edificio --id <id> --en "<Name>" --es "<Nombre>"`
2. Rellena `data/buildings/<id>.json`: `category`, `parcel_type`, `footprint` (casillas), coste y días de obra, `upkeep`,
   `storage_stacks`, `base_employees`, `zones` (puestos: id y tipo craft/sales/storage/service), `night_production`,
   `includes_housing`.
3. Escenas (en Godot, copiando las de la forja): `game/visuals/buildings/<id>.tscn` (con `Feet`, `Top` y su greybox)
   y, si tiene puestos, `game/visuals/interiors/<id>.tscn` con el nodo `Kit` (tamaño y puerta) y un `Marker2D` por
   puesto en `Stations/<id del puesto>`. Sin rutas en el JSON: la vista las encuentra por el id
   (`docs/protocolos/editar-a-mano.md`). Si un puesto es nuevo, su `game/visuals/stations/<puesto>.tscn`.
4. Arte: entradas `bld_<id>` (exterior) e `int_<id>` (kit de interior) en `assets/inventario.json`.
5. Árbol de mejoras (H5) y recetas del edificio.
6. Rituales: validador (comprueba escenas, marcadores y uid; si las escribiste fuera de Godot, `python3 tools/uids.py
   --fix`) · `arte.py` · galería (`-- --gallery`) · pruebas · arranque con un escenario que lo use.
