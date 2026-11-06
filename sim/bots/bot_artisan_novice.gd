class_name BotArtisanNovice
extends RefCounted
## Bot that plays a new game as a sensible novice blacksmith (GDD 07 §7.2, 4.16, 4.19; H3): only real orders, read
## through the same queries as the UI (Production.recipe_options, Market.offers / max_buy, Contracts.board_view,
## Loans.status). Measures the start phase: gold at days 3 and 10, debt paid before day 8, net gold per day.
##
## What it does, every minute the protagonist is free (not walking, nothing queued):
##   debt:   pays the whole loan as soon as the family has it plus a reserve (DEBT_RESERVE) for raw materials; from
##           the day before it falls due, whatever it has (keeps a little).
##   work:   inside the forge, the station work it wants now (contracts first: when the contract asks for quality,
##           careful with the master touch when its window opens — or, with live_for_quality = 1, the Forja viva at the
##           anvil, played as the recipe's sheet says, 03b §3b.8; otherwise the anvil recipe with the best margin per
##           hour at the demand left after selling what it already holds); ingots at the furnace when the anvil
##           lacks them. It only switches recipe when a cycle has just started (it never throws work away).
##   trips:  while the market is open (and it gets back before it closes): takes from the storage what it sells or
##           delivers, goes to the board (delivers; once a day looks for contracts it can make in time), to the
##           armory (sells while the demand is >= MIN_DEMAND), to the resources stall (buys what the next pieces need:
##           what fits in the bag by hand, the rest with an errand to the forge) and back home (leaves in the storage
##           what it carries).
## Choices at the start (bot_choices): none, it keeps the default stats (a novice does not optimise them).

const ID: String = "artisan_novice"
var ACTOR: String = "chr_0001"  # a var: the full player hands the forge to the next head (sim/bots/bot_full_player.gd)
const FORGE: String = "bld_0001"
const ARMORY_STALL: String = "armory"
const RAW_STALL: String = "resources"
const ANVIL: String = "anvil"
const FURNACE: String = "furnace"
const INGOT_RECIPE: String = "forge_ingot"
const RAW: Array = ["iron", "coal"]
const MIN_DEMAND: float = 0.7        # sells while the demand is at least this (bot habit, not a rule)
const DEBT_RESERVE: int = 30         # gold kept for raw materials when paying the debt early
const BATCH: int = 4                 # pieces of raw material bought for at a time
const SELL_AT: int = 2               # products ready before a trip to sell is worth it
const TRIP_MARGIN_MIN: int = 60      # minutes before closing: no new trip later than this
const MAX_HELD: int = 4              # never more unsold pieces of one product in stock than this

## 03b §3b.8: 1 = the contracts with a minimum quality at the anvil in Forja viva (played as the recipe's sheet says)
## instead of careful + master touch. 0 by default until the owner sees its bands (it moves artisan_novice's targets:
## BOT_VARS=live_for_quality=1 with --tag to measure it).
var live_for_quality: int = 0
var _trip: Array = []                # stops left: pickup, board, armory, resources, home
var _board_day: int = -1             # last day it looked at the board for new contracts


func bot_choices() -> Dictionary:
	return {}


func orders(sim: Sim) -> Array:
	var st := sim.state
	if not st.characters.has(ACTOR) or not st.buildings.has(FORGE) or not st.ending.is_empty():
		return []
	var ch: Dictionary = st.characters[ACTOR]
	if not bool(ch.get("alive", true)) or not (ch.get("order_queue", []) as Array).is_empty() \
			or not (ch.get("path", []) as Array).is_empty():
		return []
	if not Emergency.offer_of(sim, _fam(sim)).is_empty():  # Equilibrio 2: out of gold and goods, the moneylender's loan
		return [{"type": "take_emergency_loan", "actor": ACTOR}]
	var o := _repay(sim)
	if not o.is_empty():
		return [o]
	var loc := str(ch.get("location", ""))
	if _trip.is_empty():
		if loc != FORGE:
			return [_enter(FORGE)]
		if live_for_quality == 1:   # 03b §3b.8 (its subclasses that forge live give their own decisions)
			o = _live_decision(sim)
			if not o.is_empty():
				return [o]
		o = _master_touch(sim)
		if not o.is_empty():
			return [o]
		if _busy(sim):
			return []  # a cycle under way: auto-repeat goes on by itself
		if _may_leave(sim):
			_trip = _plan_trip(sim)
		if _trip.is_empty():
			o = _work(sim)
			return [] if o.is_empty() else [o]
	for guard: int in 6:
		if _trip.is_empty():
			return []
		o = _stop(sim, str(_trip[0]))
		if o.is_empty():
			_trip.pop_front()
			continue
		return [o]
	return []


