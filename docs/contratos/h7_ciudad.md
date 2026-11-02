# Contrato H7 · ciudad viva

Lo que comparte H7 (un solo subgrim, rama `h7-ciudad`, que sale de `h8-familia`; el manager la junta con `main`).
Quien cambie un nombre lo cambia aquí. Base: `docs/contratos/h1_mundo.md` … `h5_mejoras.md` y `h8_familia.md`.
GDD: 4.11 (población, rutina, actividades sociales, relaciones, estados emocionales y acciones sobre NPC), 4.5.4
(venta en mostrador), 4.20 (microeventos), 4.2.4 (SkillCheck), 4.19 (`counter_sales`, `events`), 4.23 (palanca de
microeventos), 06 (microevento, mapa con puntos sociales).
Criterios del hito (10, fila H7): captura de la plaza al atardecer con NPC socializando; cabreado sube precios; todos
en casa de noche; `sim_bench` < 2 ms; en un sim de 30 días los 3 microeventos aparecen con la frecuencia de su diana;
sin respuesta, la opción por defecto se aplica a las 2 h (test); la Seguridad frustra al ladrón con su probabilidad
(test). Además (hueco de H8): la población del pueblo se renueva.

## Zonas (ficheros)
| Zona | Ficheros | Pruebas |
|---|---|---|
| base | `sim/core/world_state.gd` (v8), `sim/meta/save_file.gd` (paso 7→8), `sim/core/catalog.gd` (`town`, `social_phrases`, `microevents`), `data/town.json`, `data/social_phrases.json`, `data/microevents/*.json`, `data/difficulty.json` (`microevent_chance`), `tools/maps/make_town_e.py` (puntos sociales, oficios, `town_e_start` v8), `tools/scenarios/make_town_scenarios.gd`, `tools/validate_content.py` (`check_h7`, `check_h7_scenario`) | `tests/test_core_h7_base.gd` |
| sim | `sim/town/town_life.gd` (rutina y actividades), `emotions.gd`, `npc_actions.gd`, `skill_check.gd`, `counter.gd` (clientes), `microevents.gd`, `population.gd` (renovación); enganches en `sim/core/sim.gd`, `orders.gd`, `sim/econ/market.gd` (precio del puesto), `staff.gd` (ausencias y emoción en la eficiencia), `sim/world/buildings.gd` (el cliente entra), `sim/family/births.gd` y `lifecycle.gd` (vecinos), `tools/sim_runner.gd`, `data/targets.json` | `tests/test_town_*.gd` |
| vista | `game/visuals/bubbles/*.tscn` (burbujas y emociones), `game/visuals/props/social_*.tscn` (banco, charla, dados), `game/world/character_view.gd` / `world_view.gd` (burbuja, frase, puntos sociales), `game/ui/microevent_card.*`, acciones y emoción en `game/ui/character_panel.*`, clientes en `game/interior/interior_view.gd`, `game/smoke/smoke_ciudad.gd` | `tests/test_game_town.gd` |

## Estado (guardado v8)
Migración 7 → 8 (`SaveFile._step`):
- **Personaje** (todos): `occupation: "" | id de oficio` (el trabajo del vecino en el pueblo: un `workplaces` del
  mapa; `""` = sin oficio, p. ej. la familia del jugador, el rival o un niño) y `town: {}` (memoria libre de
  `TownLife`: `state`, `plan`, `activity`, `spot`, `slot`, `until`, `day`, `leave_at`, `break_until`, `greets`,
  `stalls`, `customer`…). Migración: `occupation ""` y `town {}`; `TownLife` da oficio a los vecinos adultos que no lo
  tienen la primera vez que corre (mismo reparto que una partida nueva: `TownLife.assign_occupations`).
- **Raíz** `microevents: {active: [mev], pending: [plan], cooldowns: {"<def>|<edificio o familia>": hasta_día},
  last_day: {fam: día}}`. Un `mev` activo: `{id: "mev_0001", def, family, building, target, actor, started, expires,
  choices: [ids], default, context: {}}`. Un plan pendiente (sorteado al amanecer, aún sin disparar): `{def, family,
  building, day, at}`.
