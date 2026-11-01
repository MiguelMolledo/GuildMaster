extends "res://tests/test_case.gd"
## H4 · production queue (GDD 4.7.4, docs/contratos/h4_empleados.md, zone «cola»): the queue orders, set_role, the
## per-unit resolution with dependencies, strict roles, skipped entries with notices, employees' speed/efficiency,
## and the «2 empleados» scenario (3 days, the forge produces without the player, each at its station).

const FORGE: String = "bld_0001"
const PLAYER: String = "chr_0001"
const JOAN: String = "chr_0007"    # journeyman, craft 5, role anvil
const AGNES: String = "chr_0008"   # apprentice, craft 2, role furnace

var cat := Catalog.load_from()


func _sim(id: String = "two_employees") -> Sim:
	return Sim.new(NewGame.from_scenario(id, 1)["state"], cat)


## two_employees with another queue and storage. `only_joan`: Agnès has no job (Joan alone, with `joan_role`).
func _setup(entries: Array, stock: Dictionary, only_joan: bool = false, joan_role: String = "anvil") -> Sim:
	var sim := _sim()
	var st := sim.state
	var b: Dictionary = st.buildings[FORGE]
	b["inventory"]["stacks"] = []
	for item: String in stock:
		Inventory.add(b["inventory"], cat, item, 0, int(stock[item]))
	b["queue"] = {"entries": [], "loop": false, "paused": false}
	for e: Array in entries:
		eq(Orders.apply(sim, {"type": "queue_add", "actor": PLAYER, "building": FORGE, "recipe": e[0], "qty": e[1]}),
			Orders.ok(), "queue_add %s" % e[0])
	if only_joan:
		st.characters[AGNES]["job"] = null
	st.characters[JOAN]["job"]["role"] = joan_role
	return sim


func _count(sim: Sim, item: String) -> int:
	return Inventory.count(sim.state.buildings[FORGE]["inventory"], item)


## Runs `minutes` steps and returns every event.
func _run(sim: Sim, minutes: int) -> Array:
	var all: Array = []
	for i: int in minutes:
		all.append_array(sim.step())
	return all


## The events of `type` of the forge (or without building), not the rival's.
func _of(events: Array, type: String) -> Array:
	return events.filter(func(e: Dictionary) -> bool:
		return str(e["type"]) == type and str(e.get("building", FORGE)) == FORGE)


## The id of the entry at `i` of the forge's queue.
func _eid(sim: Sim, i: int) -> String:
	return str(WorkQueue.view(sim, FORGE)["entries"][i]["id"])


func _notice_keys(sim: Sim) -> Array:
	return sim.state.notices.map(func(n: Dictionary) -> String: return str(n["key"]))


# --- Orders ----------------------------------------------------------------------------------------------------------

func test_queue_add_validates() -> void:
	var sim := _setup([], {})
	var add := func(o: Dictionary) -> Dictionary:
		var base := {"type": "queue_add", "actor": PLAYER, "building": FORGE, "recipe": "forge_sword", "qty": 1}
		base.merge(o, true)
		return Orders.apply(sim, base)
	eq(add.call({}), Orders.ok(), "1 sword")
	eq(add.call({"qty": 10}), Orders.ok(), "10")
	eq(add.call({"qty": -1}), Orders.ok(), "infinite")
	eq(add.call({"qty": 5.0}), Orders.ok(), "a whole float is a number")
	eq(add.call({"qty": 0})["reason"], "bad_quantity", "0")
	eq(add.call({"qty": -2})["reason"], "bad_quantity", "-2")
	eq(add.call({"qty": "x"})["reason"], "bad_quantity", "garbage")
	eq(add.call({"qty": 1.5})["reason"], "bad_quantity", "half a sword")
	eq(add.call({"recipe": "bake_bread"})["reason"], "unknown_recipe", "unknown recipe")
	eq(add.call({"building": "bld_0002"})["reason"], "not_your_building", "the rival's forge")
	eq(add.call({"building": "bld_9999"})["reason"], "unknown_building", "no such building")
	eq(add.call({"actor": "chr_9999"})["reason"], "unknown_actor", "nobody")
	sim.state.buildings["bld_0004"]["owner"] = "fam_0001"
	eq(add.call({"building": "bld_0004"})["reason"], "wrong_building", "a sword is not made in a house")
	var v := WorkQueue.view(sim, FORGE)
	eq(v["entries"].map(func(e: Dictionary) -> int: return int(e["qty"])), [1, 10, -1, 5], "added at the end")
	var ids: Array = v["entries"].map(func(e: Dictionary) -> String: return str(e["id"]))
	check(ids.all(func(x: String) -> bool: return x.begins_with("qen_")), "qen ids")
	eq(ids.size(), 4, "4 different ids")
	check(ids[0] != ids[1] and ids[1] != ids[2] and ids[2] != ids[3], "never reused")
	eq(str(v["entries"][0]["status"]), "ok", "status ok")


