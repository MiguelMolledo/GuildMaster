# Contrato H5 · mejoras, obras, efectos e inspecciones

Lo que comparten los subgrims de H5 («arbol», «vista», «balance»; antes «base» y «visuales»). Quien cambie un nombre
lo cambia aquí. Base: `docs/contratos/h1_mundo.md` … `h4_empleados.md`. GDD: 4.8 (entero), 4.6.2-4.6.4 (estados,
propiedad, interiores y kit), 4.7 (huecos, lealtad, maestros, Seguridad), 4.5.4 (mostrador), 4.12.1-4.12.2
(reputación, títulos), 4.19 (`upgrades`, `fines`, dianas `goldflow`), 06 (ficha de mejora), 09 §9.3 (presupuesto de
visuales: genéricos reutilizables + variantes de puesto). Criterio del hito (10, fila H5): bot `artisan_expert` compra
mejoras y su producción sube lo esperado; dianas `goldflow` de «Forja con empleados» y peso de sumideros 30-60 % en
verde; 3 días seguidos jugables por el owner sin consola.

## Zonas (ficheros de cada uno)
| Subgrim | Ficheros | Pruebas |
|---|---|---|
| arbol | `sim/econ/upgrades.gd` (`order_buy`, `Upgrades.step`; puede afinar `status_of` y `complete` sin cambiar su forma), `sim/econ/inspections.gd` (`Inspections.step`), y **la integración de los efectos** en `sim/econ/production.gd`, `sim/econ/staff.gd`, `sim/econ/work_queue.gd`, `sim/econ/market.gd` (solo lo que dice la tabla «Quién lee cada efecto») | `tests/test_econ_upgrades*.gd`, `tests/test_econ_inspections*.gd` |
| vista | `game/` (panel del árbol en la barra del interior, obra en curso, visuales de mejora en interior y exterior con los ids de abajo), `game/sim_query.gd`, `data/view.json` | `tests/test_game_*.gd` |
| balance | `sim/bots/bot_artisan_expert.gd`, registro del bot y medidas nuevas en `tools/sim_runner.gd`, `data/targets.json`, y las cifras [balance] de `data/upgrades/forge/*.json` (oro, materiales, días), `data/market.json`, `data/items/*` (precios, D14) | `tests/test_bots_*.gd` |

Comunes (solo se tocan si el contrato lo dice, y se avisa): `sim/core/*`, `sim/meta/save_file.gd`,
`sim/meta/new_game.gd`, `sim/world/buildings.gd`, `sim/econ/money.gd`, `data/upgrade_rules.json`, `data/employees.json`,
`tools/maps/make_town_e.py`, `tools/scenarios/make_upgrade_scenarios.gd`, `tools/validate_content.py` (cada uno toca
solo su función: `check_h5*` es de esta base; las rutas de arte, de «visuales»). `i18n/strings.csv`: cada uno **añade
sus claves al final**. «balance» cambia cifras en las fichas de mejora, no su forma (ramas, niveles, requisitos,
tipos de efecto): eso se pide aquí.

## Estado (guardado v6, ya existe)
- **Edificio** `buildings[b]`, campos nuevos (todos los edificios):
  - `upgrades: [id]` — mejoras **terminadas**, en el orden en que terminaron. (Production, Staff y RivalAI ya lo leían
    con `get("upgrades", [])`.)
  - `upgrade_work: null | {upgrade, actor, start, end}` — la obra en curso: minutos absolutos del reloj; `end = start +
    roundi(build_days × 1440)`. Solo una a la vez (GDD 4.8).
  - `inspection: {last_day, caught, escaped, fines, escape_ready_day}` — memoria de las inspecciones
    (`Upgrades.new_inspection()`: `-1, 0, 0, 0, 0`). `last_day`: último amanecer en que se tiró; `fines`: oro multado
    en total; `escape_ready_day`: primer día en que el pasadizo vuelve a servir.
- Sin campos nuevos en la raíz, ni en personaje ni familia. La familia aún no tiene `title` (H9): `Upgrades.family_title`
  devuelve `default_title` ("common") si falta; tampoco hay `attitudes` (honestidad 0, ver Inspections).
