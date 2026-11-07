class_name BotTutorialRoute
extends BotArtisanNovice
## The default game played as a novice who follows the tutorial and the objectives (verifica's player pass of
## 2026-11-06, reports/jugador/2026-11-06/informe.md; the blocks of tools/verifica/jugador_bloques.py), with real
## orders only. Not a good player: the route the game teaches, at the pace of one sitting a day.
##   day 1 (the basics): one sword, sold at the armory; iron by errand («Enviar a…»); the carpenter's two hammers
##          (the objective) made and delivered.
##   day 2: the guard's good sword (careful mode for its quality) and iron by errand.
##   every day after, one «jornada»: when Empleados opens, an apprentice (the cheapest) with a looping queue of five
##          ingots (as the staff chapter shows); the debt paid when the gold covers it plus 40; a sword contract of the
##          board; iron ×8 and coal ×3 by errand when the forge has less than 4 iron; two swords at the anvil (ingots by
##          hand when there are none); deliver; sell the rest at the armory one by one.
## It never repays early in parts nor takes the emergency loan (a novice does not know them): what the route earns.

const PAY_SPARE: int = 40          # the player pays the debt when the gold covers it plus this
const IRON_BUY: int = 8            # iron by errand per jornada (4 on day 2)
const COAL_BUY: int = 3
const STEP_HOURS: int = 18         # a forging step gives up after this many game hours

var _plan: Array = []
var _planned_day: int = -1
var _step_since: int = -1


func orders(sim: Sim) -> Array:
	var st := sim.state
	if not st.characters.has(ACTOR) or not st.buildings.has(FORGE) or not st.ending.is_empty():
		return []
	var ch: Dictionary = st.characters[ACTOR]
	if not bool(ch.get("alive", true)) or not (ch.get("order_queue", []) as Array).is_empty() \
			or not (ch.get("path", []) as Array).is_empty():
		return []
	var today := _today(sim)
	if _planned_day != today:
		_planned_day = today
		_plan = _block(today)
		_step_since = _now(sim)
		if OS.is_debug_build():
			print("[BotTutorial] día %d: %s (oro=%d)" % [today, _plan, Money.gold(st, _fam(sim))])
	for guard: int in 8:
		if _plan.is_empty():
			break
		var r := _do(sim, str(_plan[0]))
		if r.has("wait"):
			return []
		if r.is_empty():
			_plan.pop_front()
			_step_since = _now(sim)
			continue
		return [r]
	if str(ch.get("location", "")) != FORGE:
		return [_enter(FORGE)]
	return []


func _block(day: int) -> Array:
	if day == 0:
		return ["forge:sword:1:normal", "take:sword", "sell", "iron:2", "board:hammer", "forge:hammer:2:normal",
			"take:hammer", "deliver", "home"]
	if day == 1:
		return ["board:sword", "iron:4", "forge:sword:1:careful", "take:sword", "deliver", "sell", "home"]
	return ["hire", "queue", "debt", "board:sword", "iron:%d" % IRON_BUY, "forge:sword:2:normal", "take:sword",
		"deliver", "sell", "debt", "home"]


