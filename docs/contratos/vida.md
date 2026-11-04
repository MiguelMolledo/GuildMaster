# Contrato · Vida (la ciudad viva II)

Diseño: [`docs/gdd/04f_vida_y_fiestas.md` §4.24](../gdd/04f_vida_y_fiestas.md). Guardado: **v17**. Rama `vida`.

## Interruptor

`data/life/life.json` → `enabled`. Apagado, la ciudad es la de H7 tal cual: `TownLife` sigue su rama de H7, no hay
guardia, forasteros, rumores ni sucesos, y el tope de vecinos es el de `data/town.json` (20). Las dianas de antes
corren así (`data/targets.json` → `_no_life`; `sim_runner` lo apaga para esos bots salvo `--life=on`). Las pruebas
y la partida normal lo tienen encendido. `sim_bench -- --life=off` mide el coste sin la vida.

## Sistemas (sim/life/)

| Clase | Fichero | Qué hace | Paso |
|---|---|---|---|
| `Life` | `life.gd` | Fachada: interruptor, bloques del estado, familias de servicio, personas temporales, espectáculos, multiplicadores de eventos | `Sim.step` tras `TownLife` |
| `Agenda` | `agenda.gd` | Necesidades y elección por utilidad de los vecinos (la llama `TownLife._step_one` con la vida encendida) | dentro de `TownLife` |
| `Rumors` | `rumors.gd` | Corrillos en los puntos de reunión, rumores de hechos reales y el libro de lo oído | `Life.step` |
| `Visitors` | `visitors.gd` | Forasteros que entran por las puertas, su plan y su marcha; la limosna | `Life.step` |
| `Watch` | `watch.gd` | La guardia: puertas de día, rondas de noche, plaza en fiesta, respuesta a un grito | `Life.step` |
| `Incidents` | `incidents.gd` | Altercado, asalto de bandidos y secuestro, con su carta | `Life.step` |

Orden en `Life.step`: `Visitors`, `Incidents`, `Watch`, `Rumors`. Azar: siempre `Kin.roll` con claves `life|…` o
`events_city|…`; nunca `state.rng` (las tiradas de hoy no se mueven).

## Estado (v17, `SaveFile._to_v17`)

Todo bajo `state.town` (no hay campos nuevos en la raíz, para que v18 y v19 se encadenen sin tocarse):

| Bloque | Forma |
|---|---|
| `town.life` | `{spectacles: [{id, tile, until, by}], cries: []}` |
| `town.visitors` | `{alive: [chr], day, planned: [{at, kind, city, gate, key}], alms: {fam: day}}` |
| `town.watch` | `{guards: {chr: role}, dispatch: {chr: {tile, incident, since, arrived, arrived_at}}}` |
| `town.rumors` | `{told: {point: {key, rumor, text_key, params, speaker, until, useful, …}}, heard: [{key, rumor, text_key, params, minute, point, useful, by}]}` |
| `town.incidents` | `{active: [incident], closed: [las 20 últimas], planned: [{def, at, key, building?, victim?}], nests: {route: día}, last: {def: día, kidnapping_year, altercation_pending}, warned: {key: {until, place_key, def}}, mult: número o {def: número}}` |

Personajes: `town.needs` (décimas 0-1000) y `town.needs_at` en los vecinos; las personas temporales de las familias de
servicio (`fam_watch`, `fam_visitors`, `fam_bandits`, `controlled_by: "town"`, `service: true`) llevan `guard {role,
post, wp, wait_until, greet_until}`, `visitor {kind, city, gate, purse, plan, stop, until, leaving, arrived}` o
`bandit {incident, leader}`, y `offstage` (fuera del mapa) o `captive` (id del secuestro). `visual.dress` = ropa de
la ciudad de un forastero. Las familias de servicio no son hogares (no se contratan ni se casan), no juegan y no
cuentan como vecinos.

## Órdenes

| Orden | Quién | Efecto |
|---|---|---|
| `resolve_incident {actor, incident, choice[, helpers]}` | la familia de la carta | elige en la carta del suceso (gestión: se aplica al momento, también en pausa). Rechazos: `unknown_incident`, `not_your_family`, `unknown_choice`, `too_far`, `too_late`, `away`, `not_enough_gold`, `already_negotiated`, `already_tried` |
| `give_alms {actor, target}` | cualquiera a ≤ `town.actions.range_tiles` de un mendigo | 1 de oro (`donations`); +1 de reputación una vez al día por familia. Rechazos: `not_a_beggar`, `too_far`, `not_enough_gold` |