func test_queue_remove_move_loop_pause() -> void:
	var sim := _setup([["forge_sword", 1], ["forge_ingot", 5], ["forge_hammer", 10]], {})
	var ids := func() -> Array:
		return WorkQueue.view(sim, FORGE)["entries"].map(func(e: Dictionary) -> String: return str(e["recipe"]))
	var o := {"actor": PLAYER, "building": FORGE}
	var sword := _eid(sim, 0)
	var hammer := _eid(sim, 2)
	eq(Orders.apply(sim, o.merged({"type": "queue_move", "entry": hammer, "to": 0}, true)), Orders.ok(), "move to 0")
	eq(ids.call(), ["forge_hammer", "forge_sword", "forge_ingot"], "hammer first")
	eq(Orders.apply(sim, o.merged({"type": "queue_move", "entry": hammer, "to": 99}, true)), Orders.ok(), "clamped")
	eq(ids.call(), ["forge_sword", "forge_ingot", "forge_hammer"], "hammer last")
	eq(Orders.apply(sim, o.merged({"type": "queue_move", "entry": hammer, "to": -5}, true)), Orders.ok(), "clamped low")
	eq(ids.call()[0], "forge_hammer", "hammer first again")
	eq(Orders.apply(sim, o.merged({"type": "queue_move", "entry": "qen_0099", "to": 0}, true))["reason"], "unknown_entry",
		"unknown entry")
	eq(Orders.apply(sim, o.merged({"type": "queue_remove", "entry": sword}, true)), Orders.ok(), "remove")
	eq(ids.call(), ["forge_hammer", "forge_ingot"], "sword gone")
	eq(Orders.apply(sim, o.merged({"type": "queue_remove", "entry": sword}, true))["reason"], "unknown_entry", "twice")
	eq(Orders.apply(sim, o.merged({"type": "queue_loop", "on": true}, true)), Orders.ok(), "loop on")
	eq(Orders.apply(sim, o.merged({"type": "queue_pause", "on": true}, true)), Orders.ok(), "pause on")
	var v := WorkQueue.view(sim, FORGE)
	check(bool(v["loop"]) and bool(v["paused"]), "loop and paused")
	eq(Orders.apply(sim, o.merged({"type": "queue_pause", "on": "yes"}, true)), Orders.ok(), "garbage = off")
	check(not bool(WorkQueue.view(sim, FORGE)["paused"]), "not paused")
	eq(Orders.apply(sim, {"type": "queue_loop", "actor": "chr_0006", "building": FORGE, "on": true})["reason"],
		"not_your_building", "the rival cannot touch my queue")
	var changed := _of(sim.step([o.merged({"type": "queue_loop", "on": false}, true)]), "queue_changed")
	eq(changed.size(), 1, "queue_changed")
	eq(changed[0], {"type": "queue_changed", "building": FORGE, "family": "fam_0001"}, "its shape")