- **Raíz** `town: {counters: {bld: {next_at: minuto}}}` (siguiente cliente de cada mostrador).
- **`emotions`** (ya existía): `chr → [{state, source, start, duration, intensity0}]`; `state` ∈ `grateful`,
  `offended`, `angry`, `scared` (los 4 del MVP); `source` = la **familia** que lo causó [provisional: el precio se
  paga por familia]; `start` y `duration` en minutos de juego; la intensidad se deriva
  (`intensity0 × (1 − (ahora − start) / duration)`), no se guarda minuto a minuto.
- **`relationships`** (ya existía): la relación permanente `relation` (−100..100) entre el actor y el NPC.
- Ids nuevos (`Ids.next`): `mev`.
- **Regla**: dentro de `town`, `context` de un microevento y `job` se pueden añadir campos sin subir versión (JSON,
  con prueba). `job.absent_until` (día, incluido) marca la ausencia de un empleado (microevento de empleado enfermo).
- Prueba: `tests/test_core_h7_base.gd` con `tests/data/saves/v7_family_routines.json`.

## Datos
- **`data/town.json`** → `Catalog.town`:
  - `routine`: `leave_home_delay_minutes [0, 60]`, `break_chance_per_hour [0.15, 0.20]` (cada vecino saca la suya
    al día), `break_minutes [90, 150]`, `market_hour 10`, `market_visit_chance 0.25`, `retry_minutes 30`,
    `chat_wait_minutes 30`, `greet {check_every 5, per_day 2, minutes [15, 25]}`, `child_stays_home true`.
  - `activities`: `bench`, `chat`, `market`, `greet`, `observe`, `dice` con `minutes` [mín, máx] (en `market`,
    `per_stall_minutes` y `stalls`), `spot` (`social_points` del mapa de ese tipo, `stalls`, `doors` o `none`),
    `bubble` (id de la burbuja), `weight` y `favored_by` (atributo). 4.11.3.
  - `personality {stat_min 7, favored_mult 3, exception_chance 0.12}`.
  - `emotions`: por estado `duration_days [mín, máx]`, `buy_mult`, `sell_mult`, `employee_mult`, `refuses_talk`,
    `refuses_trade_over`, `relation_on_expire`, `icon`; `incompatible` (pares), `max_per_source 2`. 4.11.5.
  - `actions`: `talk`, `gift`, `flatter`, `insult`, `threaten` con sus cifras; `range_tiles 3`. 4.11.5.
  - `counter`: `interval_hours [1, 2]`, `phases ["day"]`, `patience_minutes 60`, `serve_minutes 10`,
    `rank_bonus`, `reputation_cap 0.15`. 4.5.4.
  - `microevents`: `base_chance 0.35`, `max_per_family_day 1`, `timeout_hours 2` (por defecto; cada ficha lleva el
    suyo), `cooldown_days 8`. 4.20.
  - `population`: `min_adults 14`, `max_total 20`, `min_singles 6`, `marriage_chance 0.05`, `marriage_min_age 18`,
    `newcomer_age [18, 24]`, `house_capacity 5`, `newcomer_rank "apprentice"`.
- **`data/microevents/<id>.json`** (06): `{id, scope, trigger: {phase, conditions, chance_per_day}, cooldown_days,
  choices: [{id, text_key, effects}], default_choice, timeout_hours, text_key}`. `chance_per_day` es el **peso** de la
  ficha entre las elegibles el día que sale microevento [provisional]. Efectos declarativos (lista; los lee
  `Microevents.apply`): `sell {discount}`, `skill_check {actor_stat, target_stat|target_value, success, fail}`,
  `leave`, `emotion {state}`, `relation {amount}`, `pay {gold, category}`, `loyalty {amount}`, `absent {days}`,
  `refund_wage`, `steal {units}`, `nothing`.
- **`data/social_phrases.json`**: claves de texto por actividad (`activities`), por fase (`phases`) y por profesión
  (`professions`); 10 por actividad. Los textos en `i18n/strings.csv` (`phrase.*`).
- **`data/difficulty.json`**: palanca `microevent_chance` ×0,7 / ×1 / ×1,3 (4.23).
- **Mapa** (`data/maps/town_e.json`, lo genera `tools/maps/make_town_e.py`): `social_points` `[{id, kind (bench |
  chat | dice), slots: [[col, fila], …]}]` (bancos de 2, charla de 3, dados de 3) y `workplaces` `[{id, kind (stall |
  shop | tile), tile, building?, stall?}]` (16 oficios: los 3 puestos del mercado, la Armería, iglesia, ayuntamiento,
  campos, río, pozo y puertas). Un vecino con oficio `stall_*` es el **tendero** de ese puesto.