# --- Debt ------------------------------------------------------------------------------------------------------------

func _repay(sim: Sim) -> Dictionary:
	var fam := _fam(sim)
	var gold := Money.gold(sim.state, fam)
	for id: String in Loans.of_family(sim, fam):
		var s := Loans.status(sim, id)
		if not str(s["state"]) in ["active", "extended"]:
			continue
		var owed := int(s["outstanding"])
		if gold >= owed + DEBT_RESERVE + _accepted_inputs_cost(sim):  # equilibrio: the accepted contracts' materials too
			return {"type": "repay_loan", "actor": ACTOR, "loan": id, "amount": owed}
		if int(s["days_left"]) <= 1 and gold > 5:
			return {"type": "repay_loan", "actor": ACTOR, "loan": id, "amount": mini(owed, gold - 5)}
	return {}


## What the raw materials the accepted contracts still lack would cost (as _pays_inputs counts them): repaying the debt
## early keeps it, so a contract taken on the same trip can still be made (pacing, equilibrio 2026-11-06).
func _accepted_inputs_cost(sim: Sim) -> int:
	var st := sim.state
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	var bag: Dictionary = st.characters[ACTOR]["inventory"]
	var raw := {}
	for c: Dictionary in Contracts.accepted_of(sim, _fam(sim)):
		var rid := _recipe_for(sim, str(c["item"]))
		if rid == "":
			continue
		var missing := int(c["qty"]) - Contracts.count_valid(inv, str(c["item"]), int(c["min_quality"])) \
			- Contracts.count_valid(bag, str(c["item"]), int(c["min_quality"]))
		for i: int in maxi(missing, 0):
			_add_raw(sim, rid, raw)
	var cost := 0
	for item: String in raw:
		var have := Inventory.count(inv, item) + Inventory.count(bag, item)
		if item == "iron":
			have += 2 * (Inventory.count(inv, "iron_ingot") + Inventory.count(bag, "iron_ingot"))
		cost += roundi(maxi(0, int(raw[item]) - have) * Market.price(sim, item, Inventory.NORMAL, "buy") * 1.2)
	return cost


## Gold the family should not spend on materials: when the loan is due within 2 days, what it still owes.
func _kept(sim: Sim) -> int:
	var fam := _fam(sim)
	var keep := 0
	for id: String in Loans.of_family(sim, fam):
		var s := Loans.status(sim, id)
		if str(s["state"]) in ["active", "extended"] and int(s["days_left"]) <= 2:
			keep += int(s["outstanding"])
	return keep


# --- Work ------------------------------------------------------------------------------------------------------------

## The station work wanted now: {zone, recipe, mode} or {}.
func _wanted(sim: Sim) -> Dictionary:
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	var bag: Dictionary = sim.state.characters[ACTOR]["inventory"]
	for c: Dictionary in _contracts_by_due(sim):
		var need := int(c["qty"]) - Contracts.count_valid(inv, str(c["item"]), int(c["min_quality"])) \
			- Contracts.count_valid(bag, str(c["item"]), int(c["min_quality"]))
		if need <= 0:
			continue
		var rid := _recipe_for(sim, str(c["item"]))
		var w := _make(sim, rid, _quality_mode(sim, rid) if int(c["min_quality"]) > 0 else "normal")
		if not w.is_empty():
			return w
	var best := _best_market_recipe(sim)
	if best == "":
		return {}
	return _make(sim, best, "normal")


## Work at the anvil for `rid`, or ingots at the furnace if the anvil lacks them; {} if neither can start.
func _make(sim: Sim, rid: String, mode: String) -> Dictionary:
	if rid == "":
		return {}
	if _status(sim, ANVIL, rid) == "ok":
		return {"zone": ANVIL, "recipe": rid, "mode": mode}
	if _status(sim, ANVIL, rid) == "missing_inputs" and _status(sim, FURNACE, INGOT_RECIPE) == "ok":
		return {"zone": FURNACE, "recipe": INGOT_RECIPE, "mode": "normal"}
	return {}


func _work(sim: Sim) -> Dictionary:
	var w := _wanted(sim)
	var zone := Production.job_zone(sim, ACTOR, FORGE)
	var job: Variant = null
	if zone != "":
		job = sim.state.buildings[FORGE]["zones"][zone].get("job")
	if w.is_empty():
		return {}
	if job is Dictionary:
		if str(job["recipe"]) == str(w["recipe"]) and str(job["mode"]) == str(w["mode"]):
			return {}
		if not _fresh(sim, job):
			return {}  # never throws away a cycle under way
	if _hold_for_delivery(sim, w):
		return {}
	return {"type": "work_at", "actor": ACTOR, "building": FORGE, "zone": w["zone"], "recipe": w["recipe"],
		"mode": w["mode"]}