func test_set_role() -> void:
	var sim := _setup([], {})
	var o := {"type": "set_role", "actor": PLAYER, "employee": AGNES}
	eq(Orders.apply(sim, o.merged({"role": "anvil"}, true)), Orders.ok(), "anvil")
	eq(str(sim.state.characters[AGNES]["job"]["role"]), "anvil", "role saved")
	eq(Orders.apply(sim, o.merged({"role": "any"}, true)), Orders.ok(), "any")
	eq(Orders.apply(sim, o.merged({"role": "storage"}, true))["reason"], "unknown_role", "storage is no task")
	eq(Orders.apply(sim, o.merged({"role": "oven"}, true))["reason"], "unknown_role", "no oven")
	eq(Orders.apply(sim, o.merged({"employee": "chr_0009", "role": "any"}, true))["reason"], "not_your_employee",
		"an unemployed neighbour")
	eq(Orders.apply(sim, o.merged({"actor": "chr_0006", "role": "any"}, true))["reason"], "not_your_employee",
		"the rival cannot")
	var ev := sim.step([o.merged({"role": "furnace"}, true)])
	eq(_of(ev, "role_changed"), [{"type": "role_changed", "actor": PLAYER, "employee": AGNES, "role": "furnace"}],
		"role_changed")


# --- Employees' cycles (Production, only for employees) --------------------------------------------------------------

func test_employee_speed_and_efficiency() -> void:
	var sim := _sim()
	var ingot: Dictionary = cat.recipes()["forge_ingot"]
	var sword: Dictionary = cat.recipes()["forge_sword"]
	eq(Production.employee_cycle_minutes(sim, AGNES, ingot, "normal"), 120, "apprentice ×0,5: 1 h -> 2 h")
	eq(Production.employee_cycle_minutes(sim, JOAN, sword, "normal"), 180, "journeyman ×1: 3 h")
	eq(Production.output_units(sim, AGNES, FORGE, ingot), 1, "apprentice 0,5 × 0,8: still 1 unit")
	sim.state.characters[JOAN]["rank"] = "master"
	sim.state.characters[JOAN]["job"]["loyalty"] = 80
	eq(Production.employee_cycle_minutes(sim, JOAN, sword, "normal"), 120, "master ×1,5: 3 h -> 2 h")
	eq(Production.output_units(sim, JOAN, FORGE, sword), 2, "master 150 % loyal: 2 units")
	sim.state.characters[JOAN]["job"]["loyalty"] = 50
	eq(Production.output_units(sim, JOAN, FORGE, sword), 1, "master unhappy 1,5 × 0,8 = 1,2: 1 unit")
	eq(Production.output_units(sim, PLAYER, FORGE, sword), 1, "the owner: the recipe's qty")
	eq(Production.cycle_minutes(cat, sword, "normal"), 180, "the owner's cycle does not change")


func test_employee_does_not_repeat_alone() -> void:
	# Joan (any) alone, 1 ingot: one cycle, then nothing more (the queue decides, not the auto-repeat).
	var sim := _setup([["forge_ingot", 1]], {"iron": 20}, true, "any")
	var ev := _run(sim, 960)  # 04:30 -> 20:30
	var starts := _of(ev, "work_started")
	eq(starts.size(), 1, "one cycle")
	eq(_count(sim, "iron_ingot"), 1, "one ingot")
	eq(_count(sim, "iron"), 18, "2 iron used")
	eq(WorkQueue.view(sim, FORGE)["entries"], [], "the finished entry leaves the queue")
	check("notice.queue_empty" in _notice_keys(sim), "then: nothing to produce")


# --- Resolution with dependencies ------------------------------------------------------------------------------------

func test_dependencies_one_sword_makes_just_its_ingots() -> void:
	# Joan (any) alone: 1 sword with iron and coal but no ingots -> 2 ingots, then the sword. Never more ingots.
	var sim := _setup([["forge_sword", 1]], {"iron": 40, "coal": 10}, true, "any")
	var first := _eid(sim, 0)
	var ev := _run(sim, 960)
	var made: Array = _of(ev, "work_started").map(func(e: Dictionary) -> String: return str(e["recipe"]))
	eq(made, ["forge_ingot", "forge_ingot", "forge_sword"], "the ingots of that sword first, then the sword")
	eq(_count(sim, "sword"), 1, "1 sword")
	eq(_count(sim, "iron_ingot"), 0, "no ingot left over")
	eq(_count(sim, "iron"), 36, "4 iron")
	eq(_count(sim, "coal"), 9, "1 coal")
	var done := _of(ev, "queue_entry_done")
	eq(done, [{"type": "queue_entry_done", "building": FORGE, "entry": first, "recipe": "forge_sword"}],
		"queue_entry_done")


