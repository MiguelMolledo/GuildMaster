class_name RivalAI
extends RefCounted
## The rival smith's simple AI (GDD 4.5.5): plays like a bot, only through orders. Sim.step asks it every minute
## right after the orders from outside and before the clock ticks; it gives orders for the characters of the AI
## families with an ai_profile (data/ai_profiles/). Owner: subgrim «rival». Contract: docs/contratos/h3_mercado.md.
##
## At dawn and at every phase change (profile decide_on) it decides a plan, a list of tasks kept in
## families[fam].ai_state.plan; then, every minute the actor is free (not walking, nothing queued), the first task
## gives one order or ends. Tasks, in this order:
##   contracts: deliver an accepted contract whose pieces it has; accept one from the board (at most the family
##              maximum) if its craft allows the recipe and its production gets there before the deadline.
##   sell:      while the market is open, carry its products to their stall and sell them one by one while their
##              demand >= sell_min_demand (the difficulty's rival_sell_min_demand replaces the profile's).
##   buy:       once a day in a work phase, the inputs of the chosen recipe (best margin sell − inputs among the ones
##              its craft allows; contract pieces first) for buy_days of work, keeping gold_reserve.
##   home:      back into its building; what it carries goes to the storage.
##   work:      in the work phases, the recipe in the profile's work_mode (if an input is missing and another recipe
##              can make it from the stock, that one first).
## The checks before an order are the same queries the UI uses (Market.offers, Production.recipe_options,
## Contracts.board_view rules), so it gives no orders that would be refused; if the same order would be given twice
## with nothing changed, the task is dropped (guard). It never hires, upgrades nor goes bankrupt (H6).
## ai_state: {phase, plan: [task], recipe, bought_day, last_order, last_fp}.

const WAIT: Dictionary = {"_wait": true}  # task goes on, no order this minute
const EPS: float = 0.000001


## The orders of this minute for every AI family with a profile (sorted by family id: deterministic).
static func orders(sim: Sim) -> Array:
	var out: Array = []
	var fams: Array = sim.state.families.keys()
	fams.sort()
	for fam: String in fams:
		var f: Dictionary = sim.state.families[fam]
		if str(f.get("controlled_by", "")) != "ai" or str(f.get("ai_profile", "")) == "":
			continue
		var profile: Dictionary = sim.catalog.ai_profiles().get(str(f["ai_profile"]), {})
		if profile.is_empty():
			continue
		var actor := _actor(sim, f)
		var home := _home(sim, fam)
		if actor == "" or home == "":
			continue
		var o := _think(sim, fam, actor, home, profile)
		if not o.is_empty():
			out.append(o)
	return out


static func _think(sim: Sim, fam: String, actor: String, home: String, profile: Dictionary) -> Dictionary:
	var f: Dictionary = sim.state.families[fam]
	if not f.get("ai_state") is Dictionary:
		f["ai_state"] = {}
	var ai: Dictionary = f["ai_state"]
	var ph := Clock.phase(_now(sim), sim.catalog.time)
	if str(ai.get("phase", "")) != ph:
		var first := str(ai.get("phase", "")) == ""
		ai["phase"] = ph
		var on: Array = profile.get("decide_on", ["dawn", "phase_change"])
		if first or "phase_change" in on or (ph == "dawn" and "dawn" in on):
			_decide(sim, fam, actor, home, profile, ai, ph)
	if not _free(sim, actor):
		return {}
	for guard: int in 8:
		var plan: Array = ai.get("plan", [])
		if plan.is_empty():
			return {}
		var task := str(plan[0])
		var o := _task(sim, task, fam, actor, home, profile, ai)
		if o.is_empty():
			plan.pop_front()
			if task == "buy":
				ai["bought_day"] = Clock.day(_now(sim))
			continue
		if o.has("_wait"):
			return {}
		var key := SaveFile.canonical(o)  # canonical: 30.0 and 30 are the same after a save/load
		var fp := _fingerprint(sim, fam, actor)
		if str(ai.get("last_order", "")) == key and str(ai.get("last_fp", "")) == fp:
			if OS.is_debug_build():
				print("[RivalAI] %s atascado en %s (%s): deja la tarea" % [actor, task, key])
			plan.pop_front()
			continue
		ai["last_order"] = key
		ai["last_fp"] = fp
		if OS.is_debug_build():
			print("[RivalAI] %s (%s) tarea %s -> %s" % [actor, fam, task, key])
		return o
	return {}


