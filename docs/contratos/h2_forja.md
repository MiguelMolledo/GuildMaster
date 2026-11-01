# Contrato H2 · forja jugable a mano

Lo que comparten los subgrims de H2. Quien cambie un nombre lo cambia aquí. Base: `docs/contratos/h1_mundo.md`.
GDD: 4.1 (pausa activa), 4.3 (objetos e inventario), 4.4 (producción, calidad, modos, toque de maestro), 4.6.4 (interiores), D11.

## Estado (guardado v3, ya existe)
**Personaje** (además de lo de H1): `stats {craft, ...10}`, `gold: int`, `inventory` (peso, 30 kg),
`equipment {tool, clothes, accessory}` (cada uno `null` o `{item, quality}`), `location: ""|bld_id` (dentro de qué
edificio está; "" = en el mapa), `station: ""|zone_id` (en qué puesto está dentro), `order_queue: [orden, ...]`.

**Edificio** `state.buildings[bld]`: `{id, type, owner: fam_id|chr_id, origin [c,r], footprint [w,h], door [c,r],
state: "normal", inventory (10 pilas), zones: {zone_id: {occupant: ""|chr_id, job: null|{...}}}}`.
El escenario `town_e_start` trae `bld_0001` (forja de `fam_0001`, puerta en (26,19) sobre la calle mayor) con hierro ×10 y
carbón ×6. Hugo tiene Artesanía 7 y 100 de oro; Elena 4; Tomás 2.

**Trabajo en curso** `zones[z].job` (lo define «produccion»; mínimo): `{actor, recipe, mode, start, end, inputs: [{item,
quality, qty}], window: [start, end] | null, touched: bool}` con minutos absolutos del reloj.

## Datos
- `data/production.json` → `Catalog.production`: tabla de calidad por Artesanía, modos `fast|normal|careful`
  (`duration_mult`, `craft_delta`, `master_touch`), `master_touch {window_hours, step_up_chance}`, `tool_step_up_chance`.
- `data/buildings/forge.json`: `tool: "hammer"` (herramienta adecuada) e `interior {size, door, stations {zone: [c,r]}}`
  (disposición del interior para la vista; el sim no la usa para reglas).

## Órdenes (todas por `Orders.apply`; los manejadores ya están enlazados y devuelven `not_implemented` hasta que se hagan)
| Orden | Campos | Dueño | Regla |
|---|---|---|---|
| `enter_building` | actor, building | edificio | Edificio propio (de su familia o suyo). Camina hasta `door` (como `move_to`) y al llegar `location = bld`, `station = ""`. Si ya está en la puerta, entra al momento. |
| `exit_building` | actor | edificio | Interrumpe su trabajo si lo hay (D11), `location = ""`, `position = door`. |
| `go_to_station` | actor, zone | edificio | Dentro del edificio; el puesto existe y está libre (o es el suyo). `station = zone`. Instantáneo en el sim (la vista anima). |
| `equip` / `unequip` | actor, item, quality / actor, slot | edificio | Equipar saca el objeto del inventario a la ranura; el peso cuenta igual (`Equipment.carried_weight`). |
| `transfer` (existe) | actor, from, to, item, quality, qty | edificio | Añadir proximidad: personaje ↔ edificio solo si está dentro; personaje ↔ personaje de la familia solo en la misma casilla o dentro del mismo edificio. |
| `work_at` | actor, building, zone, recipe, mode | produccion | Dentro y en ese puesto (o lo pone en él si está libre). Receta de ese edificio y puesto, Artesanía ≥ `min_craft`, entradas en el almacén, hueco para la salida. Consume entradas al empezar. Auto-repite. |
| `stop_work` | actor | produccion | Interrumpe: devuelve las entradas (D11: almacén, si no cabe inventario del personaje, si no suelo del puesto). |
| `master_touch` | actor, building, zone | produccion | Solo modo `careful`, con la ventana abierta y el actor en el puesto. Una vez por ciclo. |
| `buy_raw` | actor, building, item, qty | produccion | **Provisional hasta H3**: dentro de su edificio, solo materias primas, paga `base_price × qty` del oro del actor y entra en el almacén. |

Motivos de rechazo nuevos (clave `reason.<id>` ES/EN en `i18n/strings.csv`): los elige cada dueño (p. ej. `not_inside`,
`not_your_building`, `station_busy`, `unknown_recipe`, `wrong_station`, `skill_too_low`, `missing_inputs`, `storage_full`,
`not_careful`, `no_window`, `already_touched`, `not_raw`, `not_enough_gold`, `too_heavy`, `too_far`).

## Pausa activa (dueño: edificio)
- `Game.give(order)` con el juego en pausa marca la orden `"queued": true`. `Sim.step` mete las `queued` en
  `order_queue` del actor (`OrderQueue.push`); una orden sin `queued` vacía su cola y se aplica ya (ya enlazado en `sim.gd`).
- `OrderQueue.step`: si el actor está **libre**, saca la primera de su cola y la aplica (si se rechaza, evento
  `order_refused` y pasa a la siguiente). Libre = sin `path` y sin trabajo en curso; un trabajo con más órdenes en cola
  cuenta como terminado al acabar su ciclo actual (no auto-repite si hay cola).
- Eventos: `order_queued {actor, order}`, `order_started {actor, order}`.

## Eventos (para la vista)
`building_entered {actor, building}`, `building_left {actor, building}`, `station_taken {actor, building, zone}`,
`work_started {actor, building, zone, recipe, mode, end}`, `work_done {actor, building, zone, item, quality, qty}`,
`work_interrupted {actor, building, zone, returned}`, `master_window {building, zone, open: bool}`,
`master_touch_done {actor, building, zone}`, `station_blocked {building, zone, reason}`, `item_equipped`, `item_unequipped`,
`items_bought {actor, building, item, qty, cost}`.

## Consultas para la UI (funciones puras del sim; la vista no calcula reglas)
- `Production.recipe_options(sim, actor, building, zone) -> [{recipe, status: "ok"|"locked"|"missing_inputs"|"no_room"}]`
- `Production.job_view(sim, building, zone) -> {} | {actor, recipe, mode, progress: 0..1, window_open: bool, touched}`
- `Equipment.carried_weight(sim, actor) -> float`, `Equipment.max_weight(sim, actor) -> float`
- `Buildings.can_enter(sim, actor, building) -> {ok, reason}`