## A contract whose pieces are ready falls due before the piece about to start would end (plus the trip margin): no
## new piece, the protagonist waits for the market and delivers first (forja, 2026-11-06: with live_for_quality, seed 2
## made the armour at 19:26, started a 233-minute sword at 05:50 with the market closed and the contract expired).
func _hold_for_delivery(sim: Sim, w: Dictionary) -> bool:
	var r: Dictionary = sim.catalog.recipes()[str(w["recipe"])]
	var end := _now(sim) + int(Production.cycle_minutes(sim.catalog, r, str(w["mode"])))
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	var bag: Dictionary = sim.state.characters[ACTOR]["inventory"]
	for c: Dictionary in _contracts_by_due(sim):
		var have := Contracts.count_valid(inv, str(c["item"]), int(c["min_quality"])) \
			+ Contracts.count_valid(bag, str(c["item"]), int(c["min_quality"]))
		if have >= int(c["qty"]) and int(c["due"]) < end + TRIP_MARGIN_MIN:
			if OS.is_debug_build():
				print("[BotNovice] min %d: no empieza %s (acaba %d): %s está listo y vence %d" % [_now(sim), w["recipe"],
					end, c["id"], int(c["due"])])
			return true
	return false


## 03b §3b.8: the mode a contract with a minimum quality is made in: Forja viva where the recipe has it (it replaces
## «con cuidado» and its master touch at the anvil), else careful.
func _quality_mode(sim: Sim, rid: String) -> String:
	return LiveForge.MODE if live_for_quality == 1 and not LiveForge.recipe_def(sim, rid).is_empty() else "careful"


## The next decision of a Forja viva job of the protagonist, played as the recipe's sheet says (its colour, its
## template, the temper the contract or the recipe wants). {} if there is nothing to decide.
func _live_decision(sim: Sim) -> Dictionary:
	var zone := Production.job_zone(sim, ACTOR, FORGE)
	if zone == "":
		return {}
	var v := LiveForge.view(sim, FORGE, zone)
	if v.is_empty() or str(v["actor"]) != ACTOR or str(v["stage"]) == "done":
		return {}
	var rdef := LiveForge.recipe_def(sim, str(v["recipe"]))
	var part: Dictionary = sim.state.buildings[FORGE]["zones"][zone]["job"]["live"]
	var o := {"type": "live_forge", "actor": ACTOR, "building": FORGE, "zone": zone}
	match str(v["stage"]):
		"heat":
			o["step"] = "heat"
			o["choice"] = str(rdef.get("heat", ""))
		"strike":
			o["step"] = "strike"
			o["choice"] = str(LiveForge.template_of(sim, rdef, part)[(v["strikes"] as Array).size()])
		"quench":
			o["step"] = "quench"
			o["choice"] = LiveForge.wanted_quench(rdef, part)
	return o


func _master_touch(sim: Sim) -> Dictionary:
	var zone := Production.job_zone(sim, ACTOR, FORGE)
	if zone == "":
		return {}
	var job: Variant = sim.state.buildings[FORGE]["zones"][zone].get("job")
	if job is Dictionary and str(job["mode"]) == "careful" and not bool(job.get("touched", false)) \
			and not job.get("result") is Dictionary and Production.window_open(job, _now(sim)):
		return {"type": "master_touch", "actor": ACTOR, "building": FORGE, "zone": zone}
	return {}


## A cycle that started this very minute (leaving now loses nothing: the inputs go back).
func _fresh(sim: Sim, job: Dictionary) -> bool:
	return int(job["start"]) >= _now(sim) and not job.get("result") is Dictionary


# --- Trips -----------------------------------------------------------------------------------------------------------

## Whether a cycle is under way at the actor's station (started before this minute and not blocked by a full
## storage: then it goes out to sell, and leaving puts the finished piece in its bag).
func _busy(sim: Sim) -> bool:
	var zone := Production.job_zone(sim, ACTOR, FORGE)
	if zone == "":
		return false
	var job: Variant = sim.state.buildings[FORGE]["zones"][zone].get("job")
	return job is Dictionary and not _fresh(sim, job) and not bool(job.get("blocked", false))


## Whether it may go out now: the market open long enough to get back before it closes.
func _may_leave(sim: Sim) -> bool:
	return Market.is_open(sim) and _minutes_to_close(sim) >= TRIP_MARGIN_MIN


