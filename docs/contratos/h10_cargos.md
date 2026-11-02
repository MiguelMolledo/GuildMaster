# Contrato H10 · cargos y elecciones

Lo que comparte H10 (un subgrim, rama `h10-cargos`, que sale de `main` dcab351 con H1-H9 y H7; el manager la junta
con `main`). Quien cambie un nombre lo cambia aquí. Base: `docs/contratos/h1_mundo.md` … `h9_titulos.md`.
GDD: 4.12.3 (cargos, gobierno procedural, vacantes, impuestos), 4.12.4 (elecciones, campaña, votación, organigrama),
4.12.1 (ocupar un cargo da reputación), 4.12.2 (la ceremonia la aprueba el Alcalde o un Concejal), 4.19 (`offices`,
`politics`, `taxes`), 4.17 (puntos por cargo y por año de mandato), 4.21 (la IA se presenta; 04c sin aprobar: aquí solo
una regla mínima), 05 (órdenes `RunForOffice`, `CampaignAction`, `UseOfficePower`; `politics/offices.gd` y
`elections.gd`), 06 (ficha de cargo), ap. A (fórmula del voto).
Criterios del hito (10, fila H10): el bot `politician` gana un cargo menor; el Inspector regula un precio y se nota en
el mercado; test: la campaña ocupa la última estación del mandato y la elección cae al cambiar de año. Además: la IA
rival se presenta (al menos una vez en 10 años con `idle_titles`).

## Zonas (ficheros)
| Zona | Ficheros | Pruebas |
|---|---|---|
| base | `sim/core/world_state.gd` (v10), `sim/meta/save_file.gd` (paso 9→10), `sim/core/catalog.gd` (`offices`), `data/offices/*.json`, `data/politics.json` (`government`, `elections`, `taxes`, `regulation`), `data/score.json`, `tools/scenarios/make_office_scenarios.gd`, `tools/validate_content.py` (`check_h10`), `tests/data/saves/v9_title_ready.json` | `tests/test_core_h10_base.gd` |
| sim | `sim/politics/offices.gd` (gobierno, mandatos, salarios, impuestos, poderes, regulaciones), `sim/politics/elections.gd` (presentarse, campaña, votación); enganches en `sim/core/sim.gd`, `orders.gd`, `sim/meta/new_game.gd` (gobierno al empezar), `sim/econ/market.gd` (precio regulado), `sim/politics/titles.gd` (quién aprueba), `sim/ai/rival_ai.gd` (tarea `office`), `sim/bots/bot_artisan_expert.gd` (ganchos `politician`), `tools/sim_runner.gd`, `data/targets.json`, `data/ai_profiles/rival_smith.json` | `tests/test_politics_offices.gd`, `tests/test_politics_elections.gd`, `tests/test_bots_politician.gd` |
| vista | `game/ui/offices_panel.*` (organigrama, presentarse, campaña y poderes), `game/ui/office_card.*` (resultado de la votación), botón «Cargos y elecciones» en `town_hall_panel.*`, botón Cargos del HUD (tecla O), acciones de campaña y cargo en `npc_panel`, cargo en `character_panel` y en el árbol (`family_tree_node`), `SimQuery.office_name`, ayuda F1, `game/smoke/smoke_cargos.gd` | `tests/test_game_offices.gd` |

## Estado (guardado v10)
Migración 9 → 10 (`SaveFile._step`), en la **raíz** (las familias y personajes no cambian):
- **`offices`** (ya existía, vacío hasta H9): `{office_id: {seats: [seat], settings: {}}}`. Un `seat`:
  `{holder: chr_id | "", since: día, until: día, cooldowns: {power: minuto}}`. `until` = el día que empieza con el
  cambio de año en que acaba el mandato (el día de la elección); en un asiento vacante, el próximo cambio de año.
  `settings` del Recaudador: `{tax_percent: int}`. La familia del titular no se guarda: es la del personaje.
  Migración: lo que no tenga esa forma pasa a `{}`. **Un `offices` vacío en un mapa con Ayuntamiento = gobierno sin
  repartir**: `Offices.step` lo reparte la primera vez que corre (partidas y escenarios v9; el mismo reparto que una
  partida nueva, que lo hace en `NewGame.from_start`).
