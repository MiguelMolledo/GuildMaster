extends "res://tests/test_case.gd"
const Pins = preload("res://tests/balance_pins.gd")
## Production by hand (GDD 4.4, D11, H2 criteria): cycles, quality, modes, master touch, interruption, refusals,
## save/load mid-cycle. Everything runs on the Sim alone: no views, no nodes (lesson L1, BUG-024).

const HUGO: String = "chr_0001"
const ELENA: String = "chr_0002"
const TOMAS: String = "chr_0003"
const MARTA: String = "chr_0004"
const FORGE: String = "bld_0001"

var cat := Pins.no_player_needs(Pins.classic(Catalog.load_from()))  # pre-H5 figures: see tests/balance_pins.gd


## The town_e_start scenario with `who` already inside the forge (placed by hand: entering is tested by «edificio»).
func _sim(seed: int = 7, who: Array = [HUGO]) -> Sim:
	var r := NewGame.from_scenario("town_e_start", seed)
	(r["state"] as WorldState).families["fam_0003"]["ai_profile"] = ""  # the rival smith (H3) off: its rolls would share state.rng
	var sim := Sim.new(r["state"], cat)
	for id: String in who:
		_inside(sim, id)
	return sim


func _inside(sim: Sim, id: String) -> void:
	var ch: Dictionary = sim.state.characters[id]
	ch["location"] = FORGE
	ch["station"] = ""
	ch["position"] = sim.state.buildings[FORGE]["door"].duplicate()


func _storage(sim: Sim) -> Dictionary:
	return sim.state.buildings[FORGE]["inventory"]


func _work(sim: Sim, actor: String, zone: String, recipe: String, mode: String = "normal") -> Dictionary:
	return Orders.apply(sim, {"type": "work_at", "actor": actor, "building": FORGE, "zone": zone, "recipe": recipe,
		"mode": mode})


## Runs `minutes` steps and returns every event.
func _run(sim: Sim, minutes: int) -> Array:
	var all: Array = []
	for i: int in minutes:
		all.append_array(sim.step())
	return all


func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool: return str(e["type"]) == type)


func _job(sim: Sim, zone: String) -> Variant:
	return sim.state.buildings[FORGE]["zones"][zone]["job"]


# --- Hito: comprar, lingote, espada, ver la calidad -----------------------------------------------------------------

func test_buy_iron_make_ingots_and_a_sword_by_hand() -> void:
	var sim := _sim()
	_storage(sim)["stacks"] = []
	var gold := Money.gold(sim.state, "fam_0001")
	# H3: bought at the resources stall with an errand to the forge (Market), no longer buy_raw.
	sim.state.clock["minute"] = 600  # by day: the market is open
	sim.state.families["fam_0003"]["ai_profile"] = ""  # the rival works by day too: only Hugo's events count here
	var hugo: Dictionary = sim.state.characters[HUGO]
	hugo["location"] = ""
	hugo["position"] = (cat.maps()["town_e"]["stalls"]["resources"]["service"] as Array).duplicate()
	var buy := {"type": "buy", "actor": HUGO, "stall": "resources", "quality": 0, "deliver_to": FORGE}
	var r := Orders.apply(sim, buy.merged({"item": "iron", "qty": 4}))
	check(r["ok"], "buys iron: %s" % r["reason"])
	r = Orders.apply(sim, buy.merged({"item": "coal", "qty": 1}))
	check(r["ok"], "buys coal: %s" % r["reason"])
	var iron := 4 * int(cat.item("iron")["base_price"])
	var coal := int(cat.item("coal")["base_price"])
	eq(Money.gold(sim.state, "fam_0001"), gold - (iron + roundi(iron * 0.2)) - (coal + roundi(coal * 0.2)),
		"price + 20 % errand from the family purse")
	_run(sim, 120)
	eq(Inventory.count(_storage(sim), "iron"), 4, "iron in the storage")
	_inside(sim, HUGO)
	r = _work(sim, HUGO, "furnace", "forge_ingot")
	check(r["ok"], "work_at furnace: %s" % r["reason"])
	eq(str(sim.state.characters[HUGO]["station"]), "furnace", "work_at puts him at the free station")
	eq(Inventory.count(_storage(sim), "iron"), 2, "inputs taken when the cycle starts")
	var ev := _run(sim, 59)
	eq(_of(ev, "work_done").size(), 0, "not done before 1 h")
	ev = _run(sim, 1)
	eq(_of(ev, "work_done").size(), 1, "ingot done at 60 min")
	eq(_of(ev, "work_started").size(), 1, "auto-repeat: second ingot started")
	ev = _run(sim, 60)
	eq(Inventory.count(_storage(sim), "iron_ingot"), 2, "two ingots")
	eq(_of(ev, "work_idle").size(), 1, "stops repeating without iron")
	eq(_job(sim, "furnace"), null, "furnace free of jobs")
	r = _work(sim, HUGO, "anvil", "forge_sword")
	check(r["ok"], "work_at anvil: %s" % r["reason"])
	eq(str(sim.state.buildings[FORGE]["zones"]["furnace"]["occupant"]), "", "left the furnace")
	ev = _run(sim, 180)
	var done := _of(ev, "work_done")
	eq(done.size(), 1, "sword done at 3 h")
	if done.size() == 1:
		var q := int(done[0]["quality"])
		eq(Inventory.count(_storage(sim), "sword", q), 1, "the sword is in the storage with its quality")
		check(q in Inventory.QUALITIES, "a valid quality")
	eq(Inventory.count(_storage(sim), "iron_ingot"), 0, "ingots used")
	eq(Inventory.count(_storage(sim), "coal"), 0, "coal used")