func test_dependencies_use_the_stock_first() -> void:
	var sim := _setup([["forge_sword", 1]], {"iron": 40, "coal": 10, "iron_ingot": 1}, true, "any")
	var made: Array = _of(_run(sim, 960), "work_started").map(func(e: Dictionary) -> String: return str(e["recipe"]))
	eq(made, ["forge_ingot", "forge_sword"], "1 ingot in stock: only 1 more")


# --- Strict roles (BUG-023) ------------------------------------------------------------------------------------------

func test_strict_role_only_its_station() -> void:
	# Only ingots in the queue: Joan (anvil) never works at the furnace, even free; Agnès (furnace) does.
	var sim := _setup([["forge_ingot", -1]], {"iron": 60})
	var ev := _run(sim, 960)
	var by_joan := _of(ev, "work_started").filter(func(e: Dictionary) -> bool: return str(e["actor"]) == JOAN)
	eq(by_joan.size(), 0, "Joan never works")
	check(_of(ev, "work_started").size() >= 3, "Agnès smelts")
	var idle := _of(ev, "employee_idle")
	check(idle.any(func(e: Dictionary) -> bool: return str(e["employee"]) == JOAN and str(e["reason"]) == "no_task"),
		"Joan idle: nothing for his role")
	check("notice.employee_idle" in _notice_keys(sim), "idle employee notice")
	# At midday he is the idle icon over the forge.
	var sim2 := _setup([["forge_ingot", -1]], {"iron": 60})
	_run(sim2, 420)  # 11:30
	eq(WorkQueue.idle_employees(sim2, FORGE), [JOAN], "Joan is the idle one")
	eq(WorkQueue.idle_buildings(sim2, "fam_0001"), [FORGE], "the forge shows the icon")
	eq(WorkQueue.task_of(sim2, JOAN), {}, "Joan has no task")
	eq(str(WorkQueue.task_of(sim2, AGNES).get("zone", "")), "furnace", "Agnès at the furnace")


func test_any_role_goes_where_needed() -> void:
	var sim := _setup([["forge_ingot", 2]], {"iron": 60}, true, "any")
	var ev := _run(sim, 960)
	eq(_of(ev, "work_started").map(func(e: Dictionary) -> String: return str(e["zone"])), ["furnace", "furnace"],
		"Joan (any) smelts")


func test_fixed_role_lacking_craft_skips_with_notice() -> void:
	# Agnès moved to the anvil (craft 2 < sword 4) and Joan away: the swords cannot be made.
	var sim := _setup([["forge_sword", 1], ["forge_hammer", 1]], {"iron": 60, "coal": 10, "iron_ingot": 4})
	var first := _eid(sim, 0)
	sim.state.characters[JOAN]["job"] = null
	sim.state.characters[AGNES]["job"]["role"] = "anvil"
	var ev := _run(sim, 960)
	var blocked := _of(ev, "queue_entry_blocked")
	check(blocked.any(func(e: Dictionary) -> bool: return str(e["entry"]) == first \
		and str(e["reason"]) == "skill_too_low"), "the sword is skipped: skill_too_low")
	eq(_count(sim, "hammer"), 1, "the hammer (craft 2) is made")
	eq(_count(sim, "sword"), 0, "no sword")
	check("notice.queue_cannot_make" in _notice_keys(sim), "notice")


# --- Impossible entries ----------------------------------------------------------------------------------------------