- **`elections`** (ya existía, lista vacía): `[election]`. Una elección: `{id: "ele_0001", office, day (el de la
  votación), campaign_day (primer día de la campaña: el invierno), status: "open" | "done", candidates: [cand],
  result: {} | {votes: {chr: n}, winners: [chr], voters, unopposed, by_family: {fam: n}}}`. Un candidato: `{character,
  family, level, incumbent, minute, support: {voter: ‰}, smear: ‰, secured: [voter], busy_until: minuto, done:
  {acción: día}}`. Se guardan las últimas `elections.keep` (12) cerradas. **Sin decimales**: los bonos van en milésimas
  (‰) y los porcentajes en enteros.
- **`market.regulations`** (ya existía, vacía): `[{item, percent (±10), until (minuto), by (chr), family}]`.
- Al repartir el gobierno, las **familias de hogar** (IA sin perfil, por id) toman el título de
  `government.household_titles[i]` (`common` si no hay).
- Ids nuevos (`Ids.next`): `ele`.
- Regla: dentro de `settings`, `cooldowns`, `result` y del candidato se pueden añadir campos sin subir versión (JSON,
  con prueba).
- Prueba: `tests/test_core_h10_base.gd` con `tests/data/saves/v9_title_ready.json`.

## Datos
- **`data/offices/<id>.json`** (uno por cargo, GDD 4.12.3 y 06): `{id, name_key, rank (minor | middle | major |
  mayor), min_title, salary (oro/día), term_years, seats, order (lugar en el organigrama, 0 = arriba), passive: [efecto],
  powers: [poder]}`. Los 6 de EA: `mayor` (Barón, 10, 4 años), `councillor` ×2 (Barón, 6, 3), `judge` (Patricio, 5,
  2), `constable` (Alguacil, Patricio, 4, 2), `tax_collector` (Ciudadano, 3, 1), `market_inspector` (Ciudadano, 2, 1).
  - Pasivos (`kind`): `class_reputation {class, percent}` (la reputación con esa clase de la familia del titular ×
    (1 + percent/100): Inspector +10 % artesanos, Juez +20 % eruditos), `tax_commission {percent}` (Recaudador 5 % de
    lo recaudado), `reputation_per_day {amount}` (Alcalde +1/día al amanecer) [provisional: el GDD dice «+reputación
    global» sin cifra], `sees_reports` / `votes_ordinances` (sin efecto hasta H11 / EA).
  - Poderes (`id`, `cooldown_days`, `ready`: `true` o el hito que lo trae): **H10**: `regulate_price` (Inspector:
    `{item, percent ±10}` durante `regulation.days`), `fine_merchant` (Inspector: `{family}`, multa `fine_gold`),
    `set_tax` (Recaudador: `{percent}` 5-15). **Más tarde** (en datos, rechazados con `power_not_ready`):
    `seize_building` (H11), `arrest` / `investigate` / `preside_trial` / `pardon` (H11), `propose_ordinance` / `veto` /
    `legislate` / `declare_event` / `name_title` (EA).
- **`data/politics.json`** → `Catalog.politics`, secciones nuevas:
  - `government`: `household_titles` (por orden de familia de hogar), `start_vacant` (`["market_inspector",
    "tax_collector"]`: GDD «se dejan 1-2 cargos menores libres»), `take_reputation` por rango (`minor 5, middle 10,
    major 20, mayor 30`) [provisional: 4.12.1 dice que ocupar un cargo da reputación, sin cifra].
  - `elections`: `levels` (`basic` 0 oro / 50 ‰, `medium` 50 / 150 ‰, `high` 200 / 300 ‰), `vote` (pesos `affinity
    0,3`, `reputation 0,3`, `class 0,2`, `campaign 0,2`; normalizaciones `relation_norm 100`, `reputation_norm 200`,
    `class_norm 50`, `campaign_norm 300` ‰; `against ["offended", "angry"]`, `favor ["grateful", "scared"]`),
    `actions` (`visit`, `bribe`, `speech`, `defame` con sus cifras), `keep 12`.
  - `taxes`: `default_percent 5`, `min 5`, `max 15`, `categories ["market_sales", "counter_sales"]`.
  - `regulation`: `percent 10`, `days 2`; `fine_gold 20`.
- **`data/ai_profiles/rival_smith.json`** `office_rule: {runs: true, offices: ["market_inspector", "tax_collector"],
  level: "medium", spare_gold: 50}` [provisional: regla mínima hasta que se apruebe 04c].
- **`data/score.json`** ya tenía `office_won` (por `rank`) y `office_year` (+10).