- **Regla:** dentro de `upgrade_work` e `inspection` el dueño («arbol») puede añadir campos sin subir versión, siempre
  JSON y con su prueba de ida y vuelta. Un campo fuera de ellos sí es cambio de formato: se pide al manager.
- Migración 5 → 6 (`SaveFile._step`): los tres campos vacíos. Prueba: `tests/test_core_h5_base.gd` con
  `tests/data/saves/v5_two_employees.json`. Todos los escenarios regenerados en v6 sin otra diferencia (comprobado).

## Datos
- **`data/upgrades/<árbol>/<id>.json`** (una ficha por mejora; carpeta = árbol) → `Catalog.upgrades()`,
  `catalog.upgrade(id)`, `catalog.upgrade_tree("forge")` (ids ordenados). Forma (06):
  `{id, name_key, tree, branch, level, cost {gold, items [{item, qty}]}, requires {upgrades [ids], stat null|{id, min},
  title null|id}, build_days, effects [{kind, <valor>}], visual {interior_node, exterior_overlay}}`.
  Plantilla: `data/_templates/_upgrade.json`. Ids: `forge_<rama>_<nivel>`.
- **`data/upgrade_rules.json`** → `catalog.upgrade_rules`, `catalog.effect_kind(kind)`: `branches` (orden de la UI),
  `levels` (3), `effect_kinds` (abajo), `titles` (escalera de 4.12.2) + `default_title`, `inspections {honesty_divisor
  200, fine [10, 50], reputation −10, escape_cooldown_days 8}`.
- **Árbol de la Forja** (24, cifras del GDD 4.8 tal cual; los costes en oro los sube «balance», D14):

| Rama | Nivel 1 | Nivel 2 | Nivel 3 |
|---|---|---|---|
| production | `forge_production_1` Fuelle: 3 oro, 2 wood, 0,5 d → `production_speed ×1,2` | `_2` Temple: 8, 5 iron_ingot, 1 d → ×1,4 | `_3` Forja de maestro: 20, craft 6, 1 d → ×1,6 + `unlock_recipe forge_steel` |
| capacity | `forge_capacity_1` Segundo yunque: 10, 5 ingot, 3 wood, 1 d → `new_zone anvil_2` (como `anvil`) | `_2` Almacén: 8, 8 wood, 1 d → `extra_storage +10` | `_3` Tercer horno: 25, 10 ingot, craft 5, 1,5 d → `new_zone furnace_2` (como `furnace`) |
| quality | `forge_quality_1` Acero templado: 5, 3 coal, 1 d → `quality_bonus +1` | `_2` Grabado: 12, craft 5, 1 d → +2 | `_3` Sello: 30, craft 7, 1,5 d → +3 y `price_multiplier ×1,5` |
| commerce | `forge_commerce_1` Mostrador: 6, 4 wood, 1 d → `counter_sales` | `_2` Escaparate: 15, 3 ingot, 1 d → `customer_bonus +0,3` | `_3` Reputación comercial: 25, **requiere `forge_facade_1`**, 1 d → +0,5 y `price_multiplier ×1,1` |
| staff | `forge_staff_1` Dormitorio: 8, 6 wood, 1 d → `max_employees +1` | `_2` Comedor: 12, 5 wood, 1,5 d → `loyalty_bonus +10` | `_3` Taller de maestro: 30, **requiere `forge_capacity_2`**, 1,5 d → `max_employees +1`, `allow_rank master` |
| facade | `forge_facade_1` Piedra: 15, 10 stone, 1,5 d → `reputation +10`, `loyalty_bonus +5` | `_2` Jardín: 20, 5 wood, 1,5 d → +20, +5 | `_3` Noble: 40, título `citizen`, 2 d → +30, +5 |
| security | `forge_security_1` Cerradura: 5, 2 ingot, 1 d → `protection 0,2` | `_2` Guardia: 15, 1 d → 0,4 | `_3` Caja fuerte: 30, 8 ingot, 1 d → 0,6 |
| secrets | `forge_secrets_1` Doble contabilidad: 10, 1 d → `tax_mult ×0,9`, `inspection_risk +0,05` | `_2` Pasadizo: 20, 5 wood, stealth 3, **requiere `forge_security_1`**, 1 d → `inspection_escape` | `_3` Contrabando: 35, stealth 5, 1 d → `illegal_profit ×2`, `inspection_risk +0,15` |

  Cada nivel N requiere el N−1 de su rama (explícito en `requires.upgrades`). Materiales del **almacén del edificio**
  (cualquier calidad). Atributo mínimo: **del actor** que da la orden. Título mínimo: de la familia dueña.
