class_name BotArtisanTrade
extends RefCounted
## H12: bot that plays a new game of any artisan trade as a sensible novice (the habits of BotArtisanNovice, GDD 07
## §7.2, 4.16, 4.19), reading the trade from the data instead of knowing the forge: the protagonist's workshop
## (bld_0001) and the recipes of its building type. Criterion 1 of H12: each profession has a bot that earns money
## with it (carpenter_novice, mason_novice, tailor_novice in tools/sim_runner.gd; dianas in data/targets.json).
## Only real orders, read through the same queries as the UI (Production.recipe_options, Market.max_buy,
## Contracts.board_view, Loans.status).
##
## The trade, from the catalog: intermediate recipes (their output is an input of another recipe of the building: the
## forge's ingot, planks, ashlars, cloth), product recipes (the rest) and raw materials (inputs no recipe of the
## building makes). Every minute the protagonist is free (not walking, nothing queued):
## Three habits more than the forge novice: it pays the debt early only keeping DEBT_RESERVE, it keeps the next
## upkeep when buying, and below BROKE gold it sells whatever the demand (without them a seed could end with no gold
## and no stock to make anything).
##   debt:   pays the whole loan as soon as the family has it plus DEBT_RESERVE; from the day before it falls due,
##           whatever it has (keeps a little).
##   work:   inside the workshop, contract pieces first (careful mode when the contract asks for quality, with the
##           master touch when the window opens), otherwise the product recipe with the best margin per hour at the
##           demand left after selling what it holds; the intermediate first when a product lacks it. It only switches
##           recipe when a cycle has just started (it never throws work away).
##   trips:  while the market is open (and it gets back before it closes): takes from the storage what it sells or
##           delivers, goes to the board (delivers; once a day looks for contracts it can make in time), to the stall
##           of each product it carries (sells while the demand is >= MIN_DEMAND), to the stall of the raw materials
##           (buys what the next pieces need: what fits in the bag by hand, the rest with an errand) and back home.
## Choices at the start (bot_choices): none, it keeps the default stats.

const ACTOR: String = "chr_0001"
const BLD: String = "bld_0001"
const MIN_DEMAND: float = 0.7        # sells while the demand is at least this (bot habit, as the novice)
const DEBT_RESERVE: int = 80         # gold kept when paying the debt early: materials + a few days of upkeep (the
                                     # forge novice keeps 30; with 30 a trade could end with no gold and no stock)
const BATCH: int = 4                 # pieces of raw material bought for at a time
const SELL_AT: int = 2               # products ready before a trip to sell is worth it
const TRIP_MARGIN_MIN: int = 60      # minutes before closing: no new trip later than this
const MAX_HELD: int = 4              # never more unsold pieces of one product in stock than this
const BROKE: int = 20                # with less gold than this it sells whatever the demand (needs cash to buy)

var _trip: Array = []                # stops left: pickup, board, sell:<stall>..., buy:<stall>..., home
var _board_day: int = -1             # last day it looked at the board for new contracts
var _type: String = ""               # the workshop's building type (read once)
var _inter: Dictionary = {}          # intermediate item -> its recipe
var _products: Array = []            # product recipe ids, sorted
var _raw: Array = []                 # raw material items, sorted


func bot_choices() -> Dictionary:
	return {}


func orders(sim: Sim) -> Array:
	var st := sim.state
	if not st.characters.has(ACTOR) or not st.buildings.has(BLD) or not st.ending.is_empty():
		return []
	if _type == "":
		_learn(sim)
	var ch: Dictionary = st.characters[ACTOR]
	if not bool(ch.get("alive", true)) or not (ch.get("order_queue", []) as Array).is_empty() \
			or not (ch.get("path", []) as Array).is_empty():
		return []
	var o := _repay(sim)
	if not o.is_empty():
		return [o]
	var loc := str(ch.get("location", ""))
	if _trip.is_empty():
		if loc != BLD:
			return [_enter(BLD)]
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
	for guard: int in 8:
		if _trip.is_empty():
			return []
		o = _stop(sim, str(_trip[0]))
		if o.is_empty():
			_trip.pop_front()
			continue
		return [o]
	return []