## Calendario (D1(b): año de 8 días, estación de 2)
- Cada asiento acaba su mandato un **cambio de año** (`until`). Esa noche (minuto 0 del día `until`, el paso con
  `year_changed`) se vota.
- **Inscripción**: durante el último año del mandato, **antes del invierno** (días `until − 8` … `until − 3`). Un asiento
  vacante vota en el próximo cambio de año.
- **Campaña**: la última estación del mandato, el invierno (`campaign_day = until − 2`). Las acciones de campaña solo
  valen entonces y solo para candidatos.
- Al empezar la partida (día 0) el gobierno arranca con mandatos que empiezan ese año: Juez y Alguacil acaban el día 16,
  Concejales el 24, Alcalde el 32; los vacantes votan el día 8.

## Paso del sim
Orden fijo (H9 + lo nuevo en negrita): … `Emotions` → **`Offices.step`** → `Reputation.step` → `Dynasty` → …
- **`Offices.step`**: reparte el gobierno si falta; con `character_died` deja vacante el asiento del muerto; con
  `season_changed` a invierno avisa a los candidatos humanos de que empieza la campaña; con `year_changed` llama a
  `Elections.resolve` de cada elección de ese día y cierra los mandatos (reelección automática del titular si nadie
  más se presenta); al amanecer paga **salarios** (`offices`, a la familia del titular, también hogares), cobra los
  **impuestos** del día anterior (si hay Recaudador: `tax_percent` de las ventas de cada familia, categoría `taxes`;
  la comisión del Recaudador a su familia, `offices`), da la reputación pasiva del Alcalde y quita las regulaciones
  que caducan.
- **`Elections.resolve(sim, election)`**: candidatos = inscritos + el titular saliente (vivo y con título; nivel
  básico). Si hay tantos o menos que asientos: ganan sin votar (`unopposed`). Si no, vota cada **vecino** (personaje
  vivo, adulto, no humano, de familia con título ≥ el que abre `vote`, que no es candidato):
  `puntos = 0,3 × relación/100 + 0,3 × reputación/200 + 0,2 × mod_clase/50 + 0,2 × campaña/300‰` (cada término en
  −1..1; mod_clase = la reputación con la clase del votante × pasivo − la global; campaña = nivel + discurso − difamación).
  Soborno → vota a ese seguro; emoción `favor` hacia la familia → la prefiere; `against` → nunca le vota. Empate →
  más reputación → id. Ganan los N más votados (empate: reputación, id). Sin azar: misma partida, mismo resultado.
- **Toma de cargo** (`Offices.take`): asiento con `holder`, `since` = hoy, `until` = hoy + `term_years` × 8, crónica
  `office_won {family, office, rank, actor}`, reputación `take_reputation[rank]` (`office_taken`), evento
  `office_taken`, aviso. El que pierde o acaba: `office_left {office, character, reason: term | lost | died}`. Cada
  cambio de año, cada titular con un año entero cumplido: crónica `office_year {family, office}` (+10).

## Órdenes
| Orden | Campos | Regla |
|---|---|---|
| `run_for_office` | actor, office, level | **Gestión** (desde el organigrama). Vivo, adulto, de una familia; título de la familia ≥ `min_title`; no ocupa otro cargo (sí puede ir a la reelección del suyo); no es ya candidato en otra elección abierta; el cargo tiene elección el próximo cambio de año; aún no es invierno; puede pagar el nivel (`politics`). Crea la elección si no existe. |
| `campaign_action` | actor, kind, target | En persona. Candidato de una elección abierta y en campaña; no ocupado (`busy_until`). `visit` (target = un vecino al alcance: +`relation` con cada adulto de su familia, ocupado 4 h), `bribe` (target = un votante al alcance; 20 de oro `politics`; voto seguro; SkillCheck Sigilo vs Empatía: fallo = −10 de reputación `bribe_scandal`), `speech` (fuera de edificios; SkillCheck Retórica vs 5; éxito: +100 ‰ con los votantes a ≤ 6 casillas; una vez al día), `defame` (target = otro candidato de la misma elección; SkillCheck Sigilo vs 5 − 20; éxito: −100 ‰ a sus votos; fallo: −20 de reputación `defame_scandal`; una vez al día). |
| `use_office_power` | actor, power, args | **Gestión**. El actor ocupa el cargo del poder; el poder está listo (`ready: true`) y sin enfriamiento. `regulate_price {item, percent}`, `fine_merchant {family}`, `set_tax {percent}`. Enfriamiento `cooldown_days` en su asiento. |