- **Tipos de efecto** (`effect_kinds`: `value`, `stack`, `when`, `reader`). `stack: branch_top` = en cada rama solo
  cuenta el nivel más alto terminado que tenga ese tipo (los niveles se sustituyen: ×1,2 → ×1,4 → ×1,6, calidad +1 →
  +2 → +3); luego las ramas se combinan (mult se multiplican, amounts se suman). `all` = cuentan todas.
  `when: query` = los demás sistemas preguntan siempre; `complete` = se aplica una vez al estado al terminar la obra.

| kind | valor | stack | when | qué hace |
|---|---|---|---|---|
| `production_speed` | mult | branch_top | query | ciclo = duración / mult (todos los que trabajan allí) |
| `quality_bonus` | amount | branch_top | query | + a la Artesanía con que se lee la tabla de calidad (como `craft_delta`), 1..10 |
| `price_multiplier` | mult | branch_top | query | precio de venta (ver decisiones) |
| `customer_bonus` | amount | branch_top | query | +% de frecuencia de clientes del mostrador (H7) |
| `protection` | amount | branch_top | query | 0..1; Seguridad (robo de empleados ahora; sabotaje/incendio después) |
| `inspection_risk` | amount | all | query | suma de riesgos (4.8: `Σ inspection_risk`) |
| `illegal_profit` | mult | all | query | sin lector todavía (actividad ilegal: H11/EA) |
| `tax_mult` | mult | all | query | sin lector todavía (impuestos: H10) |
| `unlock_recipe` | recipe | all | query | ya lo cumple `recipe.requires_upgrade` (Production `_lock_reason`); declarativo para la UI |
| `allow_rank` | rank | all | query | permite contratar/ascender a ese rango |
| `counter_sales` | flag | all | query | el mostrador vende (clientes en H7) |
| `inspection_escape` | flag | all | query | el pasadizo salva de una inspección (con enfriamiento) |
| `max_employees` | amount | all | complete | `employee_slots += amount` |
| `extra_storage` | amount | all | complete | `inventory.limit += amount` (pilas) |
| `new_zone` | zone (+`like`) | all | complete | `zones[zone] = {occupant: "", job: null}`; trabaja como `like` |
| `loyalty_bonus` | amount | all | complete | lealtad de los empleados del edificio en ese momento (`loyalty_changed`, reason `upgrade`) |
| `reputation` | amount | all | complete | reputación de la familia dueña (`reputation_changed`, reason `upgrade`) |

- Validación: `Catalog.validate()` (`_validate_upgrades`: ramas y niveles, una mejora por rama/nivel, requisitos que
  existen en su árbol, nivel N pide N−1, sin ciclos, tipos de efecto conocidos con su valor, receta y rango que
  existen, atributo y título válidos, `upgrade_tree` de cada edificio) y `tools/validate_content.py` (`check_h5`:
  lo mismo + textos `upgrade.*`, `branch.*`, `effect.*`, `like` de cada `new_zone` = puesto del edificio, receta
  desbloqueada coherente con su `requires_upgrade`, visuales como ids snake_case — nunca rutas —, aviso si una obra
  sale de 0,5-2 días; `check_h5_scenario`: mejoras de su árbol con sus requisitos, obra coherente, inspección).
  Los puestos de un edificio en un escenario = los de su tipo + los `new_zone` de sus mejoras terminadas.