## Eventos del sim (para la vista y los bots)

`activity_done`, `rumor_told`, `rumor_heard`, `visitor_arrived`, `visitor_left`, `alms_given`, `guard_hired`,
`guard_on_duty`, `guard_off_duty`, `guard_greets`, `guard_arrived`, `watch_called`, `incident_warned`,
`incident_started`, `incident_card`, `incident_fight`, `incident_choice`, `incident_negotiated`, `incident_rescue`,
`incident_raid_at_door`, `incident_raid_repelled`, `incident_raid_loot`, `incident_ended`, `spectacle_started`.
Crónica: `altercation`, `bandit_raid`, `kidnapping`, `kidnapping_end`.

## Ganchos para los otros bloques

- **Fiestas (v18):** un evento de `data/events.json` con efectos `{kind: routine, activity, mult}` multiplica una
  actividad; `{kind: holy_day}` hace día de guardar (el trabajo cede al 70 %); `{kind: incident, id, mult}` y
  `{kind: visitors, mult}` multiplican sucesos y forasteros; un evento con `festival: true` (o el `festival` de hoy)
  saca al guardia de la plaza. Un espectáculo (toros, cómicos) se anuncia con `Life.add_spectacle(sim, id, tile,
  until, by)`: los vecinos van a mirarlo (`watch_show`).
- **Posada (v19):** un sitio del mapa de tipo `tavern_inn` (o `tavern`) recibe su punto `tavern` (`ciudad.py
  reunion`): la actividad `tavern` y los altercados lo usan; los forasteros que duermen se quedarán cuando la posada
  diga que hay cama (hoy se van al atardecer).
- **Juegos:** las apuestas sobre un altercado (4.26.6) se engancharán a `incident_fight` (lleva el ganador del duelo).

## Vista (game/)

- `LifeQuery` (`game/life/life_query.gd`): burbuja (`rumor`, `fight`, la del forastero, `wave` del guardia), frase del
  rumor cuando la familia está cerca, libro de rumores, farol.
- `IncidentCard` + `IncidentPage` (`game/ui/life/`): la carta de PageCard; ilustración por
  `VisualPaths.illustration("events", <nombre>)` con el nombre del arte (`IncidentPage.ART_ALIAS`: altercation →
  `altercado`, bandit_raid → `asalto_bandidos`, kidnapping → `secuestro`; inventario `illus_<nombre>`), greybox rayado
  con etiqueta si falta.
- `RumorBook`: pestaña «Rumores» del libro de cuentas.
- Burbujas nuevas en `game/visuals/bubbles/` (`water`, `wash`, `pray`, `play`, `show`, `alms`, `rumor`, `fight`) y
  el farol `game/visuals/props/hand_lantern.tscn`.

## Mapas

`social_points` con kinds nuevos (`well`, `atrium`, `tavern`, `washhouse`, `bridge`, `gate`, `square`) y `patrols`
(`[{id, tiles}]`). Los pone `tools/city/citylib.add_life` (generador, ciudades orgánicas y `make_town_e.py`), después
del decor y nunca encima. Para un mapa ya hecho: `python3 tools/city/ciudad.py reunion [mapa…]`. town_e conserva sus
seis puntos de H7 primero (H7 solo pasea por `bench`, `chat` y `dice`). `population_max` opcional por mapa.

## Rituales

- Pruebas: `tests/test_life_*.gd` (`-- --only=test_life`).
- Bot: `godot --headless --path . -s tools/sim_runner.gd -- --scenario=life_bandits --bots=guard_watch --days=16
  --seeds=5` (QA: paso `life`, 3 semillas).
- Escenarios: `godot --headless --path . -s tools/scenarios/make_life_scenarios.gd` (`life_plaza`, `life_gate`,
  `life_night`, `life_altercation`, `life_bandits`, `life_kidnap`).
- Sonda: `godot --headless --path . -s tools/life/life_probe.gd -- [--days=2] [--off]`.
- Capturas: `grimoire heavy --timeout 5m -- godot --audio-driver Dummy --always-on-top --path . -- --smoke-script=vida`.
