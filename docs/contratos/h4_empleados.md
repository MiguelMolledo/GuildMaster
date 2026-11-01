# Contrato H4 · empleados, cola de producción y rutina

Lo que comparten los subgrims de H4 («plantilla», «cola», «vista»). Quien cambie un nombre lo cambia aquí.
Base: `docs/contratos/h1_mundo.md`, `h2_forja.md`, `h3_mercado.md`. GDD: 4.7 (entero), 4.4.3 (restricción nocturna),
4.4.5 (los empleados trabajan en modo normal), 4.6.3, 4.11.1-4.11.2 (población y rutina, solo empleados), 4.18
(avisos), 4.19 (`wages`), 06 (personaje y su `job`). Criterio del hito (10, fila H4): escenario «2 empleados»: 3 días,
la forja produce sin que el jugador entre; cada uno en su puesto; de noche se van; salario impagado baja lealtad.
Escenario «aprendiz con 1 año trabajado y lealtad 60»: aparece el aviso de ascenso.

## Zonas (ficheros de cada uno)
| Subgrim | Ficheros | Pruebas |
|---|---|---|
| plantilla | `sim/econ/staff.gd` (órdenes `hire`, `fire`, `promote`, `bonus`; `Staff.step`; puede afinar las consultas sin cambiar su forma) | `tests/test_econ_staff*.gd` |
| cola | `sim/econ/work_queue.gd` (órdenes `queue_*`, `set_role`; `WorkQueue.step`), `sim/world/routines.gd` (`Routines.step`), y en `sim/econ/production.gd` **solo** lo de empleados: velocidad y eficiencia del ciclo, no repetir solos (el reparto lo decide la cola), qué pasa con el ciclo al atardecer | `tests/test_econ_queue*.gd`, `tests/test_world_routines*.gd` |
| vista | `game/` (paneles de contratación, empleados y cola; empleados andando; icono de ocioso sobre el edificio; avisos), `game/sim_query.gd`, `data/view.json` | `tests/test_game_*.gd` |

Comunes (solo se tocan si el contrato lo dice, y se avisa): `sim/core/*`, `sim/meta/save_file.gd`,
`sim/meta/new_game.gd`, `sim/world/buildings.gd`, `sim/econ/money.gd`, `data/employees.json`,
`tools/maps/make_town_e.py`, `tools/scenarios/make_staff_scenarios.gd`. `i18n/strings.csv`: cada uno **añade sus claves
al final**, sin reordenar ni tocar las de otros. Cifras nuevas que necesite un sistema: en `data/employees.json` (se
avisa en este contrato) con su validación en `tools/validate_content.py` (`check_h4`).

## Estado (guardado v5, ya existe)
- **Personaje** `characters[chr]`, campos nuevos (todos los personajes):
  - `home: "" | bld` — su casa (edificio residencial). Los vecinos la tienen; la familia del jugador y el rival, `""`.
  - `rank: "" | "apprentice" | "journeyman" | "master"` — rango de oficio **de la persona** (sobrevive al despido;
    el candidato lo enseña). `""` = no es trabajador de oficio (familia del jugador, rival).
  - `job: null | {building, role, loyalty, hired_day, start_day, end_day, days_worked, rank_days, unpaid_days,
    promotion_offered}`:
    - `building`: donde trabaja; `role`: id de puesto del edificio (`furnace`, `anvil`, `counter`) o `"any"`.
    - `loyalty`: 0-100 (entero). Empieza en `loyalty.start` (50).
    - `hired_day`: día de la orden `hire`; `start_day`: primer día de trabajo (`hired_day + hire.start_after_days`, 1);
      `end_day`: último día de trabajo (−1 = sin fin; el despido pone el día del despido).
    - `days_worked`: días trabajados en este empleo; `rank_days`: días trabajados desde el último cambio de rango
      (lo que miran los ascensos); `unpaid_days`: amaneceres seguidos sin cobrar; `promotion_offered`: hay un aviso de
      ascenso esperando respuesta.
    - Activo el día `d` ⇔ `start_day <= d` y (`end_day < 0` o `d <= end_day`) — `Staff.is_active`.
  - `hire_bans: {fam: hasta_día}` — no recontratable por esa familia hasta ese día incluido (ladrón huido, 4.7.3).
  - `routine: {}` — memoria libre de `Routines` («cola»): estado del día, minuto de salida sorteado, etc.
