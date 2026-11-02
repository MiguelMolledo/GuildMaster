# Contrato H9 · reputación y títulos

Lo que comparte H9 (un subgrim, rama `h9-titulos`, que sale de `main` 6db5186 con H1-H8 y H7; el manager la junta con
`main`). Quien cambie un nombre lo cambia aquí. Base: `docs/contratos/h1_mundo.md` … `h8_familia.md` y `h7_ciudad.md`.
GDD: 4.12.1 (reputación), 4.12.2 (títulos y ceremonia), 4.9 (límite de edificios por título), 4.19 (`titles`), 4.17
(puntos por título en la crónica), ap. A (reputación pasiva), 4.21 (la IA pide títulos; 04c sin aprobar: aquí solo una
regla mínima), 06 (familia: `reputation`, `class_reputation`, `title`).
Criterios del hito (10, fila H9): el bot `artisan_expert` llega a Patricio en su diana; al menos una familia IA sube de
título en un sim de 10 años.

## Zonas (ficheros)
| Zona | Ficheros | Pruebas |
|---|---|---|
| base | `sim/core/world_state.gd` (v9), `sim/meta/save_file.gd` (paso 8→9), `sim/core/catalog.gd` (`titles`, `politics`), `data/titles/*.json`, `data/politics.json`, `data/maps/town_e.json` + `tools/maps/make_town_e.py` (`town_hall`), `tools/scenarios/make_title_scenarios.gd`, `tools/validate_content.py` (`check_h9`) | `tests/test_core_h9_base.gd` |
| sim | `sim/politics/reputation.gd`, `sim/politics/titles.gd`; enganches en `sim/core/sim.gd`, `orders.gd`, `sim/econ/contracts.gd`, `staff.gd`, `loans.gd`, `inspections.gd`, `upgrades.gd` (todos cambian la reputación por `Reputation.change`), `sim/town/microevents.gd` (efecto `reputation`), `sim/ai/rival_ai.gd` (tarea `title`), `sim/bots/bot_artisan_novice.gd` / `bot_artisan_expert.gd` (ganchos), `tools/sim_runner.gd`, `data/targets.json` | `tests/test_politics_*.gd` |
| vista | `game/visuals/buildings/town_hall.tscn`, `game/world/world_view.gd` (el Ayuntamiento en el mapa), `game/ui/town_hall_panel.*`, `game/ui/title_card.*`, pestaña Reputación del libro (`game/ui/ledger_panel.*`), título en el HUD y en el árbol, ayuda F1, `game/smoke/smoke_titulos.gd` | `tests/test_game_titles.gd` |

## Estado (guardado v9)
Migración 8 → 9 (`SaveFile._step`), solo en **familias** (sin campos nuevos en la raíz):
- `title`: id de `data/titles/` (`"common"` si no tenía; el valor por defecto de `upgrade_rules.default_title`).
- `class_reputation`: `{artisan, patron, scholar, rogue} → int`, el **modificador** por clase social (GDD 4.12.1:
  la reputación con una clase = `reputation + class_reputation[clase]`). Migración: todo a 0.
- `reputation_log`: los últimos `log_size` cambios `[{minute, amount, reason, class}]` (el más nuevo al final; lo
  enseña el panel).
- `reputation_caps`: `{regla: {window, count}}`, cuántas veces ha dado una regla con tope en su ventana actual.
- `reputation` (ya existía, H3): entero **que puede ser negativo** [provisional: el GDD dice «0 a ∞», pero H3 ya
  prueba −5 y −10 desde 0; no se recorta].
- Regla: dentro de `reputation_caps` se pueden añadir reglas sin subir versión (JSON, con prueba).
- Prueba: `tests/test_core_h9_base.gd` con `tests/data/saves/v8_town_microevents.json`.

El Ayuntamiento **no es estado**: es un sitio del mapa (como el tablón).

