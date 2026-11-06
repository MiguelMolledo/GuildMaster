extends "res://tests/test_case.gd"
const Pins = preload("res://tests/balance_pins.gd")
## H5 «arbol» (docs/contratos/h5_mejoras.md): buy_upgrade (requirements, gold and materials, refusals), the works
## (duration, what they block, Upgrades.step), each effect measured in the system that reads it (speed, quality, new
## stations, storage, places, allowed ranks, security), save/load with works in progress and the ledger.

const FORGE: String = "bld_0001"
const FAM: String = "fam_0001"
const HERO: String = "chr_0001"
const JOAN: String = "chr_0007"   # journeyman, role anvil
const AGNES: String = "chr_0008"  # apprentice, role furnace

var cat := Pins.classic(Catalog.load_from())  # pre-H5 figures: see tests/balance_pins.gd


func _sim(id: String = "forge_upgrades", seed: int = 1) -> Sim:
	return Sim.new(NewGame.from_scenario(id, seed)["state"], cat)


func _buy(sim: Sim, id: String, actor: String = HERO) -> Dictionary:
	return Orders.apply(sim, {"type": "buy_upgrade", "actor": actor, "building": FORGE, "upgrade": id})


## Runs `minutes` steps and returns every event.
func _run(sim: Sim, minutes: int) -> Array:
	var all: Array = []
	for i: int in minutes:
		all.append_array(sim.step())
	return all


func _of(events: Array, type: String, bld: String = "") -> Array:
	return events.filter(func(e: Dictionary) -> bool:
		return str(e["type"]) == type and (bld == "" or str(e.get("building", "")) == bld))


func _fingerprint(sim: Sim) -> Array:
	var b: Dictionary = sim.state.buildings[FORGE]
	return [Money.gold(sim.state, FAM), JSON.stringify(b["inventory"]), b["upgrade_work"], b["upgrades"].duplicate(),
		sim.state.ledger["entries"].size()]


# --- Buying -----------------------------------------------------------------------------------------------------

func test_buy_pays_and_starts_the_works() -> void:
	var sim := _sim()
	var st := sim.state
	var inv: Dictionary = st.buildings[FORGE]["inventory"]
	var now := int(st.clock["minute"])
	var entries := int(st.ledger["entries"].size())
	sim.events = []
	var r := _buy(sim, "forge_production_2")
	check(r["ok"], "buys Temple avanzado (%s)" % r.get("reason", ""))
	eq(Money.gold(st, FAM), 992, "8 gold paid")
	eq(Inventory.count(inv, "iron_ingot"), 5, "5 of the 10 ingots taken from the storage")
	eq(st.buildings[FORGE]["upgrade_work"], {"upgrade": "forge_production_2", "actor": HERO, "start": now,
		"end": now + 1440, "mode": Upgrades.CLOSED}, "works of 1 day (closed: the rule pinned before Equilibrio 9)")
	var e: Dictionary = st.ledger["entries"][entries]
	eq([e["category"], e["amount"], e["ref"], e["building"], e["actor"]], ["upgrades", -8, "forge_production_2", FORGE,
		HERO], "the ledger entry")
	var started := _of(sim.events, "upgrade_started")
	eq(started.size(), 1, "upgrade_started")
	eq(started[0], {"type": "upgrade_started", "actor": HERO, "family": FAM, "building": FORGE,
		"upgrade": "forge_production_2", "start": now, "end": now + 1440}, "its fields")
	check(Upgrades.under_works(st, FORGE), "under works")
	eq(Upgrades.status_of(sim, HERO, FORGE, "forge_production_2"), "in_works", "in works")
	eq(Upgrades.status_of(sim, HERO, FORGE, "forge_quality_2"), "busy", "one works at a time")


func test_materials_lowest_quality_first() -> void:
	var sim := _sim()
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	Inventory.remove(inv, "iron_ingot", Inventory.NORMAL, 8)
	Inventory.add(inv, cat, "iron_ingot", Inventory.GOOD, 4)
	check(_buy(sim, "forge_production_2")["ok"], "buys with 2 normal + 4 good ingots")
	eq([Inventory.count(inv, "iron_ingot", Inventory.NORMAL), Inventory.count(inv, "iron_ingot", Inventory.GOOD)], [0, 1],
		"the 2 normal first, then 3 good")