# --- Deciding ----------------------------------------------------------------------------------------------------------

static func _decide(sim: Sim, fam: String, actor: String, home: String, profile: Dictionary, ai: Dictionary,
		ph: String) -> void:
	ai["recipe"] = choose_recipe(sim, actor, home)
	var work := ph in (profile.get("work_phases", ["day"]) as Array)
	var plan: Array = []
	if ph != Production.NIGHT:
		if bool(profile.get("accepts_contracts", false)) or not Contracts.accepted_of(sim, fam).is_empty():
			plan.append("contracts")
		if Market.is_open(sim):
			plan.append("sell")
			if work and int(ai.get("bought_day", -1)) != Clock.day(_now(sim)):
				plan.append("buy")
	plan.append("home")
	if work:
		plan.append("work")
	ai["plan"] = plan
	if OS.is_debug_build():
		print("[RivalAI] %s decide en %s: receta=%s plan=%s oro=%d" % [fam, ph, ai["recipe"], plan,
			Money.gold(sim.state, fam)])


## The recipe of the home building with the best margin now: sell price of the output − buy price of the inputs
## (normal quality), among the ones the actor's craft allows. "" if none has a margin > 0.
static func choose_recipe(sim: Sim, actor: String, home: String) -> String:
	var best := ""
	var best_m := 0
	for rid: String in _home_recipes(sim, actor, home):
		var m := margin(sim, rid)
		if m > best_m:
			best = rid
			best_m = m
	return best


static func margin(sim: Sim, rid: String) -> int:
	var r: Dictionary = sim.catalog.recipes().get(rid, {})
	var out: Dictionary = r.get("output", {})
	var m := Market.price(sim, str(out.get("item", "")), Inventory.NORMAL, "sell") * int(out.get("qty", 1))
	for inp: Dictionary in r.get("inputs", []):
		m -= Market.price(sim, str(inp["item"]), Inventory.NORMAL, "buy") * int(inp["qty"])
	return m


# --- Tasks -------------------------------------------------------------------------------------------------------------

static func _task(sim: Sim, task: String, fam: String, actor: String, home: String, profile: Dictionary,
		ai: Dictionary) -> Dictionary:
	match task:
		"contracts":
			return _t_contracts(sim, fam, actor, home, profile)
		"sell":
			return _t_sell(sim, fam, actor, home, profile, ai)
		"buy":
			return _t_buy(sim, fam, actor, home, profile, ai)
		"home":
			return _t_home(sim, actor, home)
		"work":
			return _t_work(sim, fam, actor, home, profile, ai)
	return {}


static func _t_contracts(sim: Sim, fam: String, actor: String, home: String, profile: Dictionary) -> Dictionary:
	var bag := _bag(sim, actor)
	var storage := _storage(sim, home)
	var accepted := Contracts.accepted_of(sim, fam)
	for c: Dictionary in accepted:
		var item := str(c["item"])
		var min_q := int(c.get("min_quality", 0))
		var in_bag := Contracts.count_valid(bag, item, min_q)
		if in_bag >= int(c["qty"]):
			return _at_board_then(sim, actor, {"type": "deliver_contract", "actor": actor, "contract": str(c["id"])})
		if in_bag + Contracts.count_valid(storage, item, min_q) >= int(c["qty"]):
			var o := _fetch(sim, actor, home, item, min_q, int(c["qty"]) - in_bag)
			if not o.is_empty():
				return o
	if not bool(profile.get("accepts_contracts", false)):
		return {}
	var most := int(sim.catalog.market.get("board", {}).get("max_accepted_per_family", 2))
	if accepted.size() >= mini(most, int(profile.get("max_contracts", most))):
		return {}
	for c: Dictionary in sim.state.contracts.get("board", []):
		if str(c.get("script", "")) != "" and not bool(profile.get("accepts_scripted_contracts", false)):
			continue
		if makes_in_time(sim, fam, actor, home, profile, c):
			return _at_board_then(sim, actor, {"type": "accept_contract", "actor": actor, "contract": str(c["id"])})
	return {}