func test_impossible_entry_is_skipped_with_notice() -> void:
	# No coal: the swords cannot be made (raw material missing) -> notice and skip; the ingots after it are made.
	var sim := _setup([["forge_sword", 2], ["forge_ingot", 2]], {"iron": 60})
	var first := _eid(sim, 0)
	var ev := _run(sim, 960)
	var blocked := _of(ev, "queue_entry_blocked")
	check(blocked.size() >= 1, "blocked event")
	eq(blocked[0], {"type": "queue_entry_blocked", "building": FORGE, "entry": first, "reason": "missing_inputs"},
		"its shape")
	eq(_notice_keys(sim).count("notice.queue_missing_inputs"), 1, "one notice, not one per minute")
	var n: Dictionary = sim.state.notices.filter(func(x: Dictionary) -> bool:
		return str(x["key"]) == "notice.queue_missing_inputs")[0]
	eq(n["params"]["recipe"], "forge_sword", "the notice names the recipe")
	eq(str(n["target"]), FORGE, "and centres on the forge")
	eq(_count(sim, "iron_ingot"), 2, "the next entry was made")
	eq(_count(sim, "sword"), 0, "no sword")
	var v := WorkQueue.view(sim, FORGE)
	eq(v["entries"].size(), 1, "the ingots are done and gone")
	eq(str(v["entries"][0]["status"]), "missing_inputs", "the sword shows why")
	eq(str(v["stalled"]), "missing_inputs", "then nothing else can be made: stalled")
	check("notice.queue_stalled" in _notice_keys(sim), "general notice")


func test_nothing_possible_general_notice_and_idle() -> void:
	var sim := _setup([["forge_sword", 1], ["forge_hammer", 1]], {})
	var ev := _run(sim, 420)  # 11:30
	eq(_of(ev, "work_started").size(), 0, "nothing starts")
	var stalled := _of(ev, "queue_stalled")
	eq(stalled.size(), 1, "one stalled event")
	eq(str(stalled[0]["reason"]), "missing_inputs", "why")
	eq(_notice_keys(sim).count("notice.queue_stalled"), 1, "one general notice")
	eq(WorkQueue.idle_employees(sim, FORGE), [JOAN, AGNES], "both idle")
	# Coal and iron arrive: the queue moves again.
	Inventory.add(sim.state.buildings[FORGE]["inventory"], cat, "iron", 0, 20)
	Inventory.add(sim.state.buildings[FORGE]["inventory"], cat, "coal", 0, 5)
	ev = _run(sim, 30)
	eq(_of(ev, "queue_stalled").map(func(e: Dictionary) -> String: return str(e["reason"])), [""], "back to work")
	check(_of(ev, "work_started").size() >= 1, "someone starts")


# --- Loop, pause, remove ---------------------------------------------------------------------------------------------

func test_loop_starts_again() -> void:
	var sim := _setup([["forge_ingot", 1]], {"iron": 60}, true, "any")
	sim.state.buildings[FORGE]["queue"]["loop"] = true
	var ev := _run(sim, 960)
	check(_of(ev, "work_started").size() >= 5, "it keeps going")
	eq(WorkQueue.view(sim, FORGE)["entries"].size(), 1, "the entry stays")


func test_pause_and_remove_mid_cycle() -> void:
	var sim := _setup([["forge_ingot", -1]], {"iron": 60}, true, "any")
	_run(sim, 180)  # 07:30: Joan is smelting
	check(not WorkQueue.task_of(sim, JOAN).is_empty(), "working")
	sim.step([{"type": "queue_pause", "actor": PLAYER, "building": FORGE, "on": true}])
	var ev := _run(sim, 240)
	eq(_of(ev, "work_done").size(), 1, "the running cycle ends")
	eq(_of(ev, "work_started").size(), 0, "paused: nothing new")
	sim.step([{"type": "queue_pause", "actor": PLAYER, "building": FORGE, "on": false}])
	_run(sim, 5)
	check(not WorkQueue.task_of(sim, JOAN).is_empty(), "working again")
	var before := _count(sim, "iron_ingot")
	sim.step([{"type": "queue_remove", "actor": PLAYER, "building": FORGE, "entry": _eid(sim, 0)}])
	ev = _run(sim, 240)
	eq(_of(ev, "work_interrupted").size(), 0, "removing does not interrupt")
	eq(_count(sim, "iron_ingot"), before + 1, "the running cycle ends into the storage")
	eq(_of(ev, "work_started").size(), 0, "and nothing more")


# --- The «2 empleados» scenario --------------------------------------------------------------------------------------

