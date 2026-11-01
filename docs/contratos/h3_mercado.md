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

## Mercado (hecho por «mercado»)
- **«Al amanecer»** para el mercado = evento `phase_changed` con `phase == "dawn"` en este paso: la demanda de cada
  objeto tocado se mueve `recover_per_day` hacia `rest` (desde arriba también baja), siempre en `[min, max]`.
- **Venta**: `price(sell)` con la demanda de antes de la venta × `qty`, y luego la demanda baja `drop_per_unit × qty`
  (una venta de 10 cobra las 10 al primer precio: **provisional**, tal como dice la tabla de órdenes). Cualquier
  calidad se vende; solo se compra calidad normal (`bad_quality`, provisional de la base).
- **Recado**: sobrecoste `round(coste × errand.surcharge)`; dos asientos con `ref` = id del recado y `building` = destino
  (`purchases` y `errands`). Solo emite `errand_sent` (no `market_bought`). Destino válido: edificio propio (del
  personaje o de su familia) con almacén (`unknown_building`, `not_your_building`, `no_inventory`). El hueco se
  reserva **entre recados**: al pedir se cuenta lo que ya va de camino a ese almacén (`storage_full`). Producción y
  traspasos no ven la reserva: si el almacén se llena antes de que llegue, el recado **espera en la puerta** y lo
  reintenta cada minuto (evento `errand_blocked {delivery, family, to, item, quality, qty}` una vez; campo
  `blocked: true` en el recado). Si el edificio ya no existe, el recado se pierde (no pasa en H3).
- **Horario de la Armería**: `Buildings.can_enter` rechaza entrar en una tienda pública con el mercado cerrado
  (`market_closed`; `Market.shop_closed(sim, bld)`). Al cerrar (cambio de fase a una cerrada) `Market.step` saca a la
  puerta a quien siga dentro (como `exit_building`; eventos `building_left` y `shop_closed_out {actor, building}`).
- **Motivos** de `buy`/`sell`: `unknown_actor`, `dead`, `unknown_stall`, `not_at_stall`, `market_closed`,
  `unknown_item`, `wrong_stall`, `bad_quality`, `bad_quantity`, `not_enough` (venta), `no_family`, `too_heavy`,
  `not_enough_gold`, y con `deliver_to` `unknown_building`, `not_your_building`, `no_inventory`, `storage_full`.
- **Consultas extra**: `Market.max_buy(sim, actor, stall, item, quality, to := "") -> int` (oro, peso o almacén con la
  reserva y el sobrecoste), `errand_surcharge(sim, coste)`, `errand_minutes(sim)`, `own_storages(sim, actor)`,
  `pending(sim, fam) -> [recado]`, `shop_closed(sim, bld)`. En `offers`, `reason` = "" si puede comerciar ahí ahora;
  las listas se rellenan igualmente (con `max_qty` 0 y `status` = el motivo); `status` de compra: `ok`,
  `not_enough_gold`, `too_heavy` o el motivo del sitio/horario.
- **`buy_raw` retirada** (orden y enlace). `Production.raw_cost` sigue solo para que compile la vista hasta que su panel
  de almacén pase a `Market`. `bot_smith` compra por recado en el puesto `resources`.

## Cuentas (hecho por «cuentas»)
- **«Al amanecer»** = evento `phase_changed` con `phase == "dawn"` en este paso (`Ledger.is_dawn(sim)`). Upkeep, retención
  del libro y de los avisos van ahí. Una partida nueva empieza ya en el amanecer del día 0: el primer mantenimiento es
  el del día 1.
- Cifras de cuentas en **`data/accounts.json`** → `Catalog.accounts`: `ledger_detail_years 2`, `ledger_days_view 8`,
  `notices_keep_years 1`, `loan_warn_days [2, 1]`, `upkeep_damage_days 3`.
- **Libro**: `Ledger.summary(sim, fam, scope) -> Variant`. `"today"` → `{income (≥0), expense (≤0), net = income +
  expense, by_category}`; `"days"` → **Array** `[{day, income, expense, net}]` (últimos 8 hasta hoy, el más viejo
  primero, sin días < 0); `"buildings"` → `{bld_o_"": {cat: neto}}` (asientos en detalle); **`"debts"`** → `{loans:
  [Loans.status], contracts: [encargo aceptado de la familia + hours_left (−1 sin due)], upkeep: [{building, debt,
  unpaid_since, days_unpaid}]}`. `Ledger.total(state, fam)` = asientos + resúmenes (conservación).
  `summaries = {fam: {"año": {categoría: {edificio_o_"": int}}}}` (año como texto, `Clock.year` del asiento).