- **Edificio** `buildings[b]`, campos nuevos:
  - `employee_slots: int` — huecos de empleado (al crear: `base_employees` de su tipo; las mejoras de Personal de H5
    lo suben). La migración v4 pone 1 a las forjas y 0 al resto (v4 solo conocía forja y Armería).
  - `queue: {entries: [entrada], loop: bool, paused: bool}` — entrada `{id: "qen_0001", recipe, qty, done}`;
    `qty` entero ≥ 1 o **−1 = infinito**; `done`: unidades ya hechas de esa entrada.
- **Casas**: tipo nuevo `house` (`data/buildings/house.json`, categoría `residence`, 3×3, sin puestos ni almacén,
  `upkeep 0`, sin interior). Dueño: la familia del hogar. Dentro = `location == home` (el NPC desaparece en la puerta,
  4.11.1); al salir aparece en la casilla de la puerta.
- **Familias de vecinos**: una por casa, `controlled_by: "ai"`, `ai_profile: ""`, con oro propio (20). No dan órdenes
  solas (`RivalAI` solo mueve las que tienen perfil).
- Ids nuevos (`Ids.next`): `qen` (entradas de la cola).
- **Regla:** dentro de `job`, `routine`, `queue` y sus entradas el dueño puede añadir campos sin subir versión (solo
  los crean partidas v5), siempre JSON y con su prueba de ida y vuelta. Un campo nuevo en personaje, familia o
  edificio fuera de esos diccionarios, o en la raíz del estado, sí es cambio de formato: se pide al manager.
- Migración 4 → 5 (`SaveFile._step`): los campos de arriba con su valor vacío. Prueba: `tests/test_core_h4_base.gd`
  con `tests/data/saves/v4_town_e_start.json`.

## Población (`town_e`, la genera `tools/maps/make_town_e.py`)
- 8 casas en el mapa (`buildings`: `house_w_north`, `house_w_south`, `house_e_north`, `house_e_south`, `house_nw`,
  `house_ne`, `house_sw`, `house_se`), una por manzana, 3×3 en su esquina, puerta en la calle o el camino.
- `population: [{home, family_name, gold, colors, members: [{name, female, rank, stats}]}]`: 8 hogares de 2 adultos
  = **16 vecinos sin empleo**: 9 aprendices (Artesanía 1-3), 5 oficiales (4-6), 2 maestros (7-8). Atributos: los del
  Artesano con un reparto fijo por persona (sin azar). Familias: Soler, Puig, Roca, Vila, Serra, Font, Pons, Mas.
- **`town_e_start`**: además de lo de H3, `bld_0004-0011` (casas), `fam_0004-0011` (hogares), `chr_0007-0022`
  (vecinos, en casa). La forja `bld_0001` tiene 1 hueco y la cola vacía.
- **`NewGame.from_start`**: la población va **después** de las tiendas públicas: `fam_0003…`, `bld_0004…`,
  `chr_0003…`. No cambian los ids del jugador, el rival, la Armería, el préstamo ni los encargos.
  `NewGame.add_population(state, catalog, map)` sirve para otros inicios.
- **Las dianas de H3 no se mueven**: la población no gasta azar ni oro (los escenarios de deuda regenerados salen con el
  mismo `rng_state`, oro y minuto).

## Datos (`data/employees.json` → `Catalog.employees`, `catalog.rank(id)`)
- `ranks {apprentice, journeyman, master}`: `wage` 1/3/6, `efficiency` 0,5/1/1,5, `speed` 0,5/1/1,5, `next`,
  `promote_after_days` 8/16 (1 año / 2 años más), `promote_min_loyalty` 51/71 (lealtad > 50 / > 70),
  `requires_upgrade` (`""` en H4, ver decisiones), `availability`. `rank_order` en orden de ascenso.