## Paso del sim (`Sim.step`, orden fijo)
1. Órdenes de fuera; 2. `RivalAI.orders` → `FamilyAI.orders`;
3. `Clock.tick` → `OrderQueue` → `Movement` → `Buildings` → `Lifecycle.step` → **`Population.step`** → `Upgrades` →
   `Staff` → **`Microevents.step`** → `Routines` → **`TownLife.step`** → **`Counter.step`** → `Schedules` →
   `WorkQueue` → `Production` → `Courtship` → `Market` → `Contracts` → `Upkeep` → `Inspections` → `Loans` → `Births`
   → **`Emotions.step`** → `Dynasty` → `Objectives` → `Ledger` → `Notices`.
- **Azar de la ciudad**: `Kin.roll` / `Kin.randi_range` con claves `town|…`, `mev|…`, `pop|…`, `skill|…`. Nunca
  `state.rng`: la ciudad no mueve las tiradas de la economía (las dianas de H3-H5 no cambian por el azar; solo por los
  efectos reales: robos, clientes).
- **`TownLife.step`** (vecinos: adultos vivos con casa, sin empleo, de una familia de hogar —IA sin perfil—). Planes:
  noche → **a casa** (se interrumpe lo que sea, también un cliente); amanecer → sale de casa a su minuto
  (`leave_at`, retraso sorteado) y va a su oficio; día → en su oficio (`working`), con un descanso social cada hora
  con su probabilidad (una actividad de `break_minutes`) y a las `market_hour` algunos pasean el mercado; atardecer →
  tiempo libre: encadena actividades hasta la noche. Estados (`town.state`, 4.11.2): `home`, `walking`, `working`,
  `market`, `strolling`, `social` (con `activity`). Las actividades eligen por peso × personalidad (atributo ≥ 7 →
  × 3 en sus favoritas; 12 % al azar), un hueco libre de un punto social, y duran lo de su tabla. `chat` espera hasta
  30 min a que llegue otro; si no, cambia. `greet`: dos vecinos que caminan a 1 casilla se paran 15-25 min (como mucho
  2 al día cada uno). Solo da órdenes reales (`move_to`, `enter_building`, `exit_building`) por `Sim.give`.
  Los empleados siguen con `Routines` (H4); los niños se quedan en casa.
- **`Emotions`**: `Emotions.add(sim, chr, state, source)` (sustituye al incompatible y, si ya hay 2 de esa fuente, al
  más viejo; duración sorteada); `Emotions.step` (cada hora en punto) quita las que llegan a 0 y aplica
  `relation_on_expire`. Consultas: `active(st, chr, source)`, `intensity(sim, e)`, `price_mult(sim, chr, fam, side)`,
  `refuses_trade(sim, chr, fam)`, `refuses_talk(sim, chr, fam)`, `employee_mult(sim, chr, fam)`.
- **Precio con emoción** (`Market.trade_price`): en un puesto con tendero (oficio `stall_<puesto>`; la Armería con su
  dependiente) el precio de compra y venta se multiplica por `buy_mult` / `sell_mult` de las emociones del tendero
  hacia la familia del actor. Cabreado > 80 → `vendor_refuses`. `Market.price` (sin tendero) no cambia.
- **`Counter.step`** (edificios con `counter_sales` y familia dueña, en `counter.phases`): cada 1-2 h ÷ (1 +
  `customer_bonus`) llega un cliente: un vecino libre (no en casa, sin empleo, sin otro encargo) camina a la puerta,
  entra (`Buildings.can_enter` lo deja pasar con el encargo `town.customer`) y espera en el mostrador. Le atiende quien
  esté en el puesto `counter` (familiar) o un empleado activo con rol `counter` dentro (`Counter` le lleva al puesto).
  Tras `serve_minutes` compra **una unidad** del producto (categoría `product`) de más valor del almacén:
  `precio = base × calidad × (1 + carisma/100 + rango + (price_multiplier − 1) + min(reputación/100 × 0,15; 0,15)) ×
  sell_mult(emoción del cliente)`; oro con `Money.change` categoría `counter_sales` (fuente, 4.19; el vecino no paga
  de su bolsa [provisional]). Sin quien atienda en `patience_minutes`, sin producto o cabreado > 80: se va sin comprar.
