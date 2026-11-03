# Crear un objeto

1. `python3 tools/new_content.py objeto --id <id_en_ingles> --en "<Name>" --es "<Nombre>"`
2. Rellena la ficha `data/items/<id>.json`: `category` (raw, material, product, tool, equipment, consumable, special),
   `weight` (kg), `max_stack` (el de su categoría), `base_price` (> 0), `market_stall` (o `null`), `slot` si se equipa.
3. Si lo produce alguien, crea su receta (crear-receta.md).
   Si la estación o los eventos deben mover su precio (alimentos, textiles, madera, construcción, medicina, armas,
   lujo), añade su id al grupo en `data/seasons.json` → `goods` (H13).
4. Registra su icono en `assets/inventario.json` (`icon_<id>`, tipo `icono`, estado `falta` o `greybox`). La ficha no
   lleva ruta: el icono es `assets/art/icons/<id>.png` por convención.
5. Rituales: `python3 tools/validate_content.py` (0 errores) · `python3 tools/arte.py` ·
   `godot --headless --path . -s tests/run_tests.gd -- --only=data`.