- `roles {furnace, anvil, counter, any}` con su `name_key`; `default_role: "any"`.
- `loyalty {min 0, max 100, start 50, wage_paid +1, wage_unpaid −5, bonus +5, promotion_accepted +15,
  promotion_refused −10, building_damaged −2, facade_upgrade +5, dining_upgrade +10}`, `bonus_gold 5`.
- `bands` (por lealtad, la primera que la contiene): `loyal` 70-100 (×1), `unhappy` 40-69 (eficiencia ×0,8, rumor
  −1 de reputación), `disloyal` 20-39 (×0,8, rumor, **abandono 5 %/día**), `thief` 0-19 (×0,8, rumor, **robo 3 %/día**).
- `theft {units [1, 3], security_divisor 2, no_rehire_days 8}`; `wages {grace_days 1, unpaid_reputation −2}`;
  `fire {reputation_loyalty_over 70, reputation −2}`; `hire {start_after_days 1}`.
- `schedule {leave_home_phase "dawn", leave_home_delay_minutes [0, 45], work_phases ["dawn", "day"], go_home_phase
  "dusk"}`.
- Validación: `Catalog.validate()` (rangos y rol por defecto) y `tools/validate_content.py` (`check_h4`: todo lo de
  arriba, la población de cada mapa y, en escenarios v5, casa/rango/empleo de cada personaje y huecos/cola de cada
  edificio).

## Reglas ya fijadas en la base
- **Acceso** (`Buildings.can_enter`, `Production._inside_reason`): un empleado entra en el edificio donde trabaja
  (`Staff.works_at`) y da allí `go_to_station` / `work_at` / `stop_work` como el dueño. No traspasa mercancía
  (`transfer` sigue siendo del dueño).
- **`Production.may_work`** para un empleado de ese edificio: `not_controlled` si su empleo no está activo hoy;
  `night_rest` de noche (**en cualquier edificio**, 4.4.3); `off_hours` en una fase fuera de `work_phases` (el
  atardecer); `""` al amanecer y de día. Fuera de su edificio sigue `not_controlled`.
- **`work_at`** de un empleado: solo `mode: "normal"` (`mode_not_allowed`); por tanto nunca toque de maestro.
- **`Sim.give(order)`**: un sistema que mueve personajes (Routines, WorkQueue) da sus órdenes por aquí durante su
  paso: se aplican al momento como las de fuera (un rechazo deja `order_refused` en los eventos), sin grabarse (salen
  del estado). Una orden dada así **vacía la cola de órdenes** del actor (como una orden en vivo).
- Claves ya añadidas: `building.house`, `rank.*`, `role.any`, `reason.off_hours`, `reason.mode_not_allowed`.
- `random_clicker` (`sim/bots/bot_random_clicker.gd`) ya da las 10 órdenes nuevas con campos al azar (válidos e
  inválidos); su diana `ledger_mismatch 0` vigila que salarios y bonus pasen por `Money`.
- `data/view.json` ya tiene el aspecto greybox de `house` (mismo color que las manzanas del mapa).

## Órdenes (por `Orders.apply`; enlazadas, devuelven `not_implemented` hasta que se hagan)
| Orden | Campos | Dueño | Regla |
|---|---|---|---|
| `hire` | actor, building, candidate | plantilla | Edificio de la familia del actor (`not_your_building`); hueco libre (`no_slot`); candidato vecino sin empleo (`Staff.is_unemployed`: `not_a_candidate`); sin veto de esa familia (`banned`); rango permitido (`needs_upgrade`); la familia puede pagar **1 día** de salario (`not_enough_gold`). Crea `job` con `Staff.new_job` (rol `default_role`): empieza al amanecer siguiente. No cobra nada al contratar. |
| `fire` | actor, employee | plantilla | Empleado de un edificio de su familia. `end_day = hoy`: se va al final del día (trabaja lo que queda de hoy, ya cobrado). Si su lealtad era > 70: reputación −2. Un contratado que aún no empezó se va sin más. |
| `promote` | actor, employee, accept: bool | plantilla | Solo con `promotion_offered`. Aceptar: `rank = next`, `rank_days = 0`, lealtad +15, sube el salario (se cobra el nuevo desde el amanecer siguiente). Rechazar: lealtad −10. En los dos casos `promotion_offered = false`. |
| `bonus` | actor, employee | plantilla | Paga `bonus_gold` (5) por `Money` (`wages`, `ref "bonus"`) al hogar del empleado y lealtad +5 (`not_enough_gold`). |
| `queue_add` | actor, building, recipe, qty | cola | Edificio de su familia; receta de ese tipo de edificio; `qty` 1, 5, 10 o −1 (∞) (la UI ofrece esas; el sim acepta ≥ 1 o −1). Añade al final. |
| `queue_remove` | actor, building, entry | cola | Quita la entrada (lo que se esté haciendo para ella: el ciclo en curso termina o se interrumpe, decide «cola»). |
| `queue_move` | actor, building, entry, to | cola | Mueve la entrada al índice `to` (0 = primera; se recorta al rango). |
| `queue_loop` | actor, building, on | cola | Bucle global: al acabar la última, vuelve a la primera con `done = 0`. |
| `queue_pause` | actor, building, on | cola | En pausa no se reparte trabajo nuevo (los ciclos en curso acaban). |
| `set_role` | actor, employee, role | cola | Empleado de su familia; `role` = `any` o un puesto del edificio que esté en `roles` (`unknown_role`). |