func test_refusals_change_nothing() -> void:
	var sim := _sim()
	var st := sim.state
	var cases := [
		["forge_nothing", HERO, "unknown_upgrade"],
		["forge_production_1", HERO, "owned"],
		["forge_production_3", HERO, "needs_upgrade"],
		["forge_staff_3", HERO, "needs_upgrade"],
		["forge_production_2", JOAN, "not_your_building"],
		["forge_production_2", "chr_9999", "unknown_actor"],
	]
	for c: Array in cases:
		var before := _fingerprint(sim)
		eq(str(_buy(sim, str(c[0]), str(c[1]))["reason"]), str(c[2]), "%s by %s" % [c[0], c[1]])
		eq(_fingerprint(sim), before, "%s: nothing changes" % c[0])
	eq(str(Orders.apply(sim, {"type": "buy_upgrade", "actor": HERO, "building": "bld_9999",
		"upgrade": "forge_production_2"})["reason"]), "unknown_building", "unknown building")
	eq(str(Orders.apply(sim, {"type": "buy_upgrade", "actor": HERO, "building": "bld_0003",
		"upgrade": "forge_production_2"})["reason"]), "not_your_building", "the public armory")
	# Attribute of the actor: Elena (craft 4) cannot buy Grabado fino (craft 5); Hugo (craft 7) can.
	eq(str(_buy(sim, "forge_quality_2", "chr_0002")["reason"]), "stat_too_low", "Elena: craft 4 < 5")
	# Title of the family: Fachada noble needs Ciudadano (no title field until H9: common).
	Upgrades.complete(sim, FORGE, "forge_facade_1")
	Upgrades.complete(sim, FORGE, "forge_facade_2")
	eq(str(_buy(sim, "forge_facade_3")["reason"]), "title_too_low", "Fachada noble: Ciudadano")
	# Gold and materials.
	st.families[FAM]["gold"] = 7
	var before := _fingerprint(sim)
	eq(str(_buy(sim, "forge_production_2")["reason"]), "not_enough_gold", "7 < 8 gold")
	eq(_fingerprint(sim), before, "no gold, nothing changes")
	st.families[FAM]["gold"] = 1000
	Inventory.remove(st.buildings[FORGE]["inventory"], "iron_ingot", Inventory.NORMAL, 6)
	before = _fingerprint(sim)
	eq(str(_buy(sim, "forge_production_2")["reason"]), "missing_materials", "4 < 5 ingots")
	eq(_fingerprint(sim), before, "no materials, nothing changes")
	# One works at a time.
	check(_buy(sim, "forge_quality_2")["ok"], "Grabado fino starts")
	before = _fingerprint(sim)
	eq(str(_buy(sim, "forge_staff_2")["reason"]), "busy", "another works: busy")
	eq(str(_buy(sim, "forge_quality_2")["reason"]), "in_works", "the same: in_works")
	eq(_fingerprint(sim), before, "nothing changes")


func test_buy_through_the_sim_is_a_management_order() -> void:
	var sim := _sim()
	var ev := sim.step([{"type": "buy_upgrade", "actor": HERO, "building": FORGE, "upgrade": "forge_production_2"}])
	check(Upgrades.under_works(sim.state, FORGE), "the works started in the same step")
	eq(_of(ev, "order_refused").size(), 0, "not refused")
	eq(_of(ev, "upgrade_started").size(), 1, "upgrade_started in the step's events")


# --- Works --------------------------------------------------------------------------------------------------------