func test_production_runs_with_no_views() -> void:
	# Only the Sim: no game layer, no interior view open. The cycle still ends (L1, BUG-024).
	var sim := _sim()
	check(_work(sim, HUGO, "furnace", "forge_ingot")["ok"], "starts")
	sim.run_minutes(5 * 60)
	eq(Inventory.count(_storage(sim), "iron_ingot"), 5, "10 iron -> 5 ingots in 5 h with nobody looking")
	eq(Inventory.count(_storage(sim), "iron"), 0, "iron used")


func test_cycle_length_per_mode() -> void:
	var sim := _sim()
	var recipe: Dictionary = cat.recipes()["forge_sword"]
	eq(Production.cycle_minutes(cat, recipe, "fast"), 126, "3 h x 0.7")
	eq(Production.cycle_minutes(cat, recipe, "normal"), 180, "3 h")
	eq(Production.cycle_minutes(cat, recipe, "careful"), 270, "3 h x 1.5")
	_work(sim, HUGO, "furnace", "forge_ingot", "careful")
	var job: Dictionary = _job(sim, "furnace")
	var start := int(job["start"])
	eq(int(job["end"]) - start, 90, "careful ingot = 90 min")
	eq(job["window"], [start + 15, start + 75], "1 h window centred on the middle")
	var ev := _run(sim, 15)
	eq(_of(ev, "master_window").size(), 1, "window opens at the middle")
	check(Production.job_view(sim, FORGE, "furnace")["window_open"], "job_view sees it open")
	ev = _run(sim, 60)
	eq(_of(ev, "master_window").size(), 1, "and closes 1 h later")
	check(not ev.is_empty() and not bool(_of(ev, "master_window")[0]["open"]), "close event")
	_work(sim, HUGO, "furnace", "forge_ingot", "fast")
	eq(int(_job(sim, "furnace")["end"]) - int(_job(sim, "furnace")["start"]), 42, "fast ingot = 42 min")
	eq(_job(sim, "furnace")["window"], null, "no window when not careful")


# --- Hito: 200 ciclos con semilla -----------------------------------------------------------------------------------

## Runs `cycles` ingot cycles of Hugo in `mode` (seed fixed). Each finished ingot leaves the storage so it never fills.
## Returns {mean, step_ups, eligible}: step_ups counts the pieces the master touch raised, found by replaying each
## finishing roll from the rng state before the step without the touch (only production uses the rng here).
func _ingot_cycles(mode: String, cycles: int, touch: bool) -> Dictionary:
	var sim := _sim(4242)
	var st := _storage(sim)
	st["stacks"] = []
	# H7: a night thief (microevent, GDD 4.20) may take a few units of iron: some to spare
	Inventory.add(st, cat, "iron", Inventory.NORMAL, cycles * 2 + 12)
	check(_work(sim, HUGO, "furnace", "forge_ingot", mode)["ok"], "starts %s" % mode)
	var total := 0
	var done := 0
	var step_ups := 0
	var eligible := 0
	var guard := cycles * 200
	while done < cycles and guard > 0:
		guard -= 1
		var orders: Array = []
		var view := Production.job_view(sim, FORGE, "furnace")
		if touch and bool(view.get("window_open", false)) and not bool(view.get("touched", false)):
			orders.append({"type": "master_touch", "actor": HUGO, "building": FORGE, "zone": "furnace"})
		var before := sim.state.rng.state
		var touched_before := bool(view.get("touched", false)) or not orders.is_empty()
		for e: Dictionary in sim.step(orders):
			if str(e["type"]) == "order_refused":
				failures.append("refused %s: %s" % [e["order"], e["reason"]])
			if str(e["type"]) != "work_done":
				continue
			var q := int(e["quality"])
			total += q
			done += 1
			Inventory.remove(st, "iron_ingot", q, 1)
			var after := sim.state.rng.state
			sim.state.rng.state = before
			var base := Production.roll_quality(sim, HUGO, "forge", mode, false)
			sim.state.rng.state = after
			if base < Inventory.EXCELLENT:
				eligible += 1
				step_ups += q - base
			check(not touch or touched_before, "every cycle got its touch")
	eq(done, cycles, "%d %s cycles" % [cycles, mode])
	return {"mean": float(total) / maxi(done, 1), "step_ups": step_ups, "eligible": eligible}