Motivos: los elige cada dueño con su clave `reason.<id>` ES/EN (p. ej. `not_a_candidate`, `no_slot`, `banned`,
`not_your_employee`, `no_promotion`, `unknown_entry`, `unknown_role`, `bad_quantity`, `wrong_building`).
`reason.not_implemented` ya existe.

## Paso del sim (`Sim.step`, orden fijo)
1. Órdenes de fuera; 2. `RivalAI.orders`; 3. `Clock.tick` → `OrderQueue` → `Movement` → `Buildings` →
4. **`Staff.step`** → **`Routines.step`** → **`WorkQueue.step`** → `Production.step` → `Market.step` →
   `Contracts.step` → `Upkeep.step` → `Loans.step` → `Objectives.step` → `Ledger.step` → `Notices.step`.
- **«Al amanecer»** = evento `phase_changed` con `phase == "dawn"` en este paso (`Ledger.is_dawn(sim)`), como en H3.
- **Al amanecer, `Staff.step` en este orden** (cada lista de empleados en orden de id, `String`):
  1. **Contar el día que acaba de terminar** (`ayer = hoy − 1`): cada empleado activo ayer: `days_worked += 1`,
     `rank_days += 1`.
  2. **Salidas**: quien tenga `0 <= end_day < hoy` deja el empleo (`job = null`, evento `employee_left` con
     `reason: "fired"`). Si estaba dentro del edificio, sale.
  3. **Empiezan** los contratados con `start_day == hoy` (evento `employee_started`).
  4. **Salarios de hoy** a cada empleado activo hoy: con oro → `Money.change(dueño, −wage, "wages", ref "wage",
     building, empleado)` y el mismo importe **entra en la familia del empleado** (`+wage`, `wages`): el oro sigue en
     la economía (4.19); lealtad +1; `unpaid_days = 0`. Sin oro → `unpaid_days += 1`, aviso; pasada la gracia
     (`unpaid_days > grace_days`): lealtad −5 y reputación −2 de la familia por día.
  5. **Lealtad diaria**: edificio `damaged` −2. Rumores de las bandas (reputación). Lealtad siempre en [0, 100].
  6. **Abandono y robo** (`state.rng`, una tirada por empleado y día según su banda; Seguridad divide el robo).
  7. **Ascensos**: `rank_days >= promote_after_days` y `loyalty >= promote_min_loyalty` y sin oferta pendiente →
     `promotion_offered = true`, aviso y evento `promotion_offered`.
- Los salarios van **antes** que el mantenimiento (`Upkeep.step` va después en el mismo paso).
- **Rutina** (`Routines.step`, «cola»): al empezar `leave_home_phase` cada empleado activo sortea su retraso
  (`leave_home_delay_minutes`, `state.rng`) y a su minuto sale de casa (`exit_building`) y va al trabajo
  (`enter_building`, que camina hasta la puerta). Dentro, `WorkQueue` le da puesto y receta. Al empezar
  `go_home_phase` deja de recibir trabajo nuevo; vuelve a casa (`exit_building` + `enter_building` de su casa). **De
  noche nunca está en el trabajo**: si al empezar la noche sigue dentro, sale y su ciclo se interrumpe (D11).