## Visuales (ids para «vista» y «visuales»; escenas en `game/visuals/`, decisión de estructura A/C)
`visual.interior_node` aparece en el interior, `visual.exterior_overlay` sobre el edificio en el mapa. Son **ids**, no
rutas: nodos ocultos con ese nombre bajo `Upgrades/` en `game/visuals/interiors/<tipo>.tscn` (interior) y
`game/visuals/buildings/<tipo>.tscn` (exterior); la vista los enciende con `Upgrades.visuals`. Prefijo `upgrade_` = genérico reutilizable entre oficios (4.6.4, 9.3); `forge_` = variante del oficio.
- Interior: `forge_bellows`, `forge_tempering_tub`, `forge_master_furnace` (Producción); `forge_anvil_2` (en el puesto
  `anvil_2`), `upgrade_storage_shelves`, `forge_furnace_2` (en `furnace_2`) (Capacidad); `forge_quench_trough`,
  `forge_engraving_bench`, `forge_master_seal` (Calidad); `upgrade_counter` (Comercio 1); `upgrade_bunks`,
  `upgrade_dining_table`, `upgrade_master_bench` (Personal); `upgrade_strongbox` (Seguridad 3);
  `upgrade_double_ledger`, `upgrade_hidden_passage`, `upgrade_smuggler_cache` (Secretos).
- Exterior: `upgrade_shop_window`, `upgrade_trade_sign` (Comercio 2-3); `upgrade_stone_facade`, `upgrade_garden`,
  `upgrade_noble_facade` (Fachada); `upgrade_reinforced_lock`, `upgrade_guard` (Seguridad 1-2).
- La vista crea una escena por id (greybox con etiqueta mientras no haya arte). Un id sin escena no debe romper nada:
  placeholder visible. Si de una rama se ven varios niveles a la vez o solo el último, lo decide «vista» (propuesta:
  Fachada y Producción solo el último; el resto todos).

## Órdenes (por `Orders.apply`; enlazadas, devuelven `not_implemented` hasta que se hagan)
| Orden | Campos | Dueño | Regla |
|---|---|---|---|
| `buy_upgrade` | actor, building, upgrade | arbol | De gestión (`Orders.MANAGEMENT`: no camina ni vacía la cola de órdenes). Exige `Upgrades.status_of(...) == "available"` (el motivo, si no). Paga el oro con `Money.change(fam, −gold, "upgrades", ref = id de mejora, building, actor)` y saca los materiales del almacén (calidad más baja primero). Escribe `upgrade_work {upgrade, actor, start = ahora, end}`. Evento `upgrade_started`. |

- **No hay `cancel_upgrade`**: el GDD no prevé cancelar una obra (pregunta abierta abajo).
- Motivos (claves `reason.*` ya añadidas): `unknown_actor`, `unknown_building`, `not_your_building`, `unknown_upgrade`,
  `wrong_tree`, `owned`, `in_works`, `busy`, `needs_upgrade`, `stat_too_low`, `title_too_low`, `missing_materials`,
  `not_enough_gold`; y `under_works` (para Production/WorkQueue durante la obra).
- `random_clicker` ya da `buy_upgrade` con campos al azar (válidos e inválidos): la diana `ledger_mismatch 0` vigila que
  las mejoras y multas pasen por `Money`.

## Paso del sim (`Sim.step`, orden fijo)
1. Órdenes de fuera (`buy_upgrade` empieza la obra al momento); 2. `RivalAI.orders`; 3. `Clock.tick` → `OrderQueue` →
   `Movement` → `Buildings` → **`Upgrades.step`** → `Staff.step` → `Routines.step` → `WorkQueue.step` →
   `Production.step` → `Market.step` → `Contracts.step` → `Upkeep.step` → **`Inspections.step`** → `Loans.step` →
   `Objectives.step` → `Ledger.step` → `Notices.step`.