func test_careful_beats_fast_and_master_touch_adds_what_it_says() -> void:
	var fast := _ingot_cycles("fast", 200, false)
	var careful := _ingot_cycles("careful", 200, false)
	var touched := _ingot_cycles("careful", 200, true)
	# Hugo, craft 7: fast reads 4 (mean 0.6), careful reads 9 (mean 1.1).
	check(float(careful["mean"]) > float(fast["mean"]) + 0.25,
		"careful mean %.3f > fast mean %.3f" % [careful["mean"], fast["mean"]])
	eq(int(careful["step_ups"]), 0, "no step-up without the touch")
	var chance := float(cat.production["master_touch"]["step_up_chance"])
	var freq := float(touched["step_ups"]) / maxi(int(touched["eligible"]), 1)
	print("[test_production] 200 ciclos: fast=%.3f careful=%.3f careful+toque=%.3f · subidas %d/%d = %.3f" % [
		fast["mean"], careful["mean"], touched["mean"], touched["step_ups"], touched["eligible"], freq])
	check(int(touched["eligible"]) > 100, "enough pieces that could rise (%d)" % touched["eligible"])
	near(freq, chance, 0.08, "step-up frequency with the touch ~ step_up_chance")
	check(float(touched["mean"]) > float(careful["mean"]),
		"touch raises the mean (%.3f > %.3f)" % [touched["mean"], careful["mean"]])


func test_quality_reads_craft_with_mode_and_tool() -> void:
	# The quality table is read with craft + craft_delta (1..10); the right tool adds a separate step-up roll.
	var sim := _sim(99)
	eq(Production.quality_chances(cat.production, 1), [80, 18, 2], "craft 1-3")
	eq(Production.quality_chances(cat.production, 10), [5, 40, 55], "craft 10")
	sim.state.characters[TOMAS]["stats"]["craft"] = 2
	var n := 2000
	var hits := [0, 0]
	for with_tool: int in 2:
		sim.state.characters[TOMAS]["equipment"]["tool"] = {"item": "hammer", "quality": 0} if with_tool == 1 else null
		check(Production.has_right_tool(sim, TOMAS, "forge") == (with_tool == 1), "tool seen")
		for i: int in n:
			if Production.roll_quality(sim, TOMAS, "forge", "fast", false) > 0:
				hits[with_tool] += 1
	# craft 2 - 3 -> 1 (min 1): 20 % above normal; the hammer adds ~10 % of the rest.
	near(float(hits[0]) / n, 0.20, 0.03, "fast with craft 2 reads the 1-3 row")
	near(float(hits[1]) / n, 0.20 + 0.8 * 0.1, 0.03, "hammer: +10 % step-up")


# --- Hito: interrumpir devuelve las entradas (D11) ------------------------------------------------------------------