func _plan_trip(sim: Sim) -> Array:
	var deliver := not _deliverable(sim).is_empty()
	var look := _board_day != _today(sim) and Contracts.accepted_of(sim, _fam(sim)).size() \
		< int(sim.catalog.market.get("board", {}).get("max_accepted_per_family", 2))
	var sell := _to_sell(sim)
	var n_sell := 0
	for s: Dictionary in sell:
		n_sell += int(s["qty"])
	var idle := _wanted(sim).is_empty()
	var buy := _want_buy(sim, idle)
	var stuck := idle and Production.job_zone(sim, ACTOR, FORGE) == ""
	if not (deliver or look or n_sell >= SELL_AT or buy or (stuck and n_sell > 0)):
		return []
	var t: Array = []
	if deliver or n_sell > 0:
		t.append("pickup")
	if deliver or look:
		t.append("board")
	if n_sell > 0:
		t.append("armory")
	t.append("resources")
	t.append("home")
	if OS.is_debug_build():
		print("[BotNovice] día %d min %d: viaje %s (entregar=%s, tablón=%s, vender=%d, comprar=%s, oro=%d)" % [
			_today(sim), Clock.minute_of_day(_now(sim)), t, deliver, look, n_sell, buy, Money.gold(sim.state, _fam(sim))])
	return t


## One order for the stop, or {} when the stop is done.
func _stop(sim: Sim, stop: String) -> Dictionary:
	var st := sim.state
	var ch: Dictionary = st.characters[ACTOR]
	var loc := str(ch.get("location", ""))
	match stop:
		"pickup":
			if loc != FORGE:
				return {}
			var bag: Dictionary = ch["inventory"]
			for want: Dictionary in _deliverable(sim) + _to_sell(sim):
				var item := str(want["item"])
				var q := int(want["quality"])
				var n := mini(int(want["qty"]), Inventory.count(st.buildings[FORGE]["inventory"], item, q))
				while n > 0 and not Inventory.can_add(bag, sim.catalog, item, q, n):
					n -= 1
				if n > 0:
					return {"type": "transfer", "actor": ACTOR, "from": FORGE, "to": ACTOR, "item": item, "quality": q,
						"qty": n}
			return {}
		"board":
			if not Market.is_open(sim):
				return {}
			if not Contracts.at_board(sim, ACTOR):
				if loc != "":
					return {"type": "exit_building", "actor": ACTOR}
				return {"type": "move_to", "actor": ACTOR, "tile": Contracts.board_service(sim)}
			var view := Contracts.board_view(sim, ACTOR)
			for c: Dictionary in view["accepted"]:
				if str(c["status"]) == "ok":
					return {"type": "deliver_contract", "actor": ACTOR, "contract": str(c["id"])}
			if _board_day != _today(sim):
				for c: Dictionary in view["open"]:
					if str(c["status"]) == "ok" and _can_make_in_time(sim, c):
						return {"type": "accept_contract", "actor": ACTOR, "contract": str(c["id"])}
				_board_day = _today(sim)
			return {}
		"armory":
			if not Market.is_open(sim):
				return {}
			var armory := _armory(sim)
			if loc != armory:
				if _sellable_in_bag(sim).is_empty():
					return {}
				if loc != "":
					return {"type": "exit_building", "actor": ACTOR}
				return _enter(armory)
			for s: Dictionary in _sellable_in_bag(sim):
				return {"type": "sell", "actor": ACTOR, "stall": ARMORY_STALL, "item": s["item"], "quality": s["quality"],
					"qty": 1}
			return {}
		"resources":
			if not Market.is_open(sim):
				return {}
			var need := _raw_needs(sim)
			if need.is_empty():
				return {}
			if Market.stall_at(sim, ACTOR) != RAW_STALL:
				if loc != "":
					return {"type": "exit_building", "actor": ACTOR}
				return {"type": "move_to", "actor": ACTOR, "tile": _service(sim, RAW_STALL)}
			for item: String in RAW:
				if not need.has(item):
					continue
				var want := int(need[item])
				var hand := mini(want, Market.max_buy(sim, ACTOR, RAW_STALL, item, Inventory.NORMAL))
				if hand > 0:
					return {"type": "buy", "actor": ACTOR, "stall": RAW_STALL, "item": item, "quality": Inventory.NORMAL,
						"qty": hand}
				var sent := mini(want, Market.max_buy(sim, ACTOR, RAW_STALL, item, Inventory.NORMAL, FORGE))
				if sent > 0:
					return {"type": "buy", "actor": ACTOR, "stall": RAW_STALL, "item": item, "quality": Inventory.NORMAL,
						"qty": sent, "deliver_to": FORGE}
			return {}
		"home":
			if loc != FORGE:
				if loc != "":
					return {"type": "exit_building", "actor": ACTOR}
				return _enter(FORGE)
			for s: Dictionary in ch["inventory"].get("stacks", []):
				var it := str(s["item"])
				if Inventory.can_add(st.buildings[FORGE]["inventory"], sim.catalog, it, int(s["quality"]), int(s["qty"])):
					return {"type": "transfer", "actor": ACTOR, "from": ACTOR, "to": FORGE, "item": it,
						"quality": int(s["quality"]), "qty": int(s["qty"])}
			return {}
	return {}