## Datos
- **`data/titles/<id>.json`** (uno por título, GDD 4.12.2): `{id, name_key, rank (0 = común), cost_gold,
  reputation, requires: {businesses, employees, event}, unlocks: {max_buildings (null = sin límite), vote,
  office_rank}}`. `common` 0/0 (inicio, 1 edificio) · `citizen` 100/50, 1 negocio (2 edificios, votar, cargos menores) ·
  `patrician` 500/200, 2 empleados (4 edificios, cargos medios) · `baron` 2.000/500, 3 negocios (6 edificios, cargos
  mayores) · `noble` 10.000/1.000, evento especial (sin límite, todos los cargos). El orden por `rank` es el de
  `upgrade_rules.titles` (el validador lo exige).
- **`data/politics.json`** → `Catalog.politics`:
  - `reputation.classes`: `["artisan", "patron", "scholar", "rogue"]`; `log_size 12`; `class_share 0,5` (un cambio
    con clase mueve también el modificador de esa clase en `round(cantidad × class_share)`).
  - `reputation.reason_class`: la clase de los cambios que vienen de otros sistemas (`contract_done` /
    `contract_failed` / `wage_unpaid` / `fired_loyal` / `employee_rumor` → `artisan`) [provisional: los clientes del
    tablón y los empleados son artesanos].
  - `reputation.rules`: reglas que leen los eventos del paso (`Reputation.step`). Cada una: `{id, events, amount,
    class ("target" = la clase del otro: cliente del mostrador o vecino; o un id; o null), class_amount, cap,
    cap_days, min_quality, action, ok}`. Tope: como mucho `cap` veces por ventana de `cap_days` días (ventana =
    `día / cap_days`). Hoy: `fair_trade` (venta en mercado o mostrador, +1, 1 al día), `quality_trade` (venta de
    calidad buena o mejor, +1, 1 al día), `wages_paid` (+2, 1 vez al año), `npc_gift` / `npc_flatter` (+1 con la
    clase del vecino), `npc_insult` / `npc_threaten` (−1 global, −2 con su clase) [balance] [provisional: el GDD da
    «comercio justo y salarios pagados (+1/+2)» sin frecuencia; las acciones sobre vecinos no tienen cifra].
  - `reputation.passive`: `per_business_with_staff 1` (ap. A: +1/día por negocio operativo con empleados, al amanecer).
  - `ceremony`: `approvers ["mayor", "councillor"]`, `min_affinity 30` (GDD 4.12.2; hasta H10 no hay cargos: vacante →
    se aprueba solo).
- **`data/maps/town_e.json`** `town_hall: {origin, footprint, tile, service}`: el bloque sur de la plaza (6×4, casillas
  `#`), letrero en `tile`, se pide en `service` (como el tablón). Lo escribe `tools/maps/make_town_e.py`.
- **`data/microevents/*.json`**: efecto nuevo `reputation {amount}` (`Microevents.apply`). Hoy solo en «Echarle» del
  cliente que regatea (−1) [provisional].
- **`data/ai_profiles/rival_smith.json`** `title_rule: {requests: true, spare_gold: 100}` [provisional: regla mínima
  hasta que se apruebe 04c]: pide el siguiente título cuando cumple los requisitos y le sobra `spare_gold` tras pagarlo.
- **`data/upgrades/forge/*`**: sin cambios (Fachada noble ya pide Ciudadano).

## Paso del sim
Orden fijo (H7 + lo nuevo en negrita): … `Inspections` → `Loans` → `Births` → `Emotions` → **`Reputation.step`** →
`Dynasty` → `Objectives` → `Ledger` → `Notices`.
- **`Reputation.change(sim, fam, amount, reason, cls = "")`**: la única forma de cambiar la reputación. Suma a
  `reputation`; si hay clase (la dada o `reason_class[reason]`), `class_reputation[cls] += round(amount × class_share)`;
  apunta en `reputation_log`; evento `reputation_changed {family, amount, reason, class, reputation}`. Contratos,
  salarios, despidos, rumores, deuda vencida, inspecciones y fachadas pasan por aquí (antes cada uno sumaba a mano).
- **`Reputation.step`**: lee los eventos del paso (`market_sold`, `counter_sold`, `wage_paid`, `npc_action`) y aplica
  las reglas con su tope; al amanecer, la pasiva: +1 por cada negocio operativo (edificio propio de categoría
  `workshop`, sin embargar) con al menos un empleado activo. Sin azar.