func test_stop_work_returns_inputs() -> void:
	var sim := _sim()
	var st := _storage(sim)
	Inventory.add(st, cat, "iron_ingot", Inventory.GOOD, 2)
	check(_work(sim, HUGO, "anvil", "forge_sword")["ok"], "starts the sword")
	eq(Inventory.count(st, "iron_ingot"), 0, "ingots taken")
	eq(Inventory.count(st, "coal"), 5, "coal taken")
	_run(sim, 100)
	var before := int(sim.state.clock["minute"])
	var r := Orders.apply(sim, {"type": "stop_work", "actor": HUGO})
	check(r["ok"], "stop_work: %s" % r["reason"])
	eq(Inventory.count(st, "iron_ingot", Inventory.GOOD), 2, "good ingots back with their quality")
	eq(Inventory.count(st, "coal"), 6, "coal back")
	eq(_job(sim, "anvil"), null, "no job")
	eq(str(sim.state.characters[HUGO]["station"]), "anvil", "he stays at the station")
	eq(int(sim.state.clock["minute"]), before, "instant")
	eq(_of(sim.events, "work_interrupted").size(), 1, "work_interrupted event")


func test_leaving_the_station_or_the_building_interrupts() -> void:
	var sim := _sim()
	var st := _storage(sim)
	check(_work(sim, HUGO, "furnace", "forge_ingot")["ok"], "starts")
	eq(Inventory.count(st, "iron"), 8, "iron taken")
	# Leaving by any way the step notices (safety net): the job is interrupted and the iron comes back.
	sim.state.characters[HUGO]["station"] = ""
	var ev := _run(sim, 1)
	eq(_of(ev, "work_interrupted").size(), 1, "interrupted when the actor is not at the station")
	eq(Inventory.count(st, "iron"), 10, "iron back")
	# Production.interrupt, as Buildings calls it on exit_building.
	sim.state.characters[HUGO]["station"] = ""
	sim.state.buildings[FORGE]["zones"]["furnace"]["occupant"] = ""
	check(_work(sim, HUGO, "furnace", "forge_ingot")["ok"], "starts again")
	var back := Production.interrupt(sim, FORGE, "furnace")
	eq(back, [{"item": "iron", "quality": 0, "qty": 2, "to": "storage"}], "returned list")
	eq(Inventory.count(st, "iron"), 10, "iron back again")
	eq(Production.interrupt(sim, FORGE, "furnace"), [], "nothing to interrupt twice")


func test_interrupt_overflow_goes_to_actor_then_floor() -> void:
	var sim := _sim()
	var st := _storage(sim)
	st["stacks"] = []
	Inventory.add(st, cat, "iron_ingot", Inventory.NORMAL, 2)
	Inventory.add(st, cat, "coal", Inventory.NORMAL, 1)
	check(_work(sim, HUGO, "anvil", "forge_sword")["ok"], "starts")
	# Fill the storage (10 stacks) and almost all of Hugo's 30 kg (coal 1 kg fits, ingots 4 kg do not).
	for it: String in ["wood", "stone", "wool", "wheat", "flour", "herbs", "cloth", "planks", "bread", "saw"]:
		Inventory.add(st, cat, it, Inventory.NORMAL, 1)
	eq((st["stacks"] as Array).size(), 10, "storage full")
	Inventory.add(sim.state.characters[HUGO]["inventory"], cat, "iron", Inventory.NORMAL, 14)  # 28 kg
	var back := Production.interrupt(sim, FORGE, "anvil")
	eq(back, [{"item": "iron_ingot", "quality": 0, "qty": 2, "to": "floor"},
		{"item": "coal", "quality": 0, "qty": 1, "to": "actor"}], "ingots to the floor, coal to Hugo")
	eq(sim.state.buildings[FORGE]["zones"]["anvil"]["floor"], [{"item": "iron_ingot", "quality": 0, "qty": 2}],
		"floor of the station keeps them")
	eq(Inventory.count(sim.state.characters[HUGO]["inventory"], "coal"), 1, "coal carried")


func test_blocked_station_waits_for_room() -> void:
	var sim := _sim()
	var st := _storage(sim)
	st["stacks"] = []
	Inventory.add(st, cat, "iron", Inventory.NORMAL, 2)
	check(_work(sim, HUGO, "furnace", "forge_ingot")["ok"], "starts")
	for it: String in ["wood", "stone", "wool", "wheat", "flour", "herbs", "cloth", "planks", "bread", "saw"]:
		Inventory.add(st, cat, it, Inventory.NORMAL, 1)
	var ev := _run(sim, 60)
	eq(_of(ev, "station_blocked").size(), 1, "blocked when the ingot does not fit")
	check(Production.job_view(sim, FORGE, "furnace")["blocked"], "job_view says blocked")
	ev = _run(sim, 30)
	eq(_of(ev, "station_blocked").size(), 0, "warns once")
	Inventory.remove(st, "saw", Inventory.NORMAL, 1)
	ev = _run(sim, 1)
	eq(_of(ev, "work_done").size(), 1, "delivered once there is room")
	eq(Inventory.count(st, "iron_ingot"), 1, "ingot in")