# --- What to sell, deliver and buy -----------------------------------------------------------------------------------

## Contract pieces to carry: [{item, quality, qty}] for each accepted contract whose valid pieces (bag + storage) are
## all there, the lowest valid quality first (what the delivery takes).
func _deliverable(sim: Sim) -> Array:
	var out: Array = []
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	var bag: Dictionary = sim.state.characters[ACTOR]["inventory"]
	var used := {}
	for c: Dictionary in _contracts_by_due(sim):
		var item := str(c["item"])
		var minq := int(c["min_quality"])
		var left := int(c["qty"])
		var picks: Array = []
		for q: int in Inventory.QUALITIES:
			if q < minq or left == 0:
				continue
			var key := "%s|%d" % [item, q]
			var have := Inventory.count(inv, item, q) + Inventory.count(bag, item, q) - int(used.get(key, 0))
			var take := mini(left, maxi(have, 0))
			if take > 0:
				picks.append({"item": item, "quality": q, "qty": take})
				left -= take
		if left > 0:
			continue
		for p: Dictionary in picks:
			var key := "%s|%d" % [p["item"], int(p["quality"])]
			used[key] = int(used.get(key, 0)) + int(p["qty"])
			out.append(p)
	return out


## Products in the storage worth selling now: [{item, quality, qty}] (not needed by an accepted contract, demand >=
## MIN_DEMAND).
func _to_sell(sim: Sim) -> Array:
	var out: Array = []
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	var keep := _reserved(sim)
	var seen := {}
	for s: Dictionary in inv.get("stacks", []):
		var item := str(s["item"])
		var q := int(s["quality"])
		var key := "%s|%d" % [item, q]
		if seen.has(key) or str(sim.catalog.item(item).get("market_stall", "")) != ARMORY_STALL:
			continue
		seen[key] = true
		if not _sell_ok(sim, item, q):
			continue
		var n := Inventory.count(inv, item, q) - int(keep.get(key, 0))
		if n > 0:
			out.append({"item": item, "quality": q, "qty": n})
	return out


## Pieces kept for the accepted contracts: {"item|quality": qty}, the lowest valid quality first.
func _reserved(sim: Sim) -> Dictionary:
	var out := {}
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	var bag: Dictionary = sim.state.characters[ACTOR]["inventory"]
	for c: Dictionary in _contracts_by_due(sim):
		var item := str(c["item"])
		var left := int(c["qty"])
		for q: int in Inventory.QUALITIES:
			if q < int(c["min_quality"]) or left == 0:
				continue
			var key := "%s|%d" % [item, q]
			var have := Inventory.count(inv, item, q) + Inventory.count(bag, item, q) - int(out.get(key, 0))
			var take := mini(left, maxi(have, 0))
			if take > 0:
				out[key] = int(out.get(key, 0)) + take
				left -= take
	return out


## What it carries that the armory takes and is worth selling now (not kept for a contract).
func _sellable_in_bag(sim: Sim) -> Array:
	var out: Array = []
	var bag: Dictionary = sim.state.characters[ACTOR]["inventory"]
	var keep := _reserved(sim)
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	for s: Dictionary in bag.get("stacks", []):
		var item := str(s["item"])
		var q := int(s["quality"])
		if str(sim.catalog.item(item).get("market_stall", "")) != ARMORY_STALL:
			continue
		if not _sell_ok(sim, item, q):
			continue
		# kept pieces come first from the storage, then from the bag
		var key := "%s|%d" % [item, q]
		var kept_in_bag := maxi(0, int(keep.get(key, 0)) - Inventory.count(inv, item, q))
		if Inventory.count(bag, item, q) > kept_in_bag:
			out.append({"item": item, "quality": q})
	return out