func test_works_last_what_the_data_says_and_finish_alone() -> void:
	for c: Array in [["forge_production_2", 1440], ["forge_staff_2", 2160]]:
		var sim := _sim()
		var id := str(c[0])
		var start := int(sim.state.clock["minute"])
		check(_buy(sim, id)["ok"], "buys %s" % id)
		var ev := _run(sim, int(c[1]) - 1)
		check(Upgrades.under_works(sim.state, FORGE), "%s: still under works one minute before the end" % id)
		check(not Upgrades.has(sim.state, FORGE, id), "%s: not finished yet" % id)
		eq(_of(ev, "upgrade_done").size(), 0, "%s: no upgrade_done before" % id)
		ev = _run(sim, 1)
		eq(int(sim.state.clock["minute"]), start + int(c[1]), "%s: the end minute" % id)
		check(Upgrades.has(sim.state, FORGE, id), "%s: finished at the end minute" % id)
		check(not Upgrades.under_works(sim.state, FORGE), "%s: works cleared" % id)
		eq(_of(ev, "upgrade_done").size(), 1, "%s: upgrade_done once" % id)
		var n := Notices.list(sim, FAM).filter(func(x: Dictionary) -> bool: return str(x["key"]) == "notice.upgrade_done")
		eq(n.size(), 1, "%s: notice" % id)
		eq([n[0]["severity"], n[0]["params"], n[0]["target"]], [Notices.INFO, {"building": FORGE, "upgrade": id}, FORGE],
			"%s: info notice targeting the building" % id)


func test_scenario_works_end_at_16_30() -> void:
	var sim := _sim("forge_upgrade_works")
	var end := int(sim.state.buildings[FORGE]["upgrade_work"]["end"])
	eq(int(sim.state.buildings[FORGE]["inventory"]["limit"]), 10, "10 stacks during the works")
	_run(sim, end - int(sim.state.clock["minute"]))
	check(Upgrades.has(sim.state, FORGE, "forge_capacity_2"), "Almacén ampliado finished")
	eq(Clock.minute_of_day(end), 16 * 60 + 30, "at 16:30")
	eq(int(sim.state.buildings[FORGE]["inventory"]["limit"]), 20, "storage 10 + 10 stacks")


func test_works_block_production() -> void:
	var sim := _sim()
	var st := sim.state
	# Let the employees start: from 04:30 to 09:00.
	var ev := _run(sim, 270)
	check(not _of(ev, "work_started", FORGE).is_empty(), "they worked before the works")
	var running := 0
	for z: String in st.buildings[FORGE]["zones"]:
		if st.buildings[FORGE]["zones"][z].get("job") is Dictionary:
			running += 1
	check(running > 0, "cycles running at 09:00 (%d)" % running)
	var iron := Inventory.count(st.buildings[FORGE]["inventory"], "iron")
	var held := 0
	for z: String in st.buildings[FORGE]["zones"]:
		var job: Variant = st.buildings[FORGE]["zones"][z].get("job")
		if job is Dictionary:
			for s: Dictionary in job["inputs"]:
				if str(s["item"]) == "iron":
					held += int(s["qty"])
	sim.events = []
	check(_buy(sim, "forge_production_2")["ok"], "buys during the day")
	eq(_of(sim.events, "work_interrupted", FORGE).size(), running, "the running cycles are interrupted")
	eq(Inventory.count(st.buildings[FORGE]["inventory"], "iron"), iron + held, "their inputs go back to the storage")
	ev = _run(sim, 600)  # until 19:00, all inside the works
	eq(_of(ev, "work_started", FORGE).size(), 0, "nobody starts a cycle during the works")
	eq(_of(ev, "work_done", FORGE).size(), 0, "nothing produced")
	var idle := _of(ev, "employee_idle").filter(func(e: Dictionary) -> bool: return str(e["reason"]) == "under_works")
	check(not idle.is_empty(), "employees idle with reason under_works")
	# The owner by hand: refused too.
	var hero: Dictionary = st.characters[HERO]
	hero["location"] = FORGE
	eq(str(Orders.apply(sim, {"type": "work_at", "actor": HERO, "building": FORGE, "zone": "anvil",
		"recipe": "forge_sword", "mode": "normal"})["reason"]), "under_works", "the owner cannot work either")
	eq(Production.may_work(sim, HERO, FORGE), "under_works", "may_work says why")
	# After the end, the queue hands work again.
	var left := int(st.buildings[FORGE]["upgrade_work"]["end"]) - int(st.clock["minute"])
	hero["location"] = ""
	ev = _run(sim, left + 1440)
	check(Upgrades.has(st, FORGE, "forge_production_2"), "finished")
	check(not _of(ev, "work_done", FORGE).is_empty(), "production comes back after the works")