- **`Microevents.step`**: al amanecer, por familia que juega (humana o IA con perfil) con edificios: como mucho 1 al día,
  tirada `base_chance × microevent_chance`; si sale, una ficha elegible (condiciones y enfriamiento) por peso → plan.
  Disparo: `sick_employee` al momento; `night_thief` al empezar la noche + 1-5 h; `haggling_customer` con el siguiente
  cliente de Negociación ≥ 6 que se atiende ese día (si no llega antes del atardecer, se pierde sin enfriamiento;
  solo es elegible con producto que vender: condición `has_products`). Al disparar:
  `microevent_started`, aviso (humana), enfriamiento `cooldown_days` por edificio. Activo hasta que se elige
  (`resolve_microevent`) o caduca a las `timeout_hours` → la opción por defecto (`microevent_resolved {by: "timeout"}`).
  Las familias IA eligen al momento la opción por defecto (la misma orden; 4.21 sin cerrar) [provisional].
  `night_thief` sin nadie de la familia dentro: no hay tarjeta; la protección de Seguridad (`protection` 0,2 / 0,4 /
  0,6) frustra con esa probabilidad; si no, roba 1-3 del producto más valioso. Con alguien dentro: tarjeta
  Enfrentarse (SkillCheck Arte Marcial vs 5) / Dejarle (por defecto).
- **`Population.step`**: al amanecer, bodas entre vecinos solteros (hombre y mujer de casas distintas, ≥ 18, ella ≤
  `mother_max_age − 5`) con `marriage_chance` mientras queden más de `min_singles` solteros; la mujer pasa a la casa
  y familia del marido (`Courtship.marry`). Los hijos llegan por `Births` (H8) solo si el pueblo tiene menos de
  `max_total` vecinos; nacen en su casa (`home`) y a los 16 son aprendices con oficio. Al cambiar de año, si quedan
  menos de `min_adults` adultos, llegan vecinos nuevos (18-24 años, aprendices, sexo alterno) a la casa con menos gente
  (vacía primero). Un hogar cuyo cabeza muere sin heredero sigue con el primer miembro vivo (no se extingue).

## Órdenes (por `Orders.apply`)
| Orden | Campos | Regla |
|---|---|---|
| `npc_talk` | actor, target | Al alcance (`range_tiles` o el mismo edificio), una vez al día por pareja; rechaza `offended` (y `angry`). +`talk.relation`. |
| `npc_gift` | actor, target, item, quality | Una unidad del inventario del actor al del NPC. Valor (precio de venta) > `grateful_min_value` → Agradecido; si no, +valor/`gold_per_point` de relación (tope). |
| `npc_flatter` | actor, target | SkillCheck Carisma vs Empatía: éxito +relación; fallo −relación (Halagado es POST-MVP). Una vez al día. |
| `npc_insult` | actor, target | Ofendido y −10 de relación. |
| `npc_threaten` | actor, target | SkillCheck Arte Marcial vs Arte Marcial: éxito Asustado (−5); fallo Cabreado (−5) [provisional]. |
| `resolve_microevent` | actor, microevent, choice | Gestión. El actor es de la familia del microevento; la opción existe. |

Motivos nuevos (`reason.*`): `not_a_townsperson`, `refuses_talk`, `already_today`, `unknown_microevent`,
`unknown_choice`, `vendor_refuses`, `no_item`.

## Eventos y avisos
- Eventos: `town_state {character, state, activity}`, `greeted {a, b}`, `emotion_added {character, state, source}`,
  `emotion_ended {character, state, source}`, `relation_changed {actor, target, amount, relation}`,
  `npc_action {actor, target, action, ok}`, `skill_check {key, success, roll, threshold}`, `customer_arrived`,
  `customer_left {reason}`, `counter_sold {family, building, customer, seller, item, quality, price}`,
  `microevent_started {id, def, family, building}`, `microevent_resolved {id, def, family, choice, by}`,
  `theft {family, building, item, qty, frustrated}`, `townsfolk_married`, `newcomer_arrived`.
- Avisos (familia humana): `notice.microevent.<def>` (al empezar, con su tarjeta), `notice.microevent_done`,
  `notice.theft`, `notice.theft_frustrated`.