## Whether the actor's production gets `c` done before its deadline: the pieces it lacks (after what it has and what
## its other contracts take), divided by the chance of the minimum quality in the profile's mode, times the cycle,
## plus the work its other contracts still need, against the work minutes of deadline_days days.
static func makes_in_time(sim: Sim, fam: String, actor: String, home: String, profile: Dictionary,
		c: Dictionary) -> bool:
	var rid := _recipe_for(sim, actor, home, str(c["item"]))
	if rid == "":
		return false
	if not _affords(sim, fam, actor, home, profile, c, rid):
		return false
	var need := _work_minutes_for(sim, fam, actor, home, profile, c, rid)
	for other: Dictionary in Contracts.accepted_of(sim, fam):
		var orid := _recipe_for(sim, actor, home, str(other["item"]))
		if orid != "":
			need += _work_minutes_for(sim, fam, actor, home, profile, other, orid)
	return need >= 0 and need <= int(c.get("deadline_days", 1)) * work_minutes_per_day(sim, profile)


## Whether the inputs of the pieces it lacks (expected cycles for the minimum quality), minus what it has, cost no
## more than its gold over the reserve.
static func _affords(sim: Sim, fam: String, actor: String, home: String, profile: Dictionary, c: Dictionary,
		rid: String) -> bool:
	var lack := _pieces_lacking(sim, fam, actor, home, c)
	if lack <= 0:
		return true
	var p := _quality_chance(sim, actor, profile, int(c.get("min_quality", 0)))
	if p <= 0.0:
		return false
	var need := {}
	_add_inputs(sim, need, rid, ceili(lack / p / maxi(1, int(sim.catalog.recipes()[rid].get("output", {}).get("qty", 1)))))
	var cost := 0
	for item: String in need:
		var have := Inventory.count(_bag(sim, actor), item) + Inventory.count(_storage(sim, home), item) \
			+ _makeable(sim, actor, home, item)
		cost += maxi(0, int(need[item]) - have) * Market.price(sim, item, Inventory.NORMAL, "buy")
	return cost <= Money.gold(sim.state, fam) - int(profile.get("gold_reserve", 0))


static func _work_minutes_for(sim: Sim, fam: String, actor: String, home: String, profile: Dictionary,
		c: Dictionary, rid: String) -> int:
	var lack := _pieces_lacking(sim, fam, actor, home, c)
	if lack <= 0:
		return 0
	var p := _quality_chance(sim, actor, profile, int(c.get("min_quality", 0)))
	if p <= 0.0:
		return 1 << 30
	var r: Dictionary = sim.catalog.recipes()[rid]
	var cycles := ceili(lack / p / maxi(1, int(r.get("output", {}).get("qty", 1))))
	return cycles * Production.cycle_minutes(sim.catalog, r, _mode(profile))


static func _t_sell(sim: Sim, fam: String, actor: String, home: String, profile: Dictionary,
		ai: Dictionary) -> Dictionary:
	if not Market.is_open(sim):
		return {}
	var sellable := _sellable_items(sim, fam, actor, home, ai)
	var thr := sell_min_demand(sim, profile)
	var bag := _bag(sim, actor)
	for item: String in sellable:
		if Market.demand(sim, item) < thr - EPS:
			continue
		for q: int in Inventory.QUALITIES:
			if Inventory.count(bag, item, q) <= 0:
				continue
			var stall := stall_for(sim, item)
			if not _gets_there_open(sim, actor, stall):
				continue
			var go := _go_stall(sim, actor, stall)
			if not go.is_empty():
				return go
			var offers := Market.offers(sim, actor, stall)
			if not bool(offers.get("open", false)):
				return {}
			for s: Dictionary in offers.get("sell", []):
				if str(s.get("item", "")) == item and int(s.get("quality", -1)) == q and int(s.get("qty", 0)) > 0:
					return {"type": "sell", "actor": actor, "stall": stall, "item": item, "quality": q, "qty": 1}
	# Nothing to sell in the bag: fetch from the storage what the demand still takes.
	var storage := _storage(sim, home)
	for item: String in sellable:
		var takes := units_above(Market.demand(sim, item), thr, _drop(sim)) - Inventory.count(bag, item)
		if takes <= 0 or Inventory.count(storage, item) <= 0:
			continue
		var o := _fetch(sim, actor, home, item, Inventory.NORMAL, takes)
		if not o.is_empty():
			return o
	return {}