Motivos nuevos (`reason.*`): `unknown_office`, `office_needs_title`, `holds_office`, `already_candidate`,
`no_election`, `registration_closed`, `unknown_level`, `not_candidate`, `campaign_not_started`, `campaign_busy`,
`unknown_campaign_action`, `not_a_voter`, `not_a_candidate`, `indoors`, `not_office_holder`, `unknown_power`,
`power_not_ready`, `power_cooldown`, `bad_args`, `not_a_merchant`, `already_regulated`, `already_bribed` (con
`too_young`, `dead`, `unknown_actor`, `unknown_target`, `no_family`, `not_enough_gold`, `too_far`, `already_today` de
antes).

## Eventos y avisos
- Eventos: `office_candidate {election, office, character, family, level}`, `campaign_action {election, actor, kind,
  target, ok}`, `election_held {election, office, winners, votes, unopposed}`, `office_taken {office, character,
  family, until}`, `office_left {office, character, family, reason}`, `office_power {office, power, actor, args}`,
  `price_regulated {item, percent, until}`, `tax_collected {family, amount}`.
- Avisos: `notice.office_candidate` (familia humana al inscribirse), `notice.campaign_started`, `notice.office_won`,
  `notice.office_lost`, `notice.rival_candidate` / `notice.rival_office` (otra familia que juega se presenta / gana),
  `notice.price_regulated`, `notice.fined`, `notice.tax_set`.

## Consultas para la UI
`Offices.chart(sim) -> [{office, rank, seats: [{holder, name, family, family_name, until, years_left, vacant}],
salary, term_years, min_title, election: {} | {id, day, campaign_day, candidates}}]` (orden del organigrama);
`Offices.of_character(sim, chr) -> office_id | ""`; `Offices.holders(sim, office)`; `Offices.powers(sim, actor) ->
[{power, office, ready, cooldown_minutes, reason}]`; `Elections.run_status(sim, actor, office, level) -> ""|motivo`;
`Elections.campaign_of(sim, actor) -> {} | {election, office, days_left, candidates}`; `Elections.last_result(sim,
office)`; `Elections.action_status(sim, actor, kind, target)`; `Market.regulation(sim, item)`.

## Escenarios (`tools/scenarios/make_office_scenarios.gd`, desde una partida nueva Normal, semilla 1)
- **`office_campaign`**: día 4 (el 5.º, otoño del año 1), 10:00. Herrero es Ciudadano con 300 de oro, sin deuda; Hugo en el
  Ayuntamiento. El Inspector y el Recaudador están vacantes: se puede presentar (organigrama).
- **`office_election_eve`**: día 7 (el 8.º, invierno), 23:30. Hugo (nivel medio) y Bernat (el rival) se presentan a Inspector;
  la votación cae a medianoche (tarjeta con el recuento).
- **`office_inspector`**: día 9 (el 10.º), 10:00. Hugo es Inspector desde el cambio de año (día 8, hasta el 16): puede
  regular un precio
  (panel de cargos, sección Poderes).

## Bots y dianas
- `politician` (`BotArtisanExpert` con `runs_office = 1`, partida nueva Normal): juega como `artisan_expert`; ya
  Ciudadano, se presenta al primer cargo menor abierto (Inspector, luego Recaudador) con el mejor nivel que paga
  guardando su reserva; de Inspector, regula +10 % el precio del producto que más vende cuando el poder está listo.
  Diana `politician` (40 días, 10 semillas): gana un cargo menor en ≥ 80 % de las semillas.
- `idle_titles` (H9) añade `ai_office_runs >= 1`: la IA rival se presenta al menos una vez en 10 años.
- `artisan_expert` / `expert_titles` / `artisan_novice` no se presentan (`runs_office = 0`): sus dianas no se mueven
  por conducta; sí podrían por el gobierno (ver decisiones).
- Medidas nuevas en `tools/sim_runner.gd`: `office_won` (0/1), `office_won_day`, `elections_run`, `elections_won`
  (de la familia del jugador), `ai_office_runs`, `ai_offices_won`.

## Vista
- **Organigrama** (`game/ui/offices_panel.*`; botón Cargos del HUD, tecla O, o «Cargos y elecciones» en el panel del
  Ayuntamiento): Alcalde arriba, Concejales, Juez, Alguacil, Recaudador, Inspector. Cada fila: cargo (color por rango;
  su tooltip: título, salario y mandato), titular o «VACANTE», familia y día en que acaba; debajo, la elección abierta
  (día, campaña y candidatos); botón «Presentarse» con el nivel de campaña elegido arriba (apagado con el motivo).