- **Avisos**: `read_notices` rechaza (`unknown_notice`, sin cambiar nada) si algún id no es un aviso de su familia;
  `ids: []` vale. Evento `notices_read {family, ids}`. `Notices.unread_count(sim, fam)`. Claves `notice.*` de cuentas
  (params con `{nombre}` para `String.format`): `loan_due_soon {loan, days, amount}`, `loan_extension_due_soon` (igual),
  `loan_extended {loan, amount, days, reputation}`, `loan_repaid {loan, lender}`, `loan_seized {loan, gold, items}`,
  `ruin {loan, missing}`, `upkeep_unpaid {building, debt, days}`, `building_damaged {building, debt}`,
  `upkeep_settled {building, amount}`, `objective_done {objective, name_key}`.
- **Préstamo** (campos añadidos): `building` (la forja que embarga), `overdue_reputation`, `extension_seasons`,
  `extension_surcharge`, `warned: [días ya avisados del vencimiento actual]`. `Loans.create(state, fam, términos,
  principal, due_minute, building)`. Motivos de `repay_loan`: `unknown_actor`, `unknown_loan`, `not_your_loan`,
  `loan_closed`, `bad_amount` (≤ 0), `not_enough_gold`. Avisos urgentes al cruzar 2 y 1 días (si se cruzan los dos a la
  vez, solo el más urgente); al vencer: reputación + `overdue_reputation` (`reputation_changed reason "loan_overdue"`),
  `outstanding = round(outstanding × 1,25)`, `due_minute += 1 estación` y estado `extended` (la prórroga se vuelve a
  avisar a 2 y 1 días). Al vencer la prórroga: oro (asiento `loans`), luego mercancía del almacén de `building` en su
  orden, por unidades enteras a `Market.price(sell)` (la última unidad puede pasarse: **no se devuelve cambio**,
  provisional); la mercancía no apunta asiento (no es oro). Estado `seized` en los dos casos. Si no alcanza: aviso
  `ruin`, `state.ending = {kind: "ruin", family, minute, loan}` y `game_over` (una vez). La forja **no** cambia de dueño
  (la partida termina; provisional). `loan_repaid.extended` = si se pagó ya en prórroga (el objetivo pide `false`).
- **D15 confirmado** (b, 3 días): al amanecer se cobra `upkeep_debt + upkeep` hasta donde llegue el oro; lo que falta
  queda en `upkeep_debt` (`upkeep_unpaid_since` = primer día impagado; aviso `warning` cada amanecer impagado).
  Cualquier paso con un `gold_changed` positivo de la familia cobra la deuda al momento. A los 3 días (`día −
  unpaid_since ≥ 3`) pasa a `damaged` (aviso urgente, `building_damaged`). Al saldar: `upkeep_unpaid_since = −1`,
  `damaged` → `normal` (evento `building_repaired {building}`; sin coste de reparación hasta H5) y aviso `upkeep_settled`.
- **Objetivos**: `objectives[fam] = {chain: [obj], index, done: [obj], have: [int por condición del actual]}`.
  `Objectives.start(state, catalog, fam, chain)`. Tipos: número con número compara como número; `bool` solo con `bool`.
- **`NewGame.from_start`**: ids `fam_0001`/`chr_0001`/`bld_0001` el jugador; luego el rival (`fam_0002`, `chr_0002`,
  `bld_0002`); luego las tiendas públicas del mapa por nombre de sitio (`bld_0003` Armería); `lon_0001`; `ctr_0001-2`.
  Las elecciones que falten salen de `defaults` del inicio (`data/starts/<id>.json`, añadido: nombre, género, apellido y
  colores). El estado sale ya normalizado como uno cargado (`WorldState.from_dict(to_dict())`). Sin campos de edad ni
  título en el personaje (cambio de formato: cuando haga falta, H8). Errores: `unknown_start`, `unknown_difficulty`,
  `unknown_map`, `bad_choices`. Encargos guionizados directamente en `contracts.board` con la forma propuesta y
  `pay = round(qty × price(sell, min_quality) × (1 + premium))`.
- **Escenarios** `debt_due` y `debt_extension_due`: los genera `tools/scenarios/make_debt_scenarios.gd` (partida nueva
  Normal, semilla 1, sin pagar; 1 hora antes de cada vencimiento). Volver a generarlos si cambian el inicio o el sim.
- **Bot `random_clicker`** (`sim/bots/bot_random_clicker.gd`, en `tools/sim_runner.gd`): órdenes al azar válidas e
  inválidas de todos los tipos. `sim_runner` mide `ledger_mismatch` (familias cuyo libro no cuadra con su oro) en
  todos los bots; diana de `random_clicker`: 0.