## The trade from the catalog: the recipes of the workshop's building type split into intermediates and products, and
## the raw materials.
func _learn(sim: Sim) -> void:
	_type = str(sim.state.buildings[BLD].get("type", ""))
	var ids: Array = sim.catalog.recipes().keys()
	ids.sort()
	var mine: Array = []
	var inputs := {}
	var outputs := {}
	for rid: String in ids:
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) != _type or str(r.get("kind", "craft")) != "craft":
			continue
		mine.append(rid)
		outputs[str(r.get("output", {}).get("item", ""))] = rid
		for inp: Dictionary in r.get("inputs", []):
			inputs[str(inp["item"])] = true
	for rid: String in mine:
		var out := str(sim.catalog.recipes()[rid].get("output", {}).get("item", ""))
		if inputs.has(out):
			_inter[out] = rid
		else:
			_products.append(rid)
	for item: String in inputs:
		if not outputs.has(item):
			_raw.append(item)
	_raw.sort()
	if OS.is_debug_build():
		print("[BotTrade] oficio %s: intermedios %s, productos %s, materias %s" % [_type, _inter, _products, _raw])


# --- Debt ------------------------------------------------------------------------------------------------------------

func _repay(sim: Sim) -> Dictionary:
	var fam := _fam(sim)
	var gold := Money.gold(sim.state, fam)
	for id: String in Loans.of_family(sim, fam):
		var s := Loans.status(sim, id)
		if not str(s["state"]) in ["active", "extended"]:
			continue
		var owed := int(s["outstanding"])
		if gold >= owed + DEBT_RESERVE:
			return {"type": "repay_loan", "actor": ACTOR, "loan": id, "amount": owed}
		if int(s["days_left"]) <= 1 and gold > 5:
			return {"type": "repay_loan", "actor": ACTOR, "loan": id, "amount": mini(owed, gold - 5)}
	return {}


func _kept(sim: Sim) -> int:
	var keep := 0
	for id: String in Loans.of_family(sim, _fam(sim)):
		var s := Loans.status(sim, id)
		if str(s["state"]) in ["active", "extended"] and int(s["days_left"]) <= 2:
			keep += int(s["outstanding"])
	return keep


# --- Work ------------------------------------------------------------------------------------------------------------

## The station work wanted now: {zone, recipe, mode} or {}.
func _wanted(sim: Sim) -> Dictionary:
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
	var bag: Dictionary = sim.state.characters[ACTOR]["inventory"]
	for c: Dictionary in _contracts_by_due(sim):
		var need := int(c["qty"]) - Contracts.count_valid(inv, str(c["item"]), int(c["min_quality"])) \
			- Contracts.count_valid(bag, str(c["item"]), int(c["min_quality"]))
		if need <= 0:
			continue
		var w := _make(sim, _recipe_for(sim, str(c["item"])), "careful" if int(c["min_quality"]) > 0 else "normal")
		if not w.is_empty():
			return w
	var best := _best_market_recipe(sim)
	if best == "":
		return {}
	return _make(sim, best, "normal")


## Work at the recipe's station, or the intermediate it lacks at its own; {} if neither can start.
func _make(sim: Sim, rid: String, mode: String) -> Dictionary:
	if rid == "":
		return {}
	var zone := _zone(sim, rid)
	var s := _status(sim, zone, rid)
	if s == "ok":
		return {"zone": zone, "recipe": rid, "mode": mode}
	if s != "missing_inputs":
		return {}
	for inp: Dictionary in sim.catalog.recipes()[rid].get("inputs", []):
		var item := str(inp["item"])
		if _inter.has(item) and Inventory.count(sim.state.buildings[BLD]["inventory"], item) < int(inp["qty"]):
			var r2 := str(_inter[item])
			if _status(sim, _zone(sim, r2), r2) == "ok":
				return {"zone": _zone(sim, r2), "recipe": r2, "mode": "normal"}
	return {}


func _work(sim: Sim) -> Dictionary:
	var w := _wanted(sim)
	var zone := Production.job_zone(sim, ACTOR, BLD)
	var job: Variant = null
	if zone != "":
		job = sim.state.buildings[BLD]["zones"][zone].get("job")
	if w.is_empty():
		return {}
	if job is Dictionary:
		if str(job["recipe"]) == str(w["recipe"]) and str(job["mode"]) == str(w["mode"]):
			return {}
		if not _fresh(sim, job):
			return {}  # never throws away a cycle under way
	return {"type": "work_at", "actor": ACTOR, "building": BLD, "zone": w["zone"], "recipe": w["recipe"],
		"mode": w["mode"]}


