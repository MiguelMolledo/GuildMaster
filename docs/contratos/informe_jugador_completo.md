# Contrato: el informe del jugador completo (formato de los JSON)

Lo escribe `tools/full_player.gd` (docs/gdd/07_testing.md §7.4). Lo leen `tools/full_report.py` (el HTML) y cualquier
otra herramienta, como el resumen de balance de la rama `verifica`. **Formato estable:** los campos de aquí no cambian
de nombre ni de significado sin subir `format_version` y apuntarlo al final de esta página. Se pueden añadir campos
nuevos sin subirla, así que quien lo lea debe ignorar los que no conozca.

## Dónde

| Carpeta | Quién la escribe |
|---|---|
| `reports/full_player/` | `full_player`, 3 años × 5 semillas (la noche: `tools/qa/noche.py`) o a mano sin `--tag` |
| `reports/full_player_generation/` | `full_player --generation` (la noche) |
| `reports/chaos_player/` | `chaos_player`, 3 años (la noche) |
| `reports/idle_player/` | `idle_player` (el jugador no hace nada: la IA sola), 3 años |
| `reports/<bot>_<tag>/` | cualquier corrida con `--tag=<tag>` (la QA usa `_qa`) |

En cada carpeta: `<semilla>.json` (una partida), `summary.json` (las dianas y el agregado), `index.html` y `saves/`
(`<semilla>_fin.json` al final y `<semilla>_atasco.json` en el primer atasco: partidas guardadas que el juego carga).

## Convenciones

- **Días:** `day` y `*_day` son el día jugado, contado desde 1. `-1` quiere decir «nunca». Las medidas
  `title_<id>_day` valen `days + 1` cuando no se alcanzó, como en `sim_runner`.
- Un año son 8 días (D1 b). `net_year_<n>` es el oro neto por día del año n, sin la categoría `loans`.
- Los ids son los del estado: `fam_*`, `chr_*`, `bld_*`.
- La semilla es la de `NewGame.from_start(..., seed)` con `cast: fixed`. Misma versión del juego + misma semilla =
  misma partida.

## `<semilla>.json`

| Campo | Tipo | Qué es |
|---|---|---|
| `format_version` | int | 2 |
| `seed`, `bot`, `horizon`, `difficulty`, `start`, `days` | | la corrida: `horizon` es `"3y"`, `"1y"` o `"generation"` |
| `measures` | {str: número} | **las cifras planas**: las que comprueban las dianas y agrega `summary.json` (ver abajo) |
| `curve` | [{day, gold, debt, title, title_rank, reputation, offices[], members, children, staff, head}] | la familia del jugador al final de cada día |
| `family` | {weddings[], births[], deaths[], inheritance[], heir[]} | con `day` y los ids |
| `titles`, `offices` | [{day, title}] / [{day, office, character}] | del jugador |
| `unlocks` | [{id, day, window, verdict}] | `day` es el índice de día (como la ventana de 03b); `verdict`: `on_time`, `early`, `late`, `never`, `not_judged`, `hook_missing`. Vacío sin `data/unlocks.json` |
| `mechanics` | {mecánica: {orders, refused, events, first_day, used, why?}} | `why`, si no se usó: `not_in_game`, un motivo del bot (`why_not`) o `no_occasion` |
| `pacing` | {decisions, gap_median_s, gap_p90_s, gap_max_s, y1_gap_median_s, y1_gap_max_s, real_minutes} | segundos reales entre decisiones, como el bot `pacing` |
| `refused`, `refused_examples` | {"orden\|motivo": n} / [{day, minute, order, actor, reason}] | solo las órdenes del bot |
| `stalls` | [{kind, who, name?, role?, from_day, hours, where, cause}] | `kind`: `character` o `queue`; `cause`: `under_works`, `empty_queue`, `no_gold`, `no_materials` o `""` |
| `contracts_failed` | [{day, contract, item}] | |
| `engine` | {errors, warnings, lines[]} | contados con un `Logger` |
| `bench` | {steps, step_ms_mean, step_ms_p99, step_ms_max, bot_ms_mean, slow_steps, hangs} | `slow_steps` son los pasos de más de 50 ms y `hangs` los de más de 2 s |
| `chaos` | {roundtrips, roundtrip_mismatch, load_errors, gold_negative, off_map, hangs, examples[]} | guardar y cargar cada día (caótico, o `--roundtrip`) |
| `saves` | {end, first_stall?} | rutas `res://` |
| `bot_report` | {why_not, used, decisions[], heads[], focus_minutes, chaos_uses?} | lo que cuenta el propio bot |
| `rivals` | {fam: bloque} | las familias IA con perfil (ver abajo) |
| `town` | bloque | la vida del pueblo (ver abajo) |