## How many units can be sold one by one starting at demand `d` while it stays >= `thr` (each one drops `drop`).
static func units_above(d: float, thr: float, drop: float) -> int:
	if d < thr - EPS or drop <= 0.0:
		return 0
	return floori((d - thr) / drop + EPS) + 1


static func _t_buy(sim: Sim, fam: String, actor: String, home: String, profile: Dictionary,
		ai: Dictionary) -> Dictionary:
	if not Market.is_open(sim):
		return {}
	var deficit := buy_needs(sim, fam, actor, home, profile, ai)
	var reserve := int(profile.get("gold_reserve", 0))
	var items: Array = deficit.keys()
	items.sort()
	for item: String in items:
		var price := Market.price(sim, item, Inventory.NORMAL, "buy")
		var budget := Money.gold(sim.state, fam) - reserve
		if price <= 0 or budget < price:
			continue
		var n := mini(int(deficit[item]), budget / price)
		n = _max_fit(sim, _bag(sim, actor), item, Inventory.NORMAL, n)
		var stall := stall_for(sim, item)
		if n <= 0 or stall == "" or not _gets_there_open(sim, actor, stall):
			continue
		var go := _go_stall(sim, actor, stall)
		if not go.is_empty():
			return go
		var offers := Market.offers(sim, actor, stall)
		if not bool(offers.get("open", false)):
			return {}
		for b: Dictionary in offers.get("buy", []):
			if str(b.get("item", "")) == item and int(b.get("quality", -1)) == Inventory.NORMAL \
					and str(b.get("status", "ok")) == "ok" and int(b.get("max_qty", 0)) > 0:
				return {"type": "buy", "actor": actor, "stall": stall, "item": item, "quality": Inventory.NORMAL,
					"qty": mini(n, int(b["max_qty"]))}
	return {}


## What it still has to buy {item: qty}: the inputs of its contract pieces and of buy_days of work of the chosen
## recipe, minus what it has (storage and bag) and what its other recipes can make from the stock.
static func buy_needs(sim: Sim, fam: String, actor: String, home: String, profile: Dictionary,
		ai: Dictionary) -> Dictionary:
	var need := {}
	for c: Dictionary in Contracts.accepted_of(sim, fam):
		var rid := _recipe_for(sim, actor, home, str(c["item"]))
		var lack := _pieces_lacking(sim, fam, actor, home, c)
		if rid != "" and lack > 0:
			var p := maxf(_quality_chance(sim, actor, profile, int(c.get("min_quality", 0))), 0.1)
			_add_inputs(sim, need, rid, ceili(lack / p))
	var rid := str(ai.get("recipe", ""))
	if rid != "":
		var r: Dictionary = sim.catalog.recipes()[rid]
		var minutes := work_minutes_per_day(sim, profile) * int(profile.get("buy_days", 1))
		_add_inputs(sim, need, rid, minutes / Production.cycle_minutes(sim.catalog, r, _mode(profile)))
	var bag := _bag(sim, actor)
	var storage := _storage(sim, home)
	var out := {}
	for item: String in need:
		var have := Inventory.count(bag, item) + Inventory.count(storage, item) + _makeable(sim, actor, home, item)
		if int(need[item]) > have:
			out[item] = int(need[item]) - have
	return out


