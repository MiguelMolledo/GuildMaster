# Contrato H3 · mercado, dinero e inicio de partida

Lo que comparten los subgrims de H3 («mercado», «cuentas», «rival», «vista»). Quien cambie un nombre lo cambia aquí.
Base: `docs/contratos/h1_mundo.md`, `docs/contratos/h2_forja.md`. GDD: 4.5 (mercado, rival, encargos, recado), 4.16
(inicio y deuda), 4.17 (ruina), 4.18 (libro y avisos), 4.19 (fuentes y sumideros), 4.23 (dificultad), 06, D5, D12,
D15, D18.

## Zonas (ficheros de cada uno)
| Subgrim | Ficheros | Pruebas |
|---|---|---|
| mercado | `sim/econ/market.gd`, reglas de entrar/salir de la tienda pública en `sim/world/buildings.gd` | `tests/test_econ_market*.gd` |
| cuentas | `sim/econ/ledger.gd`, `notices.gd` (salvo `add`), `loans.gd`, `upkeep.gd`, `sim/meta/objectives.gd`, `NewGame.from_start` en `sim/meta/new_game.gd` | `tests/test_econ_ledger*.gd`, `test_econ_loans*.gd`, `test_meta_*.gd` |
| rival | `sim/econ/contracts.gd`, `sim/ai/rival_ai.gd` | `tests/test_econ_contracts*.gd`, `test_ai_rival*.gd` |
| vista | `game/` (paneles, HUD, pantalla de partida nueva y de final), `game/sim_query.gd`, `data/view.json` | `tests/test_game_*.gd` |

Comunes (solo se tocan si el contrato lo dice, y se avisa): `sim/econ/money.gd`, `sim/core/*`, `sim/meta/save_file.gd`,
`data/` de esta base, `tools/maps/make_town_e.py`. `i18n/strings.csv`: cada uno **añade sus claves al final**, sin
reordenar ni tocar las de otros. Datos nuevos que necesite un sistema: en su fichero de `data/`, con validación en
`tools/validate_content.py`.

## Estado (guardado v4, ya existe)
- **Familia** `families[fam]`: `gold: int` (**la bolsa de la familia**; los personajes ya no tienen `gold`),
  `reputation: int` (0), `ai_profile: "" | id de data/ai_profiles/`, `ai_state: {}` (memoria libre de la IA; la usa «rival»).
- **Edificio** `buildings[b]`: además, `upkeep_debt: int` (mantenimiento impagado, D15) y `upkeep_unpaid_since: int`
  (día del primer impago, −1 = al día). Tipo nuevo `armory` (público, `owner: ""`).
- `ledger: {entries: [asiento], summaries: {}}` — asiento `{day, minute, family, building, actor, category, amount, ref}`
  (`minute` absoluto del reloj; `day = Clock.day(minute)`; `building`/`actor` `""` si no aplica). `summaries` (forma de
  «cuentas»; propuesta `{fam: {año: {categoría: {edificio_o_"": int}}}}`).
- `notices: [aviso]` — `{id: "ntc_0001", day, minute, family, severity: "info"|"warning"|"urgent", target: bld|chr|"",
  key, params: {}, read: bool}`.
- `loans: {lon_id: préstamo}` — forma mínima: `{id, family, lender, principal, outstanding, due_minute, extended: bool,
  state: "active"|"extended"|"paid"|"seized"}` («cuentas» añade lo que necesite).
- `contracts: {board: [encargo], accepted: [encargo], cooldowns: {cliente: hasta_día}, relations: {"fam|cliente": int}}`
  — encargo (propuesta para «rival»): `{id: "ctr_0001", client, item, qty, min_quality, deadline_days, pay, posted,
  script: ""|id, family: "", actor: "", accepted: −1, due: −1}`. Los cerrados salen de las listas.
- `deliveries: [recado]` — `{id: "dlv_0001", family, actor, stall, to: bld, item, quality, qty, arrive: minuto}` («mercado»).
- `difficulty: "easy"|"normal"|"hard"`, `objectives: {fam: progreso}` (forma de «cuentas»), `ending: {}` (o
  `{kind: "ruin", family, minute}` cuando termina la partida).