- **`Upgrades.step`** («arbol»): cada minuto, edificios en orden de id (`String`): si `upgrade_work.end <= ahora` →
  `Upgrades.complete(sim, bld, id)` (añade a `upgrades`, borra la obra, aplica los efectos `complete`, emite
  `upgrade_done`) y aviso `notice.upgrade_done`. Va antes que todos los lectores: un efecto terminado este minuto ya
  cuenta este minuto.
- **`Inspections.step`** («arbol»): al amanecer (`Ledger.is_dawn`), edificios en orden de id con `Inspections.risk > 0`:
  una tirada `state.rng.randf() < risk`. Pillado: si `Inspections.can_escape` → se libra (`escaped += 1`,
  `escape_ready_day = hoy + escape_cooldown_days`, aviso `notice.inspection_escaped`); si no → multa `state.rng`
  entera en `fine` por `Money` (`fines`, ref `"inspection"`), reputación `inspections.reputation`, `caught += 1`,
  `fines += multa`, aviso urgente `notice.inspection_fined`. `last_day = hoy` siempre que se tire. Va después de
  salarios y mantenimiento (mismo criterio que H3/H4: primero lo recurrente).

## Quién lee cada efecto (integración; **todo de «arbol»** salvo lo marcado)
| Efecto | Consulta | Fichero que lo integra | Dónde |
|---|---|---|---|
| obra en curso | `Upgrades.under_works(st, bld)` | `production.gd`, `work_queue.gd` | `may_work` → `under_works` (dueño y empleados); la cola no reparte (ocioso con motivo `under_works`); los ciclos en curso al empezar la obra se interrumpen (`Production.interrupt`) [provisional] |
| `production_speed` | `Upgrades.mult(sim, bld, "production_speed")` | `production.gd` | `cycle_minutes` del dueño y `employee_cycle_minutes` (hoy: `/ Staff.speed`; añadir `/ mult`) |
| `quality_bonus` | `Upgrades.amount(...)` | `production.gd` | `roll_quality`: `craft + craft_delta + bonus`, recortado 1..10 |
| `unlock_recipe` | (ya: `recipe.requires_upgrade` en `bld.upgrades`) | — | nada que hacer |
| `new_zone` | `Upgrades.zone_kind(sim, bld, zone)`, `new_zones` | `production.gd`, `work_queue.gd`, `buildings.gd` (común: se avisa) | `work_at`/`go_to_station` aceptan la zona si `zone_kind == recipe.zone`; la cola reparte en ella; el rol fijo vale para sus copias (`anvil` trabaja en `anvil_2`) |
| `max_employees` | (aplicado: `employee_slots`) | — | `Staff.slots` ya lo lee |
| `allow_rank` | `Upgrades.allows_rank(sim, bld, rank)` | `staff.gd` | `_rank_allowed` y `candidates`: cambiar la comprobación de `ranks.<r>.requires_upgrade` por esta (o poner `requires_upgrade: "forge_staff_3"` en `data/employees.json`, común: se avisa) |
| `protection` | `Upgrades.amount(...)` | `staff.gd` | `_has_security` → `protection > 0` (robo ÷ `security_divisor` 2, 4.7.3) [provisional] |
| `loyalty_bonus` | (aplicado al terminar) | — | `data/employees.json` `loyalty.facade_upgrade`/`dining_upgrade` quedan como documentación: la cifra manda en la ficha de mejora |
| `reputation` | (aplicado al terminar) | — | — |
| `extra_storage` | (aplicado: `inventory.limit`) | — | `Inventory` ya lo lee |
| `price_multiplier` | `Upgrades.mult(...)` | `market.gd` | `order_sell` (y la vista de precios `offers`) [provisional, ver decisiones] |
| `counter_sales`, `customer_bonus` | `Upgrades.flag` / `amount` | `work_queue.gd` (rol mostrador) | sin `counter_sales` el mostrador no se usa; clientes y su frecuencia: **H7** |
| `inspection_risk`, `inspection_escape` | `Inspections.risk`, `can_escape` | `inspections.gd` | `Inspections.step` |
| `tax_mult`, `illegal_profit` | `Upgrades.mult(...)` | — | sin lector hasta H10 / H11 |