static func _t_home(sim: Sim, actor: String, home: String) -> Dictionary:
	var go := _go_home(sim, actor, home)
	if not go.is_empty():
		return go
	var storage := _storage(sim, home)
	for s: Dictionary in _bag(sim, actor).get("stacks", []):
		var n := _max_fit(sim, storage, str(s["item"]), int(s["quality"]), int(s["qty"]))
		if n > 0:
			return {"type": "transfer", "actor": actor, "from": actor, "to": home, "item": str(s["item"]),
				"quality": int(s["quality"]), "qty": n}
	return {}


static func _t_work(sim: Sim, fam: String, actor: String, home: String, profile: Dictionary,
		ai: Dictionary) -> Dictionary:
	var go := _go_home(sim, actor, home)
	if not go.is_empty():
		return go
	if Production.job_zone(sim, actor, home) != "":
		return WAIT
	if Production.may_work(sim, actor, home) != "" \
			or str(sim.state.buildings[home].get("state", "normal")) != "normal":
		return {}
	var wanted: Array = []
	for c: Dictionary in Contracts.accepted_of(sim, fam):
		var crid := _recipe_for(sim, actor, home, str(c["item"]))
		if crid != "" and _pieces_lacking(sim, fam, actor, home, c) > 0 and not crid in wanted:
			wanted.append(crid)
	if str(ai.get("recipe", "")) != "" and not str(ai["recipe"]) in wanted:
		wanted.append(str(ai["recipe"]))
	for rid: String in wanted:
		if _status(sim, actor, home, rid) == "ok":
			return _work(sim, actor, home, rid, profile)
		var r: Dictionary = sim.catalog.recipes()[rid]
		for inp: Dictionary in r.get("inputs", []):
			if Inventory.count(_storage(sim, home), str(inp["item"])) >= int(inp["qty"]):
				continue
			var sub := _recipe_for(sim, actor, home, str(inp["item"]))
			if sub != "" and sub != rid and _status(sim, actor, home, sub) == "ok":
				return _work(sim, actor, home, sub, profile)
	return {}


# --- Moving --------------------------------------------------------------------------------------------------------

static func _go_home(sim: Sim, actor: String, home: String) -> Dictionary:
	var loc := _loc(sim, actor)
	if loc == home:
		return {}
	if loc != "":
		return {"type": "exit_building", "actor": actor}
	return {"type": "enter_building", "actor": actor, "building": home}


## {} once at the stall (a map stall's service tile, or inside the shop), else the next order to get there.
static func _go_stall(sim: Sim, actor: String, stall: String) -> Dictionary:
	var def: Dictionary = sim.catalog.market.get("stalls", {}).get(stall, {})
	var loc := _loc(sim, actor)
	if str(def.get("kind", "")) == "shop":
		var bld := _building_of_type(sim, str(def.get("building", "")))
		if loc == bld:
			return {}
		if loc != "":
			return {"type": "exit_building", "actor": actor}
		return {"type": "enter_building", "actor": actor, "building": bld}
	var svc: Array = sim.catalog.maps().get(sim.state.map_id, {}).get("stalls", {}).get(stall, {}).get("service", [])
	if loc != "":
		return {"type": "exit_building", "actor": actor}
	if not _on(sim, actor, svc):
		return {"type": "move_to", "actor": actor, "tile": [int(svc[0]), int(svc[1])]}
	return {}


## Whether the actor reaches `stall` (walking the route) before the market closes; always true once there. Entering
## a shop that has closed would be refused, so it does not start a trip it cannot finish.
static func _gets_there_open(sim: Sim, actor: String, stall: String) -> bool:
	var def: Dictionary = sim.catalog.market.get("stalls", {}).get(stall, {})
	var tile: Array = []
	if str(def.get("kind", "")) == "shop":
		var bld := _building_of_type(sim, str(def.get("building", "")))
		if bld == "" or _loc(sim, actor) == bld:
			return bld != ""
		tile = sim.state.buildings[bld].get("door", [])
	else:
		tile = sim.catalog.maps().get(sim.state.map_id, {}).get("stalls", {}).get(stall, {}).get("service", [])
		if _loc(sim, actor) == "" and _on(sim, actor, tile):
			return true
	if tile.size() != 2:
		return false
	var grid := Grid.of(sim.catalog, sim.state.map_id)
	if grid == null:
		return false
	var pos: Array = sim.state.characters[actor].get("position", [0, 0])
	var path := Pathfinder.find(grid, Vector2i(int(pos[0]), int(pos[1])), Vector2i(int(tile[0]), int(tile[1])))
	var walk := (path.size() + 1) * Movement.minutes_per_tile(sim.catalog)
	return walk + 2 < _minutes_to_close(sim)