# --- Effects ------------------------------------------------------------------------------------------------------

func test_speed_cycle_minutes() -> void:
	var sim := _sim()
	var sword: Dictionary = cat.recipes()["forge_sword"]
	var ingot: Dictionary = cat.recipes()["forge_ingot"]
	eq(Production.employee_cycle_minutes(sim, JOAN, sword, "normal"), 150, "journeyman 3 h / 1.2 (bellows)")
	eq(Production.employee_cycle_minutes(sim, AGNES, ingot, "normal"), 100, "apprentice 1 h / (0.5 × 1.2)")
	eq(Production.owner_cycle_minutes(sim, FORGE, sword, "normal"), 150, "the owner by hand: 3 h / 1.2")
	eq(Production.owner_cycle_minutes(sim, FORGE, sword, "careful"), 225, "careful 4.5 h / 1.2")
	Upgrades.complete(sim, FORGE, "forge_production_2")
	eq(Production.employee_cycle_minutes(sim, JOAN, sword, "normal"), 129, "temple ×1.4 replaces ×1.2: 180 / 1.4")
	sim.state.buildings[FORGE]["upgrades"] = []
	eq(Production.employee_cycle_minutes(sim, JOAN, sword, "normal"), 180, "without upgrades: 3 h")
	eq(Production.owner_cycle_minutes(sim, FORGE, sword, "normal"), 180, "owner without upgrades: 3 h")
	eq(Production.cycle_minutes(cat, sword, "normal"), 180, "the recipe's own length does not change")


## Production per working hour measured in the forge_upgrades scenario (seed 1): two days of the queue with the
## bellows (×1.2) and with Temple avanzado (×1.4) against the same forge without production upgrades.
func test_speed_production_per_day() -> void:
	var per := {}
	for variant: String in ["none", "bellows", "temple"]:
		var sim := _sim("forge_upgrades", 1)
		var b: Dictionary = sim.state.buildings[FORGE]
		b["upgrades"] = (b["upgrades"] as Array).filter(func(u: Variant) -> bool: return str(u) != "forge_production_1")
		if variant != "none":
			Upgrades.complete(sim, FORGE, "forge_production_1")
		if variant == "temple":
			Upgrades.complete(sim, FORGE, "forge_production_2")
		var ev := _run(sim, 2 * 1440)
		var cycles := 0
		var done := 0
		for e: Dictionary in _of(ev, "work_started"):
			if str(e["actor"]) == JOAN:
				cycles += 1
		for e: Dictionary in _of(ev, "work_done"):
			if str(e["actor"]) == JOAN or str(e["actor"]) == AGNES:
				done += 1
		per[variant] = {"joan_cycles": cycles, "done": done,
			"swords": _of(ev, "work_done", FORGE).filter(func(e: Dictionary) -> bool: return str(e["item"]) == "sword").size()}
	print("[test_econ_upgrades] producción en 2 días: %s" % per)
	check(int(per["bellows"]["done"]) > int(per["none"]["done"]), "bellows: more cycles done than without (%s)" % per)
	check(int(per["temple"]["done"]) > int(per["bellows"]["done"]), "temple: more than bellows (%s)" % per)
	check(int(per["temple"]["swords"]) >= int(per["none"]["swords"]), "at least as many swords (%s)" % per)