- **Reparto** (`WorkQueue.step`, «cola»): solo a empleados activos, dentro de su edificio, sin ciclo en curso y con
  `may_work == ""`; respeta el rol (un rol fijo solo en su tipo de puesto, BUG-023), un puesto por persona, resolución
  por unidad con dependencias (4.7.4), entradas imposibles marcadas con aviso y saltadas.

## Eventos (para la vista)
- plantilla: `employee_hired {actor, family, building, employee, rank, wage, start_day}`, `employee_fired {actor,
  family, building, employee, end_day}`, `employee_started {family, building, employee}`, `employee_left {family,
  building, employee, reason: "fired"|"quit"|"theft"}`, `wage_paid {family, building, employee, amount}`,
  `wage_unpaid {family, building, employee, days}`, `loyalty_changed {employee, building, amount, loyalty, reason}`,
  `promotion_offered {family, building, employee, rank}`, `employee_promoted {actor, family, building, employee,
  rank}`, `promotion_refused {actor, family, building, employee}`, `employee_bonus {actor, family, employee, amount}`,
  `employee_stole {family, building, employee, item, quality, qty, value}`; `reputation_changed` (H3).
- cola: `queue_changed {building, family}`, `queue_entry_done {building, entry, recipe}`, `queue_entry_blocked
  {building, entry, reason}`, `queue_stalled {building, reason}` (`reason ""` al volver a poder),
  `employee_assigned {building, employee, zone, recipe, entry}`, `employee_idle {building, employee, reason}`,
  `role_changed {actor, employee, role}`, `routine_changed {employee, state}`. Las órdenes reales que da la rutina ya
  emiten los suyos (`building_left`, `building_entered`, `character_moved`, `work_started`...).
- **Avisos** (`Notices.add`, al registro de 4.18; claves `notice.*` de cada dueño, params para `String.format`):
  plantilla: salario impagable, ascenso disponible (`target` = el empleado), abandono, robo, despido;
  cola: falta de materia prima, almacén lleno, empleado ocioso, nada que producir. Urgentes: robo y abandono.
  - Hechos (plantilla): `notice.wage_unpaid {name, building, amount, days}` (warning, target empleado),
    `notice.promotion_offered {name, building, rank}` (info, target empleado), `notice.employee_quit {name, building}`
    y `notice.employee_stole {name, building, item, qty, value}` (urgent, target edificio), `notice.employee_fired
    {name, building}` (info, target empleado) y `notice.employee_fired_now` (despedido antes de empezar). `building`,
    `rank` e `item` van como id. Motivos de sus órdenes: `unknown_actor`, `unknown_building`, `not_your_building`,
    `no_slot`, `not_a_candidate`, `banned`, `needs_upgrade`, `not_enough_gold`, `not_your_employee`,
    `already_leaving`, `no_promotion`. Seguridad (H5): ids de mejora en `employees.theft.security_upgrades`
    (opcional, hoy no existe = sin Seguridad).

## Consultas para la UI (funciones puras; la vista no calcula reglas)
Hechas en la base (forma fija; el dueño puede afinarlas sin cambiarla):
- `Staff.candidates(sim, actor, bld) -> [{character, name, female, rank, stats {craft, charisma, constitution},
  wage, status}]` (mejor rango primero, luego id; `status`: `ok`, `not_your_building`, `no_slot`, `banned`,
  `needs_upgrade`, `not_enough_gold`).
- `Staff.employees(sim, bld) -> [{character, name, female, rank, role, loyalty, band, wage, days_worked, rank_days,
  unpaid_days, promotion_offered, active, start_day, end_day, routine, task}]` (`routine` = `Routines.state_of`,
  `task` = `WorkQueue.task_of`).
- `Staff.employer(state, chr)`, `works_at(state, chr, bld)`, `is_active(sim, chr)`, `employees_of(state, bld)`,
  `slots(state, bld)`, `free_slots(state, bld)`, `wage(sim, chr)`, `speed(sim, chr)`, `efficiency(sim, chr)`
  (rango × banda), `band(sim, loyalty)`, `is_unemployed(sim, chr)`, `new_job(sim, bld, day, role)`.