## Eventos (para la vista)
- base (ya): `upgrade_done {family, building, upgrade}` (lo emite `complete`); `reputation_changed {family, amount,
  reason: "upgrade"}`; `loyalty_changed {..., reason: "upgrade"}`.
- arbol: `upgrade_started {actor, family, building, upgrade, start, end}`, `upgrade_effect` no hace falta (los
  efectos se leen de las consultas); `inspection {family, building, caught: bool, escaped: bool, fine}` (solo cuando
  pilla o se libra); `gold_changed` (Money).
- **Avisos** (claves ya añadidas): `notice.upgrade_done {building, upgrade}` (info, target edificio),
  `notice.inspection_fined {building, amount}` (urgent), `notice.inspection_escaped {building}` (warning).

## Consultas para la UI (funciones puras; la vista no calcula reglas)
Hechas en la base (forma fija; «arbol» puede afinarlas sin cambiarla):
- `Upgrades.tree_view(sim, actor, bld) -> {building, tree, owned: [ids], work: {} | {upgrade, actor, start, end,
  progress 0..1, minutes_left}, branches: [{id, name_key ("branch.<id>"), upgrades: [{id, name_key, branch, level,
  status, cost {gold, items}, requires {upgrades, stat, title}, build_days, effects, visual}]}]}` (ramas en el orden de
  `upgrade_rules.branches`, mejoras por nivel).
- `Upgrades.status_of(sim, actor, bld, id) -> "owned" | "in_works" | "available" | motivo` (orden de los motivos en el
  código).
- `Upgrades.visuals(sim, bld) -> {interior: [{upgrade, node}], exterior: [{upgrade, node}]}` (orden de terminación).
- `Upgrades.owned`, `has`, `work`, `under_works`, `tree_of`, `family_title`, `title_rank`.
- Registro de efectos: `Upgrades.effects(sim, bld, kind) -> [{upgrade, branch, level, effect}]`, `mult`, `amount`,
  `unlocks` (ids), `flag`, `new_zones -> [{zone, like, upgrade}]`, `zone_kind`, `allows_rank`.
- `Inspections.view(sim, bld) -> {risk, last_day, caught, escaped, fines, can_escape}`, `risk`, `can_escape`,
  `honesty_of`.
- Textos de efectos para el panel: `effect.<kind>` con params `{mult}`, `{amount}`, `{recipe}`, `{rank}`, `{zone}` (la
  vista formatea porcentajes y nombres).

## Escenarios (los genera `tools/scenarios/make_upgrade_scenarios.gd`, desde `town_e_start`)
- **`forge_upgrades`**: día 1, 04:30. Forja `bld_0001` con 4 mejoras terminadas (`forge_production_1`,
  `forge_capacity_1`, `forge_quality_1`, `forge_staff_1` → 2 huecos, puesto `anvil_2`), **Agnès** `chr_0008` (aprendiz,
  `furnace`) y **Joan** `chr_0007` (oficial, `anvil`) empiezan hoy, **1000 de oro**, almacén con iron 60, coal 20,
  wood 20, iron_ingot 10, stone 10 (materiales para las siguientes mejoras) y cola `forge_sword` ×10.
- **`forge_upgrade_works`**: igual, con la obra de `forge_capacity_2` en curso: pagada (8 oro por `Money` → 992; 8 de
  madera), empezó hace 12 h, le quedan 12 (fin 16:30 del día 1). Para la vista de la obra; con `Upgrades.step` hecho,
  termina sola (almacén 20 pilas).
- Volver a generarlos si cambian `town_e_start`, la población, `data/employees.json`, `data/upgrades/forge/` o la forma
  del estado. «balance» que cambie costes: regenerar (el oro de la obra pagada sale de la ficha).

## Decisiones provisionales de la base
- **Los niveles de una rama se sustituyen** (`branch_top`): la tabla del GDD da el valor total de cada nivel (×1,6 al
  nivel 3, no ×2,69; calidad +3, no +6; protección 60 %). Los huecos de Personal, en cambio, se suman (+1 y +1) y el
  riesgo de inspección también (4.8 dice `Σ`).