func test_quality_bonus() -> void:
	var sim := _sim()
	var n := 600
	var sums := {}
	for variant: String in ["none", "plus3"]:
		var b: Dictionary = sim.state.buildings[FORGE]
		b["upgrades"] = []
		if variant == "plus3":
			for id: String in ["forge_quality_1", "forge_quality_2", "forge_quality_3"]:
				Upgrades.complete(sim, FORGE, id)
		sim.state.rng.seed = 42
		var total := 0
		for i: int in n:
			total += Production.roll_quality(sim, JOAN, "forge", "normal", false, FORGE)
		sums[variant] = total
	near(Upgrades.amount(sim, FORGE, "quality_bonus"), 3.0, 0.0001, "seal +3")
	print("[test_econ_upgrades] calidad media en %d tiradas (craft 5): sin=%.3f, +3=%.3f" % [n, float(sums["none"]) / n,
		float(sums["plus3"]) / n])
	check(int(sums["plus3"]) > int(sums["none"]), "the seal raises the average quality (%s)" % sums)
	# Same rolls, same table row: craft 5 + 3 = 8 reads the craft-8 row of the table.
	var want := Production.quality_chances(cat.production, 8)
	eq(Production.quality_chances(cat.production, clampi(5 + roundi(Upgrades.amount(sim, FORGE, "quality_bonus")), 1,
		10)), want, "the bonus adds to the craft before reading the table")
	sim.state.rng.seed = 7
	var a := Production.roll_quality(sim, JOAN, "forge", "normal", false)
	sim.state.rng.seed = 7
	eq(Production.roll_quality(sim, JOAN, "forge", "normal", false, ""), a, "without a building: as before")


func test_new_station_is_worked_like_its_kind() -> void:
	var sim := _sim()
	var st := sim.state
	var hero: Dictionary = st.characters[HERO]
	hero["location"] = FORGE
	var opts := Production.recipe_options(sim, HERO, FORGE, "anvil_2")
	check(opts.any(func(o: Dictionary) -> bool: return str(o["recipe"]) == "forge_sword"), "anvil_2 offers the sword")
	check(not opts.any(func(o: Dictionary) -> bool: return str(o["recipe"]) == "forge_ingot"), "not the ingot")
	check(Orders.apply(sim, {"type": "go_to_station", "actor": HERO, "zone": "anvil"})["ok"], "Hugo takes the anvil")
	eq(str(Orders.apply(sim, {"type": "work_at", "actor": HERO, "building": FORGE, "zone": "anvil_2",
		"recipe": "forge_ingot", "mode": "normal"})["reason"]), "wrong_station", "no ingots on an anvil")
	# Joan (role anvil) comes at dawn: the anvil is Hugo's, so the queue gives him the second anvil.
	var ev := _run(sim, 360)
	var mine := _of(ev, "employee_assigned").filter(func(e: Dictionary) -> bool: return str(e["employee"]) == JOAN)
	check(not mine.is_empty(), "Joan got work")
	check(mine.any(func(e: Dictionary) -> bool: return str(e["zone"]) == "anvil_2" and str(e["recipe"]) == "forge_sword"),
		"a sword on anvil_2 (%s)" % [mine])
	check(not mine.any(func(e: Dictionary) -> bool: return str(e["zone"]) == "furnace"), "never on the furnace (role)")
	eq(str(st.buildings[FORGE]["zones"]["anvil"]["occupant"]), HERO, "Hugo still holds the anvil")
	# By hand, the owner can work the second anvil too.
	var hero2 := _sim()
	hero2.state.characters[HERO]["location"] = FORGE
	check(Orders.apply(hero2, {"type": "work_at", "actor": HERO, "building": FORGE, "zone": "anvil_2",
		"recipe": "forge_sword", "mode": "normal"})["ok"], "Hugo forges on anvil_2")