## Decisiones de «rival» (encargos y herrero rival)
- **«Al amanecer»** para los encargos = evento `phase_changed` con `phase == "dawn"` en este paso. Orden de
  `Contracts.step`: vencimientos → avisos → (al amanecer) 1 encargo nuevo si hay hueco.
- **Encargo**: la forma de arriba más `warned: [horas ya avisadas]`; `posted` es el **minuto** absoluto (from_start pone
  el día: no lo lee ninguna regla). `due = accepted + deadline_days × 1440`. Vence cuando `ahora >= due`.
  `Contracts.post(sim, {client, item, qty, min_quality, deadline_days, script?})` publica fijando el pago;
  `Contracts.post_scripted(state, catalog, defs)` sirve para los guionizados de `from_start`.
- **Avisos**: `notice.contract_due` (`warning` a 24 h, `urgent` a 2 h; params `contract, client, item, qty, hours`),
  solo si al aceptar quedaba más tiempo que eso; `notice.contract_expired` al vencer (params `client, item, qty,
  reputation, days`). Abandonar no avisa (lo hace el jugador).
- **Incumplir**: el enfriamiento del cliente es global (`cooldowns[client] = día + client_cooldown_days`); los
  encargos del tablón sin aceptar no caducan (provisional: el GDD no lo define).
- **Entregar** quita primero las piezas válidas de menor calidad. Motivos: `unknown_contract`, `not_at_board`,
  `contract_taken`, `too_many_contracts`, `not_your_contract`, `missing_items`, `no_family`.
- **Rival** (`sim/ai/rival_ai.gd`): plan por fase en `ai_state {phase, plan, recipe, bought_day, last_order,
  last_fp}`; además de las órdenes de 4.5.5 usa `transfer` (llevar al saco lo que vende o entrega y guardar lo que
  compra: la venta exige llevarlo encima). Comprueba antes con `Market.offers` / `Production.recipe_options` y no
  empieza un viaje a la Armería si no llega antes del cierre. Perfil: `max_contracts 1` («acepta uno»),
  `accepts_scripted_contracts false` (los guionizados de inicio son para el jugador); no acepta un encargo si no puede
  pagar sus entradas dejando la reserva. Receta: mayor margen > 0 a calidad normal; si le falta una entrada que otra
  receta suya hace con su almacén (lingotes con su hierro), hace esa primero. Compra las entradas directas.
- **sim_runner**: mide `rival_sold` y `rival_gold_day10`; bot `idle_rival` (= idle) con la diana del rival:
  `--bots=idle_rival --days=10`.

## Vista (hecho por «vista»)
- **Arranque**: sin `--scenario` (y sin `--smoke`, `--shots=` ni `--smoke-script=`) el juego abre la **pantalla de
  partida nueva** sobre el escenario por defecto en pausa; `--new-game` la fuerza. `Game.parse_args` da `new_game`.
  Con `--scenario` o en smoke se entra directo: `boot_check` y el smoke de siempre no cambian (la variante sin
  opciones de `boot_check` arranca ahora en esa pantalla, sin errores). La semilla: `--seed` o una al azar.
- **Puestos y tablón**: clic derecho con alguien elegido → `move_to` a la casilla de servicio; el HUD abre el panel
  cuando el personaje está en ella (`SimQuery.stands_on`); otra orden del mismo personaje lo olvida. Se cierra solo
  si deja de estar (`Market.stall_at` / `Contracts.board_view.at_board`).
- **Armería**: interior del kit con solo «Salir»; clic (izq. o der.) en el mostrador → panel de mercado del puesto
  `market_stall` del edificio. Gestionar (botón o doble clic) solo en edificios propios.
- **Carteles**: los edificios de otra familia llevan su nombre (`ui.building_of`: «Forja de Ferrer»).
- **Libro**: botón del HUD y tecla L; al mostrar la pestaña Avisos se da `read_notices` con los no leídos; quien
  firma las órdenes de familia (`repay_loan`, `read_notices`) es el elegido si es de la familia, si no el primer
  miembro vivo (`SimQuery.family_actor`). Clic en un aviso con `target` → centra la cámara (y elige a la persona si es
  tuya); sin `target` → abre el libro en Avisos. Solo los `urgent` de la familia del jugador saltan (8 s, máx. 3,
  `data/view.json notices`).
- **Ruina**: con `state.ending` no vacío la vista pausa y muestra la pantalla de final (Partida nueva / Salir).
- **Almacén**: sin compra de materia prima (`buy_raw` retirada).