- **`quality_bonus` suma a la Artesanía** con que se lee la tabla de calidad: con 3 calidades, «+3» no pueden ser
  escalones.
- **Reputación y lealtad de mejoras: una vez, al terminar** (Fachada +10/+20/+30 de reputación y +5 de lealtad cada
  una; Comedor +10). Lealtad solo a los empleados que hay en ese momento.
- **Atributo mínimo: del actor** que da la orden (el GDD dice «del dueño» y el dueño es una familia).
- **Título**: la familia aún no lo guarda; sin campo = `common` → «Fachada noble» no se puede comprar hasta H9.
- **Honestidad 0** para todos (no hay `attitudes`): `p = Σ inspection_risk`.
- **Multa** `[10, 50]` (condena leve de 4.12.5) y reputación −10 (4.12.1, «condena con multa −10»); juicio automático
  en H11. El pasadizo salva de **una** inspección y vuelve a servir a los **8 días** (1 año). Si la familia no puede
  pagar la multa entera: propuesta, cobrar lo que tenga y el resto queda perdonado con aviso (decide «arbol»).
- **Puestos nuevos con id propio** (`anvil_2`, `furnace_2`) y `like` para el tipo. El sim no guarda dónde están: su
  casilla es de la vista (Marker2D `Stations/<zona>` en `game/visuals/interiors/<tipo>.tscn`, «visuales»).
- **Seguridad y robo**: cualquier mejora con `protection > 0` divide el robo entre 2 (4.7.3); los porcentajes de
  `protection` quedan para sabotaje/incendio (destruir la última mejora, 4.8; llega con los eventos).
- **`price_multiplier`** (propuesta para «arbol»): multiplica el precio al que la familia dueña vende **los productos
  que hace ese tipo de edificio** (salidas de sus recetas) en el mercado y, en H7, en el mostrador; si tiene varias
  forjas, el mayor. Si se prefiere solo para el mostrador, se cambia aquí.
- **Obra**: el edificio no produce; los ciclos en curso se interrumpen al empezar (insumos de vuelta); los empleados
  siguen viniendo y cobrando (ociosos con motivo `under_works`).
- `illegal_profit` y `tax_mult` se guardan y se consultan, pero nadie los lee hasta H10/H11.

## Preguntas abiertas (para el manager / owner)
1. ¿Se puede **cancelar** una obra? El GDD no lo dice; la base no tiene `cancel_upgrade`. Si sí: ¿devuelve algo?
2. ¿`price_multiplier` vale en el mercado o solo en el mostrador (H7)?
3. Multa impagable: ¿perdón, deuda con la ciudad (como el mantenimiento, D15) o embargo?

## Lo que debe saber cada uno
- **arbol**: `status_of` ya hace todas las comprobaciones de compra; `order_buy` = `status_of == "available"` + pagar +
  `upgrade_work`. Al terminar, llama a `Upgrades.complete` (ya aplica los efectos `complete` y emite `upgrade_done`) y
  pon el aviso. Integra los efectos `query` en los ficheros de la tabla (son de otros subgrims de H4: cambios mínimos,
  con sus pruebas en `tests/test_econ_upgrades*.gd`). La conservación del libro (`ledger_mismatch 0`) debe seguir. Al
  cambiar `may_work`/`work_at` para `anvil_2` revisa el rol fijo de la cola (BUG-023) y `Buildings.order_go_to_station`.
- **vista**: el panel lee `Upgrades.tree_view` y da `buy_upgrade`; la obra en curso sale de `tree_view.work` (barra de
  progreso, días que quedan) y del icono sobre el edificio en el mapa (propuesta: andamio/greybox mientras
  `under_works`). Los visuales salen de `Upgrades.visuals` (ids arriba) y los puestos nuevos de `Upgrades.new_zones`
  (la casilla, del Marker2D `Stations/<zona>` del interior). Escenarios de prueba: `forge_upgrades`, `forge_upgrade_works`.