- Ids nuevos (`Ids.next`): `ntc`, `lon`, `ctr`, `dlv`.
- **Regla:** dentro de los diccionarios de cada uno (préstamo, encargo, recado, progreso, `ai_state`) el dueño puede
  añadir campos sin subir versión (solo los crean partidas v4), siempre JSON y con su prueba de ida y vuelta. Un campo
  nuevo en personaje, familia o edificio, o en la raíz del estado, sí es un cambio de formato: se pide al manager.

**Escenario `town_e_start`** (arenero, sin préstamo): `fam_0001` Herrero 100 de oro (Hugo, Elena, Tomás, forja
`bld_0001`), `fam_0002` Vidal 50, `fam_0003` **Ferrer** (IA, perfil `rival_smith`) 80 con **Bernat** `chr_0006`
(Artesanía 5) **dentro** de su forja `bld_0002` (hierro ×8, carbón ×4), la **Armería** `bld_0003` (`owner: ""`).
`empty_town` también en v4. Una partida v3 migra: el oro de los personajes se suma en su familia.

## Mapa `town_e` (lo genera `tools/maps/make_town_e.py`)
- Casillas nuevas en `data/tiles.json`: `stall` (`S`) y `board` (`N`), bloqueadas.
- `stalls: {resources|food|materials: {tile, service}}` en la fila 14 de la plaza (cols 16, 19, 22), servicio en la fila 15.
- `board: {tile: [16,22], service: [16,21]}` (tablón de encargos).
- `buildings` (edificios iniciales para la partida nueva): `player_forge` (25,20; puerta 26,19), `rival_forge`
  (9,20; puerta 10,19), `armory` (25,14, 3×4, puerta (24,16) en la plaza, `owner: ""`).
- «Estar en el puesto» = `position == service` y sin ruta. «Estar en la Armería» = `location == bld` de tipo `armory`.

## Datos (cargados en `Catalog`)
- `data/market.json` → `Catalog.market`: `stalls {id: {name_key, kind: outdoor|shop, sells: [market_stall], building?}}`,
  `open_phases ["day","dusk"]`, `demand {start 1, rest 1, min 0,5, max 2, drop_per_unit 0,05, recover_per_day 0,1}`,
  `sell_ratio 0,7`, `quality_mult [1, 1,3, 1,6]`, `errand {surcharge 0,2, hours 2}`,
  `board {max_open 3, new_per_dawn 1, max_accepted_per_family 2, warn_hours [24, 2]}`.
- `data/difficulty.json` → `Catalog.difficulty`, `catalog.difficulty_levels(nivel)`: `start_debt` 100/200/300,
  `rival_craft` 4/5/6, `rival_sell_min_demand` 0,9/0,8/0,7, `buy_price_mult` 0,9/1/1,1.
- `data/ai_profiles/rival_smith.json` → `catalog.ai_profiles()`: `sell_min_demand`, `gold_reserve 20`, `work_mode`,
  `work_phases ["day"]`, `decide_on ["dawn","phase_change"]`, `buy_days 1`, `accepts_contracts` (los pesos son de H6).
- `data/starts/artisan_blacksmith.json` → `catalog.starts()`: ver su `_doc` (edad 20, oro 30, `building.site`
  `player_forge` con hierro ×8 y carbón ×4, martillo equipado, stats del Artesano + 5 puntos libres, préstamo con
  `term_days 8`, prórroga `extension_seasons 1` con `extension_surcharge 0,25` y `overdue_reputation −10`, 2 encargos
  guionizados, la cadena de 6 objetivos, el rival).
- `data/objectives/*.json` → `catalog.objectives()`: `conditions: [{event, match, count}]` (todas). Cuenta los eventos
  `event` de la familia (campo `family` del evento, o la familia de su `actor`) cuyos campos casan con `match`
  (valor = igualdad; `{"gte"|"lte"|"ne": v}` compara); `count` eventos. Solo cuenta el objetivo actual de la cadena.