## Minutes until the market closes (0 if closed now), looking ahead in steps of 5 minutes up to a day.
static func _minutes_to_close(sim: Sim) -> int:
	var open: Array = sim.catalog.market.get("open_phases", [])
	var now := _now(sim)
	var m := 0
	while m < Clock.MINUTES_PER_DAY and Clock.phase(now + m, sim.catalog.time) in open:
		m += 5
	return maxi(0, m - 5) if m > 0 else 0


static func _at_board_then(sim: Sim, actor: String, o: Dictionary) -> Dictionary:
	if _loc(sim, actor) != "":
		return {"type": "exit_building", "actor": actor}
	var svc := Contracts.board_service(sim)
	if svc.size() != 2:
		return {}
	if not Contracts.at_board(sim, actor):
		return {"type": "move_to", "actor": actor, "tile": [int(svc[0]), int(svc[1])]}
	return o


## Takes up to `n` of `item` (quality >= min_q, lowest first) from the home storage into the bag; {} if nothing fits.
static func _fetch(sim: Sim, actor: String, home: String, item: String, min_q: int, n: int) -> Dictionary:
	if n <= 0:
		return {}
	var storage := _storage(sim, home)
	for q: int in Inventory.QUALITIES:
		if q < min_q or Inventory.count(storage, item, q) <= 0:
			continue
		var k := _max_fit(sim, _bag(sim, actor), item, q, mini(n, Inventory.count(storage, item, q)))
		if k <= 0:
			return {}
		var go := _go_home(sim, actor, home)
		if not go.is_empty():
			return go
		return {"type": "transfer", "actor": actor, "from": home, "to": actor, "item": item, "quality": q, "qty": k}
	return {}


# --- Queries -------------------------------------------------------------------------------------------------------

## The demand under which it keeps its goods: the difficulty's rival_sell_min_demand, else the profile's.
static func sell_min_demand(sim: Sim, profile: Dictionary) -> float:
	var lv := sim.catalog.difficulty_levels(sim.state.difficulty)
	return float(lv.get("rival_sell_min_demand", profile.get("sell_min_demand", 0.8)))


## Minutes of the work phases in a day of the current season (data/time.json phase_starts).
static func work_minutes_per_day(sim: Sim, profile: Dictionary) -> int:
	var starts: Dictionary = sim.catalog.time["phase_starts"][Clock.season(_now(sim), sim.catalog.time)]
	var order: Array = Clock.PHASES
	var total := 0
	for ph: String in profile.get("work_phases", ["day"]):
		var i := order.find(ph)
		if i < 0:
			continue
		var a := int(starts[ph])
		var b := int(starts[order[(i + 1) % order.size()]])
		total += (b - a) if b > a else (b + Clock.MINUTES_PER_DAY - a)
	return total


## The market stall that sells `item` (its market_stall in a stall's "sells"), "" if none.
static func stall_for(sim: Sim, item: String) -> String:
	var ms := str(sim.catalog.item(item).get("market_stall", ""))
	var stalls: Dictionary = sim.catalog.market.get("stalls", {})
	var ids: Array = stalls.keys()
	ids.sort()
	for st: String in ids:
		if ms != "" and ms in (stalls[st].get("sells", []) as Array):
			return st
	return ""