func test_active_pause_queue_stops_the_auto_repeat() -> void:
	var sim := _sim()
	check(_work(sim, HUGO, "furnace", "forge_ingot")["ok"], "starts")
	_run(sim, 30)
	sim.step([{"type": "move_to", "actor": HUGO, "tile": [20, 21], "queued": true}])
	eq((sim.state.characters[HUGO]["order_queue"] as Array).size(), 1, "queued while working")
	var ev := _run(sim, 30)
	eq(_of(ev, "work_done").size(), 1, "the cycle ends")
	eq(_of(ev, "work_idle").size(), 1, "and does not repeat")
	eq(str(_of(ev, "work_idle")[0]["reason"]) if _of(ev, "work_idle").size() == 1 else "", "queued", "because of the queue")
	eq(_job(sim, "furnace"), null, "station free for the queue")


# --- Restricción nocturna --------------------------------------------------------------------------------------------

func test_only_player_characters_work_and_at_night_too() -> void:
	var sim := _sim(7, [HUGO, ELENA])
	sim.state.clock["minute"] = 1440 + 23 * 60  # night of day 1
	check(_work(sim, HUGO, "furnace", "forge_ingot")["ok"], "the player works by hand at night")
	# H8 (GDD 4.10.2, 4.10.6, 4.10.8): a family member run by AI works its family's forge like the player, also at
	# night (no hammer here only for lack of ingots), from 16; a child does not.
	sim.state.characters[ELENA]["controlled_by"] = "ai"
	eq(_work(sim, ELENA, "anvil", "forge_hammer")["reason"], "missing_inputs", "family members work at night too")
	sim.state.clock["minute"] = 1440 + 12 * 60
	sim.state.characters[ELENA]["birth_day"] = Kin.birth_day_for(10, int(sim.state.clock["minute"]), sim.catalog.time)
	eq(_work(sim, ELENA, "anvil", "forge_hammer")["reason"], "too_young", "a child of the family does not work")


# --- Rechazos con su motivo ------------------------------------------------------------------------------------------

func _refused(sim: Sim, o: Dictionary, reason: String, msg: String) -> void:
	var h := sim.state_hash()
	var r := Orders.apply(sim, o)
	eq(r["reason"], reason, msg)
	check(not r["ok"], msg + " refused")
	eq(sim.state_hash(), h, msg + ": nothing changed")