func test_storage_upgrade_fits_more_stacks() -> void:
	var sim := _sim()
	var inv: Dictionary = sim.state.buildings[FORGE]["inventory"]
	eq(int(inv["limit"]), 10, "10 stacks")
	var ids: Array = cat.items().keys().map(func(k: Variant) -> String: return str(k))
	ids.sort()
	for it: String in ids:  # one unit of each item not held yet, until the 10 stacks are full
		if Inventory.count(inv, it) == 0:
			Inventory.add(inv, cat, it, Inventory.EXCELLENT, 1)
	eq((inv["stacks"] as Array).size(), 10, "full: 10 stacks")
	var spare := ""
	for it: String in ids:
		if Inventory.count(inv, it) == 0:
			spare = it
			break
	check(not Inventory.can_add(inv, cat, spare, Inventory.NORMAL, 1), "an 11th stack does not fit")
	check(_buy(sim, "forge_capacity_2")["ok"], "buys Almacén ampliado (8 wood)")
	_run(sim, 1440)
	check(Upgrades.has(sim.state, FORGE, "forge_capacity_2"), "finished")
	eq(int(inv["limit"]), 20, "20 stacks")
	check(Inventory.can_add(inv, cat, spare, Inventory.NORMAL, 1), "now the 11th stack fits")


func test_places_and_masters_workshop() -> void:
	var sim := _sim()
	var st := sim.state
	eq(Staff.slots(st, FORGE), 2, "base 1 + dormitory 1")
	eq(Staff.free_slots(st, FORGE), 0, "both taken")
	var master := ""
	for c: String in ["chr_0011", "chr_0019"]:
		if Staff.is_unemployed(sim, c):
			master = c
			break
	check(master != "", "an unemployed master in the town")
	# A third place by hand, to see the rank rule alone.
	st.buildings[FORGE]["employee_slots"] = 3
	eq(str(Orders.apply(sim, {"type": "hire", "actor": HERO, "building": FORGE, "candidate": master})["reason"]),
		"needs_upgrade", "no masters without the master's workshop")
	var row: Array = Staff.candidates(sim, HERO, FORGE).filter(func(r: Dictionary) -> bool:
		return str(r["character"]) == master)
	eq(str(row[0]["status"]), "needs_upgrade", "the hiring panel says why")
	check(Staff._rank_allowed(sim, "journeyman", FORGE), "journeymen are not gated")
	st.buildings[FORGE]["employee_slots"] = 2
	# Requirements of the workshop: staff 2 and capacity 2 (cross); buy them all through the order and the works.
	for id: String in ["forge_staff_2", "forge_capacity_2", "forge_staff_3"]:
		check(_buy(sim, id)["ok"], "buys %s" % id)
		_run(sim, int(st.buildings[FORGE]["upgrade_work"]["end"]) - int(st.clock["minute"]))
		check(Upgrades.has(st, FORGE, id), "%s finished" % id)
	eq(Staff.slots(st, FORGE), 3, "the workshop adds a place")
	check(Upgrades.allows_rank(sim, FORGE, "master"), "masters allowed")
	var r := Orders.apply(sim, {"type": "hire", "actor": HERO, "building": FORGE, "candidate": master})
	check(r["ok"], "hires the master (%s)" % r.get("reason", ""))
	eq(str(st.characters[master]["rank"]), "master", "a master works here now")
	# The rival's forge has no workshop: its masters stay gated.
	check(Upgrades.rank_gated(sim, "bld_0002", "master"), "the rival forge's tree gates masters too")
	check(not Upgrades.rank_ok(sim, "bld_0002", "master"), "without the workshop")


func test_dining_and_facade_loyalty_when_finished() -> void:
	var sim := _sim()
	var st := sim.state
	_run(sim, 60)  # past dawn: wages paid (+1 loyalty)
	var before := {JOAN: int(st.characters[JOAN]["job"]["loyalty"]), AGNES: int(st.characters[AGNES]["job"]["loyalty"])}
	check(_buy(sim, "forge_staff_2")["ok"], "buys the dining room")
	var ev := _run(sim, int(st.buildings[FORGE]["upgrade_work"]["end"]) - int(st.clock["minute"]))
	var up := _of(ev, "loyalty_changed").filter(func(e: Dictionary) -> bool: return str(e["reason"]) == "upgrade")
	eq(up.size(), 2, "both employees +loyalty once")
	for e: Dictionary in up:
		eq(int(e["amount"]), 10, "+10 dining")
	check(int(st.characters[JOAN]["job"]["loyalty"]) >= int(before[JOAN]) + 10, "Joan's loyalty went up")