- `data/contracts/blacksmith.json` → `catalog.contracts()`: clientes, objetos con `qty [mín, máx]` y
  `min_quality_chance`, `min_qualities`, `deadline_days`, `premium 0,4`, recompensas y castigos, `client_cooldown_days 8`.
- `data/buildings/armory.json`: `public: true`, `market_stall: "armory"`, zona `counter`, `interior`, `upkeep 0`.
- Plantillas: `data/_templates/_objective.json`, `_contracts.json`, `_ai_profile.json`.

## Dinero (`Money`, ya hecho; nadie toca `gold` a mano)
- `Money.gold(state, fam) -> int`, `Money.family_of(state, entidad) -> fam|""` (familia, personaje o edificio),
  `Money.can_pay(state, fam, amount)`.
- `Money.change(sim, fam, amount, category, ref, building := "", actor := "", allow_negative := false) -> bool`:
  rechaza (sin cambiar nada) familia desconocida, categoría desconocida o quedar en negativo sin `allow_negative`.
  Apunta el asiento y emite `gold_changed {family, amount, category, gold}`. 0 = no hace nada.
- Categorías (constantes `Money.*`, 4.19): `market_sales`, `contracts`, `loans`, `counter_sales`, `events`, `property`,
  `offices`, `services`, `loot`, `purchases`, `errands`, `upkeep`, `wages`, `upgrades`, `fines`, `titles`, `politics`,
  `taxes`, `justice`, `family`, `donations`.
- Usos de H3: compra = `purchases` (precio × cantidad); recado = **dos asientos**, `purchases` y `errands` (el
  sobrecoste); venta = `market_sales`; encargo cobrado = `contracts`; pago de deuda y embargo del oro = `loans` (−);
  mantenimiento = `upkeep`. La deuda inicial **no** apunta un `+` (el préstamo pagó la forja: no entra oro).
- `buy_raw` (H2) ya paga por `Money` (`purchases`, ref `buy_raw`). Sigue vivo hasta que «mercado» decida retirarlo
  (si lo retira: `bot_smith` y sus pruebas pasan a `buy`).
- Conservación (criterio de H3): suma de asientos de cada familia = variación de su oro (`tests/test_core_money.gd`).

## Órdenes (por `Orders.apply`; enlazadas, devuelven `not_implemented` hasta que se hagan)
| Orden | Campos | Dueño | Regla |
|---|---|---|---|
| `buy` | actor, stall, item, quality, qty, deliver_to? | mercado | En el puesto (o dentro de la tienda), abierto, el objeto es de ese puesto (`sells` ∋ su `market_stall`). Sin `deliver_to`: entra en la bolsa del personaje (`too_heavy`). Con `deliver_to` (edificio propio): +20 %, llega en 2 h al almacén, el hueco se comprueba y se reserva al pedir (`storage_full`). Paga la familia (`not_enough_gold`). |
| `sell` | actor, stall, item, quality, qty | mercado | En el puesto, abierto, objeto del puesto, **nunca más de lo que lleva** el personaje (`not_enough`). Cobra `price(sell)` × qty; la demanda baja 0,05 por unidad. |
| `repay_loan` | actor, loan, amount | cuentas | Préstamo de su familia, abierto; paga `min(amount, pendiente)` (`not_enough_gold`). Desde cualquier sitio (libro de cuentas). |
| `read_notices` | actor, ids | cuentas | Marca leídos avisos de su familia. |
| `accept_contract` | actor, contract | rival | En el tablón; abierto; como mucho 2 aceptados por familia. El primero que acepta se lo queda. |
| `deliver_contract` | actor, contract | rival | En el tablón; aceptado por su familia; las piezas (calidad ≥ mínima) en la bolsa del personaje; las quita y cobra `pay`. No toca la demanda. |
| `abandon_contract` | actor, contract | rival | Aceptado por su familia: cuenta como incumplido. |