func test_each_refusal_has_its_reason() -> void:
	var sim := _sim(7, [HUGO, TOMAS, ELENA])
	var w := {"type": "work_at", "actor": HUGO, "building": FORGE, "zone": "anvil", "recipe": "forge_sword",
		"mode": "normal"}
	_refused(sim, w.merged({"actor": "chr_9999"}, true), "unknown_actor", "nobody")
	_refused(sim, w.merged({"building": "bld_9999"}, true), "unknown_building", "no building")
	_refused(sim, w.merged({"actor": MARTA}, true), "not_your_building", "another family")
	_refused(sim, w.merged({"actor": HUGO}, true), "missing_inputs", "no ingots yet")
	sim.state.characters[HUGO]["location"] = ""
	_refused(sim, w, "not_inside", "outside")
	_inside(sim, HUGO)
	_refused(sim, w.merged({"zone": "cellar"}, true), "unknown_station", "no such station")
	_refused(sim, w.merged({"recipe": "bake_bread"}, true), "unknown_recipe", "no such recipe")
	_refused(sim, w.merged({"zone": "furnace"}, true), "wrong_station", "sword at the furnace")
	_refused(sim, w.merged({"mode": "sloppy"}, true), "unknown_mode", "no such mode")
	_refused(sim, w.merged({"actor": TOMAS}, true), "skill_too_low", "Tomás craft 2 < 4")
	_refused(sim, w.merged({"zone": "furnace", "recipe": "forge_steel"}, true), "needs_upgrade", "steel locked")
	sim.state.buildings[FORGE]["state"] = "damaged"
	_refused(sim, w.merged({"zone": "furnace", "recipe": "forge_ingot"}, true), "building_not_ready", "damaged")
	sim.state.buildings[FORGE]["state"] = "normal"
	check(Orders.apply(sim, w.merged({"actor": ELENA, "zone": "furnace", "recipe": "forge_ingot"}, true))["ok"],
		"Elena takes the furnace")
	_refused(sim, w.merged({"zone": "furnace", "recipe": "forge_ingot"}, true), "station_busy", "furnace taken")
	# stop_work / master_touch
	_refused(sim, {"type": "stop_work", "actor": HUGO}, "not_working", "stop without a job")
	var t := {"type": "master_touch", "actor": HUGO, "building": FORGE, "zone": "furnace"}
	_refused(sim, t, "not_at_station", "touch at another's station")
	_refused(sim, t.merged({"actor": ELENA, "zone": "anvil"}, true), "not_at_station", "touch where she is not")
	sim.state.buildings[FORGE]["zones"]["anvil"]["occupant"] = HUGO
	sim.state.characters[HUGO]["station"] = "anvil"
	_refused(sim, t.merged({"zone": "anvil"}, true), "not_working", "touch with no job")
	_refused(sim, t.merged({"actor": ELENA}, true), "not_careful", "touch in normal mode")
	check(Orders.apply(sim, {"type": "work_at", "actor": ELENA, "building": FORGE, "zone": "furnace",
		"recipe": "forge_ingot", "mode": "careful"})["ok"], "Elena now careful")
	_refused(sim, t.merged({"actor": ELENA}, true), "no_window", "touch before the window")
	_run(sim, 15)
	check(Orders.apply(sim, t.merged({"actor": ELENA}, true))["ok"], "touch in the window")
	_refused(sim, t.merged({"actor": ELENA}, true), "already_touched", "once per cycle")
	var st := _storage(sim)
	for it: String in ["flour", "cloth", "planks", "bread", "saw", "needle", "document"]:
		check(Inventory.add(st, cat, it, Inventory.NORMAL, 1), "fills with %s" % it)
	check(Inventory.add(st, cat, "iron_ingot", Inventory.NORMAL, 3), "3 ingots: the stack stays after taking 2")
	eq((st["stacks"] as Array).size(), 10, "storage full")
	_refused(sim, w, "storage_full", "no room for any sword quality")


# --- Consultas de la UI ----------------------------------------------------------------------------------------------

## recipe_options without its UI extras (reason, stock): recipe and status only.
func _rs(opts: Array) -> Array:
	return opts.map(func(o: Dictionary) -> Dictionary: return {"recipe": o["recipe"], "status": o["status"]})


func test_recipe_options_and_job_view() -> void:
	var sim := _sim(7, [HUGO, TOMAS])
	eq(_rs(Production.recipe_options(sim, HUGO, FORGE, "furnace")), [{"recipe": "forge_ingot", "status": "ok"},
		{"recipe": "forge_steel", "status": "locked"}], "furnace for Hugo")
	eq(_rs(Production.recipe_options(sim, TOMAS, FORGE, "anvil")), [{"recipe": "forge_armor", "status": "locked"},
		{"recipe": "forge_hammer", "status": "missing_inputs"}, {"recipe": "forge_sword", "status": "locked"}],
		"anvil for Tomás (craft 2)")
	eq(Production.job_view(sim, FORGE, "anvil"), {}, "no job")
	_work(sim, HUGO, "furnace", "forge_ingot")
	_run(sim, 30)
	var v := Production.job_view(sim, FORGE, "furnace")
	eq(str(v["actor"]), HUGO, "actor")
	near(float(v["progress"]), 0.5, 0.001, "half way")
	eq(v["window_open"], false, "no window in normal")


# --- Guardar/cargar a mitad de ciclo ---------------------------------------------------------------------------------

func test_save_and_load_mid_cycle_goes_on_the_same() -> void:
	var a := _sim(31)
	Inventory.add(_storage(a), cat, "iron_ingot", Inventory.NORMAL, 4)
	check(_work(a, HUGO, "anvil", "forge_sword", "careful")["ok"], "careful sword")
	_run(a, 130)  # inside the window
	check(Orders.apply(a, {"type": "master_touch", "actor": HUGO, "building": FORGE, "zone": "anvil"})["ok"], "touch")
	_run(a, 10)
	var text := JSON.stringify(a.state.to_dict())
	var r := SaveFile.from_text(text)
	check(r["ok"], "loads")
	var b := Sim.new(r["state"], cat)
	eq(b.state_hash(), a.state_hash(), "same state after load")
	_run(a, 700)
	_run(b, 700)
	eq(b.state_hash(), a.state_hash(), "same state 700 min later (two swords done)")
	eq(Inventory.count(_storage(b), "sword"), 2, "two swords")