func _master_touch(sim: Sim) -> Dictionary:
	var zone := Production.job_zone(sim, ACTOR, BLD)
	if zone == "":
		return {}
	var job: Variant = sim.state.buildings[BLD]["zones"][zone].get("job")
	if job is Dictionary and str(job["mode"]) == "careful" and not bool(job.get("touched", false)) \
			and not job.get("result") is Dictionary and Production.window_open(job, _now(sim)):
		return {"type": "master_touch", "actor": ACTOR, "building": BLD, "zone": zone}
	return {}


func _fresh(sim: Sim, job: Dictionary) -> bool:
	return int(job["start"]) >= _now(sim) and not job.get("result") is Dictionary


# --- Trips -----------------------------------------------------------------------------------------------------------

func _busy(sim: Sim) -> bool:
	var zone := Production.job_zone(sim, ACTOR, BLD)
	if zone == "":
		return false
	var job: Variant = sim.state.buildings[BLD]["zones"][zone].get("job")
	return job is Dictionary and not _fresh(sim, job) and not bool(job.get("blocked", false))


func _may_leave(sim: Sim) -> bool:
	return Market.is_open(sim) and _minutes_to_close(sim) >= TRIP_MARGIN_MIN


func _plan_trip(sim: Sim) -> Array:
	var deliver := not _deliverable(sim).is_empty()
	var look := _board_day != _today(sim) and Contracts.accepted_of(sim, _fam(sim)).size() \
		< int(sim.catalog.market.get("board", {}).get("max_accepted_per_family", 2))
	var sell := _to_sell(sim)
	var n_sell := 0
	var sell_stalls: Array = []
	for s: Dictionary in sell:
		n_sell += int(s["qty"])
		var stall := _stall_of(sim, str(s["item"]))
		if not stall in sell_stalls:
			sell_stalls.append(stall)
	sell_stalls.sort()
	var idle := _wanted(sim).is_empty()
	var buy := idle and not _raw_needs(sim).is_empty()
	var stuck := idle and Production.job_zone(sim, ACTOR, BLD) == ""
	if not (deliver or look or n_sell >= SELL_AT or buy or (stuck and n_sell > 0)):
		return []
	var t: Array = []
	if deliver or n_sell > 0:
		t.append("pickup")
	if deliver or look:
		t.append("board")
	if n_sell > 0:
		for stall: String in sell_stalls:
			t.append("sell:" + stall)
	var buy_stalls: Array = []
	for item: String in _raw:
		var stall := _stall_of(sim, item)
		if not stall in buy_stalls:
			buy_stalls.append(stall)
	for stall: String in buy_stalls:
		t.append("buy:" + stall)
	t.append("home")
	if OS.is_debug_build():
		print("[BotTrade] día %d min %d: viaje %s (entregar=%s, tablón=%s, vender=%d, comprar=%s, oro=%d)" % [
			_today(sim), Clock.minute_of_day(_now(sim)), t, deliver, look, n_sell, buy, Money.gold(sim.state, _fam(sim))])
	return t