## {} = the step is over, {"wait": true} = wait this minute, else the order to give.
func _do(sim: Sim, step: String) -> Dictionary:
	var st := sim.state
	var ch: Dictionary = st.characters[ACTOR]
	var loc := str(ch.get("location", ""))
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	var bag: Dictionary = ch["inventory"]
	var fam := _fam(sim)
	var p := step.split(":")
	match p[0]:
		"debt":
			for id: String in Loans.of_family(sim, fam):
				var s := Loans.status(sim, id)
				if str(s["state"]) in ["active", "extended"] and Money.gold(st, fam) >= int(s["outstanding"]) + PAY_SPARE:
					return {"type": "repay_loan", "actor": ACTOR, "loan": id, "amount": int(s["outstanding"])}
			return {}
		"hire":
			if not Unlocks.is_open(st, fam, "staff") or not Staff.employees_of(st, FORGE).is_empty():
				return {}
			var best := {}
			for c: Dictionary in Staff.candidates(sim, ACTOR, FORGE):
				if str(c["status"]) == "ok" and (best.is_empty() or int(c["wage"]) < int(best["wage"])):
					best = c
			if best.is_empty():
				return {}
			return {"type": "hire", "actor": ACTOR, "building": FORGE, "candidate": str(best["character"])}
		"queue":
			if Staff.employees_of(st, FORGE).is_empty():
				return {}
			var q: Dictionary = st.buildings[FORGE].get("queue", {})
			if (q.get("entries", []) as Array).is_empty():
				return {"type": "queue_add", "actor": ACTOR, "building": FORGE, "recipe": INGOT_RECIPE, "qty": 5}
			if not bool(q.get("loop", false)):
				return {"type": "queue_loop", "actor": ACTOR, "building": FORGE, "on": true}
			return {}
		"board":
			if not Market.is_open(sim):
				return {"wait": true} if _minutes_to_open(sim) < 12 * 60 else {}
			for c: Dictionary in Contracts.accepted_of(sim, fam):
				if str(c["item"]) == p[1]:
					return {}
			if not Contracts.at_board(sim, ACTOR):
				if loc != "":
					return {"type": "exit_building", "actor": ACTOR}
				return {"type": "move_to", "actor": ACTOR, "tile": Contracts.board_service(sim)}
			for c: Dictionary in Contracts.board_view(sim, ACTOR)["open"]:
				if str(c["item"]) == p[1] and str(c["status"]) == "ok":
					return {"type": "accept_contract", "actor": ACTOR, "contract": str(c["id"])}
			return {}
		"iron":
			if Inventory.count(inv, "iron") >= 4 or Money.gold(st, fam) < 60:
				return {}
			if not Market.is_open(sim):
				return {"wait": true}
			if Market.stall_at(sim, ACTOR) != RAW_STALL:
				if loc != "":
					return {"type": "exit_building", "actor": ACTOR}
				return {"type": "move_to", "actor": ACTOR, "tile": _service(sim, RAW_STALL)}
			var pending := {}
			for d: Dictionary in Market.pending(sim, fam):
				pending[str(d["item"])] = true
			if not pending.has("iron"):
				var n := mini(int(p[1]), Market.max_buy(sim, ACTOR, RAW_STALL, "iron", Inventory.NORMAL, FORGE))
				if n > 0:
					return {"type": "buy", "actor": ACTOR, "stall": RAW_STALL, "item": "iron", "quality": Inventory.NORMAL,
						"qty": n, "deliver_to": FORGE}
			if not pending.has("coal") and Inventory.count(inv, "coal") < 3:
				var m := mini(COAL_BUY, Market.max_buy(sim, ACTOR, RAW_STALL, "coal", Inventory.NORMAL, FORGE))
				if m > 0:
					return {"type": "buy", "actor": ACTOR, "stall": RAW_STALL, "item": "coal", "quality": Inventory.NORMAL,
						"qty": m, "deliver_to": FORGE}
			return {}
		"forge":
			return _forge(sim, p[1], int(p[2]), p[3])
		"take":
			if loc != FORGE:
				return _enter(FORGE)
			var n := Inventory.count(inv, p[1])
			if n <= 0:
				return {}
			for q: int in Inventory.QUALITIES:
				var k := Inventory.count(inv, p[1], q)
				if k > 0 and Inventory.can_add(bag, sim.catalog, p[1], q, k):
					return {"type": "transfer", "actor": ACTOR, "from": FORGE, "to": ACTOR, "item": p[1], "quality": q,
						"qty": k}
			return {}
		"deliver":
			var any := false
			for c: Dictionary in Contracts.accepted_of(sim, fam):
				if Contracts.count_valid(bag, str(c["item"]), int(c["min_quality"])) >= int(c["qty"]):
					any = true
			if not any:
				return {}
			if not Market.is_open(sim):
				return {"wait": true}
			if not Contracts.at_board(sim, ACTOR):
				if loc != "":
					return {"type": "exit_building", "actor": ACTOR}
				return {"type": "move_to", "actor": ACTOR, "tile": Contracts.board_service(sim)}
			for c: Dictionary in Contracts.board_view(sim, ACTOR)["accepted"]:
				if str(c["status"]) == "ok":
					return {"type": "deliver_contract", "actor": ACTOR, "contract": str(c["id"])}
			return {}
		"sell":
			var reserved := 0
			for c: Dictionary in Contracts.accepted_of(sim, fam):
				if str(c["item"]) == "sword":
					reserved += int(c["qty"])
			if Inventory.count(bag, "sword") <= reserved:
				return {}
			if not Market.is_open(sim) or (loc != _armory(sim) and _minutes_to_close(sim) < 60):
				return {"wait": true}  # the armory closes soon: tomorrow (the swords stay in the bag)
			var armory := _armory(sim)
			if loc != armory:
				if loc != "":
					return {"type": "exit_building", "actor": ACTOR}
				return _enter(armory)
			for q: int in Inventory.QUALITIES:
				if Inventory.count(bag, "sword", q) > 0:
					return {"type": "sell", "actor": ACTOR, "stall": ARMORY_STALL, "item": "sword", "quality": q, "qty": 1}
			return {}
		"home":
			if loc != FORGE:
				if loc != "":
					return {"type": "exit_building", "actor": ACTOR}
				return _enter(FORGE)
			return {}
	return {}