### `rivals[fam]`

La IA rival que hay hoy es la de 4.5.5 más los ganchos provisionales de H9-H11. La agenda de intenciones de 04c (H6)
no está hecha: lo que aquí se llama «plan» son las tareas de `RivalAI` (`ai_state.plan`).

| Campo | Qué es |
|---|---|
| `id`, `name`, `profile`, `buildings_start` | la familia, su perfil (`rival_smith`, `rival_artisan`) y los tipos de edificio con que empieza |
| `curve` | [{day, gold, title, title_rank, reputation, buildings, members, staff}] al final de cada día |
| `titles`, `offices_run`, `offices_won` | [{day, title / office}] |
| `weddings`, `births`, `deaths`, `inherited` | su familia |
| `sold_units`, `sold_gold`, `bought_gold`, `work_done` | su negocio |
| `contracts_accepted`, `contracts_done`, `contracts_failed`, `festival_contracts_done` | encargos del tablón y de fiesta |
| `races_won_vs_player` | encargos de fiesta que ganó al jugador (`contract_lost` del jugador) |
| `accusations_vs_player` | [{day, charge, source}]: sus ataques al jugador (hoy solo el juicio; 04c añadirá más) |
| `accusations_other` | acusaciones a otras familias |
| `plan_chosen` | {tarea: veces que entró en un plan decidido} |
| `task_ended` | {tarea: veces que salió de la cabeza del plan (hecha o abandonada)} |
| `task_minutes` | {tarea: minutos al frente del plan} |
| `refused` | {"orden\|motivo": n}: órdenes de la IA rechazadas |
| `idle_days` | días sin vender ni terminar ningún ciclo |
| `broke_days` | días que acaba con menos de 10 de oro |
| `stalls` | [{from_day, hours, where, task, gold}]: su cabeza sin moverse ni trabajar 16 h |
| `duels` | duelos en que tomó parte |

### `town`

| Campo | Qué es |
|---|---|
| `activity_share` | {actividad: parte de las horas}: de los vecinos (`Agenda.view`), muestreado cada hora |
| `needs_mean` | {necesidad: media 0-100} |
| `short_share_max` | {necesidad: la peor parte de horas de un vecino con esa necesidad < 25} |
| `npc_stalls` | [{who, name, from_day, hours, activity, where}]: un vecino sin moverse ni cambiar de actividad 20 h |
| `population` | {weddings, births, deaths, newcomers, by_year: [{year, townsfolk}]}, sin la familia del jugador |
| `visitors` | {total, by_kind, by_day} |
| `incidents_by_season` | {"<estación>\|<suceso>": n}: la estación es el índice desde el inicio del calendario |
| `watch` | {called, arrived, minutes_median, minutes_max, outcomes: {"suceso\|desenlace": n}}: la guardia |
| `contested_elections` | elecciones en que se presentaron el jugador y una familia IA |
| `player_lost_races` | encargos de fiesta que el jugador perdió contra una familia IA |

### `measures` (las cifras planas)

- **Del jugador:** `days`, `gold_end`, `gold_min`, `net_year_<n>`, `debt_paid`, `debt_paid_day`, `title_<id>`,
  `title_<id>_day`, `title_rank`, `reputation`, `office_won_day`, `wed`, `wedding_day`, `had_child`, `children`,
  `first_child_day`, `inherited`, `inherit_day`, `founder_death_day`, `game_over`, `ended_by_ai` (1 si el final que
  hay en `state.ending` es de otra familia; el bloque `ending` del informe lo copia), `hired`, `upgrades_done`,
  `contracts_done`, `contracts_failed`, `festival_contracts`, `counter_sold`, `trips`, `caravans`, `treaties`,
  `duels_fought`, `duels_won`, `trials_as_accuser`, `trials_against`, `incidents`, `mechanics_used`,
  `mechanics_in_game`, `refused_orders`, `stalls`; con la forja, `masterworks`, `masterwork_day`, `spec_pieces`
  (piezas hechas a la variante de un encargo), `spec_mismatch` y `spec_mismatch_<por qué>` (las que no casaron:
  `quality`, `temper`, `length`, `guard`, `contract_gone`).