- `Routines.state_of(sim, chr) -> "home" | "at_work" | "walking" | "out" | "inside"` («cola» puede añadir
  `to_work` / `to_home`).
Con forma fija y relleno de «cola» (hoy devuelven vacío):
- `WorkQueue.view(sim, bld) -> {entries: [{id, recipe, qty, done, status}], loop, paused, stalled}` (`status`: `ok`,
  `working` o el motivo de salto: `missing_inputs`, `storage_full`, `skill_too_low`...; `stalled`: "" o el motivo).
- `WorkQueue.idle_employees(sim, bld) -> [chr]` (activos, en el trabajo, sin nada que hacer: el icono sobre el
  edificio), `WorkQueue.idle_buildings(sim, fam) -> [bld]`, `WorkQueue.task_of(sim, chr) -> {} | {zone, recipe,
  entry}`.

## Escenarios (los genera `tools/scenarios/make_staff_scenarios.gd`, desde `town_e_start`)
- **`two_employees`**: día 1, 04:30 (noche). Forja `bld_0001` con `employee_slots 2`, **Agnès** `chr_0008`
  (aprendiz, Artesanía 2, rol `furnace`) y **Joan** `chr_0007` (oficial, Artesanía 5, rol `anvil`), contratados el
  día 0, empiezan hoy (`start_day 1`), lealtad 50, en casa. Almacén: hierro ×60, carbón ×20. Cola: `forge_sword` ×10.
- **`apprentice_promotion`**: día 9, 04:50. **Agnès** aprendiz en la forja desde el día 1 (`hired_day 0`),
  `days_worked 7`, `rank_days 7`, lealtad 60; cola `forge_ingot` ∞. Al amanecer se cuenta el día 8 → `rank_days 8`
  con lealtad > 50 → aviso de ascenso.
- Los empleos se escriben con `Staff.new_job` (como contratados hace días); volver a generarlos si cambia
  `town_e_start`, la población, `data/employees.json` o la forma de `job`. Cargan y arrancan ya; se juegan bien
  cuando existan los sistemas.

## Decisiones provisionales de la base
- **El rango vive en el personaje** (`character.rank`), no en `job` (06 lo ponía en `job`): un candidato sin empleo
  necesita rango y un despedido lo conserva. 06 actualizado.
- **Lealtad inicial 50** (ejemplo de 06; el GDD no la fija). **Rol por defecto `any`.**
- **Maestros contratables y ascenso a maestro sin mejora** en H4: `requires_upgrade ""` porque el árbol de mejoras
  llega en H5 (el GDD pide «Taller de maestro»); H5 pone el id y `Staff` ya lo comprueba (`needs_upgrade`).
- **Eficiencia ×0,8 también por debajo de 40** (el GDD solo dice −20 % en 40-69). **Rumores**: −1 de reputación
  **por día** por empleado en las bandas < 70 (el GDD no dice la frecuencia) [balance, «plantilla» puede bajarlo].
- **Salario**: se paga al amanecer **el día que empieza** (prepago); el día del despido ya está pagado; el contratado
  hoy cobra su primer salario mañana al amanecer. El salario pasa al hogar del empleado (no desaparece).
- **Un día trabajado** se cuenta al amanecer siguiente si el empleo estuvo activo ese día (aunque no llegara a
  trabajar). Ascenso: `rank_days >= 8` (aprendiz) o `>= 16` (oficial).
- **Veto del ladrón por familia** (`hire_bans {fam: día}`), no global: «no recontratable» = por quien lo tenía.
- **Huecos guardados** (`employee_slots`) en vez de derivados de las mejoras: el escenario de 2 empleados necesita 2
  sin árbol de mejoras; H5 los sube al construir Personal.
- **Casas sin interior ni mantenimiento**, una familia de vecinos por casa (2 adultos), 20 de oro cada una.
- **Sin edad**: «adulto» = vecino con rango (los personajes aún no tienen `birth_day`; llega con H8).
- **`two_employees` usa 2 huecos** sin mejora (representa la de Personal).