Motivos de rechazo: los elige cada dueño con su clave `reason.<id>` ES/EN (p. ej. `unknown_stall`, `not_at_stall`,
`market_closed`, `wrong_stall`, `bad_quality`, `not_enough_gold`, `not_enough`, `too_heavy`, `storage_full`,
`unknown_loan`, `not_your_loan`, `loan_closed`, `unknown_contract`, `not_at_board`, `contract_taken`,
`too_many_contracts`, `not_your_contract`, `missing_items`). `reason.not_implemented` ya existe.

## Paso del sim (`Sim.step`, orden fijo)
1. Órdenes de fuera (UI, bots), grabadas si `record`.
2. **`RivalAI.orders(sim)`**: las órdenes de las familias IA con `ai_profile`, por el mismo camino (`_give`: con
   `queued` van a la cola del actor). No se graban: salen del estado y una repetición las vuelve a dar. Ven el reloj
   **antes** del tic de este minuto; para «al amanecer y en cada cambio de fase» comparad `Clock.phase(ahora)` con lo
   guardado en `ai_state`.
3. `Clock.tick` → `OrderQueue` → `Movement` → `Buildings` → `Production` (H1-H2).
4. **`Market.step`** (recados que llegan; demanda +0,1 al amanecer hacia `rest`) → **`Contracts.step`** (1 encargo
   nuevo al amanecer si hay hueco; avisos a 24 h y 2 h; vencimientos) → **`Upkeep.step`** (al amanecer) →
   **`Loans.step`** (avisos 2 días y 1 día antes; vencimiento → prórroga; fin de prórroga → embargo y ruina) →
   **`Objectives.step`** (lee `sim.events` de este paso: va detrás de todo lo que emite) → **`Ledger.step`** →
   **`Notices.step`** (retenciones).
- «Al amanecer» = en este paso hay un evento `phase_changed` con `phase == "dawn"` (o `day_started`, según convenga;
  decidid uno y decidlo aquí).

## Reglas ya fijadas en la base
- **Tienda pública**: `Buildings.is_public(sim, b)` (sin dueño y tipo `public: true`); `can_enter` la deja a
  cualquiera. Horario al entrar/echar al cerrar: «mercado». Dentro de la Armería no se ocupa el puesto `counter` para
  comprar o vender (basta `location`).
- **El rival trabaja**: `Production.may_work` deja trabajar a un personaje `controlled_by: "ai"` de una familia con
  `ai_profile` en su edificio, salvo `night_rest` de noche (forja `manual_only`).
- **Precio (hecho en la base, puro)**: `Market.price(sim, item, quality, side)`:
  `buy = round(base × quality_mult × demanda × buy_price_mult)`, `sell = round(base × quality_mult × demanda × 0,70)`
  (la dificultad solo toca la compra). `Market.demand(sim, item)` (sin tocar = `demand.start`), `Market.is_open(sim)`.
  En H3 el mercado vende solo calidad normal (`bad_quality`) — **provisional**, «mercado» puede cambiarlo.
- `Notices.add(sim, fam, severity, key, params := {}, target := "") -> id` (hecho): cualquiera avisa con él.
- Reputación: `families[fam].reputation` se cambia a mano (no es oro) y se emite `reputation_changed {family, amount,
  reason}`.

## Eventos (para la vista y los objetivos)
- Base: `gold_changed {family, amount, category, gold}`, `notice_added {id, family, severity, key, params, target}`.
- mercado: `market_bought {actor, family, stall, item, quality, qty, cost}`, `market_sold {actor, family, stall, item,
  quality, qty, price, total}`, `errand_sent {actor, family, delivery, stall, item, quality, qty, to, cost, surcharge,
  arrive}`, `errand_arrived {delivery, family, to, item, quality, qty}`, `demand_changed {item, demand}`.
- cuentas: `loan_payment {actor, family, loan, amount, outstanding}`, `loan_repaid {actor, family, loan, extended}`,
  `loan_extended {family, loan, outstanding}`, `loan_seized {family, loan, gold, items}`, `game_over {kind, family}`,
  `upkeep_charged {family, building, amount}`, `upkeep_unpaid {family, building, debt}`, `building_damaged {building}`,
  `objective_done {family, objective}`, `reputation_changed`.
