class_name Market
extends RefCounted
## The market square (GDD 4.5.1-4.5.3, 4.5.7): buying and selling at the stalls and the armory, demand per item,
## opening hours and errands (deliveries to an own building). Owner: subgrim «mercado».
## Contract: docs/contratos/h3_mercado.md. Figures in data/market.json (Catalog.market) and data/difficulty.json.
## Gold only moves through Money.change (purchases, errands, market_sales).
##
## Being at a stall: an outdoor stall = standing on its service tile (data/maps/<map>.json "stalls") without a route;
## a shop (the armory) = inside a building whose type is the stall's "building". The market is open in open_phases
## (day, dusk). A shop is entered only while open (Buildings.can_enter asks Market.shop_closed) and whoever is still
## inside when it closes is put out at its door (step).
##
## Demand (state.market.demand[item], float): every unit sold to the market by anybody drops it drop_per_unit; at dawn
## (the phase_changed event with phase "dawn") every touched item moves recover_per_day towards rest; always in
## [min, max]. Buying does not touch it, nor do contract deliveries.
##
## Errand (state.deliveries): a purchase sent to an own building. Costs the price plus round(price × surcharge),
## two ledger entries (purchases and errands). The room in the storage is checked at the order counting the other
## errands on their way to it (reserved); it arrives errand.hours later. If the storage was filled meanwhile by
## something else (production, a transfer), the delivery waits at the door and retries every minute.

const DAWN: String = "dawn"
const EPS: float = 0.0001


# --- Orders ----------------------------------------------------------------------------------------------------------