## Raw materials to buy for the next pieces ({item: qty}): piece by piece (contract pieces first, then up to BATCH
## of the best market recipe), what each piece needs beyond what the storage, the bag and the errands on their way
## already have, while the gold it may spend pays the whole piece (price + errand surcharge): it never buys iron
## without the coal to use it.
func _raw_needs(sim: Sim) -> Dictionary:
	var st := sim.state
	var fam := _fam(sim)
	var plan: Array = []  # recipes of the next pieces
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	var bag: Dictionary = st.characters[ACTOR]["inventory"]
	for c: Dictionary in _contracts_by_due(sim):
		var missing := int(c["qty"]) - Contracts.count_valid(inv, str(c["item"]), int(c["min_quality"])) \
			- Contracts.count_valid(bag, str(c["item"]), int(c["min_quality"]))
		var rid := _recipe_for(sim, str(c["item"]))
		for i: int in maxi(missing, 0) + (1 if int(c["min_quality"]) > 0 and missing > 0 else 0):
			if rid != "":
				plan.append(rid)
	plan.append_array(_extra_plan(sim))
	var best := _best_market_recipe(sim)
	var batch := _batch(sim, plan.size())
	while plan.size() < batch and best != "":
		plan.append(best)
	var stock := {}
	for item: String in RAW:
		stock[item] = Inventory.count(inv, item) + Inventory.count(bag, item)
		for d: Dictionary in Market.pending(sim, fam):
			if str(d["item"]) == item:
				stock[item] = int(stock[item]) + int(d["qty"])
	stock["iron"] = int(stock["iron"]) + 2 * (Inventory.count(inv, "iron_ingot") + Inventory.count(bag, "iron_ingot"))
	var budget := Money.gold(st, fam) - _kept(sim)
	var need := {}
	for rid: String in plan:
		var raw := {}
		_add_raw(sim, rid, raw)
		var buy := {}
		var cost := 0
		for item: String in raw:
			var from_stock := mini(int(raw[item]), int(stock.get(item, 0)))
			var n := int(raw[item]) - from_stock
			if n > 0:
				buy[item] = n
				cost += roundi(n * Market.price(sim, item, Inventory.NORMAL, "buy") * 1.2)
		if cost > budget:
			break
		budget -= cost
		for item: String in raw:
			stock[item] = maxi(0, int(stock.get(item, 0)) - int(raw[item]))
		for item: String in buy:
			need[item] = int(need.get(item, 0)) + int(buy[item])
	if need.is_empty() and _stocked_out(sim, inv, bag):
		need = _cheapest_affordable(sim, budget)  # without capital: a cheaper piece gets the forge going again
	return need


## Nothing to work with: no raw material, no ingots and no products to sell, in the storage or the bag.
func _stocked_out(sim: Sim, inv: Dictionary, bag: Dictionary) -> bool:
	for item: String in RAW + ["iron_ingot"]:
		if Inventory.count(inv, item) + Inventory.count(bag, item) > 0:
			return false
	for opt: Dictionary in Production.recipe_options(sim, ACTOR, FORGE, ANVIL):
		var out := _output(sim, str(opt["recipe"]))
		if Inventory.count(inv, out) + Inventory.count(bag, out) > 0:
			return false
	return true


## The raw materials of one piece of the cheapest anvil recipe it can make and pay ({} if none): the way out when the
## best recipe no longer fits in its gold (forja, 2026-11-06: a seed stuck at 33 gold with an empty storage).
func _cheapest_affordable(sim: Sim, budget: int) -> Dictionary:
	var best := {}
	var best_cost := budget + 1
	for opt: Dictionary in Production.recipe_options(sim, ACTOR, FORGE, ANVIL):
		if str(opt["status"]) == "locked":
			continue
		var raw := {}
		_add_raw(sim, str(opt["recipe"]), raw)
		var cost := 0
		for item: String in raw:
			cost += roundi(int(raw[item]) * Market.price(sim, item, Inventory.NORMAL, "buy") * 1.2)
		if cost < best_cost:
			best_cost = cost
			best = raw
	return best


func _add_raw(sim: Sim, rid: String, raw: Dictionary) -> void:
	for inp: Dictionary in sim.catalog.recipes()[rid].get("inputs", []):
		var item := str(inp["item"])
		if item == "iron_ingot":
			raw["iron"] = int(raw.get("iron", 0)) + 2 * int(inp["qty"])
		else:
			raw[item] = int(raw.get(item, 0)) + int(inp["qty"])


func _best_market_recipe(sim: Sim) -> String:
	var best := ""
	var best_rate := 0.0
	for opt: Dictionary in Production.recipe_options(sim, ACTOR, FORGE, ANVIL):
		if str(opt["status"]) == "locked":
			continue
		var rid := str(opt["recipe"])
		if str(sim.catalog.recipes()[rid].get("kind", "craft")) == "commission":  # 4.25.4: only for a contract
			continue
		if _held(sim, _output(sim, rid)) >= _max_held(sim, rid):
			continue
		var rate := _margin(sim, rid) / _hours(sim, rid, "normal")
		if rate > best_rate + 0.000001:
			best_rate = rate
			best = rid
	return best


# --- Contracts -------------------------------------------------------------------------------------------------------