## Lo que debe saber cada uno
- **plantilla**: `Staff.new_job` ya da la forma del empleo. Contratar = escribir `job`; el NPC sigue en su casa hasta
  que la rutina lo mueva. Al quitar un empleo (despido, abandono, robo) saca al NPC del edificio si está dentro
  (`Sim.give` de `exit_building`) y libera su puesto. El ladrón «huye»: provisional, vuelve a casa con `hire_bans`
  de esa familia hasta `hoy + no_rehire_days`. La conservación del libro (`ledger_mismatch 0`) debe seguir: todo oro
  por `Money.change`.
- **cola**: ciclo del empleado = `duration / (Staff.speed × mejoras)`; unidades = `max(1, round(output.qty ×
  Staff.efficiency))` (4.7.2: «siempre al menos 1»); hazlo en `Production` solo para empleados (`_is_employee_at`).
  El auto-repetir de `Production` hoy repite la misma receta: para empleados lo decide la cola. Las órdenes de la
  rutina van por `Sim.give`; recuerda que `enter_building` desde lejos deja un `enter_building` "walking" en la
  cola de órdenes hasta llegar (no le des otra orden mientras camina o lo cancelas). Los vecinos sin empleo se
  quedan en casa (su rutina completa es de H7).
- **vista**: las casas son edificios (`type: "house"`) y salen con bloque, puerta y cartel («Casa de Soler»): decide si
  sus carteles se ven siempre. Un personaje dentro de su casa no se dibuja (como dentro de cualquier edificio). Los
  paneles leen solo las consultas de arriba y dan las órdenes de la tabla. Quien firma las órdenes de familia: como en
  H3 (`SimQuery.family_actor`).

## Hecho por «cola» (para «vista» y «plantilla»)
- **Memoria nueva** (dentro de lo permitido, sin subir versión): `queue.assigned {chr: {zone, recipe, entry}}` (tarea en
  curso de cada empleado), `queue.idle {chr: reason}` (ociosos ahora: `no_task`, `paused`, `empty_queue`, `stalled`),
  `queue.stalled` (`""`, `empty_queue` o el motivo de la primera entrada), `entry.blocked` (`""` o motivo);
  `character.routine {day, leave_at, retry_at, state}` con `state` = `home`/`to_work`/`at_work`/`to_home`/`out`
  (lo emite `routine_changed`; `Routines.state_of` mantiene los valores de la base).
- **Motivos de salto** de una entrada (`view().entries[].status`): `missing_inputs`, `storage_full`, `skill_too_low`,
  `needs_upgrade`, `no_worker` (ningún empleado activo con rol para ese puesto). Claves nuevas: `reason.unknown_entry`,
  `reason.wrong_building`, `reason.unknown_role`, `reason.no_worker`, `reason.empty_queue`, `notice.queue_missing_inputs`,
  `notice.queue_storage_full`, `notice.queue_cannot_make`, `notice.queue_empty`, `notice.queue_stalled`,
  `notice.employee_idle` (params `building`, `recipe`, `reason`, `employee`, `role`).
- **Avisos**: uno al cambiar de estado (no uno por minuto): entrada saltada, cola parada / vacía, empleado ocioso por
  `no_task`. Se evalúan solo mientras hay algún empleado dentro y en horario.
- `Production.employee_cycle_minutes(sim, actor, recipe, mode)` y `Production.output_units(sim, actor, bld, recipe)`
  (para el dueño: la cantidad de la receta). `WorkQueue.cycle_done(...)` lo llama `Production` al entregar un empleado.
- **Decisiones provisionales «cola»**: `queue_remove` deja terminar el ciclo en curso (la salida va al almacén y no
  cuenta para ninguna entrada); sin bucle, las entradas terminadas salen de la cola; los intermedios se hacen solo
  para la siguiente unidad sin empezar (como mucho una unidad de adelanto); al atardecer el ciclo en curso termina y
  luego se va (uno bloqueado por almacén lleno no lo retiene); de noche sale y el ciclo se interrumpe (D11); tras una
  orden rechazada la rutina reintenta a los 30 min; los empleados con rol fijo se reparten antes que los «cualquiera».