- rival: `contract_posted {contract}`, `contract_accepted {actor, family, contract}`, `contract_delivered {actor,
  family, contract, client, item, qty, min_quality, pay, script}`, `contract_failed {family, contract, reason:
  "expired"|"abandoned"}`, `reputation_changed`.
- Los objetivos de inicio escuchan: `work_done` (H2), `market_sold`, `contract_delivered`, `errand_sent`, `loan_repaid`.
  Si alguien cambia uno de estos nombres o campos, cambia también `data/objectives/`.

## Consultas para la UI (funciones puras; la vista no calcula reglas)
- `Market.is_open(sim)`, `Market.demand(sim, item)`, `Market.price(sim, item, quality, side)` (hechas);
  `Market.stall_at(sim, actor) -> stall|""`; `Market.offers(sim, actor, stall) -> {open, reason, buy: [{item, quality,
  price, max_qty, status}], sell: [{item, quality, qty, price}], deliver_to: [bld]}`.
- `Ledger.summary(sim, fam, scope)`: `"today"` → `{income, expense, net, by_category {cat: int}}`; `"days"` →
  `[{day, income, expense, net}]` (últimos 8); `"buildings"` → `{bld_o_"": {cat: int}}`. `Ledger.entries(sim, fam,
  from_day, to_day)`.
- `Notices.list(sim, fam, unread_only := false)` (más nuevo primero).
- `Loans.status(sim, loan) -> {id, family, lender, principal, outstanding, due_minute, extended, state, days_left}`,
  `Loans.of_family(sim, fam) -> [loan_id]`.
- `Contracts.board_view(sim, actor) -> {at_board, open: [encargo + status], accepted: [encargo + status, hours_left]}`.
- `Objectives.view(sim, fam) -> {current, done, progress: [{have, need}]}`.
- `NewGame.from_start(catalog, start_id, difficulty, choices, seed) -> {ok, state | error}` con
  `choices = {name, female, family_name, colors {primary, secondary}, stats_add {stat: puntos}}` (suma ≤ `free_points`,
  cada stat en `[stat_min, stat_max]`; si no, `{"ok": false, "error": "bad_choices"}`).
- La vista lee el oro con `Money.gold(state, familia_del_seleccionado)` (HUD y paneles ya lo hacen).

## Decisiones provisionales del manager
- **D15 = (b)**: el mantenimiento impagado se acumula en `upkeep_debt` (deuda con la ciudad), se cobra en cuanto hay
  oro y a los **3 días** impagado el edificio pasa a `state: "damaged"` (Producción ya rechaza con
  `building_not_ready`). Propuesta de la base: al saldar la deuda vuelve a `"normal"` (no hay coste de reparación
  hasta H5); «cuentas» lo confirma o lo cambia aquí.
- **D16**: no aplica aún (mostrador en H7).
- **D18 = sí**: la ruina termina la partida (`state.ending`, evento `game_over`, pantalla de final de «vista»). El sim
  no se para solo: la vista pausa.
- **D5 = 5** puntos libres (`free_points` del inicio).

## Decisiones provisionales de la base
- Los clientes de los encargos son datos (`data/contracts/<profesión>.json clients`), no personajes: la relación con
  ellos vive en `contracts.relations` hasta que haya NPC de verdad (H7). El enfriamiento de 1 año es por cliente.
- El tablón y los puestos son casillas bloqueadas con casilla de servicio (no edificios).
- La Armería: `parcel_type: "government"` (es de la ciudad), `upkeep 0`, almacén de 0 pilas (stock ilimitado, 4.5.2).
- Bernat, en el arenero, tiene las stats del Artesano con Artesanía 5 (la de Normal) y 80 de oro (4.5.5).
- El préstamo vence al final del día `start.day + term_days − 1`: `due_minute = (start.day + term_days) × 1440`.