## Whether the open contract `c` can be made in time with what is already promised: hours of work (careful when it
## asks for quality, enough pieces for the chance of reaching it) within 60 % of the hours it really has.
## Equilibrio 11 (docs/decisiones.json): a festival contract falls due when its feast ends (due_at), and deadline_days
## rounds those hours up to whole days; the real hours left are read instead (the same check fiestas built, kept with
## its capacity; and no contract whose inputs it cannot pay).
func _can_make_in_time(sim: Sim, c: Dictionary) -> bool:
	var rid := _recipe_for(sim, str(c["item"]))
	if rid == "" or _status(sim, ANVIL, rid) == "locked":
		return false
	if not _pays_inputs(sim, c, rid):
		return false
	var hours := _contract_hours(sim, c)
	for a: Dictionary in Contracts.accepted_of(sim, _fam(sim)):
		hours += _contract_hours(sim, a)
	if bool(c.get("race", false)):  # fiestas (4.25.4): the hours until its fixed hour, not the rounded day
		var left := float(int(c.get("due_at", 0)) - int(sim.state.clock["minute"])) / 60.0
		return hours <= left * 0.6 * _capacity(sim)
	return hours <= float(int(c["deadline_days"]) * 24) * 0.6 * _capacity(sim)


## Whether the gold it may spend pays the raw materials of the pieces `c` still lacks (what the storage and the bag
## do not have, at the buy price + errand surcharge, as _raw_needs): it takes no contract it cannot make.
func _pays_inputs(sim: Sim, c: Dictionary, rid: String) -> bool:
	return _inputs_cost(sim, c, rid) <= Money.gold(sim.state, _fam(sim)) - _kept(sim)


## Gold for the raw materials of the pieces contract `c` still lacks (recipe `rid`).
func _inputs_cost(sim: Sim, c: Dictionary, rid: String) -> int:
	var st := sim.state
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	var bag: Dictionary = st.characters[ACTOR]["inventory"]
	var missing := int(c["qty"]) - Contracts.count_valid(inv, str(c["item"]), int(c["min_quality"])) \
		- Contracts.count_valid(bag, str(c["item"]), int(c["min_quality"]))
	var raw := {}
	for i: int in maxi(missing, 0):
		_add_raw(sim, rid, raw)
	var cost := 0
	for item: String in raw:
		var have := Inventory.count(inv, item) + Inventory.count(bag, item)
		if item == "iron":
			have += 2 * (Inventory.count(inv, "iron_ingot") + Inventory.count(bag, "iron_ingot"))
		cost += roundi(maxi(0, int(raw[item]) - have) * Market.price(sim, item, Inventory.NORMAL, "buy") * 1.2)
	return cost


func _contract_hours(sim: Sim, c: Dictionary) -> float:
	var rid := _recipe_for(sim, str(c["item"]))
	var minq := int(c["min_quality"])
	var mode := _quality_mode(sim, rid) if minq > 0 else "normal"
	var p := _chance_at_least(sim, mode, minq)
	if p <= 0.0:
		return INF
	return float(int(c["qty"])) / p * _hours(sim, rid, mode)


## Chance that a piece made in `mode` reaches `minq` (quality table, right tool, master touch when careful).
func _chance_at_least(sim: Sim, mode: String, minq: int) -> float:
	var prod := sim.catalog.production
	var live := mode == LiveForge.MODE   # played well: the table read as normal, then one step up
	if live:
		return _chance_at_least(sim, "normal", maxi(0, minq - int(sim.catalog.live_forge.get("steps_all_right", 1))))
	var craft := clampi(int(sim.state.characters[ACTOR]["stats"].get("craft", 1)) + int(prod["modes"][mode].get(
		"craft_delta", 0)), 1, 10)
	var ch: Array = Production.quality_chances(prod, craft)
	var total := 0.0
	for x: Variant in ch:
		total += float(x)
	var steps: Array = [float(prod.get("tool_step_up_chance", 0.0))]
	if bool(prod["modes"][mode].get("master_touch", false)):
		steps.append(float(prod.get("master_touch", {}).get("step_up_chance", 0.0)))
	var dist: Array = []
	for x: Variant in ch:
		dist.append(float(x) / total)
	for s: float in steps:
		var nd: Array = [0.0, 0.0, 0.0]
		for q: int in 3:
			nd[mini(q + 1, 2)] += dist[q] * s
			nd[q] += dist[q] * (1.0 - s)
		dist = nd
	var p := 0.0
	for q: int in range(minq, 3):
		p += dist[q]
	return p


func _contracts_by_due(sim: Sim) -> Array:
	var list: Array = Contracts.accepted_of(sim, _fam(sim)).duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["due"]) < int(b["due"]) or (int(a["due"]) == int(b["due"]) and str(a["id"]) < str(b["id"])))
	return list


# --- Hooks (BotArtisanExpert changes them; the novice keeps its habits) --------------------------------------------