## {"type": "buy", "actor", "stall", "item", "quality", "qty", "deliver_to"?: bld_id}.
## Reasons: unknown_actor, dead, unknown_stall, not_at_stall, market_closed, unknown_item, wrong_stall, bad_quality,
## bad_quantity, no_family, unknown_building, not_your_building, no_inventory, storage_full, too_heavy, not_enough_gold.
static func order_buy(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var stall := str(o.get("stall", ""))
	var item := str(o.get("item", ""))
	var quality := int(o.get("quality", Inventory.NORMAL))
	var qty := int(o.get("qty", 0))
	var to := str(o.get("deliver_to", ""))
	var why := _trade_reason(sim, actor, stall, item)
	if why != "":
		return Orders.fail(why)
	if quality != Inventory.NORMAL:
		return Orders.fail("bad_quality")  # provisional (contract): the market only sells normal quality in H3
	if qty <= 0:
		return Orders.fail("bad_quantity")
	var fam := Money.family_of(st, actor)
	if fam == "" or not st.families.has(fam):
		return Orders.fail("no_family")
	var unit := trade_price(sim, actor, stall, item, quality, "buy")
	var cost := unit * qty
	if to != "":
		why = _errand_reason(sim, actor, to, item, quality, qty)
		if why != "":
			return Orders.fail(why)
		var surcharge := errand_surcharge(sim, cost, stall)
		if not Money.can_pay(st, fam, cost + surcharge):
			return Orders.fail("not_enough_gold")
		return _send_errand(sim, actor, fam, stall, to, item, quality, qty, cost, surcharge)
	if not Inventory.can_add(st.characters[actor]["inventory"], sim.catalog, item, quality, qty):
		return Orders.fail("too_heavy")  # a character's limit counts its equipment (Equipment)
	if not Money.can_pay(st, fam, cost):
		return Orders.fail("not_enough_gold")
	Money.change(sim, fam, -cost, Money.PURCHASES, "buy", "", actor)
	Inventory.add(st.characters[actor]["inventory"], sim.catalog, item, quality, qty)
	sim.events.append({"type": "market_bought", "actor": actor, "family": fam, "stall": stall, "item": item,
		"quality": quality, "qty": qty, "cost": cost})
	if OS.is_debug_build():
		print("[Market] %s compra %s x%d (q=%d) en %s por %d (unidad=%d, oro=%d)" % [actor, item, qty, quality, stall,
			cost, unit, Money.gold(st, fam)])
	return Orders.ok()


## {"type": "sell", "actor", "stall", "item", "quality", "qty"}. Never more than the actor carries (not_enough).
## Pays unit by unit: each unit at price(sell) with the demand left by the previous one, which then drops
## drop_per_unit × the item's demand_weight (H12, 04d 4.22.3.4: Catalog.demand_weight, 1 by default) (the same as
## selling them one at a time). market_sold.price = the first unit's, total = the sum.
## Reasons: unknown_actor, dead, unknown_stall, not_at_stall, market_closed, unknown_item, wrong_stall, bad_quality,
## bad_quantity, not_enough, no_family.
static func order_sell(sim: Sim, o: Dictionary) -> Dictionary:
	var st := sim.state
	var actor := str(o.get("actor", ""))
	var stall := str(o.get("stall", ""))
	var item := str(o.get("item", ""))
	var quality := int(o.get("quality", Inventory.NORMAL))
	var qty := int(o.get("qty", 0))
	var why := _trade_reason(sim, actor, stall, item)
	if why != "":
		return Orders.fail(why)
	if not quality in Inventory.QUALITIES:
		return Orders.fail("bad_quality")
	if qty <= 0:
		return Orders.fail("bad_quantity")
	var inv: Dictionary = st.characters[actor]["inventory"]
	if Inventory.count(inv, item, quality) < qty:
		return Orders.fail("not_enough")
	var fam := Money.family_of(st, actor)
	if fam == "" or not st.families.has(fam):
		return Orders.fail("no_family")
	# Unit by unit: each unit is paid at the demand left by the one before (selling 10 at once = 10 sales of 1).
	var unit := trade_price(sim, actor, stall, item, quality, "sell")
	var total := 0
	var drop := float(_demand_cfg(sim).get("drop_per_unit", 0.05)) * sim.catalog.demand_weight(item)
	for n: int in qty:
		total += trade_price(sim, actor, stall, item, quality, "sell")
		_set_demand(sim, item, demand(sim, item) - drop, false)
	Inventory.remove(inv, item, quality, qty)
	Money.change(sim, fam, total, Money.MARKET_SALES, "sell", "", actor)
	sim.events.append({"type": "market_sold", "actor": actor, "family": fam, "stall": stall, "item": item,
		"quality": quality, "qty": qty, "price": unit, "total": total})
	sim.events.append({"type": "demand_changed", "item": item, "demand": demand(sim, item)})
	if OS.is_debug_build():
		print("[Market] %s vende %s x%d (q=%d) en %s por %d (unidad=%d, demanda=%.2f, oro=%d)" % [actor, item, qty,
			quality, stall, total, unit, demand(sim, item), Money.gold(st, fam)])
	return Orders.ok()


# --- Step ------------------------------------------------------------------------------------------------------------

## Errands that arrive this minute; demand recovery at dawn; shops closing put out whoever is inside.
static func step(sim: Sim) -> void:
	_step_deliveries(sim)
	for e: Dictionary in sim.events:
		if str(e.get("type", "")) != "phase_changed":
			continue
		if str(e.get("phase", "")) == DAWN:
			_recover_demand(sim)
		if not is_open(sim):
			_close_shops(sim)


static func _step_deliveries(sim: Sim) -> void:
	var st := sim.state
	if st.deliveries.is_empty():
		return
	var now := int(st.clock["minute"])
	var keep: Array = []
	for d: Dictionary in st.deliveries:
		if int(d.get("arrive", 0)) > now:
			keep.append(d)
			continue
		var to := str(d.get("to", ""))
		if not st.buildings.has(to):
			if OS.is_debug_build():
				print("[Market] recado %s perdido: el edificio %s ya no existe" % [d.get("id", ""), to])
			continue
		var inv: Dictionary = st.buildings[to].get("inventory", {})
		var item := str(d["item"])
		var quality := int(d.get("quality", 0))
		var qty := int(d["qty"])
		if inv.is_empty() or not Inventory.add(inv, sim.catalog, item, quality, qty):
			if not bool(d.get("blocked", false)):
				d["blocked"] = true
				sim.events.append({"type": "errand_blocked", "delivery": str(d["id"]), "family": str(d["family"]),
					"to": to, "item": item, "quality": quality, "qty": qty})
				if OS.is_debug_build():
					print("[Market] recado %s espera en la puerta de %s: el almacén está lleno" % [d["id"], to])
			keep.append(d)
			continue
		sim.events.append({"type": "errand_arrived", "delivery": str(d["id"]), "family": str(d["family"]), "to": to,
			"item": item, "quality": quality, "qty": qty})
		if OS.is_debug_build():
			print("[Market] recado %s llega a %s: %s x%d (q=%d)" % [d["id"], to, item, qty, quality])
	st.deliveries = keep


static func _recover_demand(sim: Sim) -> void:
	var cfg := _demand_cfg(sim)
	var rest := float(cfg.get("rest", 1.0))
	var step_by := float(cfg.get("recover_per_day", 0.1))
	var d: Dictionary = sim.state.market.get("demand", {})
	for item: String in _sorted_keys(d):
		var now := float(d[item])
		var next := minf(now + step_by, rest) if now < rest else maxf(now - step_by, rest)
		if absf(next - now) > EPS:
			_set_demand(sim, item, next)
			if OS.is_debug_build():
				print("[Market] amanecer: demanda de %s %.2f -> %.2f" % [item, now, demand(sim, item)])


static func _close_shops(sim: Sim) -> void:
	var st := sim.state
	for id: String in _sorted_keys(st.characters):
		var loc := str(st.characters[id].get("location", ""))
		if loc != "" and shop_closed(sim, loc):
			Buildings.order_exit(sim, {"type": "exit_building", "actor": id})
			sim.events.append({"type": "shop_closed_out", "actor": id, "building": loc})
			if OS.is_debug_build():
				print("[Market] cierra %s: %s sale a la plaza" % [loc, id])


# --- Queries for the UI and the AI -----------------------------------------------------------------------------------

## Whether the market is open now (data/market.json open_phases). Done in the base (pure data).
static func is_open(sim: Sim) -> bool:
	var ph := Clock.phase(int(sim.state.clock["minute"]), sim.catalog.time)
	return ph in (sim.catalog.market.get("open_phases", []) as Array)


## The demand of `item` now (state.market.demand; data/market.json demand.start if nobody touched it yet).
static func demand(sim: Sim, item: String) -> float:
	var d: Dictionary = sim.state.market.get("demand", {})
	return float(d.get(item, sim.catalog.market.get("demand", {}).get("start", 1.0)))


## H13: the demand the price uses: demand() × the active events' demand effects, clamped to demand min / max.
static func effective_demand(sim: Sim, item: String) -> float:
	var d := demand(sim, item)
	var m := WorldEvents.demand_mult(sim, item)
	if m == 1.0:
		return d
	var cfg := _demand_cfg(sim)
	return clampf(d * m, float(cfg.get("min", 0.5)), float(cfg.get("max", 2.0)))


## Unit price of `item` at `quality` now (GDD 4.5.3, phase 1). Done in the base (pure data):
##   buy  = round(base_price × quality_mult[quality] × demand × buy_price_mult of the difficulty)
##   sell = round(base_price × quality_mult[quality] × demand × sell_ratio)   (the difficulty only touches buying)
## H13 (phase 2): demand × the events' demand effects (clamped to demand min/max), then × mod_estación × mod_evento
## (WorldEvents.price_mult); a multiplier of exactly 1 is not applied (the same figures as before H13).
## 0 for an unknown item or quality.
static func price(sim: Sim, item: String, quality: int, side: String) -> int:
	var def := sim.catalog.item(item)
	var qm: Array = sim.catalog.market.get("quality_mult", [])
	if def.is_empty() or quality < 0 or quality >= qm.size():
		return 0
	var p := float(def.get("base_price", 0)) * float(qm[quality]) * effective_demand(sim, item)
	var sm := WorldEvents.price_mult(sim, item)
	if sm != 1.0:
		p *= sm
	var reg := Offices.regulation(sim, item)  # H10: the market inspector's regulation (GDD 4.12.3)
	if reg != 0:
		p *= float(100 + reg) / 100.0
	if side == "buy":
		p *= float(sim.catalog.difficulty_levels(sim.state.difficulty).get("buy_price_mult", 1.0))
	else:
		p *= float(sim.catalog.market.get("sell_ratio", 0.7))
	return roundi(p)


## H7: the price `actor` pays (side "buy") or gets ("sell") at `stall`: price() × the emotions of the stall's keeper
## (the townsperson whose trade is that stall) towards the actor's family (GDD 4.11.5: angry +25 % / −25 %...).
## Without a keeper or emotions it is exactly price().
static func trade_price(sim: Sim, actor: String, stall: String, item: String, quality: int, side: String) -> int:
	var p := price(sim, item, quality, side)
	if side == "sell" and sim.state.characters.has(actor):  # H12 Patrón: the farm's Commerce branch (market_price)
		var fm := Fields.sale_mult(sim, Money.family_of(sim.state, actor), item)
		if fm != 1.0:
			p = roundi(float(p) * fm)
	var keeper := TownLife.stall_keeper(sim.state, sim.catalog, stall)
	if keeper == "" or not sim.state.characters.has(actor):
		return p
	var m := Emotions.price_mult(sim, keeper, Money.family_of(sim.state, actor), side)
	return p if m == 1.0 else roundi(float(p) * m)


## What selling `qty` of `item` at `quality` at `stall` would give now, unit by unit as order_sell pays it (each unit at
## the demand the one before left): {prices: [int], total, demand_after}. Read only: the state is put back as it was.
static func sell_preview(sim: Sim, actor: String, stall: String, item: String, quality: int, qty: int) -> Dictionary:
	var had_table := sim.state.market.has("demand")
	var table: Dictionary = sim.state.market.get("demand", {})
	var had := table.has(item)
	var before := float(table.get(item, 0.0))
	var drop := float(_demand_cfg(sim).get("drop_per_unit", 0.05)) * sim.catalog.demand_weight(item)
	var prices: Array = []
	var total := 0
	for n: int in maxi(0, qty):
		var p := trade_price(sim, actor, stall, item, quality, "sell")
		prices.append(p)
		total += p
		_set_demand(sim, item, demand(sim, item) - drop, false)
	var after := demand(sim, item)
	if not had_table:
		sim.state.market.erase("demand")
	elif had:
		sim.state.market["demand"][item] = before
	else:
		(sim.state.market["demand"] as Dictionary).erase(item)
	return {"prices": prices, "total": total, "demand_after": after}


## The demand of `item` after the next dawn's recovery (towards demand.rest by recover_per_day), as _recover_demand.
static func demand_tomorrow(sim: Sim, item: String) -> float:
	var cfg := _demand_cfg(sim)
	var rest := float(cfg.get("rest", 1.0))
	var step_by := float(cfg.get("recover_per_day", 0.1))
	var now := demand(sim, item)
	return minf(now + step_by, rest) if now < rest else maxf(now - step_by, rest)


## The unit sell price of `item` at `quality` once the demand is `d` (the same formula as price, with that demand).
## Read only: the demand is set for the call and put back.
static func sell_price_at(sim: Sim, item: String, quality: int, d: float) -> int:
	var had_table := sim.state.market.has("demand")
	var table: Dictionary = sim.state.market.get("demand", {})
	var had := table.has(item)
	var before := float(table.get(item, 0.0))
	_set_demand(sim, item, d, false)
	var p := price(sim, item, quality, "sell")
	if not had_table:
		sim.state.market.erase("demand")
	elif had:
		sim.state.market["demand"][item] = before
	else:
		(sim.state.market["demand"] as Dictionary).erase(item)
	return p


## The surcharge of an errand over a purchase of `cost` gold: round(cost × errand.surcharge); H12 Patrón: a stall's own
## errand_surcharge if it has one (livestock: 0, the animals walk there, 04d 4.22.4.2).
static func errand_surcharge(sim: Sim, cost: int, stall: String = "") -> int:
	var sdef: Dictionary = sim.catalog.market.get("stalls", {}).get(stall, {})
	var rate := float(sdef.get("errand_surcharge", sim.catalog.market.get("errand", {}).get("surcharge", 0.2)))
	return roundi(cost * rate)


## Minutes an errand takes to arrive (errand.hours of game time; H13: × the events' errands effect, cut routes).
static func errand_minutes(sim: Sim) -> int:
	return roundi(float(sim.catalog.market.get("errand", {}).get("hours", 2)) * 60.0 * WorldEvents.errands_mult(sim))


## What `actor` can do at `stall` now: {open, reason, buy: [{item, quality, price, max_qty, status}],
## sell: [{item, quality, qty, price}], deliver_to: [bld_id]}. `reason` is "" when it can trade there now (else the
## reason a buy/sell would be refused: unknown_actor, unknown_stall, not_at_stall, market_closed...); the lists are
## filled anyway. buy: the items of the stall at normal quality (provisional), max_qty = most units the actor can buy
## and carry now (gold and weight), status "ok" or the reason (`reason`, not_enough_gold, too_heavy). sell: what the
## actor carries that the stall takes, one row per (item, quality). deliver_to: the own buildings with a storage
## (for max_buy(..., to) and buy with deliver_to).
static func offers(sim: Sim, actor: String, stall: String) -> Dictionary:
	var st := sim.state
	var out := {"open": is_open(sim), "reason": "", "buy": [], "sell": [], "deliver_to": []}
	var def: Dictionary = sim.catalog.market.get("stalls", {}).get(stall, {})
	if not st.characters.has(actor):
		out["reason"] = "unknown_actor"
		return out
	if def.is_empty():
		out["reason"] = "unknown_stall"
		return out
	out["reason"] = _where_reason(sim, actor, stall)
	var sells: Array = def.get("sells", [])
	for item: String in _sorted_keys(sim.catalog.items()):
		if not str(sim.catalog.item(item).get("market_stall", "")) in sells:
			continue
		var n := max_buy(sim, actor, stall, item, Inventory.NORMAL)
		var status := str(out["reason"])
		if status == "":
			status = "ok" if n > 0 else _buy_block(sim, actor, item, Inventory.NORMAL)
		(out["buy"] as Array).append({"item": item, "quality": Inventory.NORMAL,
			"price": trade_price(sim, actor, stall, item, Inventory.NORMAL, "buy"), "max_qty": n, "status": status})
	var held := {}
	for s: Dictionary in st.characters[actor].get("inventory", {}).get("stacks", []):
		var it := str(s["item"])
		if str(sim.catalog.item(it).get("market_stall", "")) in sells:
			var key := "%s|%d" % [it, int(s["quality"])]
			held[key] = int(held.get(key, 0)) + int(s["qty"])
	for key: String in _sorted_keys(held):
		var parts := key.split("|")
		var q := int(parts[1])
		(out["sell"] as Array).append({"item": parts[0], "quality": q, "qty": int(held[key]),
			"price": trade_price(sim, actor, stall, parts[0], q, "sell")})
	out["deliver_to"] = own_storages(sim, actor)
	return out


## Most units of `item` the actor can buy now: limited by the family gold and by room (its bag, or with `to` the
## storage of that building counting the errands already on their way, and the surcharge). 0 if it cannot trade
## there now.
static func max_buy(sim: Sim, actor: String, stall: String, item: String, quality: int, to: String = "") -> int:
	if _trade_reason(sim, actor, stall, item) != "":
		return 0
	var st := sim.state
	var fam := Money.family_of(st, actor)
	var unit := trade_price(sim, actor, stall, item, quality, "buy")
	if fam == "" or not st.families.has(fam) or quality != Inventory.NORMAL:
		return 0
	if to != "" and _errand_target_reason(sim, actor, to) != "":
		return 0
	var gold := Money.gold(st, fam)
	var hi := 999 if unit <= 0 else gold / unit
	var lo := 0
	while lo < hi:  # largest n in [0, hi] that fits and is affordable (both are monotonic in n)
		var mid := (lo + hi + 1) / 2
		if _fits(sim, actor, to, item, quality, mid) and _pen_reason(sim, to, item, mid) == "" \
				and (to == "" or mid * unit + errand_surcharge(sim, mid * unit, stall) <= gold):
			lo = mid
		else:
			hi = mid - 1
	return lo


## The stall `actor` is at ("" if none): a map stall's service tile, or inside a shop whose type has market_stall.
static func stall_at(sim: Sim, actor: String) -> String:
	if not sim.state.characters.has(actor):
		return ""
	for stall: String in _sorted_keys(sim.catalog.market.get("stalls", {})):
		if _where_reason(sim, actor, stall) in ["", "market_closed"]:
			return stall
	return ""


## Whether `building` is a public shop of the market and the market is closed now (Buildings.can_enter refuses then).
static func shop_closed(sim: Sim, building: String) -> bool:
	if not Buildings.is_public(sim, building):
		return false
	var type := str(sim.state.buildings[building].get("type", ""))
	if str(sim.catalog.buildings().get(type, {}).get("market_stall", "")) == "":
		return false
	return not is_open(sim)


## The own buildings (of the actor or its family) with a storage, sorted: where an errand may go.
static func own_storages(sim: Sim, actor: String) -> Array:
	var out: Array = []
	for b: String in _sorted_keys(sim.state.buildings):
		if _errand_target_reason(sim, actor, b) == "":
			out.append(b)
	return out


## The errands of a family on their way, oldest first (copies).
static func pending(sim: Sim, fam: String) -> Array:
	var out: Array = []
	for d: Dictionary in sim.state.deliveries:
		if str(d.get("family", "")) == fam:
			out.append(d.duplicate(true))
	return out


# --- Internals -------------------------------------------------------------------------------------------------------

## "" when `actor` may trade `item` at `stall` now, else the reason (in the order the player meets them).
static func _trade_reason(sim: Sim, actor: String, stall: String, item: String) -> String:
	var st := sim.state
	if not st.characters.has(actor):
		return "unknown_actor"
	if not bool(st.characters[actor].get("alive", true)):
		return "dead"
	var def: Dictionary = sim.catalog.market.get("stalls", {}).get(stall, {})
	if def.is_empty():
		return "unknown_stall"
	var where := _where_reason(sim, actor, stall)
	if where != "":
		return where
	var it := sim.catalog.item(item)
	if it.is_empty():
		return "unknown_item"
	if not str(it.get("market_stall", "")) in (def.get("sells", []) as Array):
		return "wrong_stall"
	var keeper := TownLife.stall_keeper(st, sim.catalog, stall)
	if keeper != "" and Emotions.refuses_trade(sim, keeper, Money.family_of(st, actor)):
		return "vendor_refuses"  # H7: an angry keeper above 80 will not trade (GDD 4.11.5)
	return ""


## "" when the actor is at the stall and the market is open; not_at_stall / market_closed otherwise.
static func _where_reason(sim: Sim, actor: String, stall: String) -> String:
	var ch: Dictionary = sim.state.characters[actor]
	var def: Dictionary = sim.catalog.market.get("stalls", {}).get(stall, {})
	var loc := str(ch.get("location", ""))
	if str(def.get("kind", "")) == "shop":
		var b: Dictionary = sim.state.buildings.get(loc, {})
		if b.is_empty() or str(b.get("type", "")) != str(def.get("building", "")):
			return "not_at_stall"
	else:
		var map: Dictionary = sim.catalog.maps().get(sim.state.map_id, {})
		var service: Array = map.get("stalls", {}).get(stall, {}).get("service", [])
		var pos: Array = ch.get("position", [])
		if loc != "" or service.size() != 2 or pos.size() != 2 or not (ch.get("path", []) as Array).is_empty() \
				or int(pos[0]) != int(service[0]) or int(pos[1]) != int(service[1]):
			return "not_at_stall"
	if not is_open(sim):
		return "market_closed"
	return ""


## "" when `to` can receive an errand of the actor: an own building with a storage.
static func _errand_target_reason(sim: Sim, actor: String, to: String) -> String:
	var st := sim.state
	if not st.buildings.has(to):
		return "unknown_building"
	if not Buildings.owns(st, actor, to):
		return "not_your_building"
	var inv: Dictionary = st.buildings[to].get("inventory", {})
	if inv.is_empty() or float(inv.get("limit", 0)) <= 0.0:
		return "no_inventory"
	return ""


static func _errand_reason(sim: Sim, actor: String, to: String, item: String, quality: int, qty: int) -> String:
	var why := _errand_target_reason(sim, actor, to)
	if why != "":
		return why
	if not _fits(sim, actor, to, item, quality, qty):
		return "storage_full"
	return _pen_reason(sim, to, item, qty)


## H12 Patrón (04d 4.22.4.2): an animal sent to a building goes to its pen: "no_pen" if it has none, "pen_full" if the
## herd, the animals on their way and `qty` exceed its capacity; "" otherwise (and for anything that is not an animal).
static func _pen_reason(sim: Sim, to: String, item: String, qty: int) -> String:
	if to == "" or not sim.catalog.animals().has(item):
		return ""
	if not Herds.has_pen(sim, to):
		return "no_pen"
	var coming := 0
	for d: Dictionary in sim.state.deliveries:
		if str(d.get("to", "")) == to and sim.catalog.animals().has(str(d.get("item", ""))):
			coming += int(d.get("qty", 0))
	return "pen_full" if Herds.head_count(sim, to) + coming + qty > Herds.capacity(sim, to) else ""


## Whether `qty` fits: in the actor's bag (to == ""), or in the storage of `to` after the errands on their way to it.
static func _fits(sim: Sim, actor: String, to: String, item: String, quality: int, qty: int) -> bool:
	if qty <= 0:
		return true
	if to == "":
		return Inventory.can_add(sim.state.characters[actor]["inventory"], sim.catalog, item, quality, qty)
	var inv: Dictionary = (sim.state.buildings[to]["inventory"] as Dictionary).duplicate(true)
	for d: Dictionary in sim.state.deliveries:
		if str(d.get("to", "")) == to and not Inventory.add(inv, sim.catalog, str(d["item"]), int(d.get("quality", 0)),
				int(d["qty"])):
			return false  # the storage is already overbooked: nothing more fits
	return Inventory.can_add(inv, sim.catalog, item, quality, qty)


## Why not even one unit can be bought and carried (for offers): not_enough_gold or too_heavy.
static func _buy_block(sim: Sim, actor: String, item: String, quality: int) -> String:
	var fam := Money.family_of(sim.state, actor)
	if not Money.can_pay(sim.state, fam, price(sim, item, quality, "buy")):
		return "not_enough_gold"
	return "too_heavy"


static func _send_errand(sim: Sim, actor: String, fam: String, stall: String, to: String, item: String, quality: int,
		qty: int, cost: int, surcharge: int) -> Dictionary:
	var st := sim.state
	var id := Ids.next(st, "dlv")
	var arrive := int(st.clock["minute"]) + errand_minutes(sim)
	Money.change(sim, fam, -cost, Money.PURCHASES, id, to, actor)
	Money.change(sim, fam, -surcharge, Money.ERRANDS, id, to, actor)
	st.deliveries.append({"id": id, "family": fam, "actor": actor, "stall": stall, "to": to, "item": item,
		"quality": quality, "qty": qty, "arrive": arrive})
	sim.events.append({"type": "errand_sent", "actor": actor, "family": fam, "delivery": id, "stall": stall,
		"item": item, "quality": quality, "qty": qty, "to": to, "cost": cost, "surcharge": surcharge, "arrive": arrive})
	if OS.is_debug_build():
		print("[Market] %s envía %s x%d (q=%d) de %s a %s: %d + %d de recado, llega en el minuto %d (oro=%d)" % [
			actor, item, qty, quality, stall, to, cost, surcharge, arrive, Money.gold(st, fam)])
	return Orders.ok()


static func _demand_cfg(sim: Sim) -> Dictionary:
	return sim.catalog.market.get("demand", {})


static func _set_demand(sim: Sim, item: String, value: float, emit: bool = true) -> void:
	var cfg := _demand_cfg(sim)
	var v := snappedf(clampf(value, float(cfg.get("min", 0.5)), float(cfg.get("max", 2.0))), EPS)
	if not sim.state.market.has("demand"):
		sim.state.market["demand"] = {}
	sim.state.market["demand"][item] = v
	if emit:
		sim.events.append({"type": "demand_changed", "item": item, "demand": v})


static func _sorted_keys(d: Dictionary) -> Array:
	var keys: Array = []
	for k: Variant in d.keys():
		keys.append(str(k))
	keys.sort()
	return keys