func _stop(sim: Sim, stop: String) -> Dictionary:
	var st := sim.state
	var ch: Dictionary = st.characters[ACTOR]
	var loc := str(ch.get("location", ""))
	if stop.begins_with("sell:"):
		return _stop_sell(sim, stop.substr(5), loc)
	if stop.begins_with("buy:"):
		return _stop_buy(sim, stop.substr(4), loc)
	match stop:
		"pickup":
			if loc != BLD:
				return {}
			var bag: Dictionary = ch["inventory"]
			for want: Dictionary in _deliverable(sim) + _to_sell(sim):
				var item := str(want["item"])
				var q := int(want["quality"])
				var n := mini(int(want["qty"]), Inventory.count(st.buildings[BLD]["inventory"], item, q))
				while n > 0 and not Inventory.can_add(bag, sim.catalog, item, q, n):
					n -= 1
				if n > 0:
					return {"type": "transfer", "actor": ACTOR, "from": BLD, "to": ACTOR, "item": item, "quality": q,
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
		"home":
			if loc != BLD:
				if loc != "":
					return {"type": "exit_building", "actor": ACTOR}
				return _enter(BLD)
			for s: Dictionary in ch["inventory"].get("stacks", []):
				var it := str(s["item"])
				if Inventory.can_add(st.buildings[BLD]["inventory"], sim.catalog, it, int(s["quality"]), int(s["qty"])):
					return {"type": "transfer", "actor": ACTOR, "from": ACTOR, "to": BLD, "item": it,
						"quality": int(s["quality"]), "qty": int(s["qty"])}
			return {}
	return {}


func _stop_sell(sim: Sim, stall: String, loc: String) -> Dictionary:
	if not Market.is_open(sim):
		return {}
	var mine: Array = []
	for s: Dictionary in _sellable_in_bag(sim):
		if _stall_of(sim, str(s["item"])) == stall:
			mine.append(s)
	if mine.is_empty():
		return {}
	var go := _go_stall(sim, stall, loc)
	if not go.is_empty():
		return go
	var s0: Dictionary = mine[0]
	return {"type": "sell", "actor": ACTOR, "stall": stall, "item": s0["item"], "quality": s0["quality"], "qty": 1}


func _stop_buy(sim: Sim, stall: String, loc: String) -> Dictionary:
	if not Market.is_open(sim):
		return {}
	var need := _raw_needs(sim)
	var here: Array = []
	for item: String in _raw:
		if need.has(item) and _stall_of(sim, item) == stall:
			here.append(item)
	if here.is_empty():
		return {}
	var go := _go_stall(sim, stall, loc)
	if not go.is_empty():
		return go
	for item: String in here:
		var want := int(need[item])
		var hand := mini(want, Market.max_buy(sim, ACTOR, stall, item, Inventory.NORMAL))
		if hand > 0:
			return {"type": "buy", "actor": ACTOR, "stall": stall, "item": item, "quality": Inventory.NORMAL, "qty": hand}
		var sent := mini(want, Market.max_buy(sim, ACTOR, stall, item, Inventory.NORMAL, BLD))
		if sent > 0:
			return {"type": "buy", "actor": ACTOR, "stall": stall, "item": item, "quality": Inventory.NORMAL,
				"qty": sent, "deliver_to": BLD}
	return {}


## The order that takes the actor to `stall` ({} when it is already there): a shop is a building to enter, an
## outdoor stall a service tile of the map.
func _go_stall(sim: Sim, stall: String, loc: String) -> Dictionary:
	var def: Dictionary = sim.catalog.market.get("stalls", {}).get(stall, {})
	if str(def.get("kind", "")) == "shop":
		var b := _building_of_type(sim, str(def.get("building", "")))
		if loc == b:
			return {}
		if loc != "":
			return {"type": "exit_building", "actor": ACTOR}
		return _enter(b)
	if Market.stall_at(sim, ACTOR) == stall:
		return {}
	if loc != "":
		return {"type": "exit_building", "actor": ACTOR}
	return {"type": "move_to", "actor": ACTOR, "tile": _service(sim, stall)}


# --- What to sell, deliver and buy -----------------------------------------------------------------------------------

func _deliverable(sim: Sim) -> Array:
	var out: Array = []
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
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


## Products of the trade in the storage worth selling now: [{item, quality, qty}].
func _to_sell(sim: Sim) -> Array:
	var out: Array = []
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
	var keep := _reserved(sim)
	var seen := {}
	for s: Dictionary in inv.get("stacks", []):
		var item := str(s["item"])
		var q := int(s["quality"])
		var key := "%s|%d" % [item, q]
		if seen.has(key) or not _is_product(sim, item) or _stall_of(sim, item) == "":
			continue
		seen[key] = true
		if not _sell_ok(sim, item):
			continue
		var n := Inventory.count(inv, item, q) - int(keep.get(key, 0))
		if n > 0:
			out.append({"item": item, "quality": q, "qty": n})
	return out


func _reserved(sim: Sim) -> Dictionary:
	var out := {}
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
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


func _sellable_in_bag(sim: Sim) -> Array:
	var out: Array = []
	var bag: Dictionary = sim.state.characters[ACTOR]["inventory"]
	var keep := _reserved(sim)
	var inv: Dictionary = sim.state.buildings[BLD]["inventory"]
	for s: Dictionary in bag.get("stacks", []):
		var item := str(s["item"])
		var q := int(s["quality"])
		if not _is_product(sim, item) or _stall_of(sim, item) == "" or not _sell_ok(sim, item):
			continue
		var key := "%s|%d" % [item, q]
		var kept_in_bag := maxi(0, int(keep.get(key, 0)) - Inventory.count(inv, item, q))
		if Inventory.count(bag, item, q) > kept_in_bag:
			out.append({"item": item, "quality": q})
	return out


## Raw materials to buy for the next pieces ({item: qty}), as BotArtisanNovice: contract pieces first, then up to
## BATCH of the best market recipe, each whole piece only if the gold it may spend pays it (price + errand surcharge);
## a piece that does not fit is skipped and the next one tried.
func _raw_needs(sim: Sim) -> Dictionary:
	var st := sim.state
	var fam := _fam(sim)
	var plan: Array = []
	var inv: Dictionary = st.buildings[BLD]["inventory"]
	var bag: Dictionary = st.characters[ACTOR]["inventory"]
	for c: Dictionary in _contracts_by_due(sim):
		var missing := int(c["qty"]) - Contracts.count_valid(inv, str(c["item"]), int(c["min_quality"])) \
			- Contracts.count_valid(bag, str(c["item"]), int(c["min_quality"]))
		var rid := _recipe_for(sim, str(c["item"]))
		for i: int in maxi(missing, 0) + (1 if int(c["min_quality"]) > 0 and missing > 0 else 0):
			if rid != "":
				plan.append(rid)
	var best := _best_market_recipe(sim)
	while plan.size() < BATCH and best != "":
		plan.append(best)
	var stock := {}
	for item: String in _raw:
		stock[item] = Inventory.count(inv, item) + Inventory.count(bag, item)
		for d: Dictionary in Market.pending(sim, fam):
			if str(d["item"]) == item:
				stock[item] = int(stock[item]) + int(d["qty"])
	for item: String in _inter:  # intermediates in stock count as the raw materials they were made of
		var held := Inventory.count(inv, item) + Inventory.count(bag, item)
		if held > 0:
			var raw := {}
			_add_raw(sim, str(_inter[item]), raw, float(held))
			for r: String in raw:
				stock[r] = int(stock.get(r, 0)) + int(raw[r])
	# keeps tomorrow's upkeep (a habit the forge novice lacks: with it the trade never ends broke with no stock)
	var budget := Money.gold(st, fam) - _kept(sim) - int(sim.catalog.buildings().get(_type, {}).get("upkeep", 0))
	var need := {}
	for rid: String in plan:
		var raw := {}
		_add_raw(sim, rid, raw)
		var buy := {}
		var cost := 0
		for item: String in raw:
			var n := int(raw[item]) - mini(int(raw[item]), int(stock.get(item, 0)))
			if n > 0:
				buy[item] = n
				cost += roundi(n * Market.price(sim, item, Inventory.NORMAL, "buy") * 1.2)
		if cost > budget:
			continue  # this piece does not fit: a cheaper one may (the forge novice stops here)
		budget -= cost
		for item: String in raw:
			stock[item] = maxi(0, int(stock.get(item, 0)) - int(raw[item]))
		for item: String in buy:
			need[item] = int(need.get(item, 0)) + int(buy[item])
	return need


## Raw materials of `times` pieces of `rid` (intermediates expanded into what they are made of).
func _add_raw(sim: Sim, rid: String, raw: Dictionary, times: float = 1.0) -> void:
	var r: Dictionary = sim.catalog.recipes()[rid]
	var per := times / float(maxi(1, int(r.get("output", {}).get("qty", 1))))
	for inp: Dictionary in r.get("inputs", []):
		var item := str(inp["item"])
		if _inter.has(item):
			_add_raw(sim, str(_inter[item]), raw, per * int(inp["qty"]))
		else:
			raw[item] = int(raw.get(item, 0)) + ceili(per * int(inp["qty"]) - 0.000001)


func _best_market_recipe(sim: Sim) -> String:
	var best := ""
	var best_rate := 0.0
	for rid: String in _products:
		if _status(sim, _zone(sim, rid), rid) in ["locked", ""]:
			continue
		if _stall_of(sim, _output(sim, rid)) == "" or _held(sim, _output(sim, rid)) >= MAX_HELD:
			continue
		var rate := _margin(sim, rid) / _hours(sim, rid, "normal")
		if rate > best_rate + 0.000001:
			best_rate = rate
			best = rid
	return best


# --- Contracts -------------------------------------------------------------------------------------------------------

func _can_make_in_time(sim: Sim, c: Dictionary) -> bool:
	var rid := _recipe_for(sim, str(c["item"]))
	if rid == "" or _status(sim, _zone(sim, rid), rid) in ["locked", ""]:
		return false
	var hours := _contract_hours(sim, c)
	for a: Dictionary in Contracts.accepted_of(sim, _fam(sim)):
		hours += _contract_hours(sim, a)
	if bool(c.get("race", false)):  # fiestas (4.25.4): the hours until its fixed hour, not the rounded day
		return hours <= float(int(c.get("due_at", 0)) - int(sim.state.clock["minute"])) / 60.0 * 0.6
	return hours <= float(int(c["deadline_days"]) * 24) * 0.6


func _contract_hours(sim: Sim, c: Dictionary) -> float:
	var rid := _recipe_for(sim, str(c["item"]))
	if rid == "":
		return INF
	var minq := int(c["min_quality"])
	var mode := "careful" if minq > 0 else "normal"
	var p := _chance_at_least(sim, mode, minq)
	if p <= 0.0:
		return INF
	return float(int(c["qty"])) / p * _hours(sim, rid, mode)


func _chance_at_least(sim: Sim, mode: String, minq: int) -> float:
	var prod := sim.catalog.production
	var craft := clampi(int(sim.state.characters[ACTOR]["stats"].get("craft", 1)) + int(prod["modes"][mode].get(
		"craft_delta", 0)), 1, 10)
	var ch: Array = Production.quality_chances(prod, craft)
	var total := 0.0
	for x: Variant in ch:
		total += float(x)
	var steps: Array = []
	if Production.has_right_tool(sim, ACTOR, _type):
		steps.append(float(prod.get("tool_step_up_chance", 0.0)))
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


# --- Helpers ---------------------------------------------------------------------------------------------------------

func _sell_ok(sim: Sim, item: String) -> bool:
	return Market.demand(sim, item) >= MIN_DEMAND - 0.000001 or Money.gold(sim.state, _fam(sim)) < BROKE


## Sell price at normal quality with the demand left after selling what it holds − raw materials at buy price.
func _margin(sim: Sim, rid: String) -> float:
	var item := _output(sim, rid)
	var d := maxf(Market.demand(sim, item) - 0.05 * _held(sim, item), 0.5)
	var sell := float(sim.catalog.item(item).get("base_price", 0)) * d * float(sim.catalog.market.get("sell_ratio", 0.7))
	var raw := {}
	_add_raw(sim, rid, raw)
	var cost := 0.0
	for it: String in raw:
		cost += Market.price(sim, it, Inventory.NORMAL, "buy") * int(raw[it])
	return sell - cost


## Hours of work of one piece of `rid` in `mode`, its intermediates included.
func _hours(sim: Sim, rid: String, mode: String) -> float:
	var r: Dictionary = sim.catalog.recipes()[rid]
	var h := Production.cycle_minutes(sim.catalog, r, mode) / 60.0
	for inp: Dictionary in r.get("inputs", []):
		var item := str(inp["item"])
		if _inter.has(item):
			var r2: Dictionary = sim.catalog.recipes()[str(_inter[item])]
			h += int(inp["qty"]) * _hours(sim, str(_inter[item]), "normal") / float(maxi(1, int(r2.get("output", {}).get("qty", 1))))
	return h


func _held(sim: Sim, item: String) -> int:
	var n := Inventory.count(sim.state.buildings[BLD]["inventory"], item) \
		+ Inventory.count(sim.state.characters[ACTOR]["inventory"], item)
	var keep := _reserved(sim)
	for key: String in keep:
		if key.begins_with(item + "|"):
			n -= int(keep[key])
	return maxi(n, 0)


func _is_product(sim: Sim, item: String) -> bool:
	for rid: String in _products:
		if _output(sim, rid) == item:
			return true
	return false


func _recipe_for(sim: Sim, item: String) -> String:
	for rid: String in _products:
		if _output(sim, rid) == item:
			return rid
	return ""


func _output(sim: Sim, rid: String) -> String:
	return str(sim.catalog.recipes()[rid].get("output", {}).get("item", ""))


func _zone(sim: Sim, rid: String) -> String:
	return str(sim.catalog.recipes()[rid].get("zone", ""))


func _status(sim: Sim, zone: String, rid: String) -> String:
	for opt: Dictionary in Production.recipe_options(sim, ACTOR, BLD, zone):
		if str(opt["recipe"]) == rid:
			return str(opt["status"])
	return ""


func _stall_of(sim: Sim, item: String) -> String:
	var ms := str(sim.catalog.item(item).get("market_stall", ""))
	var stalls: Dictionary = sim.catalog.market.get("stalls", {})
	var ids: Array = stalls.keys()
	ids.sort()
	for s: String in ids:
		if ms in (stalls[s].get("sells", []) as Array):
			return s
	return ""


func _building_of_type(sim: Sim, type: String) -> String:
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		if str(sim.state.buildings[b].get("type", "")) == type:
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