- **Del tribunal y la región** (añadidas por equilibrio, 2026-11-06): `facts_vs_others` y `fact_day_vs_others` (hechos
  públicos contra otras familias: casos para acusar) y `fact_<tipo>`; `caravan_home_value` (lo que valía en la villa la
  carga de sus caravanas), `caravan_sold`, `caravans_ambushed`, `city_sales_gold`, `quota_units`, `quota_gold`,
  `treaties_broken`, `treaty_costs`, `carts_bought`. Para los 3 primeros años en cualquier horizonte:
  `masterworks_y3` y `stalls_y3`.
- **Del motor y del bench:** `engine_errors`, `engine_warnings`, `step_ms_mean`, `step_ms_max`, `bot_ms_mean`,
  `hangs`, `ledger_mismatch`.
- **Del ritmo:** `gap_median_s`, `gap_p90_s`, `gap_max_s`, `y1_gap_median_s`, `y1_gap_max_s`, `unlocks_off`.
- **Del guardado:** `roundtrips`, `roundtrip_mismatch`, `load_errors`, `gold_negative`, `off_map`.
- **De los rivales:** `ai_families`, `ai_titled_families`, `ai_title_ups`, `ai_office_runs`, `ai_offices_won`,
  `ai_attacks_vs_player`, `ai_refused`, `ai_refused_per_family_year`, `ai_idle_days_max`, `ai_broke_days_max`,
  `ai_stalls`, `ai_weddings`, `ai_births`, `ai_contracts_accepted`, `ai_races_won_vs_player`, `contested_elections`.
- **Del pueblo:** `npc_stalls`, `npc_hungry_share_max`, `npc_short_<necesidad>_max`, `town_weddings`,
  `town_births`, `town_deaths`, `townsfolk_end`, `visitors_per_day`, `watch_called`, `watch_arrived_share`.
- **Del propio bot:** `bot_<medida>` (las de `festive`, `dynasty` y `guard_watch`: `bot_fest_*`, `bot_raids`...; con
  la taberna, las de `innkeeper`: `bot_inn_net_day`, `bot_inn_operating_day`, `bot_inn_fame`, `bot_inn_bed_share`,
  `bot_inn_guests_night`, `bot_inn_complaints_night`, `bot_inn_fights`, `bot_inn_upgrades`, `bot_inn_licensed`).
  Las mecánicas `tavern`, `games` y `bets` cuentan desde la posada y los juegos, y `live_forge`, `masterwork`,
  `variant_contracts` y `unlocks` desde la forja (órdenes `buy_building`, `inn_*`,
  `game_enter`, `game_play`, `game_bet`; sucesos `building_bought`, `game_played`, `game_bet_settled`).

## `summary.json`

`{format_version, bot, horizon, difficulty, start, seeds[], aggregate: {mean_<m>, min_<m>, max_<m>, share_<m>},
misses[], proposed_misses[], targets, runs: [measures de cada semilla]}`. `targets` es el bloque de `data/targets.json` que se comprobó, ya sin las medidas que la corrida
no podía juzgar (`_needs_days`).

## Referencia en git: `reports/full_player_ref/`

`reports/` no va a git, salvo esta carpeta. `python3 tools/full_ref.py [carpetas]` copia el `summary.json` de cada
corrida (por defecto `full_player`, `full_player_generation`, `chaos_player` e `idle_player`) a
`reports/full_player_ref/<carpeta>.json`. Cada copia lleva lo de `summary.json` más `runs` (las `measures` de cada
semilla), `source` (la carpeta), `written` (la fecha) y `commit` (el del código que la escribió). La llama
`tools/qa/noche.py` al acabar. Son unos 15-30 KB por corrida: se suben con el commit del bloque, para que `verifica` y
el equilibrio las lean sin depender del worktree que corrió las partidas. Las copias con `format_version` 1 son de
antes de los rivales y el pueblo.

## Historial

| Versión | Cambio |
|---|---|
| 1 | Primera (2026-11-05): el jugador y el motor |
| 2 | 2026-11-05: `rivals`, `town` y sus medidas; `idle_player`; el ritmo del año 1; en `summary.json`, `runs` y `proposed_misses`; la copia en `reports/full_player_ref/` |