## Products it sells: outputs of its building's recipes that have a stall, minus the inputs of what it is going to
## make and minus the items of its accepted contracts (contracts first, GDD 4.5.5).
static func _sellable_items(sim: Sim, fam: String, actor: String, home: String, ai: Dictionary) -> Array:
	var keep := {}
	for c: Dictionary in Contracts.accepted_of(sim, fam):
		keep[str(c["item"])] = true
		var crid := _recipe_for(sim, actor, home, str(c["item"]))
		if crid != "":
			for inp: Dictionary in sim.catalog.recipes()[crid].get("inputs", []):
				keep[str(inp["item"])] = true
	var rid := str(ai.get("recipe", ""))
	if rid != "":
		for inp: Dictionary in sim.catalog.recipes()[rid].get("inputs", []):
			keep[str(inp["item"])] = true
	var out: Array = []
	var btype := str(sim.state.buildings[home].get("type", ""))
	var ids: Array = sim.catalog.recipes().keys()
	ids.sort()
	for r_id: String in ids:
		var r: Dictionary = sim.catalog.recipes()[r_id]
		var item := str(r.get("output", {}).get("item", ""))
		if str(r.get("building", "")) == btype and not keep.has(item) and not item in out and stall_for(sim, item) != "":
			out.append(item)
	return out


## Pieces of contract `c` still to make: its qty minus the valid ones it has (bag + storage) not taken by its
## family's contracts accepted before it.
static func _pieces_lacking(sim: Sim, fam: String, actor: String, home: String, c: Dictionary) -> int:
	var item := str(c["item"])
	var min_q := int(c.get("min_quality", 0))
	var have := Contracts.count_valid(_bag(sim, actor), item, min_q) \
		+ Contracts.count_valid(_storage(sim, home), item, min_q)
	for other: Dictionary in Contracts.accepted_of(sim, fam):
		if str(other["id"]) == str(c["id"]):
			break
		if str(other["item"]) == item:
			have -= int(other["qty"])
	return int(c["qty"]) - maxi(have, 0)


## Chance that a piece comes out at `min_q` or better (quality table at craft + the mode's craft_delta).
static func _quality_chance(sim: Sim, actor: String, profile: Dictionary, min_q: int) -> float:
	var craft := int(sim.state.characters[actor].get("stats", {}).get("craft", 1))
	var mode: Dictionary = sim.catalog.production.get("modes", {}).get(_mode(profile), {})
	craft = clampi(craft + int(mode.get("craft_delta", 0)), 1, 10)
	var chances: Array = Production.quality_chances(sim.catalog.production, craft)
	var p := 0.0
	for q: int in chances.size():
		if q >= min_q:
			p += float(chances[q])
	return p / 100.0


## Units of `item` its recipes can make from what is in the storage now (one level: ingots from iron).
static func _makeable(sim: Sim, actor: String, home: String, item: String) -> int:
	var rid := _recipe_for(sim, actor, home, item)
	if rid == "":
		return 0
	var r: Dictionary = sim.catalog.recipes()[rid]
	var storage := _storage(sim, home)
	var times := 1 << 30
	for inp: Dictionary in r.get("inputs", []):
		times = mini(times, Inventory.count(storage, str(inp["item"])) / maxi(1, int(inp["qty"])))
	return 0 if times == 1 << 30 else times * int(r.get("output", {}).get("qty", 1))


## The recipe of the home building the actor's craft allows that makes `item` ("" if none).
static func _recipe_for(sim: Sim, actor: String, home: String, item: String) -> String:
	for rid: String in _home_recipes(sim, actor, home):
		if str(sim.catalog.recipes()[rid].get("output", {}).get("item", "")) == item:
			return rid
	return ""


## Recipes of the home building's type that the actor's craft (and the building's upgrades) allow, by id.
static func _home_recipes(sim: Sim, actor: String, home: String) -> Array:
	var bld: Dictionary = sim.state.buildings[home]
	var craft := int(sim.state.characters[actor].get("stats", {}).get("craft", 0))
	var out: Array = []
	var ids: Array = sim.catalog.recipes().keys()
	ids.sort()
	for rid: String in ids:
		var r: Dictionary = sim.catalog.recipes()[rid]
		if str(r.get("building", "")) != str(bld.get("type", "")) or craft < int(r.get("min_craft", 1)):
			continue
		var up := str(r.get("requires_upgrade", ""))
		if up != "" and not up in (bld.get("upgrades", []) as Array):
			continue
		out.append(rid)
	return out