## Consultas para la UI
`TownLife.view(sim, chr) -> {state, activity, bubble, occupation}`, `TownLife.is_townsperson`;
`Emotions.list(sim, chr) -> [{state, source, intensity, icon}]`, `Emotions.top_icon(sim, chr)`;
`NpcActions.status(sim, actor, target, action) -> ""|motivo`; `Microevents.active_for(sim, fam)`,
`Microevents.view(sim, mev_id) -> {def, text_key, choices: [{id, text_key}], default, minutes_left, params}`;
`Counter.customers(sim, bld) -> [chr]`; `Market.trade_price(sim, actor, stall, item, q, side)`.

## Escenarios (`tools/scenarios/make_town_scenarios.gd`, desde una partida nueva Normal, semilla 1)
- **`plaza_dusk`**: día 1, 18:40. Los vecinos en sus oficios (fuera de casa); a las 19:00 empieza el atardecer y
  se van a la plaza a socializar. Captura de la plaza.
- **`town_microevents`**: día 0, amanecer. Forja con Mostrador (`forge_commerce_1`), dos empleados (uno con rol
  `counter`), almacén con 140 espadas, lingotes, hierro y carbón (un mes de clientes), 300 de oro, sin deuda. El arenero de los microeventos y
  los clientes (diana de 30 días).
- **`microevent_card`**: `town_microevents` al amanecer del día 1 con un `sick_employee` activo (la tarjeta).

## Dianas
- `data/targets.json` `idle_town` (bot `idle` desde `town_microevents`, 30 días): cada microevento entre 1 y 4 veces
  por semilla, como mucho 1 por familia y día, y algún cliente atendido. Ritual: `godot --headless --path . -s
  tools/sim_runner.gd -- --scenario=town_microevents --bots=idle_town --days=30 --seeds=3` (en `run_all.py`, paso
  `town`, con 2 semillas). Medido: regateo 1-3, enfermo 2-3, ladrón 2-3 por semilla; ~170 ventas de mostrador.
- `data/targets.json` `town_population`: en 60 años saltando de amanecer en amanecer (`tests/test_town_population.gd`),
  los vecinos vivos siempre en `[14, 22]` y al final quedan solteros en edad de tener hijos.

## Decisiones provisionales
- **Oficio del vecino** (`occupation`): un sitio del mapa donde pasa el día (puesto, Armería, iglesia, campos…). Es
  cosmético salvo el tendero (su emoción cambia el precio del puesto). Sigue siendo candidato a empleado; contratado,
  manda `Routines` (H4) y al atardecer va a casa.
- **Fuente de la emoción = la familia** del actor (el precio y el trato son de la familia).
- **Amenaza fallida → Cabreado**; halago fallido → −2 de relación (el GDD no dice qué pasa al fallar).
- **Conversar** +2 de relación una vez al día; **regalo barato** +1 por cada 5 de oro (tope 10).
- **Cliente**: un vecino libre; no paga de su bolsa (el oro de la venta es una fuente, como el mercado).
- **Peso de cada microevento** = su `chance_per_day`, entre las fichas elegibles el día que sale.
- **Familias IA**: eligen la opción por defecto al momento (hasta que se cierre 4.21).
- **Seguridad contra el ladrón** solo cuando no hay nadie dentro (como dice la tabla de 4.20).
- **Renovación de la población**: bodas entre vecinos + hijos (H8) con tope de 20 + vecinos nuevos si faltan adultos.
- **Los niños se quedan en casa** hasta los 16 (no hay escuela visible).
- **Regateo solo con producto** (`has_products`): sin nada que vender no hay regateo que valga.
- **El estado de la ciudad no guarda decimales** (`break_permil` en milésimas): un float no vuelve idéntico de un
  guardado y rompía la ida y vuelta.
- **Riesgo de balance (abierto)**: la frecuencia de clientes de 4.5.4 ([propuesta], 1 cada 1-2 h de día) con el
  precio del mostrador (base × calidad × (1 + bonus), sin demanda) da ~300-500 de oro al día con una forja con
  Mostrador (6 de oro y 4 de madera). Ningún bot de esta rama compra `forge_commerce_1`, así que las dianas de H3-H5 no
  se mueven, pero `artisan_expert` (en main) sí puede: hay que pasarlo y ajustar `counter.interval_hours` o el precio.