- **`Titles`** (`sim/politics/titles.gd`): `current(sim, fam)`, `next_of(sim, fam)` (`""` si ya es el último),
  `businesses(sim, fam)`, `employees(sim, fam)`, `max_buildings(sim, fam)` (−1 = sin límite; **preparado para H6**,
  hoy nadie lo lee), `status(sim, actor) -> {family, current, next, cost, requirements: [{kind, need, have, ok}],
  at_town_hall, reason}`, `ready(sim, fam, spare)` (requisitos y oro + `spare`; lo usan la IA y el bot), `at_town_hall`.

## Órdenes
| Orden | Campos | Regla |
|---|---|---|
| `request_title` | actor, title? | No es de gestión (se pide en persona). El actor está vivo, es adulto y de una familia; quieto en la casilla `service` del Ayuntamiento; la familia no tiene ya el último título; `title` (si viene) es el siguiente; cumple reputación, negocios, empleados y evento; puede pagar; el cargo que aprueba (Alcalde, si no Concejal) tiene afinidad ≥ 30 con el actor o está vacante. **Ceremonia**: cobra `cost_gold` (categoría `titles`, ref `title_<id>`), `title` = el nuevo, crónica `title {family, title, actor}` (puntos de `data/score.json`), evento `title_granted {family, actor, title, from}`, aviso `notice.title_granted` a la familia y `notice.rival_title` a la humana si es otra. |

Motivos nuevos (`reason.*`): `not_at_town_hall`, `max_title`, `wrong_title`, `title_needs_reputation`,
`title_needs_businesses`, `title_needs_employees`, `title_needs_event`, `title_not_approved` (con `too_young`,
`dead`, `unknown_actor`, `not_enough_gold` de antes).

## Eventos y avisos
- Eventos: `reputation_changed {family, amount, reason, class, reputation}` (ya existía; ahora con `class` y el total),
  `title_granted {family, actor, title, from}`.
- Avisos: `notice.title_granted` (info, la familia), `notice.rival_title` (info, la humana cuando sube otra).

## IA rival (provisional)
`RivalAI._decide` añade la tarea `title` al principio del plan (al amanecer y en cada cambio de fase) si el perfil
tiene `title_rule.requests` y `Titles.ready(sim, fam, spare_gold)`. La tarea: sale del edificio, camina a la casilla
`service` del Ayuntamiento y da `request_title`. Nada de los módulos de 04c.

## Bots
- `artisan_novice`: sin cambios de conducta (los ganchos nuevos devuelven vacío).
- `artisan_expert` (`BotArtisanExpert`): **pide títulos** con dos ganchos: (1) parada `town_hall` en su viaje cuando
  `Titles.ready(sim, fam, RESERVE + reserva de mejoras)`; (2) cuando el siguiente título pide más empleados de los que
  tiene y ya llega a la mitad de la reputación necesaria, quiere tantos empleados como pide (su regla del segundo horno
  se deja de lado para eso). Antes de eso juega igual que en H5.
- Medidas nuevas en `tools/sim_runner.gd`: `title_<id>_day` (día jugado en que la familia del jugador lo consigue; −1
  si no), `title_rank` final, `reputation` final, `ai_title_ups` (títulos que suben las familias IA con perfil).

## Dianas (`data/targets.json`)
- `artisan_expert_titles` (bot `artisan_expert`, partida nueva Normal, 96 días = 12 años): llega a Patricio en ≥ 80 %
  de las semillas, de media entre el día 40 y el 96 (GDD 4.19: «Patricio (H9-H11) años 7-12»; 4.21: la IA pide sus
  títulos). Ritual largo, a mano.
- `idle_titles` (bot `idle`, partida nueva Normal, 80 días = 10 años): al menos una familia IA sube de título
  (`ai_title_ups >= 1`) en ≥ 80 % de las semillas.