func test_security_halves_theft() -> void:
	var sim := _sim()
	check(not Staff._has_security(sim, FORGE), "no security upgrade yet")
	check(_buy(sim, "forge_security_1")["ok"], "buys the lock")
	_run(sim, 1440)
	check(Upgrades.has(sim.state, FORGE, "forge_security_1"), "finished")
	check(Staff._has_security(sim, FORGE), "protection 0.2 > 0: security")
	# Measured: a thief-band employee with theft chance 0.5 rolls every dawn; with security it halves.
	var thefts := {}
	for variant: String in ["none", "lock"]:
		var stolen := 0
		for s: int in 40:
			var w := _sim("forge_upgrades", 100 + s)
			w.catalog = Catalog.load_from()
			(w.catalog.employees["bands"] as Array)[3]["theft_chance"] = 0.5
			if variant == "lock":
				Upgrades.complete(w, FORGE, "forge_security_1")
			w.state.characters[JOAN]["job"]["loyalty"] = 5
			var ev := _run(w, 60)
			stolen += _of(ev, "employee_stole").size()
		thefts[variant] = stolen
	print("[test_econ_upgrades] robos en 40 amaneceres (p=0,5): %s" % thefts)
	check(int(thefts["lock"]) < int(thefts["none"]), "the lock halves the thefts (%s)" % thefts)


# --- Save, ledger ---------------------------------------------------------------------------------------------------

func test_save_load_with_works_in_progress() -> void:
	var a := _sim()
	check(_buy(a, "forge_production_2")["ok"], "buys")
	_run(a, 300)
	var text := JSON.stringify(a.state.to_dict())
	var r := SaveFile.from_text(text)
	check(r["ok"], "loads")
	var b := Sim.new(r["state"], cat)
	eq(typeof(b.state.buildings[FORGE]["upgrade_work"]["end"]), TYPE_INT, "the end comes back as int")
	eq(b.state_hash(), a.state_hash(), "same state after loading")
	var left := int(a.state.buildings[FORGE]["upgrade_work"]["end"]) - int(a.state.clock["minute"])
	_run(a, left + 60)
	_run(b, left + 60)
	check(Upgrades.has(b.state, FORGE, "forge_production_2"), "the loaded game finishes the works")
	eq(b.state_hash(), a.state_hash(), "and stays identical")


func test_ledger_adds_up_with_upgrades() -> void:
	var sim := _sim()
	var st := sim.state
	var gold0 := Money.gold(st, FAM)
	var book0 := Ledger.total(st, FAM)
	for id: String in ["forge_production_2", "forge_quality_2", "forge_staff_2"]:
		check(_buy(sim, id)["ok"], "buys %s" % id)
		_run(sim, int(st.buildings[FORGE]["upgrade_work"]["end"]) - int(st.clock["minute"]))
	eq(Money.gold(st, FAM) - gold0, Ledger.total(st, FAM) - book0, "the book adds up to the gold")
	var spent := 0
	for e: Dictionary in st.ledger["entries"]:
		if str(e["family"]) == FAM and str(e["category"]) == "upgrades":
			spent += int(e["amount"])
	eq(spent, -(8 + 12 + 12), "the three upgrades in category upgrades")


func test_random_orders_keep_the_book() -> void:
	var sim := _sim()
	var st := sim.state
	var gold0 := Money.gold(st, FAM)
	var book0 := Ledger.total(st, FAM)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var ids := cat.upgrade_tree("forge")
	ids.append("forge_nothing")
	for i: int in 3 * 1440:
		var orders: Array = []
		if i % 97 == 0:
			orders.append({"type": "buy_upgrade", "actor": [HERO, JOAN, "chr_0002"][rng.randi_range(0, 2)],
				"building": [FORGE, "bld_0002"][rng.randi_range(0, 1)], "upgrade": ids[rng.randi_range(0, ids.size() - 1)]})
		sim.step(orders)
	check(not Upgrades.owned(st, FORGE).is_empty(), "something was bought")
	eq(Money.gold(st, FAM) - gold0, Ledger.total(st, FAM) - book0, "0 mismatches with random purchases")