static func _status(sim: Sim, actor: String, home: String, rid: String) -> String:
	var zone := str(sim.catalog.recipes()[rid].get("zone", ""))
	var occupant := str(sim.state.buildings[home].get("zones", {}).get(zone, {}).get("occupant", ""))
	if occupant != "" and occupant != actor:
		return "station_busy"
	for opt: Dictionary in Production.recipe_options(sim, actor, home, zone):
		if str(opt["recipe"]) == rid:
			return str(opt["status"])
	return ""


static func _work(sim: Sim, actor: String, home: String, rid: String, profile: Dictionary) -> Dictionary:
	return {"type": "work_at", "actor": actor, "building": home, "zone": str(sim.catalog.recipes()[rid]["zone"]),
		"recipe": rid, "mode": _mode(profile)}


static func _add_inputs(sim: Sim, need: Dictionary, rid: String, cycles: int) -> void:
	if cycles <= 0:
		return
	for inp: Dictionary in sim.catalog.recipes()[rid].get("inputs", []):
		need[str(inp["item"])] = int(need.get(str(inp["item"]), 0)) + int(inp["qty"]) * cycles


## The first alive member of the family controlled by the AI ("" if none).
static func _actor(sim: Sim, f: Dictionary) -> String:
	for id: String in f.get("members", []):
		var ch: Dictionary = sim.state.characters.get(str(id), {})
		if not ch.is_empty() and bool(ch.get("alive", true)) and str(ch.get("controlled_by", "")) == "ai":
			return str(id)
	return ""


## The family's first building (by id) with stations: where it lives and works.
static func _home(sim: Sim, fam: String) -> String:
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		var bld: Dictionary = sim.state.buildings[b]
		if str(bld.get("owner", "")) == fam and not (bld.get("zones", {}) as Dictionary).is_empty():
			return b
	return ""


static func _building_of_type(sim: Sim, type: String) -> String:
	var ids: Array = sim.state.buildings.keys()
	ids.sort()
	for b: String in ids:
		if str(sim.state.buildings[b].get("type", "")) == type:
			return b
	return ""


static func _free(sim: Sim, actor: String) -> bool:
	var ch: Dictionary = sim.state.characters[actor]
	return (ch.get("path", []) as Array).is_empty() and (ch.get("order_queue", []) as Array).is_empty()


## What changes when an order works: if it is the same after giving the same order, that order was refused.
static func _fingerprint(sim: Sim, fam: String, actor: String) -> String:
	var ch: Dictionary = sim.state.characters[actor]
	return SaveFile.canonical([ch.get("position"), ch.get("location"), ch.get("station"), ch.get("inventory"),
		Money.gold(sim.state, fam), Contracts.accepted_of(sim, fam).size(), (sim.state.contracts.get("board", []) as Array).size()])


static func _on(sim: Sim, actor: String, tile: Array) -> bool:
	var pos: Array = sim.state.characters[actor].get("position", [])
	return tile.size() == 2 and pos.size() == 2 and int(pos[0]) == int(tile[0]) and int(pos[1]) == int(tile[1])


static func _max_fit(sim: Sim, inv: Dictionary, item: String, quality: int, n: int) -> int:
	var k := n
	while k > 0 and not Inventory.can_add(inv, sim.catalog, item, quality, k):
		k -= 1
	return k


static func _mode(profile: Dictionary) -> String:
	return str(profile.get("work_mode", "normal"))


static func _drop(sim: Sim) -> float:
	return float(sim.catalog.market.get("demand", {}).get("drop_per_unit", 0.05))


static func _loc(sim: Sim, actor: String) -> String:
	return str(sim.state.characters[actor].get("location", ""))


static func _bag(sim: Sim, actor: String) -> Dictionary:
	return sim.state.characters[actor]["inventory"]


static func _storage(sim: Sim, home: String) -> Dictionary:
	return sim.state.buildings[home]["inventory"]


static func _now(sim: Sim) -> int:
	return int(sim.state.clock["minute"])