- Medido (2026-11-02, Normal): `expert_titles` 10 semillas × 96 días: Patricio 10/10, día medio 60,6 (50-70),
  Ciudadano día 17,9 (16-22), reputación final ~320; `idle_titles` 10 semillas × 80 días: el rival sube a Ciudadano
  10/10 (días 24-40). No llega a Patricio: no contrata (H6).
- **`goldflow.staff` excluye `titles`** (como `start` excluye `loans`): la ceremonia de Ciudadano (100 de oro, una vez)
  cae en los días 16-22 del experto y bajaba su neto de los días 9-24 de 68,8 a 61,4 (10 semillas, `BOT_VARS=
  asks_titles=0/1`), al borde de la diana de H5. Con la exclusión: 67,4. Las cifras de la diana no cambian.

## Escenarios (`tools/scenarios/make_title_scenarios.gd`, desde una partida nueva Normal, semilla 1)
- **`title_ready`**: día 3, 10:00, sin deuda, 400 de oro, reputación 60, la Forja con un oficial; Hugo en la casilla
  del Ayuntamiento. Puede pedir Ciudadano; después, Patricio sale con requisitos pendientes.

## Vista
- **Ayuntamiento** en el mapa: `game/visuals/buildings/town_hall.tscn` en el `origin` de `town_hall` (sus casillas no
  se rellenan de casas), letrero «Ayuntamiento». Clic derecho con alguien elegido → camina a `service` y abre el panel.
- **Panel del Ayuntamiento** (`game/ui/town_hall_panel.*`): título actual, siguiente, coste, requisitos con ✓/✗
  (tengo/necesito), lo que abre, botón «Pedir el título» (apagado con el motivo).
- **Tarjeta de ceremonia** (`game/ui/title_card.*`): al `title_granted` de la familia humana; centrada, con el escudo
  de colores, el nombre y el título; se cierra con un clic o sola a los 8 s.
- **Reputación**: pestaña del libro de cuentas: global, por clase, título y lo que abre, últimos cambios.
- **Título** en el HUD (junto al nombre de la familia) y en la cabecera del árbol genealógico.
- Ayuda (F1): sección «Reputación y títulos» (`help.titles*`).
- Capturas: `grimoire heavy --timeout 3m -- /opt/homebrew/bin/godot --audio-driver Dummy --always-on-top --path . --
  --smoke-script=titulos` → `h9_reputacion`, `h9_ayuntamiento`, `h9_ceremonia`.

## Decisiones provisionales
- **«Ganancias pasivas» = reputación pasiva** (ap. A: +1/día por negocio operativo con empleados). El GDD no da otra
  ganancia pasiva por título.
- **Reputación negativa permitida** (H3 ya la prueba); `class_reputation` es un modificador que se suma a la global.
- **Frecuencias** de «comercio justo» (+1 al día con alguna venta), «venta de calidad» (+1 al día con alguna de calidad
  buena), «salarios pagados» (+2 al año) y de las acciones sobre vecinos [balance].
- **Clase de los cambios**: contratos y empleados → artesanos; mostrador y acciones → la clase del vecino.
- **Ceremonia instantánea** al pedirla (sin días de espera); sin cargos (H10) siempre se aprueba.
- **Negocio operativo** = edificio propio de categoría `workshop` sin embargar; **empleados** = contratados de la
  familia (cualquier edificio).
- **Noble** pide un evento especial que aún no existe: no se puede pedir (`title_needs_event`).
- **Límite de edificios** en datos (`unlocks.max_buildings`) y en `Titles.max_buildings`; lo aplicará H6.
- **IA rival**: regla mínima en datos (`title_rule`), no los módulos de 04c.
- **El Ayuntamiento no tiene horario** (se puede pedir a cualquier hora en que el actor esté allí).
- **El experto pide títulos cuando termina su plan de mejoras** (primero el negocio, luego el estatus) y, para
  Patricio, contrata el segundo empleado cuando tiene la mitad de la reputación (su regla del segundo horno cede).
- **Sprite del Ayuntamiento**: `house_noble_2` de Guild Renew (casa noble con torre) a escala 1,6; la huella del mapa es
  6×4 (el GDD dice 6×6: el bloque de la plaza es de 6×4).