- **Campaña**: en el mismo panel, mientras la persona elegida es candidata: cargo, día de la votación, días que quedan,
  rivales y el discurso público. Visitar, sobornar y difamar están en la **ficha del vecino** (`npc_panel`, en dorado,
  junto a las acciones de H7); lejos, camina primero.
- **Resultado** (`game/ui/office_card.*`): al `election_held` con un candidato humano o la familia humana votada:
  cargo, recuento por candidato con barras, ganador; se cierra con un clic o a los 10 s.
- **Cargo** en la ficha del personaje y del vecino («Inspector de mercado hasta el día 17») y en el árbol.
- **Poderes**: sección del mismo panel con los del cargo de la persona elegida y su enfriamiento: regular precio (objeto
  y ±10 %), multar (familia con negocio), impuesto (5-15 %); los de H11 y EA salen apagados con su hito.
- Ayuda (F1): sección «Cargos y elecciones» (`help.offices*`).
- Capturas: `--smoke-script=cargos` → `h10_organigrama`, `h10_campana`, `h10_resultado`, `h10_poderes`.

## Decisiones provisionales
- **Títulos de las familias de hogar** en datos (`government.household_titles`): una Patricia, cuatro Ciudadanas, tres
  comunes. Nadie del pueblo es Barón: **Alcalde y Concejales empiezan vacantes** y la ceremonia de títulos sigue
  aprobándose sola (como en H9) hasta que alguien los ocupe.
- **Inspector y Recaudador empiezan vacantes** (GDD: 1-2 cargos menores libres). Sin Recaudador no hay impuestos.
- **«Afinidad» del voto = la relación de H7** (−100..100) entre votante y candidato; la ceremonia de títulos sigue
  leyendo la afinidad de cortejo (H9, sin cambios).
- **Los NPC con cargo no se presentan contra nadie**: el titular saliente entra solo en la elección de su asiento
  (nivel básico) y gana si no hay otro candidato. Un vacante sin candidatos sigue vacante.
- **Inscripción por el organigrama** (orden de gestión, sin ir al Ayuntamiento); la campaña, en persona.
- **Visita**: +5 de relación con cada adulto de la familia visitada y 4 h sin otra acción de campaña (no bloquea
  caminar ni trabajar).
- **Impuestos** al amanecer sobre las ventas (mercado y mostrador) del día anterior de cada familia; la comisión del
  Recaudador sale de lo recaudado.
- **Regulación**: ±10 % al precio de compra y venta del mercado (y, por él, al del mostrador) durante 2 días;
  enfriamiento de 1 estación. **Multa** del Inspector: 20 de oro a una familia con negocio, enfriamiento de 1 estación.
  **Impuesto**: enfriamiento de 1 estación.
- **Reputación al ocupar un cargo** y **pasiva del Alcalde** (+1/día): cifras en datos [balance].
- **Poderes de H11 y EA** en datos con `ready` = su hito: el panel los enseña apagados.
- **El Alcalde o Concejal que pide su propio título se aprueba a sí mismo** (la afinidad consigo mismo no existe).
- **Sin módulo de azar nuevo**: la votación no tira dados (empates por reputación e id); las tiradas de campaña
  (soborno, discurso, difamación) usan `SkillCheck` con la corriente de la ciudad (`Kin.roll`, semilla del mundo), no
  `state.rng`, para no mover las tiradas de la economía (como H7).
- **IA rival**: regla mínima en datos (`office_rule`), no los módulos de 04c.
- **Quién vota**: los vecinos adultos de familias no humanas con título ≥ Ciudadano (también el rival si no es
  candidato); la familia del jugador no vota y los candidatos tampoco.
- **Pasivos de clase** (Inspector +10 % artesanos, Juez +20 % eruditos): multiplican la reputación de la familia con esa
  clase cuando se lee (voto y consultas), no cada cambio (con +1 el redondeo se lo comería).
- **Salarios**: también a los titulares de hogares (los NPC con cargo «cobran», 4.12.3).
- **Bot `politician`** = `artisan_expert` con `runs_office = 1` (el 07 lo pedía aparte; así sus dianas de H5/H9 no
  cambian y el político solo añade la política).