## Pieces of `item` at the anvil until `n` are in the storage: ingots by hand at the furnace when there are none,
## waiting for the errand's iron; gives up without materials or after STEP_HOURS.
func _forge(sim: Sim, item: String, n: int, mode: String) -> Dictionary:
	var st := sim.state
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	var loc := str(st.characters[ACTOR].get("location", ""))
	var rid := "forge_" + item
	if loc != FORGE:
		if loc != "":
			return {"type": "exit_building", "actor": ACTOR}
		return _enter(FORGE)
	var zone := Production.job_zone(sim, ACTOR, FORGE)
	if Inventory.count(inv, item) >= n or _now(sim) - _step_since > STEP_HOURS * 60:
		if zone != "":
			return {"type": "stop_work", "actor": ACTOR}
		return {}
	var job: Variant = st.buildings[FORGE]["zones"][zone].get("job") if zone != "" else null
	var need_ingots := 0
	for i: Dictionary in sim.catalog.recipes()[rid].get("inputs", []):
		if str(i["item"]) == "iron_ingot":
			need_ingots = int(i["qty"])
	if job is Dictionary and str(job["recipe"]) == rid:
		return {"wait": true}  # the anvil repeats on its own
	var zones: Dictionary = st.buildings[FORGE]["zones"]
	var anvil_free := str(zones[ANVIL].get("occupant", "")) in ["", ACTOR]
	if Inventory.count(inv, "iron_ingot") >= need_ingots and anvil_free and _status(sim, ANVIL, rid) == "ok":
		return {"type": "work_at", "actor": ACTOR, "building": FORGE, "zone": ANVIL, "recipe": rid, "mode": mode}
	if job is Dictionary and str(job["recipe"]) == INGOT_RECIPE:
		return {"wait": true}
	var furnace_free: bool = not zones[FURNACE].get("job") is Dictionary \
		and str(zones[FURNACE].get("occupant", "")) in ["", ACTOR]
	if Inventory.count(inv, "iron") >= 2 and furnace_free and _status(sim, FURNACE, INGOT_RECIPE) == "ok":
		return {"type": "work_at", "actor": ACTOR, "building": FORGE, "zone": FURNACE, "recipe": INGOT_RECIPE,
			"mode": "normal"}
	if not Market.pending(sim, _fam(sim)).is_empty() or not furnace_free or not anvil_free:
		return {"wait": true}  # the errand's iron, the apprentice's ingots or a free anvil are on their way
	return {}  # nothing to make it with


func _minutes_to_open(sim: Sim) -> int:
	var t := sim.catalog.time
	var m := 0
	while m < Clock.MINUTES_PER_DAY and not Clock.phase(_now(sim) + m, t) in \
			(sim.catalog.market.get("open_phases", []) as Array):
		m += 15
	return m