- **balance**: `artisan_expert` juega desde `artisan_blacksmith` (o `forge_upgrades` para pruebas cortas) hasta el
  día 24: contrata, llena la cola y compra mejoras con `buy_upgrade` (hasta que «arbol» la haga devuelve
  `not_implemented`: empieza por contratar y la cola). Dianas: `goldflow` de la fase «Forja con empleados» (días 9-24,
  +60 a +150/día) y el peso de los sumideros recurrentes (salarios + mantenimiento + impuestos) en 30-60 % de los
  ingresos brutos (medida nueva en `tools/sim_runner.gd`). Revisa la diana provisional del oro del rival
  ([40, 500] con idle, H3). Los costes en oro de las mejoras parten de los del GDD (muy bajos): ×5-×10 (D14).

## Respuestas del manager (2026-11-01)
1. **Cancelar una obra:** no existe en H5 (el GDD no lo prevé; no se inventa). Sin `cancel_upgrade`.
2. **Multiplicador de precio de las mejoras (Comercio/Fachada):** solo en la venta de mostrador (4.5.4, H7). No toca el precio del mercado.
3. **Multa impagable:** igual que el mantenimiento (D15): se acumula como deuda con la ciudad del edificio y se cobra en cuanto haya oro; aviso urgente. Provisional.

## Hecho por «arbol» (2026-11-01)
- `buy_upgrade`: `status_of` + `Money` (`upgrades`, ref = id) + materiales del almacén (calidad más baja primero) +
  `Production.interrupt` de los ciclos en curso + `upgrade_work`. Evento `upgrade_started`. `Upgrades.step` termina
  las obras (`complete` + aviso `notice.upgrade_done`); una obra que ya no puede terminar (mejora borrada) se descarta.
- La obra no cambia `building.state` (sigue `normal`): bloquea por `Upgrades.under_works`. `Production.may_work` →
  `under_works` para todos (dueño a mano incluido); la cola marca ociosos con motivo `under_works` (sin aviso).
- Velocidad: `Production.owner_cycle_minutes(sim, bld, recipe, mode)` (nuevo, el dueño y la IA a mano) y
  `employee_cycle_minutes` dividen por `Upgrades.mult(..., "production_speed")`. `cycle_minutes(catalog, …)` sigue sin
  mejoras (lo usan bots y rival para estimar).
- Calidad: `Production.roll_quality(..., bld_id = "")` suma `quality_bonus` a la Artesanía antes de recortar 1..10.
- Puestos nuevos: `work_at` y `recipe_options` comparan `recipe.zone` con `Upgrades.zone_kind`; la cola busca el
  primer puesto libre de ese tipo (`WorkQueue._free_station`: el propio, luego las copias por id). El rol fijo es el
  tipo (`anvil` trabaja en `anvil_2`).
- Rangos: `Upgrades.rank_gated(sim, bld, rank)` = alguna mejora del árbol del edificio tiene `allow_rank` de ese rango;
  `Upgrades.rank_ok` = no restringido o permitido. `Staff._rank_allowed` (contratar, ascender, panel de candidatos) lo
  usa; `ranks.<r>.requires_upgrade` sigue valiendo si se rellena. Sin cambios en `data/employees.json`.
- Seguridad: `Staff._has_security` = `protection > 0` (o la lista antigua `theft.security_upgrades`, vacía).
- Inspecciones: campo nuevo **`inspection.fine_debt`** (int, dentro de `inspection`: sin subir versión; prueba de ida y
  vuelta en `tests/test_econ_inspections.gd`). Consulta `Inspections.fine_debt(sim, bld)` (`view` no cambia de forma).
  Se cobra al amanecer o en un paso en que sube el oro de la familia (como `Upkeep`); aviso urgente
  `notice.inspection_debt {building, debt}` (clave nueva). Evento `reputation_changed` con reason `inspection`.
- Sin lector en H5: `price_multiplier`, `counter_sales`, `customer_bonus` (mostrador, H7), `tax_mult`, `illegal_profit`.
  `market.gd` no se toca.