func test_two_employees_three_days() -> void:
	var sim := _sim()
	var st := sim.state
	var swords_started := 0
	var ingots_done := 0
	var zones := {JOAN: {}, AGNES: {}}
	var bad_night: Array = []
	var bad_ingots: Array = []
	for i: int in 3 * Clock.MINUTES_PER_DAY:
		var ev := sim.step()
		for e: Dictionary in ev:
			if str(e["type"]) == "work_started" and str(e["building"]) == FORGE:
				zones[str(e["actor"])][str(e["zone"]) + ":" + str(e["recipe"])] = true
				if str(e["recipe"]) == "forge_sword":
					swords_started += 1
			if str(e["type"]) == "work_interrupted" and str(e["building"]) == FORGE and str(e["zone"]) == "anvil":
				swords_started -= 1  # interrupted at night: its ingots went back to the storage (D11)
			if str(e["type"]) == "work_done" and str(e["building"]) == FORGE and str(e["item"]) == "iron_ingot":
				ingots_done += int(e["qty"])
		var now := int(st.clock["minute"])
		check(str(st.characters[PLAYER]["location"]) != FORGE, "the player never enters")
		if Clock.phase(now, cat.time) == "night":
			for c: String in [JOAN, AGNES]:
				if str(st.characters[c]["location"]) == FORGE:
					bad_night.append("%s at %s" % [c, Routines._hhmm(now)])
		# Ingots made and not yet in a started sword: at most the next sword's 2, plus the 2 of a sword interrupted at
		# night (given back, D11) waiting for the morning.
		var spare := ingots_done - 2 * swords_started
		if spare < 0 or spare > 4:
			bad_ingots.append("%s spare=%d" % [Routines._hhmm(now), spare])
	eq(bad_night, [], "nobody inside the forge at night")
	eq(bad_ingots, [], "just the ingots of the next sword (never a stock)")
	var swords := _count(sim, "sword")
	check(swords >= 6, "the forge produces swords alone (got %d)" % swords)
	eq(zones[AGNES].keys(), ["furnace:forge_ingot"], "Agnès only at the furnace")
	eq(zones[JOAN].keys(), ["anvil:forge_sword"], "Joan only at the anvil")
	check(Inventory.count(st.buildings[FORGE]["inventory"], "iron_ingot") <= 4, "no pile of ingots")
	eq(ingots_done, 2 * swords, "every ingot made went into a sword (10 swords, 20 ingots)")
	for c: String in [JOAN, AGNES]:
		eq(str(st.characters[c]["location"]), str(st.characters[c]["home"]), "%s sleeps at home" % c)


func test_production_runs_with_no_view() -> void:
	# The sim alone (RefCounted, no node, no scene): nobody looks at the forge and it produces (L1, BUG-024).
	var sim := _sim()
	check(sim is RefCounted, "the sim is no node")
	sim.run_minutes(Clock.MINUTES_PER_DAY)
	check(_count(sim, "sword") >= 2, "swords on day 1 with 0 views")


func test_save_and_load_mid_day_goes_on_the_same() -> void:
	var a := _sim()
	a.run_minutes(Clock.MINUTES_PER_DAY + 380)  # day 2, 10:50: both at work, cycles running
	check(not WorkQueue.task_of(a, JOAN).is_empty() or not WorkQueue.task_of(a, AGNES).is_empty(), "mid-cycle")
	var b := Sim.new(SaveFile.from_text(JSON.stringify(a.state.to_dict()))["state"], cat)
	eq(b.state_hash(), a.state_hash(), "same state after loading")
	eq(SaveFile.canonical(b.state.buildings[FORGE]["queue"]), SaveFile.canonical(a.state.buildings[FORGE]["queue"]),
		"queue memory round-trips")
	eq(SaveFile.canonical(b.state.characters[JOAN]["routine"]), SaveFile.canonical(a.state.characters[JOAN]["routine"]),
		"routine memory round-trips")
	for i: int in Clock.MINUTES_PER_DAY:
		a.step()
		b.step()
	eq(b.state_hash(), a.state_hash(), "a day later, the same")
	eq(_count(b, "sword"), _count(a, "sword"), "same swords")
