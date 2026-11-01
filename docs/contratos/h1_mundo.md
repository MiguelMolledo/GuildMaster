# Contrato H1 · mundo y movimiento

Lo que comparten el sim y la vista en H1. Quien cambie algo de aquí lo cambia en este fichero y avisa al manager.

## Datos (ya existen)
- `data/tiles.json` → `Catalog.tiles`: `kind -> {char, walk_cost, color}`. `walk_cost` null = bloqueada.
  `Catalog.tile_kind_of_char(ch)`.
- `data/maps/town_e.json` → `Catalog.maps()["town_e"]`: `size [w, h]`, `rows` (h cadenas de w caracteres; `rows[row][col]`),
  `spawns {nombre: [col, row]}`. Lo genera `tools/maps/make_town_e.py` (no editar el JSON a mano).
- `WorldState.map_id` (VERSION 2): id del mapa de la partida; "" = sin mapa (escenario `empty_town`).
- Escenario `data/scenarios/town_e_start.json`: familia humana `fam_0001` (chr_0001-0003) y familia IA `fam_0002`
  (chr_0004-0005) en `town_e`, a las 08:00 del día 0.

## Personaje (campos de H1)
`{id, name, female, family, controlled_by: "human"|"ai", alive, position: [col, row], path: [[col, row], ...], move_progress: int}`
- `position`: casilla actual (enteros). `path`: casillas que faltan, la primera es la siguiente; vacío = quieto.
- `move_progress`: minutos acumulados hacia la siguiente casilla del `path`.

## Sim (subgrim «sim»)
- `sim/world/grid.gd` (`class_name Grid`): rejilla de costes a partir de `Catalog` + `map_id` (bounds, walkable, cost).
  Se puede cachear fuera del estado (es estático), nunca dentro de `WorldState`.
- `sim/world/path.gd` (`class_name Path`... o el nombre que no choque con Godot): A* determinista, 8 vecinos sin cortar
  esquinas, desempate fijo.
- Movimiento en `Sim.step`: cada personaje con `path` suma minutos; al llegar a `minutes_per_tile` (cifra en `data/`)
  pasa a la siguiente casilla. Eventos: `character_moved {actor, from, to}` por casilla y `character_arrived {actor, tile}`.
- Orden `{"type": "move_to", "actor": chr_id, "tile": [col, row]}`. Motivos de rechazo (con su clave `reason.<id>` en
  `i18n/strings.csv`): `unknown_actor`, `no_map`, `out_of_bounds`, `blocked`, `unreachable`, `dead`.
  Un `move_to` nuevo sustituye la ruta que quede. Destino = casilla actual → ok sin ruta.

## Vista (subgrim «vista»)
- Lee `Game.state`, `Data.catalog` y `Events`; no calcula reglas (salvo `Iso` para pantalla↔casilla).
- Para interpolar: posición en pantalla = lerp(`position`, `path[0]`, `move_progress / minutes_per_tile`).
- Un clic sobre una casilla con un personaje seleccionado → `Game.give({"type": "move_to", ...})`. Nunca escribe el estado.