## Whether one more unit of `item` at quality `q` is worth selling now: the novice sells while the demand is >=
## MIN_DEMAND.
func _sell_ok(sim: Sim, item: String, _q: int) -> bool:
	return Market.demand(sim, item) >= MIN_DEMAND - 0.000001


## Whether the trip should stop at the resources stall when nothing else calls it: the novice only when idle.
func _want_buy(sim: Sim, idle: bool) -> bool:
	return idle and not _raw_needs(sim).is_empty()


## Recipes of extra pieces to buy raw materials for, after the contracts' and before its own (the novice: none).
func _extra_plan(_sim: Sim) -> Array:
	return []


## Pieces of raw materials it plans ahead when `planned` are already planned for contracts and others: BATCH.
func _batch(_sim: Sim, _planned: int) -> int:
	return BATCH


## Hands that make contract pieces, as a multiplier of the deadline share it accepts (the novice: only itself).
func _capacity(_sim: Sim) -> float:
	return 1.0


## Most unsold pieces of the output of `rid` it keeps before choosing another recipe by hand.
func _max_held(_sim: Sim, _rid: String) -> int:
	return MAX_HELD


# --- Helpers ---------------------------------------------------------------------------------------------------------

## sell price at normal quality with the demand left after selling what it holds − inputs at buy price.
func _margin(sim: Sim, rid: String) -> float:
	var item := _output(sim, rid)
	var d := maxf(Market.demand(sim, item) - 0.05 * _held(sim, item), 0.5)
	var base := float(sim.catalog.item(item).get("base_price", 0))
	var sell := base * d * float(sim.catalog.market.get("sell_ratio", 0.7))
	var raw := {}
	_add_raw(sim, rid, raw)
	var cost := 0.0
	for it: String in raw:
		cost += Market.price(sim, it, Inventory.NORMAL, "buy") * int(raw[it])
	return sell - cost


## Hours of work of one piece of `rid` in `mode`, ingots included.
func _hours(sim: Sim, rid: String, mode: String) -> float:
	var r: Dictionary = sim.catalog.recipes()[rid]
	var h := Production.cycle_minutes(sim.catalog, r, mode) / 60.0
	for inp: Dictionary in r.get("inputs", []):
		if str(inp["item"]) == "iron_ingot":
			h += int(inp["qty"]) * Production.cycle_minutes(sim.catalog, sim.catalog.recipes()[INGOT_RECIPE], "normal") \
				/ 60.0
	return h


## Units of `item` the family holds unsold (storage + bag), not counting the ones kept for contracts.
func _held(sim: Sim, item: String) -> int:
	var n := Inventory.count(sim.state.buildings[FORGE]["inventory"], item) \
		+ Inventory.count(sim.state.characters[ACTOR]["inventory"], item)
	var keep := _reserved(sim)
	for key: String in keep:
		if key.begins_with(item + "|"):
			n -= int(keep[key])
	return maxi(n, 0)


func _recipe_for(sim: Sim, item: String) -> String:
	var ids: Array = sim.catalog.recipes().keys()
	ids.sort()
	for rid: String in ids:
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) == "forge" and str(r.get("zone", "")) == ANVIL \
				and str(r.get("output", {}).get("item", "")) == item:
			return rid
	return ""


func _output(sim: Sim, rid: String) -> String:
	return str(sim.catalog.recipes()[rid].get("output", {}).get("item", ""))


func _status(sim: Sim, zone: String, rid: String) -> String:
	for opt: Dictionary in Production.recipe_options(sim, ACTOR, FORGE, zone):
		if str(opt["recipe"]) == rid:
			return str(opt["status"])
	return ""


func _armory(sim: Sim) -> String:
	for b: String in sim.state.buildings:
		if str(sim.state.buildings[b].get("type", "")) == "armory":
			return b
	return ""


func _enter(b: String) -> Dictionary:
	return {"type": "enter_building", "actor": ACTOR, "building": b}


func _service(sim: Sim, stall: String) -> Array:
	return sim.catalog.maps().get(sim.state.map_id, {}).get("stalls", {}).get(stall, {}).get("service", [0, 0])


func _minutes_to_close(sim: Sim) -> int:
	var now := _now(sim)
	var t := sim.catalog.time
	var m := 0
	while m < Clock.MINUTES_PER_DAY and Market.is_open(sim) and Clock.phase(now + m, t) in \
			(sim.catalog.market.get("open_phases", []) as Array):
		m += 15
	return m


func _fam(sim: Sim) -> String:
	return Money.family_of(sim.state, ACTOR)


func _now(sim: Sim) -> int:
	return int(sim.state.clock["minute"])


func _today(sim: Sim) -> int:
	return Clock.day(_now(sim))
