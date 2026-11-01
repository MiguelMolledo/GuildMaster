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
- Detalles (edificio): en un mismo minuto se encadenan las órdenes instantáneas (entrar desde la puerta, puesto,
  equipar) hasta la primera que deja al actor ocupado (ruta o trabajo). Un trabajo con el ciclo acabado pero la salida
  bloqueada (`job.result` puesto) cuenta como terminado para la cola. `OrderQueue.has_pending(sim, actor)` y
  `OrderQueue.is_free(sim, actor)` son públicas.

## Reglas concretas de «edificio» (decisiones provisionales)
- **Dentro no se anda por el mapa**: `move_to` con `location != ""` se rechaza con `not_inside_map`; hay que dar antes
  `exit_building` (en pausa: `exit_building` y luego `move_to`, en cola).
- **`enter_building` desde lejos** camina a la puerta y queda como **primera orden de `order_queue`** con
  `"walking": true` hasta llegar; `Buildings.step` lo mete dentro en el mismo minuto de la llegada. Así no hace falta
  estado nuevo, una orden en vivo lo cancela (vacía la cola) y lo encolado después corre ya dentro. La vista puede
  mostrarlo como orden en curso. Entrar estando en otro edificio: `inside_other_building`; en el mismo: ok sin efecto.
- **Propiedad**: edificio propio = `owner` es el actor o su familia (`Buildings.owns`), también para `transfer`.
- **Cambiar de puesto** (`go_to_station` a otro) interrumpe el trabajo del puesto anterior (D11), igual que salir.
  Salir y cambiar de puesto llaman a `Production.interrupt(sim, building, zone)` y liberan `occupant`.
- **Proximidad en `transfer`**: personaje ↔ edificio: el personaje dentro (`not_inside`); si el actor no es una de las
  partes (dueño moviendo del almacén a otro), también dentro. Personaje ↔ personaje: misma familia (`not_family`) y
  misma casilla en el mapa o dentro del mismo edificio (`too_far`). Edificio ↔ edificio: `too_far`.
- **Peso del equipo**: `inventory.limit` del personaje guarda el hueco de la bolsa = `max_weight − peso equipado`;
  equipar/desequipar mueve el peso y el límite a la vez, así que `Inventory.can_add` (transfer, producción, compra) ya
  cuenta el equipo. `max_weight = limit + equipado` (30 kg del escenario); el bonus de Constitución (4.2.2, propuesta)
  irá en `Equipment.max_weight`. Si al personaje no le cabe: `too_heavy` (en `transfer`).
- **Ranuras**: la da el campo `slot` del objeto (`tool` herramientas, `clothes` ropa de trabajo y armadura,
  `accessory` la capa de viaje). Equipar con la ranura llena devuelve lo anterior a la bolsa.
- Motivos de «edificio»: `unknown_building`, `not_your_building`, `inside_other_building`, `no_door`, `not_inside`,
  `unknown_station`, `station_busy`, `not_inside_map`, `not_equippable`, `unknown_slot`, `slot_empty`, `too_heavy`,
  `too_far`, `not_family`.

## Reglas concretas de «produccion» (decisiones provisionales)
- **`job` completo**: `{actor, recipe, mode, start, end, inputs, window, touched, result: null|{item, quality, qty},
  blocked: bool}`. `result` se pone al acabar el ciclo (calidad tirada entonces); si la salida no cabe, `blocked = true`,
  evento `station_blocked` una vez y reintenta cada minuto. Al entregar: `work_done` y `job = null` (o ciclo nuevo).
- **Duración** = `roundi(duration_hours × 60 × duration_mult)` minutos (mín. 1). **Ventana** del toque: `window_hours`
  centrada en la mitad del ciclo y recortada al ciclo, `[ini, fin)`; solo en modos con `master_touch`.
