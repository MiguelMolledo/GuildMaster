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
- `sim/world/grid.gd` (`class_name Grid`): rejilla de costes a partir de `Catalog` + `map_id`: `in_bounds`, `walkable`,
  `cost`, `walkable_tiles`. `Grid.of(catalog, map_id)` la cachea fuera del estado (es estática), nunca en `WorldState`;
  `null` si no hay mapa.
- `sim/world/pathfinder.gd` (`class_name Pathfinder`; no `Path`): A* determinista, 8 vecinos sin cortar esquinas, paso
  = walk_cost × 10 recto / × 14 diagonal (enteros), desempate fijo (f, luego h, luego índice).
  `Pathfinder.find(grid, from: Vector2i, to: Vector2i) -> [[col, row], ...]` (sin `from`; vacío = sin camino o mismo sitio).
- `sim/world/movement.gd` (`class_name Movement`): el movimiento en `Sim.step` (después del reloj) y las reglas de
  `move_to`. Cada personaje con `path` suma 1 a `move_progress` por minuto; al llegar a `minutes_per_tile` pasa a la
  siguiente casilla (recta o diagonal, mismo tiempo). **`minutes_per_tile` = 2**, en `data/time.json`
  (`Data.catalog.time["minutes_per_tile"]`, o `Movement.minutes_per_tile(catalog)`). La variante dev no lo cambia. Eventos: `character_moved {actor, from, to}` por casilla y `character_arrived {actor, tile}`.
- Orden `{"type": "move_to", "actor": chr_id, "tile": [col, row]}`. Motivos de rechazo (con su clave `reason.<id>` en
  `i18n/strings.csv`): `unknown_actor`, `no_map`, `out_of_bounds`, `blocked`, `unreachable`, `dead`.
  Un `move_to` nuevo sustituye la ruta que quede (conserva `move_progress` solo si la siguiente casilla es la misma).
  Destino = casilla actual → ok sin ruta. Un personaje muerto pierde la ruta.
- Bot `wanderer` (`sim/bots/bot_wanderer.gd`): `move_to` aleatorios a los quietos. `tools/sim_runner.gd` y
  `tools/sim_bench.gd` usan por defecto el escenario `town_e_start`.

## Vista (subgrim «vista»)
- Lee `Game.state`, `Data.catalog` y `Events`; no calcula reglas (salvo `Iso` para pantalla↔casilla).
- Para interpolar: posición en pantalla = lerp(`position`, `path[0]`, `move_progress / minutes_per_tile`).
- Un clic sobre una casilla con un personaje seleccionado → `Game.give({"type": "move_to", ...})`. Nunca escribe el estado.
- Controles elegidos (vista): clic izquierdo sobre alguien de la familia humana lo selecciona (en otro sitio, deselecciona);
  clic derecho en una casilla = `move_to` del seleccionado. `minutes_per_tile` lo lee de `Movement.minutes_per_tile()`.
  Cifras de presentación (zoom 1/2, alturas greybox, tinte día/noche) en `data/view.json`.