- **Calidad**: fila de la tabla con `clamp(craft + craft_delta, 1, 10)`; después una tirada aparte por cada bonus
  (herramienta del edificio en `equipment.tool`: `tool_step_up_chance`; toque dado: `step_up_chance`), cada acierto
  sube un escalón hasta excelente. Siempre las mismas tiradas en el mismo orden (`state.rng`).
- **Entradas**: se cogen del almacén de menor a mayor calidad. **Hueco**: tras quitar las entradas, la salida debe caber
  en cualquiera de las 3 calidades (así no se bloquea salvo que el almacén cambie durante el ciclo).
- **`work_at` en el puesto donde ya trabaja** reinicia el ciclo con la receta/modo nuevos (devuelve antes las entradas,
  D11); en otro puesto del edificio, deja el anterior. Las validaciones cuentan ya lo que se devolvería.
- **Interrupción** (`Production.interrupt(sim, building, zone) -> returned`): devuelve lo que tiene el trabajo (las
  entradas, o el `result` si estaba bloqueado) al almacén, si no cabe a la bolsa del actor, y si tampoco al **suelo
  del puesto**: `zones[z].floor = [{item, quality, qty}]` (nadie lo recoge aún: queda abierto). No mueve a nadie.
  `Production.step` también interrumpe el trabajo si el actor ya no está en el puesto (`location`/`station`) o muere.
- **Auto-repetición**: al entregar, repite si el actor sigue en el puesto, `order_queue` vacía, edificio `normal`,
  `may_work`, receta desbloqueada, entradas y hueco. Si no, evento `work_idle {actor, building, zone, reason}` con
  `reason` = `queued` | un motivo de rechazo (`missing_inputs`, `storage_full`, `night_rest`...).
- **Quién trabaja** (`Production.may_work(sim, actor, building) -> "" | motivo`): `controlled_by == "human"` siempre
  (también de noche). El resto, en edificios con `night_production: "manual_only"` de noche → `night_rest`; en H2,
  en cualquier caso → `not_controlled` (no hay empleados hasta H5).
- **`buy_raw`**: coste `ceil(base_price × raw_purchase_markup × qty)` (data/production.json), entra como calidad normal.
- Públicas además: `Production.job_zone(sim, actor, building) -> zone|""`, `cycle_minutes`, `cycle_window`,
  `roll_quality`, `raw_cost`. `job_view` añade `blocked`.
- Motivos de «produccion»: `unknown_recipe`, `wrong_station`, `unknown_mode`, `building_not_ready`, `skill_too_low`,
  `needs_upgrade`, `missing_inputs`, `storage_full`, `not_working`, `not_at_station`, `not_careful`, `no_window`,
  `already_touched`, `unknown_item`, `not_raw`, `not_enough_gold`, `not_controlled`, `night_rest` (reutiliza
  `unknown_actor`, `dead`, `unknown_building`, `not_your_building`, `not_inside`, `unknown_station`, `station_busy`,
  `bad_quantity`).

## Eventos (para la vista)
`building_entered {actor, building}`, `building_left {actor, building}`, `station_taken {actor, building, zone}`,
`work_started {actor, building, zone, recipe, mode, end}`, `work_done {actor, building, zone, item, quality, qty}`,
`work_interrupted {actor, building, zone, returned}`, `master_window {building, zone, open: bool}`,
`master_touch_done {actor, building, zone}`, `station_blocked {building, zone, reason}`, `item_equipped`, `item_unequipped`,
`items_bought {actor, building, item, qty, cost}`, `work_idle {actor, building, zone, reason}` (deja de repetir).

## Consultas para la UI (funciones puras del sim; la vista no calcula reglas)
- `Production.recipe_options(sim, actor, building, zone) -> [{recipe, status: "ok"|"locked"|"missing_inputs"|"no_room"}]`
- `Production.job_view(sim, building, zone) -> {} | {actor, recipe, mode, progress: 0..1, window_open: bool, touched}`
- `Equipment.carried_weight(sim, actor) -> float`, `Equipment.max_weight(sim, actor) -> float`
- `Buildings.can_enter(sim, actor, building) -> {ok, reason}`
